function tests = test_check_session_counts
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', '..', 'BatchCellReg')));
end

function scan = make_scan()
    sess = @(ids) struct('session_id', ids, 'file_path', '');
    d = @(id, ids, skip, reason) struct('dataset_id', id, 'sessions', sess(ids), ...
        'skip', skip, 'skip_reason', reason);
    scan.datasets = [d('A', {'1D', '2D', '3D'}, false, ''), ...
                     d('B', {'1D', '3D'}, false, ''), ...
                     d('C', {'1D', '2D', '3D', '4D'}, false, ''), ...
                     d('S', {'1D'}, true, 'fewer than 2 sessions')];
    scan.session_names = {'1D', '2D', '3D', '4D'};
end

function test_marks_datasets_off_the_expected_count(tc)
    c = check_session_counts(make_scan(), 3);
    verifyEqual(tc, {c.dataset_id}, {'A', 'B', 'C', 'S'});
    verifyEqual(tc, [c.ok], [true false false true]);
    verifyEqual(tc, c(2).missing, {'2D', '4D'});
    verifyEqual(tc, c(2).text, '2 of 3: no 2D, 4D');
    verifyTrue(tc, c(3).extra);
    verifyMatches(tc, c(4).text, '^skipped');
end

function test_all_ok(tc)
    c = check_session_counts(make_scan(), 4);
    verifyEqual(tc, [c.ok], [false false true true]);
    verifyEqual(tc, c(3).text, 'OK');
end
