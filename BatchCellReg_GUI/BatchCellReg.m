function app = BatchCellReg()
%BATCHCELLREG Launch the batch wrapper GUI.
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', 'BatchCellReg')));
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', 'CellReg')));
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', 'Helper')));

    app = struct();
    app.config = batch_default_config();
    app.scan = [];

    app.fig = uifigure('Name', 'Batch CellReg', 'Position', [100 100 900 600]);
    app.tabs = uitabgroup(app.fig, 'Position', [10 10 880 580]);

    build_setup_tab(app);
    build_parameters_tab(app);
    build_run_tab(app);

    setappdata(app.fig, 'app', app);
end

function build_setup_tab(app)
    t = uitab(app.tabs, 'Title', 'Setup');
    uilabel(t, 'Position', [20 540 100 22], 'Text', 'Input folder:');
    app.ui.input_edit = uieditfield(t, 'text', 'Position', [120 540 500 22]);
    uibutton(t, 'Position', [630 540 80 22], 'Text', 'Browse...', ...
        'ButtonPushedFcn', @(s,e) on_browse(app.fig));
    uibutton(t, 'Position', [720 540 80 22], 'Text', 'Scan', ...
        'ButtonPushedFcn', @(s,e) on_scan(app.fig));

    app.ui.output_label = uilabel(t, 'Position', [20 510 800 22], ...
        'Text', 'Output: <choose folder first>');

    app.ui.datasets_table = uitable(t, 'Position', [20 60 840 440], ...
        'ColumnName', {'Run','Dataset','# sessions','sessions'}, ...
        'ColumnEditable', [true false false false]);

    app.ui.unparsed_label = uilabel(t, 'Position', [20 30 800 22], 'Text', 'Unparsed files: 0');

    save_app(app);
end

function save_app(app)
    %SAVE_APP Merge `app` into the figure's appdata, preserving fields written
    % by other build_*_tab functions. ui sub-fields are merged, not replaced.
    if isfield(getappdata(app.fig), 'app') %#ok<GFLD>
        prev = getappdata(app.fig, 'app');
        if isfield(prev, 'ui') && isfield(app, 'ui')
            fns = fieldnames(prev.ui);
            for k = 1:numel(fns)
                if ~isfield(app.ui, fns{k})
                    app.ui.(fns{k}) = prev.ui.(fns{k});
                end
            end
        end
    end
    setappdata(app.fig, 'app', app);
end

function on_browse(fig)
    app = getappdata(fig, 'app');
    d = uigetdir(app.config.io.input_folder);
    if isnumeric(d) && d == 0; return; end
    app.config.io.input_folder = d;
    app.ui.input_edit.Value = d;
    app.ui.output_label.Text = ['Output: ' fullfile(d, app.config.io.output_subfolder_name)];
    setappdata(fig, 'app', app);
end

function on_scan(fig)
    app = getappdata(fig, 'app');
    folder = app.ui.input_edit.Value;
    if isempty(folder) || ~exist(folder, 'dir')
        uialert(fig, 'Input folder is empty or does not exist.', 'Scan');
        return
    end
    app.scan = scan_input_folder(folder);
    rows = {};
    for k = 1:numel(app.scan.datasets)
        d = app.scan.datasets(k);
        sids = strjoin({d.sessions.session_id}, ', ');
        rows(end+1, :) = {~d.skip, d.dataset_id, numel(d.sessions), sids}; %#ok<AGROW>
    end
    app.ui.datasets_table.Data = rows;
    app.ui.unparsed_label.Text = sprintf('Unparsed files: %d', numel(app.scan.unparsed));
    setappdata(fig, 'app', app);
end

