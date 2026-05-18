# Batch Results Loader Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the analyst load a saved `_batch_results.csv` into the Run & Results tab — colored warnings table, two-line headers, click-to-decode — without re-running.

**Architecture:** Two pure, unit-tested helpers in `BatchCellReg/` (CSV parser, decode map). All GUI wiring (button, callback, headers, shared severity styler, decode line) in `BatchCellReg_GUI/BatchCellReg.m`. No engine/vendor changes.

**Tech Stack:** MATLAB R2020a (`uifigure`, `uitable`, `uistyle`, `containers.Map`, `matlab.unittest` functiontests).

---

## File Structure

- Create `BatchCellReg/anomaly_decode_map.m` — code → struct(short, desc).
- Create `BatchCellReg/parse_batch_results_csv.m` — parse + validate the CSV.
- Create `tests/BatchCellReg/test_anomaly_decode_map.m`.
- Create `tests/BatchCellReg/test_parse_batch_results_csv.m`.
- Modify `BatchCellReg_GUI/BatchCellReg.m` — headers, shared styler, Load
  button, decode line, callbacks.
- Modify `tests/BatchCellReg/runAllTests.m` — include new tests.

The 17 results-table columns (unchanged order): `Dataset, Sess, Cells,
%match, FPR, W1, W2, W2b_hard, W2b_rel, W3a, W3b, W4, W5a, W5b, W6a, W6b, W7`.
W-columns are table columns 6..17.

---

### Task 1: Anomaly decode map

**Files:**
- Create: `BatchCellReg/anomaly_decode_map.m`
- Test: `tests/BatchCellReg/test_anomaly_decode_map.m`

- [ ] **Step 1: Write the failing test**

```matlab
% tests/BatchCellReg/test_anomaly_decode_map.m
function tests = test_anomaly_decode_map
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', '..', 'BatchCellReg')));
end

function test_has_all_codes(tc)
    m = anomaly_decode_map();
    codes = {'W1','W2','W2b_hard','W2b_rel','W3a','W3b','W4','W5a','W5b','W6a','W6b','W7'};
    for k = 1:numel(codes)
        verifyTrue(tc, isKey(m, codes{k}), sprintf('missing %s', codes{k}));
        e = m(codes{k});
        verifyTrue(tc, isfield(e,'short') && isfield(e,'desc'));
        verifyNotEmpty(tc, e.short);
        verifyNotEmpty(tc, e.desc);
    end
end

function test_short_is_brief(tc)
    m = anomaly_decode_map();
    verifyEqual(tc, m('W3a').short, 'low xcorr');
    verifyEqual(tc, m('W6a').short, 'bad MSE');
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd 'C:/Users/User/PycharmProjects/CellReg'; matlab -batch "addpath(genpath('BatchCellReg')); addpath(genpath('tests/BatchCellReg')); runtests('tests/BatchCellReg/test_anomaly_decode_map.m')"`
Expected: FAIL — `anomaly_decode_map` undefined.

- [ ] **Step 3: Write minimal implementation**

