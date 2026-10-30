function tests = test_place_sessions
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', '..', 'BatchCellReg')));
end

function test_complete_dataset_keeps_its_columns(tc)
    % Other names than the batch (1D_1T vs 1D) do not matter at full count.
    p = place_sessions({'1D_1T', '2D_1T', '3D_1T'}, {'1D', '2D', '3D'}, 3);
    verifyEqual(tc, p.columns, 1:3);
    verifyEqual(tc, p.n_columns, 3);
    verifyEmpty(tc, p.missing);
end

function test_missing_session_by_name(tc)
    p = place_sessions({'1D', '2D', '4D', '5D'}, {'1D', '2D', '3D', '4D', '5D'}, 5);
    verifyEqual(tc, p.columns, [1 2 4 5]);
    verifyEqual(tc, p.n_columns, 5);
    verifyEqual(tc, p.missing, {'3D'});
    verifyTrue(tc, p.known);
end

function test_trial_part_is_ignored_when_names_differ(tc)
    p = place_sessions({'1D_1T', '3D_1T'}, {'1D', '2D', '3D'}, 3);
    verifyEqual(tc, p.columns, [1 3]);
    verifyEqual(tc, p.missing, {'2D'});
end

function test_unknown_names_put_zeros_last(tc)
    p = place_sessions({'a', 'b'}, {'1D', '2D', '3D'}, 3);
    verifyFalse(tc, p.known);
    verifyEqual(tc, p.columns, [1 2]);
    verifyEqual(tc, p.n_columns, 3);
    verifyEmpty(tc, p.missing);
    p = place_sessions({'1D', '2D'}, {}, 3);
    verifyFalse(tc, p.known);
end

function test_two_trials_of_one_day_do_not_take_one_column(tc)
    % 1D_1T and 1D_2T both strip to 1D: no unique place, zeros last.
    p = place_sessions({'1D_1T', '1D_2T'}, {'1D', '2D', '3D'}, 3);
    verifyFalse(tc, p.known);
end

function test_extra_sessions_and_no_expected_count(tc)
    p = place_sessions({'1D', '2D', '3D'}, {'1D', '2D'}, 2);
    verifyEqual(tc, [p.n_columns, p.columns], [3 1 2 3]);
    p = place_sessions({'1D', '2D'}, {}, 0);
    verifyEqual(tc, p.n_columns, 2);
end
