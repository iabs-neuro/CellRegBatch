function summary = batch_run(input_folder, cfg, opts)
%BATCH_RUN Orchestrate scan -> per-dataset run -> anomaly detection.
%
%   input_folder: path scanned for session files.
%   cfg:         full batch config struct.
%   opts (struct, all optional):
%     .live_log_callback   function handle (msg) for GUI
%     .stop_check          function handle returning logical (set true to stop)
%     .selected_datasets   cell array of dataset_ids to run (default: all non-skip)
%
%   Returns summary struct: results, anomalies, output_dir, log_file, results_csv,
%   detail_csv, n_succeeded, n_failed, n_with_warnings, stopped.

    if nargin < 3; opts = struct(); end
    if ~isfield(opts, 'live_log_callback'); opts.live_log_callback = []; end
    if ~isfield(opts, 'stop_check'); opts.stop_check = @() false; end
    if ~isfield(opts, 'selected_datasets'); opts.selected_datasets = {}; end

    scan = scan_input_folder(input_folder);

    output_dir = fullfile(input_folder, cfg.io.output_subfolder_name);
    if ~exist(output_dir, 'dir'); mkdir(output_dir); end
    log_file = fullfile(output_dir, sprintf('_batch_log_%s.txt', datestr(now, 'yyyymmdd_HHMMSS')));
    logger = batch_logger(log_file, opts.live_log_callback);
    cleanup = onCleanup(@() logger.close());

    config_to_json(cfg, fullfile(output_dir, '_batch_config.json'));
    logger.info('GLOBAL', 'input=%s, output=%s, datasets=%d, unparsed=%d', ...
        input_folder, output_dir, numel(scan.datasets), numel(scan.unparsed));

    results = [];
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
        if ~isempty(opts.selected_datasets) && ~ismember(d.dataset_id, opts.selected_datasets)
            logger.info(d.dataset_id, 'skipped: not selected');
            continue
        end
        sub = fullfile(output_dir, d.dataset_id);
        if ~exist(sub, 'dir'); mkdir(sub); end
        try
            r = run_single_dataset(d, cfg, sub, logger);
            logger.info(d.dataset_id, 'done (%d cells)', r.match_stats(1));
        catch ME
            r = struct();
            r.dataset_id = d.dataset_id;
            r.error = ME.message;
            logger.error(d.dataset_id, 'FAILED: %s', ME.message);
            logger.error(d.dataset_id, 'Stack: %s', getReport(ME, 'basic'));
        end
        results = [results, normalize_result(r)]; %#ok<AGROW>
    end

    anomalies = detect_anomalies(results, cfg.anomaly_thresholds);

    [results_csv, detail_csv] = export_results(results, anomalies, output_dir);

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
        'chosen_fpr', NaN, 'p_same_unreachable', false);
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
        'W1','W2','W3a','W3b','W4','W5a','W5b','W6a','W6b', ...
        'W3a_min_xcorr', 'W5a_max_shift_px', 'W6a_mse', 'error'};
    for k = 1:numel(results)
        r = results(k);
        f = anomalies.flags(k); m = anomalies.metrics(k);
        rows(end+1, :) = { ...
            r.dataset_id, numel(r.sessions), maybe_first(r.match_stats), ...
            ratio(r.match_stats), r.chosen_fpr, ...
            f.W1, f.W2, f.W3a, f.W3b, f.W4, f.W5a, f.W5b, f.W6a, f.W6b, ...
            m.W3a_min_xcorr, m.W5a_max_shift, m.W6a_mse, r.error}; %#ok<AGROW>
    end
    write_cell_csv(rows, results_csv);

    detail = {'dataset_id', 'session', 'anomaly_type', 'value', 'threshold'};
    for k = 1:numel(results)
        r = results(k); f = anomalies.flags(k); m = anomalies.metrics(k);
        if ~isempty(r.error); continue; end
        if f.W3a
            [v, idx] = min(r.maximal_cross_correlation(:));
            detail(end+1, :) = {r.dataset_id, sess_at(r, idx), 'W3a_low_xcorr_hard', v, NaN}; %#ok<AGROW>
        end
        if f.W5a
            shifts = r.alignment_shift_px; shifts(r.reference_session_index) = NaN;
            [v, idx] = max(abs(shifts));
            detail(end+1, :) = {r.dataset_id, sess_at(r, idx), 'W5a_shift_hard', v, NaN}; %#ok<AGROW>
        end
        if f.W4
            detail(end+1, :) = {r.dataset_id, '-', 'W4_fpr_unreachable', r.chosen_fpr, NaN}; %#ok<AGROW>
        end
        if f.W6a
            detail(end+1, :) = {r.dataset_id, '-', 'W6a_mse_hard', r.MSE_model, NaN}; %#ok<AGROW>
        end
        if f.W1
            detail(end+1, :) = {r.dataset_id, '-', 'W1_pct_match_outlier', m.pct_in_all, NaN}; %#ok<AGROW>
        end
    end
    write_cell_csv(detail, detail_csv);
end

function s = sess_at(r, idx)
    if idx >= 1 && idx <= numel(r.sessions); s = r.sessions{idx}; else; s = '-'; end
end

function v = maybe_first(s)
    if isempty(s); v = 0; else; v = s(1); end
end

function v = ratio(s)
    if numel(s) < 2 || s(1) == 0; v = NaN; else; v = s(2)/s(1); end
end

function write_cell_csv(rows, path)
    fid = fopen(path, 'w');
    if fid < 0; error('BatchCellReg:CsvWrite', 'Cannot write %s', path); end
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
