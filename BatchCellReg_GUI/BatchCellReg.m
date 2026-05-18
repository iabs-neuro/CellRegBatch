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

    % build_*_tab already persisted a fully-merged `app` (with all `ui`
    % handles) into appdata via save_app. Read it back instead of writing the
    % original ui-less local struct, which would clobber every ui.* handle and
    % break Browse/Scan/Run.
    app = getappdata(app.fig, 'app');
end

function refocus(fig)
    %REFOCUS Bring the uifigure back to front. Java dialogs (uigetdir/
    % uigetfile/uiputfile) steal focus from uifigures and leave another window
    % active when they close; pull focus back so the GUI stays usable.
    drawnow;
    try
        figure(fig);
    catch
        fig.Visible = 'off';
        fig.Visible = 'on';
    end
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
    start = app.config.io.input_folder;
    if isempty(start) || ~exist(start, 'dir'); start = pwd; end
    d = uigetdir(start);
    refocus(fig);
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
    y = add_drop_disabled(t, 'Registration approach',   'cellreg.registration_approach',   y, ...
                 {'Probabilistic','Simple threshold'});
    y = add_drop_disabled(t, 'Initial registration',    'cellreg.initial_registration_type', y, ...
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

function y = add_drop_disabled(t, label, path, y, items)
    uilabel(t, 'Position', [20 y 220 22], 'Text', label);
    f = uidropdown(t, 'Position', [250 y 200 22], 'Items', items);
    f.Tag = path;
    f.ValueChangedFcn = @(s,e) set_path(ancestor(s, 'figure'), path, s.Value);
    f.Enable = 'off';
    f.Tooltip = 'Fixed in v1: GUI control reserved for future use';
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
    refocus(fig);
    if isnumeric(name); return; end
    app = getappdata(fig, 'app');
    app.config = config_from_json(fullfile(path, name));
    setappdata(fig, 'app', app);
    refresh_param_fields(fig);
end

function on_save_cfg(fig)
    [name, path] = uiputfile('*.json', 'Save config');
    refocus(fig);
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
    t = uitab(app.tabs, 'Title', 'Run & Results');

    uibutton(t, 'Position', [20 540 80 24], 'Text', 'Run batch', ...
        'ButtonPushedFcn', @(s,e) on_run(app.fig));
    uibutton(t, 'Position', [110 540 80 24], 'Text', 'Stop', ...
        'ButtonPushedFcn', @(s,e) on_stop(app.fig));
    app.ui.progress_label = uilabel(t, 'Position', [200 540 400 24], 'Text', 'idle');

    app.ui.log_area = uitextarea(t, 'Position', [20 320 840 200], 'Editable', 'off');

    app.ui.results_table = uitable(t, 'Position', [20 80 840 230], ...
        'ColumnName', results_table_headers(), ...
        'ColumnFormat', {'char','numeric','numeric','numeric','numeric', ...
                         'numeric','numeric','numeric','numeric','numeric','numeric', ...
                         'numeric','numeric','numeric','numeric','numeric','numeric'});

    uibutton(t, 'Position', [20 30 160 24], 'Text', 'Export results CSV', ...
        'ButtonPushedFcn', @(s,e) on_export(app.fig, 'results'));
    uibutton(t, 'Position', [190 30 160 24], 'Text', 'Export log TXT', ...
        'ButtonPushedFcn', @(s,e) on_export(app.fig, 'log'));
    uibutton(t, 'Position', [360 30 160 24], 'Text', 'Open output folder', ...
        'ButtonPushedFcn', @(s,e) on_open_out(app.fig));

    save_app(app);
    setappdata(app.fig, 'stop_requested', false);
end

function on_run(fig)
    app = getappdata(fig, 'app');
    folder = app.ui.input_edit.Value;
    if isempty(folder); uialert(fig, 'Choose an input folder first.', 'Run'); return; end
    setappdata(fig, 'stop_requested', false);

    selected = {};
    if ~isempty(app.ui.datasets_table.Data)
        rows = app.ui.datasets_table.Data;
        for k = 1:size(rows, 1)
            if rows{k, 1}; selected{end+1} = rows{k, 2}; end %#ok<AGROW>
        end
    end

    opts = struct();
    opts.live_log_callback = @(msg) append_log(fig, msg);
    opts.stop_check = @() getappdata(fig, 'stop_requested');
    opts.selected_datasets = selected;

    app.ui.progress_label.Text = 'running...';
    drawnow;
    summary = batch_run(folder, app.config, opts);
    app.ui.progress_label.Text = sprintf('done: %d ok, %d failed, %d warned', ...
        summary.n_succeeded, summary.n_failed, summary.n_with_warnings);

    app = getappdata(fig, 'app');
    app.last_summary = summary;
    setappdata(fig, 'app', app);
    fill_results_table(fig, summary);
end

function on_stop(fig)
    setappdata(fig, 'stop_requested', true);
end

function append_log(fig, msg)
    app = getappdata(fig, 'app');
    cur = app.ui.log_area.Value;
    if ischar(cur); cur = {cur}; end
    cur{end+1} = msg;
    if numel(cur) > 500; cur = cur(end-499:end); end
    app.ui.log_area.Value = cur;
    drawnow;
end

function fill_results_table(fig, summary)
    app = getappdata(fig, 'app');
    n = numel(summary.results);
    rows = cell(n, 17);
    for k = 1:n
        r = summary.results(k); f = summary.anomalies.flags(k);
        if numel(r.match_stats) >= 2; pct = r.match_stats(2)/max(r.match_stats(1),1);
        else; pct = NaN; end
        rows(k, :) = {r.dataset_id, numel(r.sessions), r.match_stats(1), pct, r.chosen_fpr, ...
            f.W1, f.W2, f.W2b_hard, f.W2b_rel, f.W3a, f.W3b, f.W4, f.W5a, f.W5b, f.W6a, f.W6b, f.W7};
    end
    app.ui.results_table.Data = rows;
    apply_severity_styles(app.ui.results_table, rows, 6:17);
end

function on_export(fig, which)
    app = getappdata(fig, 'app');
    if ~isfield(app, 'last_summary')
        uialert(fig, 'No run results yet.', 'Export'); return;
    end
    if strcmp(which, 'results')
        [n, p] = uiputfile('*.csv', 'Save results', '_batch_results.csv');
        refocus(fig);
        if isnumeric(n); return; end
        copyfile(app.last_summary.results_csv, fullfile(p, n));
    else
        [n, p] = uiputfile('*.txt', 'Save log', '_batch_log.txt');
        refocus(fig);
        if isnumeric(n); return; end
        copyfile(app.last_summary.log_file, fullfile(p, n));
    end
end

function on_open_out(fig)
    app = getappdata(fig, 'app');
    if isfield(app, 'last_summary')
        winopen(app.last_summary.output_dir);
    end
end

function names = results_table_headers()
%RESULTS_TABLE_HEADERS Two-line (code\nwords) column labels for results_table.
    m = anomaly_decode_map();
    wcodes = {'W1','W2','W2b_hard','W2b_rel','W3a','W3b','W4','W5a','W5b','W6a','W6b','W7'};
    wtags  = {'W1','W2','W2b_h','W2b_r','W3a','W3b','W4','W5a','W5b','W6a','W6b','W7'};
    names = {'Dataset','Sess','Cells','%match','FPR'};
    for k = 1:numel(wcodes)
        names{end+1} = sprintf('%s\n%s', wtags{k}, m(wcodes{k}).short); %#ok<AGROW>
    end
end

function apply_severity_styles(tbl, rows, wcols)
%APPLY_SEVERITY_STYLES Color W cells: 2=red, 1=yellow. R2020a-safe.
    try
        removeStyle(tbl);
        redS = uistyle('BackgroundColor', [1 0.6 0.6]);
        yelS = uistyle('BackgroundColor', [1 1 0.6]);
        for rr = 1:size(rows, 1)
            for cc = wcols
                v = rows{rr, cc};
                if isequal(v, 2)
                    addStyle(tbl, redS, 'cell', [rr cc]);
                elseif isequal(v, 1)
                    addStyle(tbl, yelS, 'cell', [rr cc]);
                end
            end
        end
    catch
    end
end
