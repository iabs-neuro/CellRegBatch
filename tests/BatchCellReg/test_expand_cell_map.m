function tests = test_expand_cell_map
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', '..', 'BatchCellReg')));
end

function test_missing_session_becomes_zero_column(tc)
    map = [1 2 3 4; 5 0 6 7];
    verifyEqual(tc, expand_cell_map(map, [1 2 4 5], 5), [1 2 0 3 4; 5 0 0 6 7]);
end

function test_complete_dataset_is_unchanged(tc)
    map = magic(3);
    verifyEqual(tc, expand_cell_map(map, 1:3, 3), map);
end

function test_empty_map_keeps_the_columns(tc)
    verifySize(tc, expand_cell_map(zeros(0, 2), [1 3], 3), [0 3]);
end
