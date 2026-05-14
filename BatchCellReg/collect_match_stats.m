function s = collect_match_stats(cell_to_index_map)
%COLLECT_MATCH_STATS Per-dataset match statistics from cell_to_index_map.
%   match_stats(1) = total cells
%   match_stats(k+1) for k=1..S = number of cells found in (S - k + 1) sessions,
%                                 i.e. (2)=in all S, (3)=in S-1, ..., (S+1)=in 1.
    present = cell_to_index_map ~= 0;
    cells_per_session_count = sum(present, 2);
    S = size(cell_to_index_map, 2);
    total = size(cell_to_index_map, 1);

    match_stats = zeros(1, S + 1);
    match_stats(1) = total;
    for k = 1:S
        sessions_present = S - (k - 1);
        match_stats(k + 1) = sum(cells_per_session_count == sessions_present);
    end

    s = struct( ...
        'match_stats', match_stats, ...
        'n_cells_per_session', sum(present, 1), ...
        'pct_in_all', match_stats(2) / max(total, 1));
end
