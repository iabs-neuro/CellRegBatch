function r = parse_batch_results_csv(path, required)
%PARSE_BATCH_RESULTS_CSV Read & validate a CSV written by batch_run.
%   required: column names the file must have. Default: the columns the
%   GUI shows from _batch_results.csv.
    if nargin < 2
        [~, names] = anomaly_decode_map();
        required = [{'dataset_id', 'n_sessions', 'n_cells', 'pct_in_all_of_mean', ...
            'chosen_fpr_pct'}, names];
    end
    r = struct('ok', false, 'error', '', 'headers', {{}}, 'rows', {{}});
    if exist(path, 'file') ~= 2
        r.error = sprintf('File not found: %s', path); return
    end
    fid = fopen(path, 'r');
    if fid < 0; r.error = sprintf('Cannot open %s', path); return; end
    c = onCleanup(@() fclose(fid));
    raw = {};
    while true
        ln = fgetl(fid);
        if ~ischar(ln); break; end
        if isempty(strtrim(ln)); continue; end
        raw{end+1} = ln; %#ok<AGROW>
    end
    if isempty(raw); r.error = 'Empty file'; return; end
    headers = strsplit(raw{1}, ',', 'CollapseDelimiters', false);
    headers = strtrim(headers);
    if any(strcmp(headers, 'W1'))
        r.error = ['This file was written by an older version (warnings W1-W7). ' ...
            'Run the batch again to get the current warnings.'];
        return
    end
    for k = 1:numel(required)
        if ~any(strcmp(headers, required{k}))
            r.error = sprintf('Missing required column: %s', required{k}); return
        end
    end
    n = numel(headers);
    rows = cell(numel(raw)-1, n);
    for i = 2:numel(raw)
        parts = strsplit(raw{i}, ',', 'CollapseDelimiters', false);
        for j = 1:n
            if j <= numel(parts); rows{i-1, j} = strtrim(parts{j}); else; rows{i-1, j} = ''; end
        end
    end
    r.ok = true; r.headers = headers; r.rows = rows;
end
