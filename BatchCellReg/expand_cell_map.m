function full = expand_cell_map(map, columns, n_columns)
%EXPAND_CELL_MAP Place the columns of a cell map in the batch layout.
%   map: cells x sessions, as in cell_registered_struct.cell_to_index_map.
%   columns, n_columns: from place_sessions. Column j of map goes to column
%   columns(j) of full; the other columns of full are zeros. So a dataset
%   with a missing session has a zero column there, and every cell map of
%   the batch has the same number of columns.
    full = zeros(size(map, 1), n_columns);
    full(:, columns) = map;
end
