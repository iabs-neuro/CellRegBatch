function summary = batch_run(input_folder, cfg, opts)
%BATCH_RUN Orchestrate scan -> per-dataset run -> anomaly detection.
%
%   input_folder: path scanned for session files.
%   cfg:         full batch config struct.
%   opts (struct, all optional):
%     .live_log_callback   function handle (msg) for GUI
%     .stop_check          function handle returning logical (set true to stop)
%     .selected_datasets   cell array of dataset_ids to run. Absent: all
%                          non-skipped datasets. Present but empty: none.
%
%   Returns summary struct: results, anomalies, output_dir, log_file, results_csv,
%   detail_csv, match_stats_csv, n_succeeded, n_failed, n_with_warnings, stopped.

    if nargin < 3; opts = struct(); end
    if ~isfield(opts, 'live_log_callback'); opts.live_log_callback = []; end
    if ~isfield(opts, 'stop_check'); opts.stop_check = @() false; end
    has_selection = isfield(opts, 'selected_datasets');

    scan = scan_input_folder(input_folder);

    output_dir = fullfile(input_folder, cfg.io.output_subfolder_name);
    if ~exist(output_dir, 'dir'); mkdir(output_dir); end
    log_file = fullfile(output_dir, sprintf('_batch_log_%s.txt', datestr(now, 'yyyymmdd_HHMMSS')));
    logger = batch_logger(log_file, opts.live_log_callback);
    cleanup = onCleanup(@() logger.close());

    config_to_json(cfg, fullfile(output_dir, '_batch_config.json'));
    logger.info('GLOBAL', 'input=%s, output=%s, datasets=%d, unparsed=%d', ...
        input_folder, output_dir, numel(scan.datasets), numel(scan.unparsed));

    results = struct([]);
    stopped = false;
    for k = 1:numel(scan.datasets)
        d = scan.datasets(k);
        if opts.stop_check()
            stopped = true;
            logger.info('GLOBAL', 'stop requested; %d datasets not processed', ...
                numel(scan.datasets) - k + 1);
            break
        end
        if d.skip
            logger.warn(d.dataset_id, 'skipped: %s', d.skip_reason);
            continue
        end
        if has_selection && ~ismember(d.dataset_id, opts.selected_datasets)
            logger.info(d.dataset_id, 'skipped: not selected');
            continue
        end
        sub = fullfile(output_dir, d.dataset_id);
        if ~exist(sub, 'dir'); mkdir(sub); end
        try
            r = run_single_dataset(d, cfg, sub, logger);
            logger.info(d.dataset_id, 'done (%d cells; in %s sessions: %s)', ...
                r.match_stats(1), ...
                strjoin(arrayfun(@num2str, numel(r.sessions):-1:1, 'UniformOutput', false), '/'), ...
                strjoin(arrayfun(@num2str, r.match_stats(2:end), 'UniformOutput', false), '/'));
        catch ME
            r = struct();
            r.dataset_id = d.dataset_id;
            r.error = ME.message;
            logger.error(d.dataset_id, 'FAILED: %s', ME.message);
            logger.error(d.dataset_id, 'Stack: %s', getReport(ME, 'basic'));
        end
        results = [results, normalize_result(r)]; %#ok<AGROW>
    end

    at = cfg.anomaly_thresholds;
    at.expected_n_sessions = cfg.cellreg.expected_n_sessions;
    at.fpr_max = cfg.p_same_tuning.fpr_max;
    anomalies = detect_anomalies(results, at);

    [results_csv, detail_csv] = export_results(results, anomalies, output_dir);
    match_stats_csv = fullfile(output_dir, '_match_statistics.csv');
    write_cell_csv(match_statistics_table(results), match_stats_csv);

    n_succeeded = sum(arrayfun(@(r) isempty(r.error), results));
    n_failed    = numel(results) - n_succeeded;
    n_warned    = count_with_warnings(anomalies);
    logger.info('GLOBAL', 'summary: %d succeeded, %d failed, %d with warnings', ...
        n_succeeded, n_failed, n_warned);

    if cfg.cellreg.use_parallel_processing
        delete(gcp('nocreate'));
    end

    summary = struct( ...
        'results', results, ...
        'anomalies', anomalies, ...
        'output_dir', output_dir, ...
        'log_file', log_file, ...
        'results_csv', results_csv, ...
        'detail_csv', detail_csv, ...
        'match_stats_csv', match_stats_csv, ...
        'n_succeeded', n_succeeded, ...
        'n_failed', n_failed, ...
        'n_with_warnings', n_warned, ...
        'stopped', stopped);
end