```matlab
% BatchCellReg/anomaly_decode_map.m
function m = anomaly_decode_map()
%ANOMALY_DECODE_MAP code -> struct(short, desc) for results-table warnings.
%   short: 1-2 word column-header tag. desc: full click-to-decode sentence.
    e = @(s,d) struct('short', s, 'desc', d);
    m = containers.Map('KeyType','char','ValueType','any');
    m('W1')       = e('%match',     'W1 - %match population outlier: pct_in_all low vs batch (graded).');
    m('W2')       = e('cells/sess', 'W2 - cells/session intra-dataset z-outlier.');
    m('W2b_hard') = e('ratio>3',    'W2b_hard - max/min cells-per-session ratio > 3 (hard).');
    m('W2b_rel')  = e('ratio rel',  'W2b_rel - cells-per-session ratio high vs batch (graded).');
    m('W3a')      = e('low xcorr',  'W3a - low cross-correlation (hard): min(max_xcorr) < min_xcorr (0.3) = bad alignment.');
    m('W3b')      = e('xcorr rel',  'W3b - low cross-correlation relative: intra-dataset z of max_xcorr.');
    m('W4')       = e('FPR unreach','W4 - P_same FPR target unreachable (P_same capped at 0.95).');
    m('W5a')      = e('big shift',  'W5a - large alignment shift (hard): max |shift_px| > max_translation_px (30).');
    m('W5b')      = e('shift rel',  'W5b - large alignment shift relative: intra-dataset z of per-session shift.');
    m('W6a')      = e('bad MSE',    'W6a - bad model fit (hard): MSE_model > max_mse (0.1).');
    m('W6b')      = e('MSE rel',    'W6b - bad model fit relative: MSE high vs batch (graded).');
    m('W7')       = e('sess count', 'W7 - session count != expected_n_sessions.');
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: same command as Step 2.
Expected: PASS (2 tests).

- [ ] **Step 5: Commit**

```bash
git add BatchCellReg/anomaly_decode_map.m tests/BatchCellReg/test_anomaly_decode_map.m
git commit -m "feat(gui): anomaly decode map for results table"
```

---

### Task 2: Results CSV parser

**Files:**
- Create: `BatchCellReg/parse_batch_results_csv.m`
- Test: `tests/BatchCellReg/test_parse_batch_results_csv.m`

`parse_batch_results_csv(path)` returns a struct:
- `.ok` (logical), `.error` (char, '' if ok)
- `.headers` (1xN cellstr)
- `.rows` (MxN cellstr; numeric-looking fields stay char, converted by caller)

Required columns (must all be present in header): `dataset_id, n_sessions,
n_cells, pct_in_all, chosen_fpr, W1, W2, W2b_hard, W2b_rel, W3a, W3b, W4, W5a,
W5b, W6a, W6b, W7`. Missing any → `.ok=false`, `.error` names the first missing.

- [ ] **Step 1: Write the failing test**

```matlab
% tests/BatchCellReg/test_parse_batch_results_csv.m
function tests = test_parse_batch_results_csv
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', '..', 'BatchCellReg')));
end

function p = tmpcsv(lines)
    p = [tempname '.csv'];
    fid = fopen(p,'w'); for i=1:numel(lines); fprintf(fid,'%s\n',lines{i}); end; fclose(fid);
end

function test_parses_valid(tc)
    hdr = 'dataset_id,n_sessions,n_cells,pct_in_all,chosen_fpr,W1,W2,W2b_hard,W2b_rel,W3a,W3b,W4,W5a,W5b,W6a,W6b,W7,W3a_min_xcorr,W5a_max_shift_px,W6a_mse,W2b_ratio,error';
    p = tmpcsv({hdr, 'CC_H01,2,236,0.22,0,0,0,0,0,0,0,0,0,0,2,0,2,0.5,1,0.12,1.1,', ...
                     'CC_H04,2,237,0.13,0,0,0,2,1,2,0,0,0,0,2,0,2,0.29,2,0.13,3.2,'});
    r = parse_batch_results_csv(p);
    verifyTrue(tc, r.ok);
    verifyEqual(tc, numel(r.headers), 22);
    verifyEqual(tc, size(r.rows,1), 2);
    verifyEqual(tc, r.rows{2,1}, 'CC_H04');
    delete(p);
end

function test_missing_column(tc)
    p = tmpcsv({'dataset_id,n_sessions,n_cells,pct_in_all,chosen_fpr,W1', 'X,1,2,0.1,0,0'});
    r = parse_batch_results_csv(p);
    verifyFalse(tc, r.ok);
    verifySubstring(tc, r.error, 'W2');
    delete(p);
end

function test_bad_path(tc)
    r = parse_batch_results_csv('Z:/nope/none.csv');
    verifyFalse(tc, r.ok);
    verifyNotEmpty(tc, r.error);
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `cd 'C:/Users/User/PycharmProjects/CellReg'; matlab -batch "addpath(genpath('BatchCellReg')); addpath(genpath('tests/BatchCellReg')); runtests('tests/BatchCellReg/test_parse_batch_results_csv.m')"`
Expected: FAIL — `parse_batch_results_csv` undefined.

- [ ] **Step 3: Write minimal implementation**

