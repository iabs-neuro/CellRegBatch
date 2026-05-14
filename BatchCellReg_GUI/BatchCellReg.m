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
    uitab(app.tabs, 'Title', 'Parameters');  % implemented in Task 13
end

function build_run_tab(app)
    uitab(app.tabs, 'Title', 'Run & Results');  % implemented in Task 14
end
