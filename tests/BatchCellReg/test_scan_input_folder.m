function tests = test_scan_input_folder
    tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    here = fileparts(mfilename('fullpath'));
    addpath(genpath(fullfile(here, '..', '..', 'BatchCellReg')));
    addpath(fullfile(here, 'fixtures'));
    testCase.TestData.flat_dir = make_fixtures();
end

function test_groups_datasets_by_exp_mouse(testCase)
    r = scan_input_folder(testCase.TestData.flat_dir);
    ids = {r.datasets.dataset_id};
    verifyTrue(testCase, ismember('BOWL_D01', ids));
    verifyTrue(testCase, ismember('BOWL_D03', ids));
    verifyTrue(testCase, ismember('BOWL_D05', ids));
end

function test_sessions_are_alphabetical(testCase)
    r = scan_input_folder(testCase.TestData.flat_dir);
    d01 = r.datasets(strcmp({r.datasets.dataset_id}, 'BOWL_D01'));
    session_ids = {d01.sessions.session_id};
    verifyEqual(testCase, session_ids, {'1D', '2D', '3D'});
end

function test_single_session_dataset_flagged(testCase)
    r = scan_input_folder(testCase.TestData.flat_dir);
    d05 = r.datasets(strcmp({r.datasets.dataset_id}, 'BOWL_D05'));
    verifyTrue(testCase, d05.skip);
    verifyMatches(testCase, d05.skip_reason, 'sessions');
end

function test_unparsed_files_listed(testCase)
    r = scan_input_folder(testCase.TestData.flat_dir);
    verifyTrue(testCase, any(contains(r.unparsed, 'README.mat')));
end

function test_duplicate_session_id_is_error(testCase)
    tmp = tempname; mkdir(tmp);
    cleanup = onCleanup(@() rmdir(tmp, 's'));
    A = uint8(zeros(2,4,4));
    save(fullfile(tmp, 'X_M01_1D_a.mat'), 'A');
    save(fullfile(tmp, 'X_M01_1D_b.mat'), 'A');
    r = scan_input_folder(tmp);
    d = r.datasets(strcmp({r.datasets.dataset_id}, 'X_M01'));
    verifyTrue(testCase, d.skip);
    verifyMatches(testCase, d.skip_reason, 'duplicate');
end

function test_session_names_are_the_union_of_run_datasets(testCase)
    % D05 is skipped (one session), so its sessions do not count.
    r = scan_input_folder(testCase.TestData.flat_dir);
    ids = {};
    for d = r.datasets(~[r.datasets.skip])
        ids = [ids, {d.sessions.session_id}]; %#ok<AGROW>
    end
    verifyEqual(testCase, r.session_names, unique(ids));
end
