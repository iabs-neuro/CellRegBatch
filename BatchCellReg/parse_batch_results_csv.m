function r = parse_batch_results_csv(path)
%PARSE_BATCH_RESULTS_CSV Read & validate a _batch_results.csv export.
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
    required = {'dataset_id','n_sessions','n_cells','pct_in_all','chosen_fpr', ...
        'W1','W2','W2b_hard','W2b_rel','W3a','W3b','W4','W5a','W5b','W6a','W6b','W7'};
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
