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

function test_experiment_names_the_folder(testCase)
    r = scan_input_folder(testCase.TestData.flat_dir);
    verifyEqual(testCase, r.experiment, 'BOWL');
end

function test_any_letters_and_digits_per_part(testCase)
    % Parts of any length; numbers in session names sort by value; a trial
    % part _<n>T belongs to the session; the rest after _ is ignored.
    tmp = make_empty({'Exp2_mouse12_day3.mat', 'Exp2_mouse12_day10.mat', ...
        'Exp2_mouse12_day2_filters.mat', 'Exp2_mouse12_day2_12T_filters.mat', ...
        'b7_M1_1.mat', 'b7_M1_2.mat'});
    cleanup = onCleanup(@() rmdir(tmp, 's'));
    r = scan_input_folder(tmp);
    verifyEmpty(testCase, r.unparsed);
    verifyEqual(testCase, {r.datasets.dataset_id}, {'Exp2_mouse12', 'b7_M1'});
    d = r.datasets(1);
    verifyEqual(testCase, {d.exp_id, d.mouse_id}, {'Exp2', 'mouse12'});
    verifyEqual(testCase, {d.sessions.session_id}, {'day2', 'day2_12T', 'day3', 'day10'});
    verifyEqual(testCase, r.experiment, 'Exp2+b7');
end

function test_names_off_the_rule_are_unparsed(testCase)
    bad = {'mouse3_day1.mat', 'CA-1_M01_1D.mat', 'CA1__1D.mat', 'CA1_M01_1D-a.mat', ...
        '_batch_results.mat'};
    tmp = make_empty(bad);
    cleanup = onCleanup(@() rmdir(tmp, 's'));
    r = scan_input_folder(tmp);
    verifyEqual(testCase, sort(r.unparsed), sort(bad));
    verifyEmpty(testCase, r.datasets);
    verifyEqual(testCase, r.experiment, '');
end

function tmp = make_empty(names)
    tmp = tempname; mkdir(tmp);
    for k = 1:numel(names)
        fid = fopen(fullfile(tmp, names{k}), 'w'); fclose(fid);
    end
end
