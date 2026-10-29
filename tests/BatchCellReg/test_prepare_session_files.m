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

function test_pixels_by_cells_matrix_is_refused_with_file_name(testCase)
    % A CaImAn-style A (pixels x cells) must stop with a message that names
    % the file, not with a CellReg index error later.
    tmp = [tempname '.mat'];
    cleanup = onCleanup(@() delete(tmp));
    A = sparse(64, 3);
    save(tmp, 'A');
    [~, f] = fileparts(tmp);
    try
        prepare_session_files({tmp});
        verifyFail(testCase, 'no error');
    catch ME
        verifyEqual(testCase, ME.identifier, 'BatchCellReg:BadInput');
        verifySubstring(testCase, ME.message, f);
        verifySubstring(testCase, ME.message, '64x3 sparse double');
    end
end

function test_takes_first_field_like_load_single_session(testCase)
    tmp = [tempname '.mat'];
    cleanup = onCleanup(@() delete(tmp));
    zzz = uint8(ones(2, 4, 4));
    save(tmp, 'zzz');
    fp = prepare_session_files({tmp});
    verifyEqual(testCase, fp{1}, double(zzz));
end
