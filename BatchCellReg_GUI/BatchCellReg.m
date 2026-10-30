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

function info_button(parent, pos, key, ttl)
    %INFO_BUTTON A "?" button that explains one field (text: parameter_info).
    uibutton(parent, 'Position', pos, 'Text', '?', 'FontWeight', 'bold', ...
        'Tooltip', 'What is this?', ...
        'ButtonPushedFcn', @(s,e) show_info(ancestor(s, 'figure'), key, ttl));
end

function show_info(fig, key, ttl)
    m = parameter_info();
    if isKey(m, key); txt = m(key); else; txt = 'No help text for this field.'; end
    uialert(fig, txt, ttl, 'Icon', 'info');
end

function build_setup_tab(app)
    t = uitab(app.tabs, 'Title', 'Setup');
    % Keep the top row below y+h = 550: the tab header takes ~25 px of the
    % 580 px tab group, and anything higher is clipped.
    uilabel(t, 'Position', [20 525 100 22], 'Text', 'Input folder:');
    app.ui.input_edit = uieditfield(t, 'text', 'Position', [120 525 500 22]);
    uibutton(t, 'Position', [630 525 80 22], 'Text', 'Browse...', ...
        'ButtonPushedFcn', @(s,e) on_browse(app.fig));
    uibutton(t, 'Position', [720 525 80 22], 'Text', 'Scan', ...
        'ButtonPushedFcn', @(s,e) on_scan(app.fig));
    info_button(t, [810 525 22 22], 'input_folder', 'Input folder');

    app.ui.output_label = uilabel(t, 'Position', [20 497 800 22], ...
        'Text', 'Output: <choose folder first>');

    uilabel(t, 'Position', [20 469 190 22], 'Text', 'Expected sessions per mouse:');
    f = uieditfield(t, 'numeric', 'Position', [210 469 50 22], ...
        'Limits', [1 Inf], 'RoundFractionalValues', 'on', ...
        'Value', app.config.cellreg.expected_n_sessions);
    % Same config field as the JSON file: Load config and Reset update it.
    f.Tag = 'cellreg.expected_n_sessions';
    f.ValueChangedFcn = @(s,e) on_expected_changed(ancestor(s, 'figure'), s.Value);
    info_button(t, [265 469 22 22], 'cellreg.expected_n_sessions', 'Expected sessions');

    app.ui.session_check_label = uilabel(t, 'Position', [20 443 840 22], ...
        'Text', 'Scan the folder to check the session count of each dataset.');

    app.ui.datasets_table = uitable(t, 'Position', [20 60 840 378], ...
        'ColumnName', {'Run','Dataset','# sessions','Sessions','Check'}, ...
        'ColumnWidth', {40, 120, 75, 330, 'auto'}, ...
        'ColumnFormat', {'logical', 'char', 'shortG', 'char', 'char'}, ...
        'ColumnEditable', [true false false false false]);

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
        rows(end+1, :) = {~d.skip, d.dataset_id, numel(d.sessions), sids, ''}; %#ok<AGROW>
    end
    app.ui.datasets_table.Data = rows;
    app.ui.unparsed_label.Text = sprintf('Unparsed files: %d', numel(app.scan.unparsed));
    setappdata(fig, 'app', app);
    update_session_check(fig);
end

function on_expected_changed(fig, value)
    set_path(fig, 'cellreg.expected_n_sessions', value);
    update_session_check(fig);
end