function r = normalize_result(r)
    defaults = struct( ...
        'sessions', {{}}, 'n_cells_per_session', [], 'match_stats', [0 0], ...
        'maximal_cross_correlation', [], 'alignment_translations', [], ...
        'alignment_shift_px', [], 'reference_session_index', 1, ...
        'MSE_model', NaN, 'best_model_string', '', 'chosen_p_same', NaN, ...
        'chosen_fpr', NaN, 'p_same_unreachable', false, ...
        'alignment_mode', '', 'forced_low_xcorr', false);
    fns = fieldnames(defaults);
    for k = 1:numel(fns)
        if ~isfield(r, fns{k})
            r.(fns{k}) = defaults.(fns{k});
        end
    end
    if ~isfield(r, 'error'); r.error = ''; end
end

function n = count_with_warnings(a)
    if isempty(a.flags); n = 0; return; end
    cnt = 0;
    fns = fieldnames(a.flags(1));
    for k = 1:numel(a.flags)
        if any(structfun(@(x) x, a.flags(k)))
            cnt = cnt + 1;
        end
    end
    n = cnt;
end

function [results_csv, detail_csv] = export_results(results, anomalies, output_dir)
    results_csv = fullfile(output_dir, '_batch_results.csv');
    detail_csv  = fullfile(output_dir, '_batch_warnings_detail.csv');

    rows = {};
    rows(end+1, :) = {'dataset_id', 'n_sessions', 'n_cells', 'pct_in_all', 'chosen_fpr', ...
        'W1','W2','W2b_hard','W2b_rel','W3a','W3b','W4','W5a','W5b','W6a','W6b','W7', ...
        'W3a_min_xcorr', 'W5a_max_shift_px', 'W6a_mse', 'W2b_ratio', 'error'};
    for k = 1:numel(results)
        r = results(k);
        f = anomalies.flags(k); m = anomalies.metrics(k);
        rows(end+1, :) = { ...
            r.dataset_id, numel(r.sessions), maybe_first(r.match_stats), ...
            ratio(r.match_stats), r.chosen_fpr, ...
            f.W1, f.W2, f.W2b_hard, f.W2b_rel, f.W3a, f.W3b, f.W4, f.W5a, f.W5b, f.W6a, f.W6b, f.W7, ...
            m.W3a_min_xcorr, m.W5a_max_shift, m.W6a_mse, m.W2b_ratio, r.error}; %#ok<AGROW>
    end
    write_cell_csv(rows, results_csv);

    detail = {'dataset_id', 'session', 'anomaly_type', 'value', 'threshold', 'severity'};
    for d = anomalies.details
        detail(end+1, :) = {d.dataset_id, d.session, d.anomaly_type, d.value, d.threshold, d.severity}; %#ok<AGROW>
    end
    write_cell_csv(detail, detail_csv);
end

function v = maybe_first(s)
    if isempty(s); v = 0; else; v = s(1); end
end

function v = ratio(s)
    if numel(s) < 2 || s(1) == 0; v = NaN; else; v = s(2)/s(1); end
end

function write_cell_csv(rows, path)
    % A locked target (e.g. the CSV is open in Excel) must never discard a
    % completed batch: retry briefly, then fall back to a timestamped name.
    fid = fopen(path, 'w');
    if fid < 0
        for attempt = 1:3
            pause(1);
            fid = fopen(path, 'w');
            if fid >= 0; break; end
        end
    end
    if fid < 0
        [p, n, e] = fileparts(path);
        alt = fullfile(p, sprintf('%s_%s%s', n, datestr(now, 'yyyymmdd_HHMMSS'), e));
        fid = fopen(alt, 'w');
        if fid < 0
            warning('BatchCellReg:CsvWrite', ...
                'Cannot write %s (locked?) nor fallback %s; skipping CSV.', path, alt);
            return
        end
        warning('BatchCellReg:CsvWrite', ...
            '%s was locked; wrote %s instead. Close the file in Excel.', path, alt);
    end
    cleanup = onCleanup(@() fclose(fid));
    for r = 1:size(rows, 1)
        line = '';
        for c = 1:size(rows, 2)
            v = rows{r, c};
            if islogical(v); s = ternary(v, '1', '0');
            elseif isnumeric(v) && isscalar(v); s = num2str(v);
            elseif ischar(v); s = strrep(v, ',', ';');
            else; s = ''; end
            if c == 1; line = s; else; line = [line ',' s]; end %#ok<AGROW>
        end
        fprintf(fid, '%s\n', line);
    end
end

function s = ternary(cond, a, b)
    if cond; s = a; else; s = b; end
end