```matlab
% BatchCellReg/parse_batch_results_csv.m
function r = parse_batch_results_csv(path)
%PARSE_BATCH_RESULTS_CSV Read & validate a _batch_results.csv export.
    r = struct('ok', false, 'error', '', 'headers', {{}}, 'rows', {{}});
    if exist(path, 'file') ~= 2
        r.error = sprintf('File not found: %s', path); return
    end
    fid = fopen(path, 'r');
    if fid < 0; r.error = sprintf('Cannot open %s', path); return; end
    c = onCleanup(@() fclose(fid));
    raw = {};
    while true
        ln = fgetl(fid);
        if ~ischar(ln); break; end
        if isempty(strtrim(ln)); continue; end
        raw{end+1} = ln; %#ok<AGROW>
    end
    if isempty(raw); r.error = 'Empty file'; return; end
    headers = strsplit(raw{1}, ',', 'CollapseDelimiters', false);
    headers = strtrim(headers);
    required = {'dataset_id','n_sessions','n_cells','pct_in_all','chosen_fpr', ...
        'W1','W2','W2b_hard','W2b_rel','W3a','W3b','W4','W5a','W5b','W6a','W6b','W7'};
    for k = 1:numel(required)
        if ~any(strcmp(headers, required{k}))
            r.error = sprintf('Missing required column: %s', required{k}); return
        end
    end
    n = numel(headers);
    rows = cell(numel(raw)-1, n);
    for i = 2:numel(raw)
        parts = strsplit(raw{i}, ',', 'CollapseDelimiters', false);
        for j = 1:n
            if j <= numel(parts); rows{i-1, j} = strtrim(parts{j}); else; rows{i-1, j} = ''; end
        end
    end
    r.ok = true; r.headers = headers; r.rows = rows;
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: same command as Step 2.
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add BatchCellReg/parse_batch_results_csv.m tests/BatchCellReg/test_parse_batch_results_csv.m
git commit -m "feat(gui): parser/validator for saved batch results CSV"
```

---

### Task 3: Two-line headers + shared severity styler

**Files:**
- Modify: `BatchCellReg_GUI/BatchCellReg.m` (`build_run_tab`, `fill_results_table`)

- [ ] **Step 1: Replace the results_table ColumnName in `build_run_tab`**

Find in `build_run_tab`:

```matlab
    app.ui.results_table = uitable(t, 'Position', [20 80 840 230], ...
        'ColumnName', {'Dataset','Sess','Cells','%match','FPR', ...
                       'W1','W2','W2b_h','W2b_r','W3a','W3b','W4','W5a','W5b','W6a','W6b','W7'}, ...
        'ColumnFormat', {'char','numeric','numeric','numeric','numeric', ...
                         'numeric','numeric','numeric','numeric','numeric','numeric', ...
                         'numeric','numeric','numeric','numeric','numeric','numeric'});
```

Replace with:

```matlab
    app.ui.results_table = uitable(t, 'Position', [20 80 840 230], ...
        'ColumnName', results_table_headers(), ...
        'ColumnFormat', {'char','numeric','numeric','numeric','numeric', ...
                         'numeric','numeric','numeric','numeric','numeric','numeric', ...
                         'numeric','numeric','numeric','numeric','numeric','numeric'});
```

- [ ] **Step 2: Add `results_table_headers` local function**

Add at the end of `BatchCellReg_GUI/BatchCellReg.m` (after the last local function):

```matlab
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
```

- [ ] **Step 3: Extract the coloring into `apply_severity_styles`**

In `fill_results_table`, find the coloring block:

```matlab
    app.ui.results_table.Data = rows;
    % Apply severity coloring: red=2, yellow=1 for W columns (cols 6-17)
    try
        removeStyle(app.ui.results_table);
        redS = uistyle('BackgroundColor', [1 0.6 0.6]);
        yelS = uistyle('BackgroundColor', [1 1 0.6]);
        wcols = 6:17;
        for rr = 1:size(rows, 1)
            for cc = wcols
                v = rows{rr, cc};
                if isequal(v, 2)
                    addStyle(app.ui.results_table, redS, 'cell', [rr cc]);
                elseif isequal(v, 1)
                    addStyle(app.ui.results_table, yelS, 'cell', [rr cc]);
                end
            end
        end
    catch
    end
```

Replace with:

```matlab
    app.ui.results_table.Data = rows;
    apply_severity_styles(app.ui.results_table, rows, 6:17);
```

- [ ] **Step 4: Add `apply_severity_styles` local function**

Add at the end of `BatchCellReg_GUI/BatchCellReg.m`:

```matlab
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
```

- [ ] **Step 5: Smoke-test the GUI still builds and headers applied**

Run: `cd 'C:/Users/User/PycharmProjects/CellReg'; matlab -batch "addpath('BatchCellReg_GUI'); addpath(genpath('BatchCellReg')); app=BatchCellReg(); a=getappdata(app.fig,'app'); h=a.ui.results_table.ColumnName; assert(numel(h)==17); assert(contains(h{10},'W3a') && contains(h{10},'low xcorr')); disp('OK headers'); close(app.fig);"`
Expected: prints `OK headers`.