function update_session_check(fig)
    %UPDATE_SESSION_CHECK Fill the Check column and the summary line.
    app = getappdata(fig, 'app');
    if isempty(app.scan) || isempty(app.scan.datasets); return; end
    expected = app.config.cellreg.expected_n_sessions;
    [checks, columns] = check_session_counts(app.scan, expected);
    tbl = app.ui.datasets_table;
    rows = tbl.Data;
    for k = 1:numel(checks); rows{k, 5} = checks(k).text; end
    tbl.Data = rows;
    bad = find(~[checks.ok]);
    try
        removeStyle(tbl);
        if ~isempty(bad)
            addStyle(tbl, uistyle('BackgroundColor', [1 0.75 0.75]), 'cell', [bad(:), 5 * ones(numel(bad), 1)]);
        end
    catch
        % uistyle needs R2019b; the Check text still says what is wrong.
    end
    names = strjoin(columns, ', ');
    if isempty(names); names = sprintf('not known (no dataset has %d sessions)', expected); end
    n_run = sum(~[app.scan.datasets.skip]);
    if isempty(bad)
        txt = sprintf('Cell map columns: %s. All %d datasets have %d sessions.', ...
            names, n_run, expected);
    else
        txt = sprintf(['Cell map columns: %s. %d of %d datasets do not have %d ' ...
            'sessions: they will be matched and get a red Sessions warning.'], ...
            names, numel(bad), n_run, expected);
    end
    app.ui.session_check_label.Text = txt;
    if isempty(bad)
        app.ui.session_check_label.FontColor = [0 0 0];
    else
        app.ui.session_check_label.FontColor = [0.75 0 0];
    end
end

function build_parameters_tab(app)
    t = uitab(app.tabs, 'Title', 'Parameters');
    y = 525;

    y = section_header(t, 'CellReg core', 20, y);
    y = add_num (t, 'Microns per pixel',       'cellreg.microns_per_pixel',       y);
    y = add_drop(t, 'Alignment type',          'cellreg.alignment_type',          y, ...
                 {'Translations','Translations and Rotations','Non-rigid'});
    y = add_num (t, 'Maximal rotation (deg)',  'cellreg.maximal_rotation',        y);
    y = add_num (t, 'Reference session',       'cellreg.reference_session_index', y);
    y = add_num (t, 'Maximal distance (um)',   'cellreg.maximal_distance_um',     y);
    y = add_num (t, 'Alignment gate (min. xcorr)', 'cellreg.alignment_min_xcorr', y);
    y = add_drop(t, 'Registration model',      'cellreg.initial_registration_type', y, ...
                 {'auto','Spatial correlation','Centroid distance'});
    y = add_drop_disabled(t, 'Registration approach', 'cellreg.registration_approach', y, ...
                 {'Probabilistic','Simple threshold'});

    y = section_header(t, 'P_same auto-tune', 20, y);
    y = add_num (t, 'FPR max',                 'p_same_tuning.fpr_max',           y);

    y = section_header(t, 'I/O', 20, y);
    y = add_bool(t, 'Write to file',           'cellreg.write_to_file',           y);
    y = add_drop(t, 'Figures visibility',      'cellreg.figures_visibility',      y, {'off','on'});
    add_bool(t, 'Use parallel processing',     'cellreg.use_parallel_processing', y);

    % Right column: warning thresholds, one row per rule (yellow, red).
    y = section_header(t, 'Warning thresholds', 495, 525);
    uilabel(t, 'Position', [695 y 55 22], 'Text', 'yellow', 'HorizontalAlignment', 'center');
    uilabel(t, 'Position', [760 y 55 22], 'Text', 'red', 'HorizontalAlignment', 'center');
    y = y - 26;
    y = add_pair(t, 'Few cells: median per session <', 'few_cells', y);
    y = add_pair(t, 'Cell drop: worst / median <',     'cell_drop', y);
    y = add_pair(t, 'Alignment: cross-correlation <',  'xcorr',     y);
    y = add_pair(t, 'Alignment: shift (px) >',         'shift',     y);
    y = add_pair(t, 'Model fit: MSE >',                'mse',       y);
    y = add_pair(t, 'Low match: z below batch >',      'match_z',   y);
    y = add_pair(t, 'Low match: session link <',       'session_link', y);
    uilabel(t, 'Position', [495 y 360 22], 'FontColor', [0.3 0.3 0.3], ...
        'Text', 'Sessions: set "Expected sessions" on the Setup tab.');

    uibutton(t, 'Position', [20 20 120 24], 'Text', 'Load config...', ...
        'ButtonPushedFcn', @(s,e) on_load_cfg(ancestor(s, 'figure')));
    uibutton(t, 'Position', [150 20 120 24], 'Text', 'Save config as...', ...
        'ButtonPushedFcn', @(s,e) on_save_cfg(ancestor(s, 'figure')));
    uibutton(t, 'Position', [280 20 140 24], 'Text', 'Reset to defaults', ...
        'ButtonPushedFcn', @(s,e) on_reset_cfg(ancestor(s, 'figure')));