function build_parameters_tab(app)
    t = uitab(app.tabs, 'Title', 'Parameters');
    y = 530;

    y = section_header(t, 'CellReg core', y);
    y = add_num (t, 'Microns per pixel',       'cellreg.microns_per_pixel',       y);
    y = add_drop(t, 'Alignment type',          'cellreg.alignment_type',          y, ...
                 {'Translations','Translations and Rotations','Non-rigid'});
    y = add_num (t, 'Maximal rotation (deg)',  'cellreg.maximal_rotation',        y);
    y = add_num (t, 'Reference session',       'cellreg.reference_session_index', y);
    y = add_num (t, 'Maximal distance (um)',   'cellreg.maximal_distance_um',     y);
    y = add_drop(t, 'Registration approach',   'cellreg.registration_approach',   y, ...
                 {'Probabilistic','Simple threshold'});
    y = add_drop(t, 'Initial registration',    'cellreg.initial_registration_type', y, ...
                 {'auto','Spatial correlation','Centroid distance'});

    y = section_header(t, 'P_same auto-tune', y);
    y = add_num (t, 'FPR max',                 'p_same_tuning.fpr_max',           y);

    y = section_header(t, 'Anomaly thresholds', y);
    y = add_num (t, 'z-score threshold',       'anomaly_thresholds.z_threshold',  y);
    y = add_num (t, 'Max translation (px)',    'anomaly_thresholds.max_translation_px', y);
    y = add_num (t, 'Min cross-correlation',   'anomaly_thresholds.min_xcorr',    y);
    y = add_num (t, 'Max model MSE',           'anomaly_thresholds.max_mse',      y);

    y = section_header(t, 'I/O', y);
    y = add_bool(t, 'Write to file',           'cellreg.write_to_file',           y);
    y = add_drop(t, 'Figures visibility',      'cellreg.figures_visibility',      y, {'off','on'});
    y = add_bool(t, 'Use parallel processing', 'cellreg.use_parallel_processing', y);

    uibutton(t, 'Position', [20 20 120 24], 'Text', 'Load config...', ...
        'ButtonPushedFcn', @(s,e) on_load_cfg(ancestor(s, 'figure')));
    uibutton(t, 'Position', [150 20 120 24], 'Text', 'Save config as...', ...
        'ButtonPushedFcn', @(s,e) on_save_cfg(ancestor(s, 'figure')));
    uibutton(t, 'Position', [280 20 140 24], 'Text', 'Reset to defaults', ...
        'ButtonPushedFcn', @(s,e) on_reset_cfg(ancestor(s, 'figure')));
end

function y = section_header(t, label, y)
    uilabel(t, 'Position', [20 y 800 22], 'Text', label, 'FontWeight', 'bold');
    y = y - 28;
end

function y = add_num(t, label, path, y)
    uilabel(t, 'Position', [20 y 220 22], 'Text', label);
    f = uieditfield(t, 'numeric', 'Position', [250 y 100 22]);
    f.Tag = path;
    f.ValueChangedFcn = @(s,e) set_path(ancestor(s, 'figure'), path, s.Value);
    sync_field_from_config(f);
    y = y - 26;
end

function y = add_bool(t, label, path, y)
    uilabel(t, 'Position', [20 y 220 22], 'Text', label);
    f = uicheckbox(t, 'Position', [250 y 200 22], 'Text', '');
    f.Tag = path;
    f.ValueChangedFcn = @(s,e) set_path(ancestor(s, 'figure'), path, s.Value);
    sync_field_from_config(f);
    y = y - 26;
end

function y = add_drop(t, label, path, y, items)
    uilabel(t, 'Position', [20 y 220 22], 'Text', label);
    f = uidropdown(t, 'Position', [250 y 200 22], 'Items', items);
    f.Tag = path;
    f.ValueChangedFcn = @(s,e) set_path(ancestor(s, 'figure'), path, s.Value);
    sync_field_from_config(f);
    y = y - 26;
end

function sync_field_from_config(f)
    fig = ancestor(f, 'figure');
    app = getappdata(fig, 'app');
    v = get_path(app.config, f.Tag);
    if ~isempty(v); f.Value = v; end
end

function set_path(fig, path, value)
    app = getappdata(fig, 'app');
    parts = strsplit(path, '.');
    app.config = setfield_deep(app.config, parts, value);
    setappdata(fig, 'app', app);
end

function v = get_path(s, path)
    parts = strsplit(path, '.');
    v = s;
    for k = 1:numel(parts)
        if isfield(v, parts{k}); v = v.(parts{k}); else; v = []; return; end
    end
end

function s = setfield_deep(s, parts, value)
    if numel(parts) == 1
        s.(parts{1}) = value;
    else
        inner = struct();
        if isfield(s, parts{1}); inner = s.(parts{1}); end
        s.(parts{1}) = setfield_deep(inner, parts(2:end), value);
    end
end

function on_load_cfg(fig)
    [name, path] = uigetfile('*.json', 'Load config');
    if isnumeric(name); return; end
    app = getappdata(fig, 'app');
    app.config = config_from_json(fullfile(path, name));
    setappdata(fig, 'app', app);
    refresh_param_fields(fig);
end

function on_save_cfg(fig)
    [name, path] = uiputfile('*.json', 'Save config');
    if isnumeric(name); return; end
    app = getappdata(fig, 'app');
    config_to_json(app.config, fullfile(path, name));
end

function on_reset_cfg(fig)
    app = getappdata(fig, 'app');
    app.config = batch_default_config();
    setappdata(fig, 'app', app);
    refresh_param_fields(fig);
end

function refresh_param_fields(fig)
    children = findall(fig, 'Type', 'uieditfield');
    children = [children; findall(fig, 'Type', 'uicheckbox')];
    children = [children; findall(fig, 'Type', 'uidropdown')];
    for k = 1:numel(children)
        if ~isempty(children(k).Tag)
            sync_field_from_config(children(k));
        end
    end
end

function build_run_tab(app)
    uitab(app.tabs, 'Title', 'Run & Results');  % implemented in Task 14
end
