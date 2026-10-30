function tests = test_check_session_counts
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', '..', 'BatchCellReg')));
end

function scan = make_scan(varargin)
    % varargin: pairs of dataset id and session ids; a third element 'skip'.
    sess = @(ids) struct('session_id', ids, 'file_path', '');
    scan.datasets = struct('dataset_id', {}, 'sessions', {}, 'skip', {}, 'skip_reason', {});
    for k = 1:numel(varargin)
        a = varargin{k};
        skip = numel(a) > 2;
        reason = ''; if skip; reason = 'fewer than 2 sessions'; end
        scan.datasets(end+1) = struct('dataset_id', a{1}, 'sessions', sess(a{2}), ...
            'skip', skip, 'skip_reason', reason);
    end
end

function test_marks_datasets_off_the_expected_count(tc)
    scan = make_scan({'A', {'1D', '2D', '3D'}}, {'B', {'1D', '3D'}}, ...
        {'C', {'1D', '2D', '3D', '4D'}}, {'S', {'1D'}, 'skip'});
    [c, names] = check_session_counts(scan, 3);
    verifyEqual(tc, names, {'1D', '2D', '3D'});
    verifyEqual(tc, {c.dataset_id}, {'A', 'B', 'C', 'S'});
    verifyEqual(tc, [c.ok], [true false false true]);
    verifyEqual(tc, c(2).missing, {'2D'});
    verifyEqual(tc, c(2).text, '2 of 3: no 2D');
    verifyTrue(tc, c(3).extra);
    verifyEqual(tc, c(3).text, '4 sessions, expected 3');
    verifyMatches(tc, c(4).text, '^skipped');
end

function test_mice_may_name_sessions_differently(tc)
    % As in the HOS experiment: most mice 1D..3D, some 1D_1T..3D_1T. The
    % columns are the most common names; nobody misses a session.
    scan = make_scan({'A', {'1D', '2D', '3D'}}, {'B', {'1D_1T', '2D_1T', '3D_1T'}}, ...
        {'C', {'1D', '2D', '3D'}}, {'D', {'1D_1T', '3D_1T'}});
    [c, names] = check_session_counts(scan, 3);
    verifyEqual(tc, names, {'1D', '2D', '3D'});
    verifyEqual(tc, [c.ok], [true true true false]);
    verifyEqual(tc, c(4).text, '2 of 3: no 2D');
end

function test_union_when_no_dataset_is_complete(tc)
    scan = make_scan({'A', {'1D', '2D'}}, {'B', {'2D', '10D'}});
    [c, names] = check_session_counts(scan, 3);
    verifyEqual(tc, names, {'1D', '2D', '10D'});
    verifyEqual(tc, c(2).text, '2 of 3: no 1D');
end

function test_unknown_columns(tc)
    scan = make_scan({'A', {'1D', '2D'}}, {'B', {'x', 'y'}});
    [c, names] = check_session_counts(scan, 3);
    verifyEmpty(tc, names);
    verifyEqual(tc, c(1).text, '2 of 3: cannot tell which is missing');
end

function test_empty_scan(tc)
    [c, names] = check_session_counts(make_scan(), 3);
    verifyEmpty(tc, c);
    verifyEmpty(tc, names);
end