end

function y = section_header(t, label, x, y)
    uilabel(t, 'Position', [x y 360 22], 'Text', label, 'FontWeight', 'bold');
    y = y - 28;
end

function y = add_num(t, label, path, y)
    uilabel(t, 'Position', [20 y 220 22], 'Text', label);
    f = uieditfield(t, 'numeric', 'Position', [250 y 100 22]);
    f.Tag = path;
    f.ValueChangedFcn = @(s,e) set_path(ancestor(s, 'figure'), path, s.Value);
    sync_field_from_config(f);
    info_button(t, [455 y 22 22], path, label);
    y = y - 26;
end

function y = add_pair(t, label, rule, y)
    %ADD_PAIR One warning rule: yellow and red limit fields side by side.
    % The shift rule has a yellow limit only.
    uilabel(t, 'Position', [495 y 195 22], 'Text', label);
    if strcmp(rule, 'shift')
        paths = {'anomaly_thresholds.shift_yellow_px'};
    else
        paths = {['anomaly_thresholds.' rule '_yellow'], ['anomaly_thresholds.' rule '_red']};
    end
    xs = [695 760];
    for k = 1:numel(paths)
        f = uieditfield(t, 'numeric', 'Position', [xs(k) y 55 22]);
        f.Tag = paths{k};
        p = paths{k};
        f.ValueChangedFcn = @(s,e) set_path(ancestor(s, 'figure'), p, s.Value);
        sync_field_from_config(f);
    end
    info_button(t, [822 y 22 22], paths{1}, label);
    y = y - 26;
end

function y = add_bool(t, label, path, y)
    uilabel(t, 'Position', [20 y 220 22], 'Text', label);
    f = uicheckbox(t, 'Position', [250 y 200 22], 'Text', '');
    f.Tag = path;
    f.ValueChangedFcn = @(s,e) set_path(ancestor(s, 'figure'), path, s.Value);
    sync_field_from_config(f);
    info_button(t, [455 y 22 22], path, label);
    y = y - 26;
end

function y = add_drop(t, label, path, y, items)
    uilabel(t, 'Position', [20 y 220 22], 'Text', label);
    f = uidropdown(t, 'Position', [250 y 200 22], 'Items', items);
    f.Tag = path;
    f.ValueChangedFcn = @(s,e) set_path(ancestor(s, 'figure'), path, s.Value);
    sync_field_from_config(f);
    info_button(t, [455 y 22 22], path, label);
    y = y - 26;
end

