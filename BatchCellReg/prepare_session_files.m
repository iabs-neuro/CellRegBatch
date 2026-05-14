function spatial_footprints = prepare_session_files(file_paths)
%PREPARE_SESSION_FILES Load .mat files, silently casting first field to double.
%
%   Mirrors CellReg/load_single_session.m's first-field convention.
%   Returns a 1xN cell array of double NxYxX matrices.
    spatial_footprints = cell(1, numel(file_paths));
    for k = 1:numel(file_paths)
        tmp = load(file_paths{k});
        if isstruct(tmp)
            fields = fieldnames(tmp);
            data = tmp.(fields{1});
        else
            data = tmp;
        end
        if ~isa(data, 'double')
            data = double(data);
        end
        spatial_footprints{k} = data;
    end
end
