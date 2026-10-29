function summary = batch_run(input_folder, cfg, opts)
%BATCH_RUN Orchestrate scan -> per-dataset run -> anomaly detection.
%
%   input_folder: path scanned for session files.
%   cfg:         full batch config struct.
%   opts (struct, all optional):
%     .live_log_callback   function handle (msg) for each log line. Absent:
%                          print the lines to the command window. []: silent.
%     .stop_check          function handle returning logical (set true to stop)
%     .selected_datasets   cell array of dataset_ids to run. Absent: all
%                          non-skipped datasets. Present but empty: none.
%
%   Returns summary struct: results, anomalies, session_names (the cell map
%   columns), output_dir, log_file, results_csv, detail_csv, match_stats_csv,
%   warnings_png, n_succeeded, n_failed, n_with_warnings, stopped.

    if nargin < 3; opts = struct(); end
    if ~isfield(opts, 'live_log_callback'); opts.live_log_callback = @(msg) fprintf('%s\n', msg); end
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
    expected = cfg.cellreg.expected_n_sessions;
    logger.info('GLOBAL', ['microns_per_pixel=%g, maximal_distance_um=%g, ' ...
        'expected_n_sessions=%d, model=%s, fpr_max=%g'], cfg.cellreg.microns_per_pixel, ...
        cfg.cellreg.maximal_distance_um, expected, cfg.cellreg.initial_registration_type, ...
        cfg.p_same_tuning.fpr_max);
    if ~isempty(scan.unparsed)
        shown = scan.unparsed(1:min(20, end));
        logger.warn('GLOBAL', ['%d files do not match <EXPERIMENT>_<ANIMAL>_<SESSION>*.mat ' ...
            '(ANIMAL = 1-2 letters + 2 digits, SESSION = digit + D or T) and are ignored: %s%s'], ...
            numel(scan.unparsed), strjoin(shown, ', '), ...
            repmat(' ...', 1, numel(scan.unparsed) > numel(shown)));
    end
    if isempty(scan.datasets)
        logger.warn('GLOBAL', 'no dataset found: rename the files (manual, section 1.2)');
        warning('BatchCellReg:NoDatasets', ['No dataset found in %s: %d .mat files do ' ...
            'not match the naming rule (manual, section 1.2).'], input_folder, numel(scan.unparsed));
    end
    logger.info('GLOBAL', 'cell map columns (sessions of the batch): %s', ...
        strjoin(scan.session_names, ', '));
    if numel(scan.session_names) ~= expected
        logger.warn('GLOBAL', ['the batch has %d session names, expected %d: ' ...
            'check the file names'], numel(scan.session_names), expected);
    end
    for c = check_session_counts(scan, expected)
        if ~c.ok
            logger.warn(c.dataset_id, 'session count: %s (will be matched and flagged red)', c.text);
        end
    end

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
            r = run_single_dataset(d, cfg, sub, logger, scan.session_names);
            logger.info(d.dataset_id, 'done (%d cells; in %s sessions: %s)', ...
                r.match_stats(1), ...
                strjoin(arrayfun(@num2str, numel(r.sessions):-1:1, 'UniformOutput', false), '/'), ...
                strjoin(arrayfun(@num2str, r.match_stats(2:end), 'UniformOutput', false), '/'));
        catch ME
            r = struct();
            r.dataset_id = d.dataset_id;
            r.sessions = {d.sessions.session_id};
            r.error = ME.message;
            logger.error(d.dataset_id, 'FAILED: %s', ME.message);
            logger.error(d.dataset_id, 'Stack: %s', getReport(ME, 'extended', 'hyperlinks', 'off'));
        end
        results = [results, normalize_result(r)]; %#ok<AGROW>
    end

    at = cfg.anomaly_thresholds;
    at.expected_n_sessions = expected;
    at.fpr_max = cfg.p_same_tuning.fpr_max;
    at.alignment_min_xcorr = cfg.cellreg.alignment_min_xcorr;
    anomalies = detect_anomalies(results, at);

    [results_csv, detail_csv] = export_results(results, anomalies, output_dir);
    match_stats_csv = fullfile(output_dir, '_match_statistics.csv');
    write_cell_csv(match_statistics_table(results), match_stats_csv);
    warnings_png = fullfile(output_dir, '_batch_warnings.png');
    try
        plot_batch_warnings(results, anomalies, at, warnings_png);
    catch ME
        % The figure is a summary of the CSV files; never lose a batch over it.
        logger.warn('GLOBAL', 'warnings figure skipped: %s', ME.message);
        warnings_png = '';
    end

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
        'session_names', {scan.session_names}, ...
        'output_dir', output_dir, ...
        'log_file', log_file, ...
        'results_csv', results_csv, ...
        'detail_csv', detail_csv, ...
        'match_stats_csv', match_stats_csv, ...
        'warnings_png', warnings_png, ...
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
        'alignment_mode', '', 'forced_low_xcorr', false, 'missing_sessions', {{}}, ...
        'linked_fraction', []);
    fns = fieldnames(defaults);
    for k = 1:numel(fns)
        if ~isfield(r, fns{k})
            r.(fns{k}) = defaults.(fns{k});
        end
    end
    if ~isfield(r, 'error'); r.error = ''; end