function y = add_drop_disabled(t, label, path, y, items)
    uilabel(t, 'Position', [20 y 220 22], 'Text', label);
    f = uidropdown(t, 'Position', [250 y 200 22], 'Items', items);
    f.Tag = path;
    f.ValueChangedFcn = @(s,e) set_path(ancestor(s, 'figure'), path, s.Value);
    f.Enable = 'off';
    f.Tooltip = 'The batch supports the probabilistic approach only';
    sync_field_from_config(f);
    info_button(t, [455 y 22 22], path, label);
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
    try
        app.config = config_from_json(fullfile(path, name));
    catch ME
        uialert(fig, ME.message, 'Load config');
        return
    end
    setappdata(fig, 'app', app);
    refresh_param_fields(fig);
    update_session_check(fig);
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
    update_session_check(fig);
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

    uibutton(t, 'Position', [20 524 80 24], 'Text', 'Run batch', ...
        'ButtonPushedFcn', @(s,e) on_run(app.fig));
    uibutton(t, 'Position', [110 524 70 24], 'Text', 'Stop', ...
        'ButtonPushedFcn', @(s,e) on_stop(app.fig));
    uibutton(t, 'Position', [190 524 140 24], 'Text', 'Load results CSV...', ...
        'ButtonPushedFcn', @(s,e) on_load_results(app.fig));
    app.ui.progress_label = uilabel(t, 'Position', [340 524 500 24], 'Text', 'idle');

    app.ui.log_area = uitextarea(t, 'Position', [20 320 840 194], 'Editable', 'off');

    headers = results_table_headers();
    app.ui.results_table = uitable(t, 'Position', [20 102 840 210], ...
        'ColumnName', headers, ...
        'ColumnWidth', [{105, 45, 55, 65, 55}, repmat({77}, 1, numel(headers) - 5)], ...
        'ColumnFormat', [{'char'}, repmat({'shortG'}, 1, numel(headers) - 1)], ...
        'CellSelectionCallback', @(s,e) on_results_cell_selected(app.fig, e));

    app.ui.decode_line = uitextarea(t, 'Position', [20 52 810 44], ...
        'Editable', 'off', 'Value', 'Click a warning cell to see the rule and the value.');
    info_button(t, [835 74 22 22], 'warnings', 'Warnings');

    uibutton(t, 'Position', [20 16 160 24], 'Text', 'Export results CSV', ...
        'ButtonPushedFcn', @(s,e) on_export(app.fig, 'results'));
    uibutton(t, 'Position', [190 16 160 24], 'Text', 'Export log TXT', ...
        'ButtonPushedFcn', @(s,e) on_export(app.fig, 'log'));
    uibutton(t, 'Position', [360 16 160 24], 'Text', 'Open output folder', ...
        'ButtonPushedFcn', @(s,e) on_open_out(app.fig));
    uibutton(t, 'Position', [530 16 160 24], 'Text', 'Warnings figure', ...
        'ButtonPushedFcn', @(s,e) on_show_figure(app.fig));

    save_app(app);
    setappdata(app.fig, 'stop_requested', false);
end

function on_run(fig)
    app = getappdata(fig, 'app');
    folder = app.ui.input_edit.Value;
    if isempty(folder); uialert(fig, 'Choose an input folder first.', 'Run'); return; end
    setappdata(fig, 'stop_requested', false);

    opts = struct();
    opts.live_log_callback = @(msg) append_log(fig, msg);
    opts.stop_check = @() getappdata(fig, 'stop_requested');
    % Without a Scan the table is empty and batch_run takes every dataset.
    % After a Scan, pass the ticked rows only, so clearing every box cannot
    % fall back to "run all".
    rows = app.ui.datasets_table.Data;
    if ~isempty(rows)
        selected = rows([rows{:, 1}], 2)';
        if isempty(selected)
            uialert(fig, 'No dataset is selected. Tick Run for at least one dataset on the Setup tab.', 'Run');
            return
        end
        opts.selected_datasets = selected;
    end

    app.ui.progress_label.Text = 'running...';
    drawnow;
    summary = batch_run(folder, app.config, opts);
    app.ui.progress_label.Text = sprintf('done: %d ok, %d failed, %d with warnings', ...
        summary.n_succeeded, summary.n_failed, summary.n_with_warnings);
    if summary.n_kept > 0
        app.ui.progress_label.Text = sprintf('%s; table also shows %d from earlier runs', ...
            app.ui.progress_label.Text, summary.n_kept);
    end

    app = getappdata(fig, 'app');
    app.last_summary = summary;
    app.last_details = summary.anomalies.details;
    app.last_errors = arrayfun(@(r) r.error, summary.results, 'UniformOutput', false);
    app.figure_path = summary.warnings_png;
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
    [~, names] = anomaly_decode_map();
    n = numel(summary.results);
    rows = cell(n, 5 + numel(names));
    for k = 1:n
        r = summary.results(k); f = summary.anomalies.flags(k);
        m = summary.anomalies.metrics(k);
        n_cells = 0;
        if ~isempty(r.match_stats); n_cells = r.match_stats(1); end
        sev = cellfun(@(nm) f.(nm), names, 'UniformOutput', false);
        rows(k, :) = [{r.dataset_id, numel(r.sessions), n_cells, ...
            round(m.match_pct, 1), round(100 * r.chosen_fpr, 2)}, sev];
    end
    app.ui.results_table.Data = rows;
    apply_severity_styles(app.ui.results_table, rows, 6:5 + numel(names), app.last_errors);
