function rows = check_session_counts(scan, expected_n_sessions)
%CHECK_SESSION_COUNTS Compare each scanned dataset with the expected session count.
%   scan: output of scan_input_folder.
%   rows(k): dataset_id, n_sessions, ok (n_sessions == expected), missing
%   (session names of the batch that this dataset does not have), extra
%   (more sessions than expected), text (one line for the GUI and the log).
%   Skipped datasets get ok = true and their skip reason as text: they do
%   not run, so their session count does not matter.
    rows = struct('dataset_id', {}, 'n_sessions', {}, 'ok', {}, ...
        'missing', {}, 'extra', {}, 'text', {});
    for k = 1:numel(scan.datasets)
        d = scan.datasets(k);
        ids = {d.sessions.session_id};
        n = numel(ids);
        missing = setdiff(scan.session_names, ids);
        r = struct('dataset_id', d.dataset_id, 'n_sessions', n, ...
            'ok', d.skip || n == expected_n_sessions, 'missing', {missing}, ...
            'extra', n > expected_n_sessions, 'text', '');
        if d.skip
            r.text = ['skipped: ' d.skip_reason];
        elseif r.ok
            r.text = 'OK';
        elseif ~isempty(missing)
            r.text = sprintf('%d of %d: no %s', n, expected_n_sessions, strjoin(missing, ', '));
        else
            r.text = sprintf('%d sessions, expected %d', n, expected_n_sessions);
        end
        rows(end+1) = r; %#ok<AGROW>
    end
end
