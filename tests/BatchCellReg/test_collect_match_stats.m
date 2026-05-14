function tests = test_collect_match_stats
    tests = functiontests(localfunctions);
end

function test_counts_cells_present_in_k_sessions(testCase)
    % rows = cells, cols = sessions. Non-zero = present.
    cell_to_index_map = [ ...
        1 2 3;       % in all 3
        4 0 5;       % in 2
        6 0 0;       % in 1
        7 8 9;       % in all 3
        0 0 10];     % in 1
    s = collect_match_stats(cell_to_index_map);
    % match_stats(1) = total cells = 5
    % match_stats(2) = in all 3 = 2
    % match_stats(3) = in 2 = 1
    % match_stats(4) = in 1 = 2
    verifyEqual(testCase, s.match_stats, [5 2 1 2]);
    verifyEqual(testCase, s.n_cells_per_session, [4 2 4]);
    verifyEqual(testCase, s.pct_in_all, 2/5);
end
