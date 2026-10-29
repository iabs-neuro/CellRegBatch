function spatial_footprints = prepare_session_files(file_paths)
%PREPARE_SESSION_FILES Load .mat files, silently casting first field to double.
%
%   Mirrors CellReg/load_single_session.m's first-field convention.
%   Returns a 1xN cell array of double NxYxX matrices. A file whose first
%   variable is not a 3-D numeric array stops the dataset with an error that
%   names the file; otherwise CellReg fails later with an index error that
%   does not say which file is wrong.
    spatial_footprints = cell(1, numel(file_paths));
    for k = 1:numel(file_paths)
        tmp = load(file_paths{k});
        name = '(none)';
        if isstruct(tmp)
            fields = fieldnames(tmp);
            if isempty(fields)
                error('BatchCellReg:BadInput', '%s contains no variable.', file_paths{k});
            end
            name = fields{1};
            data = tmp.(name);
        else
            data = tmp;
        end
        if ~(isnumeric(data) || islogical(data)) || ndims(data) ~= 3
            [~, f, e] = fileparts(file_paths{k});
            kind = class(data);
            if issparse(data); kind = ['sparse ' kind]; end
            error('BatchCellReg:BadInput', ['%s%s: the first variable, %s, is a %s %s. ' ...
                'Expected spatial footprints as a 3-D array, cells x height x width ' ...
                '(N x Y x X). A matrix of pixels x cells (for example CaImAn''s A) must be ' ...
                'reshaped first: see the manual, section 1.1.'], ...
                f, e, name, strjoin(arrayfun(@num2str, size(data), 'UniformOutput', false), 'x'), ...
                kind);
        end
        if ~isa(data, 'double')
            data = double(data);
        end
        spatial_footprints{k} = data;
    end
end
