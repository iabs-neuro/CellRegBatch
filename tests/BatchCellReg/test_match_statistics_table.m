function tests = test_match_statistics_table
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', '..', 'BatchCellReg')));
end

function r = make_result(id, n_sessions, ncells, mstats, err)
    sessions = arrayfun(@(k) sprintf('%dD', k), 1:n_sessions, 'UniformOutput', false);
    r = struct('dataset_id', id, 'sessions', {sessions}, ...
        'n_cells_per_session', ncells, 'match_stats', mstats, 'error', err);
end

function test_columns_count_sessions_from_the_largest_dataset(testCase)
    % A: 5 sessions, 10 cells: 2 in all 5, 1 in 4, 3 in 3, 3 in 2, 1 in 1.
    % B: 3 sessions, 8 cells: its "in all" must land in in_3_sessions.
    % F: failed, so it gets no row.
    rs = [make_result('A', 5, [6 6 5 5 4], [10 2 1 3 3 1], ''), ...
          make_result('B', 3, [4 4 6],     [8 3 1 4],      ''), ...
          make_result('F', 0, [],          [0 0],          'failed')];
    rows = match_statistics_table(rs);

    verifyEqual(testCase, rows(1, :), {'dataset_id', 'n_sessions', 'n_cells', ...
        'in_5_sessions', 'in_4_sessions', 'in_3_sessions', 'in_2_sessions', 'in_1_sessions', ...
        'mean_cells_per_session', 'pct_in_all', 'pct_in_all_of_mean'});
    verifyEqual(testCase, size(rows, 1), 3);

    verifyEqual(testCase, rows(2, 1:8), {'A', 5, 10, 2, 1, 3, 3, 1});
    verifyEqual(testCase, rows{2, 9}, 5.2, 'AbsTol', 1e-12);
    verifyEqual(testCase, rows{2, 10}, 0.2, 'AbsTol', 1e-12);
    verifyEqual(testCase, rows{2, 11}, 2 / 5.2, 'AbsTol', 1e-12);

    verifyEqual(testCase, rows(3, 1:8), {'B', 3, 8, '', '', 3, 1, 4});
    verifyEqual(testCase, rows{3, 11}, 3 / mean([4 4 6]), 'AbsTol', 1e-12);
end

function test_empty_batch_gives_header_only(testCase)
    rows = match_statistics_table(struct([]));
    verifyEqual(testCase, rows, {'dataset_id', 'n_sessions', 'n_cells', ...
        'mean_cells_per_session', 'pct_in_all', 'pct_in_all_of_mean'});
end