- [ ] **Step 6: Commit**

```bash
git add BatchCellReg_GUI/BatchCellReg.m
git commit -m "feat(gui): two-line W headers + shared severity styler"
```

---

### Task 4: "Load results CSV…" button + callback

**Files:**
- Modify: `BatchCellReg_GUI/BatchCellReg.m` (`build_run_tab`, new `on_load_results`, `fill_results_from_csv`)

- [ ] **Step 1: Reposition top buttons and add Load button in `build_run_tab`**

Find:

```matlab
    uibutton(t, 'Position', [20 540 80 24], 'Text', 'Run batch', ...
        'ButtonPushedFcn', @(s,e) on_run(app.fig));
    uibutton(t, 'Position', [110 540 80 24], 'Text', 'Stop', ...
        'ButtonPushedFcn', @(s,e) on_stop(app.fig));
    app.ui.progress_label = uilabel(t, 'Position', [200 540 400 24], 'Text', 'idle');
```

Replace with:

```matlab
    uibutton(t, 'Position', [20 540 80 24], 'Text', 'Run batch', ...
        'ButtonPushedFcn', @(s,e) on_run(app.fig));
    uibutton(t, 'Position', [110 540 70 24], 'Text', 'Stop', ...
        'ButtonPushedFcn', @(s,e) on_stop(app.fig));
    uibutton(t, 'Position', [190 540 140 24], 'Text', 'Load results CSV...', ...
        'ButtonPushedFcn', @(s,e) on_load_results(app.fig));
    app.ui.progress_label = uilabel(t, 'Position', [340 540 280 24], 'Text', 'idle');
```

- [ ] **Step 2: Add `on_load_results` and `fill_results_from_csv` local functions**

Add at the end of `BatchCellReg_GUI/BatchCellReg.m`:

```matlab
function on_load_results(fig)
    [name, path] = uigetfile('*.csv', 'Load _batch_results.csv');
    refocus(fig);
    if isnumeric(name); return; end
    full = fullfile(path, name);
    r = parse_batch_results_csv(full);
    if ~r.ok
        uialert(fig, r.error, 'Load results');
        return
    end
    fill_results_from_csv(fig, r, full);
end

function fill_results_from_csv(fig, r, full)
    app = getappdata(fig, 'app');
    col = @(nm) find(strcmp(r.headers, nm), 1);
    want = {'dataset_id','n_sessions','n_cells','pct_in_all','chosen_fpr', ...
        'W1','W2','W2b_hard','W2b_rel','W3a','W3b','W4','W5a','W5b','W6a','W6b','W7'};
    idx = cellfun(col, want);
    n = size(r.rows, 1);
    rows = cell(n, 17);
    for k = 1:n
        rows{k,1} = r.rows{k, idx(1)};
        for c = 2:17
            v = str2double(r.rows{k, idx(c)});
            if isnan(v); v = 0; end
            rows{k,c} = v;
        end
    end
    app.ui.results_table.Data = rows;
    apply_severity_styles(app.ui.results_table, rows, 6:17);
    app.loaded_csv_path = full;
    app.ui.progress_label.Text = sprintf('loaded %d rows from %s', n, full);
    setappdata(fig, 'app', app);
end
```

- [ ] **Step 3: Make Export results / Open output folder honor a loaded CSV**

Find `on_export`:

```matlab
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
```

Replace the `if strcmp(which,'results')` branch guard so a loaded CSV works:

```matlab
function on_export(fig, which)
    app = getappdata(fig, 'app');
    has_run = isfield(app, 'last_summary');
    has_loaded = isfield(app, 'loaded_csv_path') && ~isempty(app.loaded_csv_path);
    if ~has_run && ~has_loaded
        uialert(fig, 'No run or loaded results yet.', 'Export'); return;
    end
    if strcmp(which, 'results')
        [n, p] = uiputfile('*.csv', 'Save results', '_batch_results.csv');
        refocus(fig);
        if isnumeric(n); return; end
        if has_run; src = app.last_summary.results_csv; else; src = app.loaded_csv_path; end
        copyfile(src, fullfile(p, n));
    else
```

(Leave the `else` log branch and its `end` unchanged — log export still
requires a live run; if only loaded, `app.last_summary` is absent and
`copyfile` line is not reached because `has_run` is false: change the log
branch to guard.)

Find the log branch:

