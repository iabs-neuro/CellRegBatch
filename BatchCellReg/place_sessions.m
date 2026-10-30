function p = place_sessions(sessions, names, expected)
%PLACE_SESSIONS Columns of one dataset's sessions in its cell map.
%   sessions: session ids of the dataset, in order.
%   names:    column names of the batch (second output of check_session_counts).
%   expected: expected number of sessions per dataset.
%
%   p.columns(j)  column of session j
%   p.n_columns   max(numel(sessions), expected)
%   p.missing     names of the zero columns, in column order
%   p.known       false if the sessions do not match the names: the zero
%                 columns are then the last ones and p.missing is {}.
%
%   Only a dataset with fewer sessions than expected gets zero columns. A
%   session matches a name exactly or without its _<n>T part, so that
%   1D_1T of one mouse takes the column 1D of the others.
    n = numel(sessions);
    p = struct('columns', 1:n, 'n_columns', max(n, expected), 'missing', {{}}, 'known', true);
    if ~(n < expected); return; end
    col = [];
    if numel(names) == expected
        col = match(sessions, names);
        if isempty(col); col = match(strip_trial(sessions), strip_trial(names)); end
    end
    if isempty(col)
        p.known = false;
        return
    end
    p.columns = col;
    p.missing = names(setdiff(1:expected, col));
end

function col = match(a, b)
    [found, col] = ismember(a, b);
    if ~all(found) || numel(unique(b)) < numel(b) || numel(unique(col)) < numel(col)
        col = [];
    end
end

function s = strip_trial(s)
    s = regexprep(s, '_\d+T$', '');
end
