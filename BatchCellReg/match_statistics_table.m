function rows = match_statistics_table(results)
%MATCH_STATISTICS_TABLE Per-dataset match statistics as a cell table (header row first).
%   One row per successful dataset. in_<k>_sessions = cells found in exactly
%   k sessions. Columns run from the largest session count in the batch down
%   to 1, so a dataset with fewer sessions leaves its top columns empty.
%   pct_in_all = cells in all sessions / all registered cells, in percent.
%   pct_in_all_of_mean = cells in all sessions / mean cells per session, in
%   percent (the lab's "matching %").
    ok = results(arrayfun(@(r) isempty(r.error), results));
    s_max = max([0, arrayfun(@(r) numel(r.sessions), ok)]);
    in_cols = arrayfun(@(k) sprintf('in_%d_sessions', k), s_max:-1:1, 'UniformOutput', false);
    rows = [{'dataset_id', 'n_sessions', 'missing_sessions', 'n_cells'}, in_cols, ...
        {'mean_cells_per_session', 'pct_in_all', 'pct_in_all_of_mean'}];
    for r = ok
        S = numel(r.sessions);
        in_k = repmat({''}, 1, s_max);
        in_k(s_max - S + 1:end) = num2cell(r.match_stats(2:end));
        mean_per_session = mean(r.n_cells_per_session);
        missing = '';
        if isfield(r, 'missing_sessions'); missing = strjoin(r.missing_sessions, ' '); end
        rows(end+1, :) = [{r.dataset_id, S, missing, r.match_stats(1)}, in_k, ...
            {mean_per_session, 100 * r.match_stats(2) / max(r.match_stats(1), 1), ...
             100 * r.match_stats(2) / max(mean_per_session, 1)}]; %#ok<AGROW>
    end
end
