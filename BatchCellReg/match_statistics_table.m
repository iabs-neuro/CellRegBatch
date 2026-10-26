function rows = match_statistics_table(results)
%MATCH_STATISTICS_TABLE Cell table (header + one row per succeeded dataset)
%   for _match_statistics.csv, the lab's Stats_match numbers: registered cells,
%   then cells found in exactly k sessions, from k = the largest session count
%   in the batch down to 1. A dataset with fewer sessions has empty cells in
%   the columns above its own count, so each column means the same k for all
%   rows. pct_in_all divides by the registered cells (as _batch_results.csv);
%   pct_in_all_of_mean divides by the mean number of cells per session.
    ok = results(arrayfun(@(r) isempty(r.error), results));
    s_max = max([0, arrayfun(@(r) numel(r.sessions), ok)]);
    in_cols = arrayfun(@(k) sprintf('in_%d_sessions', k), s_max:-1:1, 'UniformOutput', false);
    rows = [{'dataset_id', 'n_sessions', 'n_cells'}, in_cols, ...
        {'mean_cells_per_session', 'pct_in_all', 'pct_in_all_of_mean'}];
    for r = ok
        S = numel(r.sessions);
        in_k = repmat({''}, 1, s_max);
        in_k(s_max - S + 1:end) = num2cell(r.match_stats(2:end));
        mean_per_session = mean(r.n_cells_per_session);
        rows(end+1, :) = [{r.dataset_id, S, r.match_stats(1)}, in_k, ...
            {mean_per_session, r.match_stats(2) / max(r.match_stats(1), 1), ...
             r.match_stats(2) / max(mean_per_session, 1)}]; %#ok<AGROW>
    end
end
