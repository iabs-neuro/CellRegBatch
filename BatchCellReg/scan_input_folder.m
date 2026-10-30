function result = scan_input_folder(input_folder)
%SCAN_INPUT_FOLDER Group .mat session files by (experiment, mouse).
%
%   File names: <EXP>_<MOUSE>_<SESSION>[_<n>T][_<anything>].mat, where EXP,
%   MOUSE and SESSION are letters and digits only. An optional _<n>T part
%   (trial) belongs to the session id; the rest is ignored.
%
%   result.datasets(k).dataset_id           '<EXP>_<MOUSE>'
%   result.datasets(k).exp_id
%   result.datasets(k).mouse_id
%   result.datasets(k).sessions(j).session_id  '1D' / '1D_1T' / 'day10' ...
%   result.datasets(k).sessions(j).file_path
%   result.datasets(k).skip                 logical
%   result.datasets(k).skip_reason          string
%   result.experiment                       the experiment names of the
%                                           folder joined by '+'; the batch
%                                           output files start with it
%   result.unparsed                         cellstr of filenames
%
%   Datasets and sessions are in natural order (natural_order): session 2D
%   comes before 10D.

    pattern = '^([A-Za-z0-9]+)_([A-Za-z0-9]+)_([A-Za-z0-9]+)(_\d+T)?(_.*)?\.mat$';

    listing = dir(fullfile(input_folder, '*.mat'));
    parsed = struct('exp', {}, 'mouse', {}, 'session_id', {}, ...
        'file_path', {}, 'name', {});
    unparsed = {};

    for k = 1:numel(listing)
        name = listing(k).name;
        tok = regexp(name, pattern, 'tokens', 'once');
        if isempty(tok)
            unparsed{end+1} = name; %#ok<AGROW>
            continue
        end
        parsed(end+1) = struct( ...
            'exp', tok{1}, 'mouse', tok{2}, 'session_id', [tok{3} tok{4}], ...
            'file_path', fullfile(input_folder, name), 'name', name); %#ok<AGROW>
    end

    % Sort by experiment, mouse, session, then file name; char(1) sorts
    % before any character of a name, so the parts compare one by one.
    if ~isempty(parsed)
        keys = arrayfun(@(p) strjoin({p.exp, p.mouse, p.session_id, p.name}, char(1)), ...
            parsed, 'UniformOutput', false);
        parsed = parsed(natural_order(keys));
    end

    % Group by (exp, mouse).
    datasets = struct('dataset_id', {}, 'exp_id', {}, 'mouse_id', {}, ...
        'sessions', {}, 'skip', {}, 'skip_reason', {});
    seen = containers.Map();
    for k = 1:numel(parsed)
        key = [parsed(k).exp '_' parsed(k).mouse];
        if ~isKey(seen, key)
            seen(key) = numel(datasets) + 1;
            datasets(end+1) = struct( ...
                'dataset_id', key, 'exp_id', parsed(k).exp, ...
                'mouse_id', parsed(k).mouse, 'sessions', struct( ...
                    'session_id', {}, 'file_path', {}), ...
                'skip', false, 'skip_reason', ''); %#ok<AGROW>
        end
        idx = seen(key);
        datasets(idx).sessions(end+1) = struct( ...
            'session_id', parsed(k).session_id, ...
            'file_path', parsed(k).file_path);
    end

    % Validate: duplicate session_id, <2 sessions.
    for k = 1:numel(datasets)
        ids = {datasets(k).sessions.session_id};
        if numel(unique(ids)) < numel(ids)
            datasets(k).skip = true;
            datasets(k).skip_reason = 'duplicate session ids';
        elseif numel(ids) < 2
            datasets(k).skip = true;
            datasets(k).skip_reason = 'fewer than 2 sessions';
        end
    end

    experiment = '';
    if ~isempty(datasets); experiment = strjoin(unique({datasets.exp_id}), '+'); end
    result = struct('datasets', datasets, 'experiment', experiment, ...
        'unparsed', {unparsed});
end