end

function on_export(fig, which)
    app = getappdata(fig, 'app');
    has_run = isfield(app, 'last_summary');
    has_loaded = isfield(app, 'loaded_csv_path') && ~isempty(app.loaded_csv_path);
    if ~has_run && ~has_loaded
        uialert(fig, 'No run or loaded results yet.', 'Export'); return;
    end
    if strcmp(which, 'results')
        if has_run; src = app.last_summary.results_csv; else; src = app.loaded_csv_path; end
        [~, nm, ext] = fileparts(src);
        [n, p] = uiputfile('*.csv', 'Save results', [nm ext]);
        refocus(fig);
        if isnumeric(n); return; end
        copyfile(src, fullfile(p, n));
    else
        if ~has_run
            uialert(fig, 'Log export needs a live run (not a loaded CSV).', 'Export');
            return
        end
        [~, nm, ext] = fileparts(app.last_summary.log_file);
        [n, p] = uiputfile('*.txt', 'Save log', [nm ext]);
        refocus(fig);
        if isnumeric(n); return; end
        copyfile(app.last_summary.log_file, fullfile(p, n));
    end
end

function on_open_out(fig)
    app = getappdata(fig, 'app');
    if isfield(app, 'last_summary')
        open_path(app.last_summary.output_dir);
    elseif isfield(app, 'loaded_csv_path') && ~isempty(app.loaded_csv_path)
        open_path(fileparts(app.loaded_csv_path));
    end
end

function on_show_figure(fig)
    app = getappdata(fig, 'app');
    p = '';
    if isfield(app, 'figure_path'); p = app.figure_path; end
    if isempty(p) || exist(p, 'file') ~= 2
        uialert(fig, 'No warnings figure yet. Run a batch or load a results CSV.', 'Warnings figure');
        return
    end
    open_path(p);
end

function open_path(p)
    % Opens a folder or a file with the system viewer. winopen exists on
    % Windows only.
    if ispc
        winopen(p);
    elseif ismac
        system(sprintf('open "%s"', p));
    else
        system(sprintf('xdg-open "%s" &', p));
    end
end

function names = results_table_headers()
%RESULTS_TABLE_HEADERS Column labels: fixed columns, then the six warnings.
    [m, order] = anomaly_decode_map();
    names = {'Dataset', 'Sess', 'Cells', 'Match %', 'FPR %'};
    for k = 1:numel(order)
        names{end+1} = m(order{k}).short; %#ok<AGROW>
    end
end

function apply_severity_styles(tbl, rows, wcols, errors)
%APPLY_SEVERITY_STYLES Color warning cells: 2 = red, 1 = yellow; failed
%   datasets grey. uistyle needs R2019b; older releases show numbers only.
    try
        removeStyle(tbl);
        redS = uistyle('BackgroundColor', [1 0.6 0.6]);
        yelS = uistyle('BackgroundColor', [1 1 0.6]);
        greyS = uistyle('BackgroundColor', [0.8 0.8 0.8]);
        for rr = 1:size(rows, 1)
            if rr <= numel(errors) && ~isempty(errors{rr})
                addStyle(tbl, greyS, 'row', rr);
                continue
            end
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

function on_load_results(fig)
    [name, path] = uigetfile({'*_batch_results.csv', 'Batch results'; '*.csv', 'All CSV files'}, ...
        'Load <EXPERIMENT>_batch_results.csv');
    refocus(fig);
    if isnumeric(name); return; end
    full = fullfile(path, name);
    r = parse_batch_results_csv(full);
    if ~r.ok
        uialert(fig, r.error, 'Load results');
        return
    end
    if size(r.rows, 1) == 0
        uialert(fig, 'CSV has no data rows.', 'Load results');
        return
    end
    fill_results_from_csv(fig, r, full);
end