```matlab
    else
        [n, p] = uiputfile('*.txt', 'Save log', '_batch_log.txt');
        refocus(fig);
        if isnumeric(n); return; end
        copyfile(app.last_summary.log_file, fullfile(p, n));
    end
```

Replace with:

```matlab
    else
        if ~has_run
            uialert(fig, 'Log export needs a live run (not a loaded CSV).', 'Export');
            return
        end
        [n, p] = uiputfile('*.txt', 'Save log', '_batch_log.txt');
        refocus(fig);
        if isnumeric(n); return; end
        copyfile(app.last_summary.log_file, fullfile(p, n));
    end
```

Find `on_open_out`:

```matlab
function on_open_out(fig)
    app = getappdata(fig, 'app');
    if isfield(app, 'last_summary')
        winopen(app.last_summary.output_dir);
    end
end
```

Replace with:

```matlab
function on_open_out(fig)
    app = getappdata(fig, 'app');
    if isfield(app, 'last_summary')
        winopen(app.last_summary.output_dir);
    elseif isfield(app, 'loaded_csv_path') && ~isempty(app.loaded_csv_path)
        winopen(fileparts(app.loaded_csv_path));
    end
end
```

- [ ] **Step 4: Headless smoke — load the real CC results CSV**

Run: `cd 'C:/Users/User/PycharmProjects/CellReg'; matlab -batch "addpath('BatchCellReg_GUI'); addpath(genpath('BatchCellReg')); app=BatchCellReg(); fig=app.fig; r=parse_batch_results_csv('h:/Dataset/CalciumData/CC/5_Filters/Matching/_batch_results.csv'); assert(r.ok, r.error); F=@fill_results_from_csv; disp('parser ok rows='); disp(size(r.rows,1)); close(fig);"`
Expected: `parser ok rows=` then 16 (CC has 16 processed datasets).

- [ ] **Step 5: Commit**

```bash
git add BatchCellReg_GUI/BatchCellReg.m
git commit -m "feat(gui): Load results CSV button + loaded-state exports"
```

---

### Task 5: Click-to-decode line

**Files:**
- Modify: `BatchCellReg_GUI/BatchCellReg.m` (`build_run_tab`, new `on_results_cell_selected`)

- [ ] **Step 1: Add the decode line and wire CellSelectionCallback in `build_run_tab`**

Find:

```matlab
    app.ui.results_table = uitable(t, 'Position', [20 80 840 230], ...
        'ColumnName', results_table_headers(), ...
        'ColumnFormat', {'char','numeric','numeric','numeric','numeric', ...
                         'numeric','numeric','numeric','numeric','numeric','numeric', ...
                         'numeric','numeric','numeric','numeric','numeric','numeric'});
```

Replace with:

```matlab
    app.ui.results_table = uitable(t, 'Position', [20 80 840 230], ...
        'ColumnName', results_table_headers(), ...
        'ColumnFormat', {'char','numeric','numeric','numeric','numeric', ...
                         'numeric','numeric','numeric','numeric','numeric','numeric', ...
                         'numeric','numeric','numeric','numeric','numeric','numeric'}, ...
        'CellSelectionCallback', @(s,e) on_results_cell_selected(app.fig, e));

    app.ui.decode_line = uitextarea(t, 'Position', [20 56 840 22], ...
        'Editable', 'off', 'Value', 'Click a W cell to decode the warning.');
```

- [ ] **Step 2: Add `on_results_cell_selected` local function**

Add at the end of `BatchCellReg_GUI/BatchCellReg.m`:

```matlab
function on_results_cell_selected(fig, e)
    app = getappdata(fig, 'app');
    if ~isfield(app.ui, 'decode_line'); return; end
    if isempty(e.Indices)
        app.ui.decode_line.Value = 'Click a W cell to decode the warning.';
        return
    end
    rr = e.Indices(1); cc = e.Indices(2);
    wcodes = {'W1','W2','W2b_hard','W2b_rel','W3a','W3b','W4','W5a','W5b','W6a','W6b','W7'};
    if cc < 6 || cc > 17
        app.ui.decode_line.Value = 'Not a warning column.';
        return
    end
    m = anomaly_decode_map();
    code = wcodes{cc - 5};
    data = app.ui.results_table.Data;
    sev = 0; ds = '';
    if ~isempty(data) && rr <= size(data,1)
        v = data{rr, cc};
        if ~isempty(v) && isnumeric(v); sev = v; end
        if ~isempty(data{rr,1}); ds = data{rr,1}; end
    end
    sevw = {'none','YELLOW','RED'};
    si = max(0, min(2, round(sev))) + 1;
    app.ui.decode_line.Value = sprintf('%s   [%s] severity = %g (%s)', ...
        m(code).desc, ds, sev, sevw{si});
end
```