end

function n = count_with_warnings(a)
    n = 0;
    for k = 1:numel(a.flags)
        if any(structfun(@(x) x, a.flags(k)))
            n = n + 1;
        end
    end
end

function [results_csv, detail_csv] = export_results(results, anomalies, output_dir)
    results_csv = fullfile(output_dir, '_batch_results.csv');
    detail_csv  = fullfile(output_dir, '_batch_warnings_detail.csv');

    [~, names] = anomaly_decode_map();
    rows = [{'dataset_id', 'n_sessions', 'missing_sessions', 'n_cells', ...
        'pct_in_all', 'pct_in_all_of_mean', 'chosen_p_same', 'chosen_fpr_pct', ...
        'model', 'alignment_mode'}, names, ...
        {'median_cells', 'worst_session_ratio', 'min_xcorr', 'max_shift_px', ...
        'model_mse', 'worst_link_ratio', 'error'}];
    for k = 1:numel(results)
        r = results(k);
        f = anomalies.flags(k); m = anomalies.metrics(k);
        n_cells = 0; in_all = 0;
        if ~isempty(r.match_stats); n_cells = r.match_stats(1); in_all = r.match_stats(2); end
        pct = NaN; pct_mean = NaN;
        if isempty(r.error)
            pct = 100 * in_all / max(n_cells, 1);
            pct_mean = 100 * in_all / max(mean(r.n_cells_per_session), 1);
        end
        sev = cellfun(@(nm) f.(nm), names, 'UniformOutput', false);
        rows(end+1, :) = [{r.dataset_id, numel(r.sessions), strjoin(r.missing_sessions, ' '), ...
            n_cells, pct, pct_mean, round(100 * r.chosen_p_same) / 100, 100 * r.chosen_fpr, ...
            r.best_model_string, r.alignment_mode}, sev, ...
            {m.median_cells, m.worst_session_ratio, m.min_xcorr, m.max_shift_px, ...
            m.model_mse, m.worst_link_ratio, r.error}]; %#ok<AGROW>
    end
    write_cell_csv(rows, results_csv);

    detail = {'dataset_id', 'session', 'warning', 'rule', 'value', 'threshold', 'severity'};
    for d = anomalies.details
        detail(end+1, :) = {d.dataset_id, d.session, d.warning, d.rule, ...
            d.value, d.threshold, d.severity}; %#ok<AGROW>
    end
    write_cell_csv(detail, detail_csv);
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
            elseif isnumeric(v) && isscalar(v); s = sprintf('%.15g', round(v, 3));
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