function fill_results_from_csv(fig, r, full)
    app = getappdata(fig, 'app');
    [~, names] = anomaly_decode_map();
    want = [{'dataset_id', 'n_sessions', 'n_cells', 'pct_in_all_of_mean', 'chosen_fpr_pct'}, names];
    idx = cellfun(@(nm) find(strcmp(r.headers, nm), 1), want);
    n = size(r.rows, 1);
    rows = cell(n, numel(want));
    for k = 1:n
        rows{k, 1} = r.rows{k, idx(1)};
        for c = 2:numel(want)
            v = str2double(r.rows{k, idx(c)});
            if isnan(v) && c > 5; v = 0; end
            rows{k, c} = v;
        end
    end
    errors = repmat({''}, 1, n);
    ecol = find(strcmp(r.headers, 'error'), 1);
    if ~isempty(ecol); errors = r.rows(:, ecol)'; end

    % The detail file and the figure sit next to the results file and have
    % the same <EXPERIMENT> start of the name.
    [folder, nm] = fileparts(full);
    base = fullfile(folder, regexprep(nm, '_batch_results$', ''));
    app.last_details = read_details([base '_batch_warnings_detail.csv']);
    app.last_errors = errors;
    app.figure_path = [base '_batch_warnings.png'];
    app.ui.results_table.Data = rows;
    apply_severity_styles(app.ui.results_table, rows, 6:numel(want), errors);
    app.loaded_csv_path = full;
    app.ui.progress_label.Text = sprintf('loaded %d rows from %s', n, full);
    setappdata(fig, 'app', app);
end

function d = read_details(path)
    d = struct('dataset_id', {}, 'session', {}, 'warning', {}, 'rule', {}, ...
        'value', {}, 'threshold', {}, 'severity', {});
    r = parse_batch_results_csv(path, fieldnames(d)');
    if ~r.ok; return; end
    col = @(nm) find(strcmp(r.headers, nm), 1);
    for k = 1:size(r.rows, 1)
        d(end+1) = struct('dataset_id', r.rows{k, col('dataset_id')}, ...
            'session', r.rows{k, col('session')}, 'warning', r.rows{k, col('warning')}, ...
            'rule', r.rows{k, col('rule')}, 'value', str2double(r.rows{k, col('value')}), ...
            'threshold', str2double(r.rows{k, col('threshold')}), ...
            'severity', r.rows{k, col('severity')}); %#ok<AGROW>
    end
end

function on_results_cell_selected(fig, e)
    app = getappdata(fig, 'app');
    if ~isfield(app.ui, 'decode_line'); return; end
    if isempty(e.Indices)
        app.ui.decode_line.Value = 'Click a warning cell to see the rule and the value.';
        return
    end
    rr = e.Indices(1); cc = e.Indices(2);
    data = app.ui.results_table.Data;
    if isempty(data) || rr > size(data, 1); return; end
    ds = data{rr, 1};
    [m, names] = anomaly_decode_map();
    if isfield(app, 'last_errors') && rr <= numel(app.last_errors) && ~isempty(app.last_errors{rr})
        app.ui.decode_line.Value = sprintf('%s failed: %s', ds, app.last_errors{rr});
        return
    end
    if cc <= 5
        app.ui.decode_line.Value = 'Click a warning cell (Sessions to Low match) to see why it is coloured.';
        return
    end
    name = names{cc - 5};
    lines = {};
    if isfield(app, 'last_details')
        for d = app.last_details
            if strcmp(d.dataset_id, ds) && strcmp(d.warning, name)
                where = '';
                if ~strcmp(d.session, '-'); where = sprintf(' (session %s)', d.session); end
                lines{end+1} = sprintf('%s: %s = %s%s, %s limit %s.', upper(d.severity), ...
                    d.rule, num2str(d.value, 4), where, d.severity, num2str(d.threshold, 4)); %#ok<AGROW>
            end
        end
    end
    if isempty(lines)
        lines = {sprintf('%s: no %s warning.', ds, m(name).short)};
    else
        lines = [{sprintf('%s: %s warning.', ds, m(name).short)}, lines];
    end
    lines{end+1} = ['What it checks: ' m(name).desc];
    app.ui.decode_line.Value = lines;
end
