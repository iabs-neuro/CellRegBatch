function [rows, names] = check_session_counts(scan, expected_n_sessions)
%CHECK_SESSION_COUNTS Compare each scanned dataset with the expected session count.
%   scan: output of scan_input_folder.
%   rows(k): dataset_id, n_sessions, ok (n_sessions == expected), missing
%   (names of the sessions this dataset does not have, see place_sessions),
%   extra (more sessions than expected), text (one line for the GUI and the log).
%   Skipped datasets get ok = true and their skip reason as text: they do
%   not run, so their session count does not matter.
%
%   names: the column names of the cell maps: the most common list of
%   session ids among the datasets with the expected number of sessions.
%   A union of all ids would be wrong: the mice of one experiment may name
%   their sessions differently (1D..5D, 1D_1T..5D_1T). With no such
%   dataset, the union of the ids if it has the expected size, else {}.
    run = scan.datasets(~[scan.datasets.skip]);
    names = batch_names(run, expected_n_sessions);

    rows = struct('dataset_id', {}, 'n_sessions', {}, 'ok', {}, ...
        'missing', {}, 'extra', {}, 'text', {});
    for k = 1:numel(scan.datasets)
        d = scan.datasets(k);
        ids = {d.sessions.session_id};
        n = numel(ids);
        p = place_sessions(ids, names, expected_n_sessions);
        r = struct('dataset_id', d.dataset_id, 'n_sessions', n, ...
            'ok', d.skip || n == expected_n_sessions, 'missing', {p.missing}, ...
            'extra', n > expected_n_sessions, 'text', '');
        if d.skip
            r.text = ['skipped: ' d.skip_reason];
        elseif r.ok
            r.text = 'OK';
        elseif r.extra
            r.text = sprintf('%d sessions, expected %d', n, expected_n_sessions);
        elseif p.known
            r.text = sprintf('%d of %d: no %s', n, expected_n_sessions, strjoin(p.missing, ', '));
        else
            r.text = sprintf('%d of %d: cannot tell which is missing', n, expected_n_sessions);
        end
        rows(end+1) = r; %#ok<AGROW>
    end
end

function names = batch_names(run, expected)
    names = {};
    lists = {};
    for d = run
        ids = {d.sessions.session_id};
        if numel(ids) == expected; lists{end+1} = strjoin(ids, char(1)); end %#ok<AGROW>
    end
    if ~isempty(lists)
        [u, ~, j] = unique(lists, 'stable');
        [~, best] = max(accumarray(j(:), 1));
        names = strsplit(u{best}, char(1));
        return
    end
    all_ids = {};
    for d = run; all_ids = [all_ids, {d.sessions.session_id}]; end %#ok<AGROW>
    all_ids = unique(all_ids);
    if numel(all_ids) == expected
        names = all_ids(natural_order(all_ids));
    end
end