- [ ] **Step 3: Headless smoke — callback runs without error**

Run: `cd 'C:/Users/User/PycharmProjects/CellReg'; matlab -batch "addpath('BatchCellReg_GUI'); addpath(genpath('BatchCellReg')); app=BatchCellReg(); fig=app.fig; a=getappdata(fig,'app'); a.ui.results_table.Data={'CC_H04',2,237,0.13,0,0,0,2,1,2,0,0,0,0,2,0,2}; setappdata(fig,'app',a); on_results_cell_selected(fig, struct('Indices',[1 10])); b=getappdata(fig,'app'); disp(b.ui.decode_line.Value); assert(contains(char(b.ui.decode_line.Value),'W3a')); assert(contains(char(b.ui.decode_line.Value),'RED')); disp('decode OK'); close(fig);"`
Expected: prints the W3a decode line containing `RED`, then `decode OK`.

- [ ] **Step 4: Commit**

```bash
git add BatchCellReg_GUI/BatchCellReg.m
git commit -m "feat(gui): click-to-decode line for warnings table"
```

---

### Task 6: Test registration + full regression + manual verification

**Files:**
- Modify: `tests/BatchCellReg/runAllTests.m`

- [ ] **Step 1: Add new tests to `runAllTests.m`**

Open `tests/BatchCellReg/runAllTests.m`. It builds a list of test files. Add
`'test_anomaly_decode_map'` and `'test_parse_batch_results_csv'` to that list
in the same style as the existing entries (match the surrounding code exactly;
if it uses a cell array `tests = {...}`, append both names).

- [ ] **Step 2: Run the full BatchCellReg test suite**

Run: `cd 'C:/Users/User/PycharmProjects/CellReg'; matlab -batch "addpath(genpath('BatchCellReg')); addpath(genpath('tests/BatchCellReg')); runAllTests"`
Expected: all tests pass (previous count + the 5 new assertions across 2 files).

- [ ] **Step 3: Manual verification checklist (record results)**

Launch `BatchCellReg` in interactive MATLAB and verify:
1. Run & Results tab shows two-line headers (`W3a` over `low xcorr`, etc.).
2. Click **Load results CSV…**, pick
   `h:/Dataset/CalciumData/CC/5_Filters/Matching/_batch_results.csv`.
3. Table fills with 16 rows; W6a column shows red cells (sev 2), any sev-1
   cells yellow; window stays focused after the dialog.
4. Click a red W6a cell → decode line reads the W6a "bad model fit" sentence
   with `[CC_xx] severity = 2 (RED)`.
5. Click the `Dataset` cell → decode line says "Not a warning column."
6. Pick an unrelated CSV via Load → `uialert` appears, table unchanged.
7. Export results CSV after a load → writes a copy of the loaded file.
8. A fresh `Run batch` still fills + colors the table (shared styler path).

- [ ] **Step 4: Commit**

```bash
git add tests/BatchCellReg/runAllTests.m
git commit -m "test(gui): register decode-map and CSV-parser tests"
```

---

## Self-Review

- **Spec coverage:** R1 Load button → Task 4; CSV parse/validate → Task 2;
  uialert on bad → Task 4 Step 2. R2 two-line headers → Task 3. R3 shared
  styler → Task 3 Steps 3-4 (used by run path and load path Task 4 Step 2).
  R4 decode line + CellSelectionCallback + static map → Task 1 + Task 5.
  Non-goals respected (no engine/vendor edits; CSV-only; click not hover).
  Testing section → Task 6.
- **Placeholder scan:** none; all steps contain full code/commands.
- **Type consistency:** `anomaly_decode_map` returns `containers.Map` of
  `struct('short','desc')` — used as `m(code).short` (headers) and
  `m(code).desc` (decode) consistently. `parse_batch_results_csv` returns
  `.ok/.error/.headers/.rows` — consumed with those exact fields in Task 4.
  `apply_severity_styles(tbl, rows, wcols)` defined Task 3, called Task 3 & 4
  with identical signature. `results_table_headers()` returns 17 entries,
  asserted in Task 3 Step 5.
