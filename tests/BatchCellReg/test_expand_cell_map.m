function tests = test_expand_cell_map
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', '..', 'BatchCellReg')));
end

function test_missing_session_becomes_zero_column(tc)
    map = [1 2 3 4; 5 0 6 7];
    full = expand_cell_map(map, {'1D', '2D', '4D', '5D'}, {'1D', '2D', '3D', '4D', '5D'});
    verifyEqual(tc, full, [1 2 0 3 4; 5 0 0 6 7]);
end

function test_complete_dataset_is_unchanged(tc)
    map = magic(3);
    verifyEqual(tc, expand_cell_map(map, {'1D', '2D', '3D'}, {'1D', '2D', '3D'}), map);
end

function test_empty_map_keeps_the_columns(tc)
    full = expand_cell_map(zeros(0, 2), {'1D', '3D'}, {'1D', '2D', '3D'});
    verifySize(tc, full, [0 3]);
end

function test_unknown_session_is_an_error(tc)
    verifyError(tc, @() expand_cell_map([1 2], {'1D', '9D'}, {'1D', '2D'}), ...
        'BatchCellReg:SessionNotInBatch');
end
