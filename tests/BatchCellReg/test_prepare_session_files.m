function tests = test_prepare_session_files
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', '..', 'BatchCellReg')));
end

function test_uint8_is_converted_to_double(testCase)
    tmp = [tempname '.mat'];
    cleanup = onCleanup(@() delete(tmp));
    A = uint8(zeros(3, 8, 8));
    A(1, 2, 3) = 200;
    save(tmp, 'A');
    fp = prepare_session_files({tmp});
    verifyTrue(testCase, isa(fp{1}, 'double'));
    verifyEqual(testCase, size(fp{1}), [3 8 8]);
    verifyEqual(testCase, fp{1}(1, 2, 3), 200);
end

function test_double_passthrough_unchanged(testCase)
    tmp = [tempname '.mat'];
    cleanup = onCleanup(@() delete(tmp));
    matrix_data = rand(3, 8, 8);
    save(tmp, 'matrix_data');
    fp = prepare_session_files({tmp});
    verifyTrue(testCase, isa(fp{1}, 'double'));
    verifyEqual(testCase, fp{1}, matrix_data);
end

function test_takes_first_field_like_load_single_session(testCase)
    tmp = [tempname '.mat'];
    cleanup = onCleanup(@() delete(tmp));
    zzz = uint8(ones(2, 4, 4));
    save(tmp, 'zzz');
    fp = prepare_session_files({tmp});
    verifyEqual(testCase, fp{1}, double(zzz));
end
