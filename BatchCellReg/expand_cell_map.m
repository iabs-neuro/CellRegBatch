function full = expand_cell_map(map, sessions, session_names)
%EXPAND_CELL_MAP Place the columns of a cell map under the batch's session names.
%   map: cells x numel(sessions), as in cell_registered_struct.cell_to_index_map.
%   sessions: session ids of this dataset, one per column of map.
%   session_names: session ids of the whole batch (scan_input_folder).
%   full: cells x numel(session_names). A session this dataset does not
%   have becomes a column of zeros, so every cell map of the batch has the
%   same columns.
    [found, col] = ismember(sessions, session_names);
    if ~all(found)
        error('BatchCellReg:SessionNotInBatch', 'Session %s is not in the batch session list.', ...
            strjoin(sessions(~found), ', '));
    end
    full = zeros(size(map, 1), numel(session_names));
    full(:, col) = map;
end
