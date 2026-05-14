# Batch CellReg Wrapper Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a MATLAB GUI wrapper that scans a flat folder of session `.mat` files, runs the full CellReg pipeline (Stages 1–5) on each `(experiment, mouse)` dataset with automatic `P_same` tuning, and reports per-dataset metrics plus six batch-wide anomaly flags in a scrollable, exportable table.

**Architecture:** Engine under `BatchCellReg/` (pure functions, no GUI dependencies, fully unit-tested with `matlab.unittest`). GUI under `BatchCellReg_GUI/` (single `uifigure` with three tabs) is a thin driver. Vendor code under `CellReg/`, `GUI/`, `Helper/` is not modified.

**Tech Stack:** MATLAB R2019b+ (`uifigure`, `jsonencode`/`jsondecode`, `matlab.unittest`).

**Spec:** `Docs/superpowers/specs/2026-05-14-batch-cellreg-wrapper-design.md`

---

## File map

```
BatchCellReg/                       (engine — no GUI deps)
├── batch_default_config.m
├── config_to_json.m
├── config_from_json.m
├── scan_input_folder.m
├── prepare_session_files.m
├── choose_p_same_by_fpr.m
├── collect_match_stats.m
├── detect_anomalies.m
├── batch_logger.m
├── run_single_dataset.m
└── batch_run.m

BatchCellReg_GUI/
└── BatchCellReg.m                  (uifigure with 3 tabs)

tests/BatchCellReg/
├── runAllTests.m
├── test_config_roundtrip.m
├── test_scan_input_folder.m
├── test_prepare_session_files.m
├── test_choose_p_same_by_fpr.m
├── test_collect_match_stats.m
├── test_detect_anomalies.m
├── test_batch_logger.m
└── fixtures/
    ├── make_fixtures.m            (generates synthetic .mat files)
    ├── flat_folder/               (generated)
    └── tiny_sessions/             (generated)
```

## Test running convention

All tests run from the repo root via:

```powershell
matlab -batch "addpath(genpath('BatchCellReg')); addpath(genpath('CellReg')); addpath(genpath('Helper')); cd tests/BatchCellReg; runAllTests"
```

A single test file:

```powershell
matlab -batch "addpath(genpath('BatchCellReg')); cd tests/BatchCellReg; runtests('test_config_roundtrip')"
```

Expected output on pass: ends with `Done <name>` / `Totals: ... 0 Failed`.

---

## Task 0: Repository scaffolding

**Files:**
- Create: `BatchCellReg/.gitkeep`
- Create: `BatchCellReg_GUI/.gitkeep`
- Create: `tests/BatchCellReg/runAllTests.m`
- Modify: `.gitignore`

- [ ] **Step 1: Create folders and runner**

`BatchCellReg/.gitkeep`: empty file.
`BatchCellReg_GUI/.gitkeep`: empty file.

`tests/BatchCellReg/runAllTests.m`:

```matlab
function results = runAllTests()
%RUNALLTESTS Run every test_*.m in this directory and exit with proper code.
    here = fileparts(mfilename('fullpath'));
    suite = matlab.unittest.TestSuite.fromFolder(here);
    runner = matlab.unittest.TestRunner.withTextOutput('OutputDetail', ...
        matlab.unittest.Verbosity.Detailed);
    results = runner.run(suite);
    if any([results.Failed])
        error('runAllTests:Failed', '%d tests failed', sum([results.Failed]));
    end
end
```

- [ ] **Step 2: Add output dirs to `.gitignore`**

Append to `.gitignore` (create if absent):

```
# Batch wrapper output and test fixtures
**/Matching/
tests/BatchCellReg/fixtures/flat_folder/
tests/BatchCellReg/fixtures/tiny_sessions/
```

- [ ] **Step 3: Smoke-run the test runner (empty)**

```powershell
matlab -batch "cd tests/BatchCellReg; runAllTests"
```

Expected: `Totals: 0 Passed, 0 Failed, 0 Incomplete.` (or warning that no tests found — both acceptable).

- [ ] **Step 4: Commit**

```bash
git add BatchCellReg/.gitkeep BatchCellReg_GUI/.gitkeep tests/BatchCellReg/runAllTests.m .gitignore
git commit -m "feat(batch): scaffold BatchCellReg engine and GUI directories"
```

---

## Task 1: Default config + JSON roundtrip

**Files:**
- Create: `BatchCellReg/batch_default_config.m`
- Create: `BatchCellReg/config_to_json.m`
- Create: `BatchCellReg/config_from_json.m`
- Create: `tests/BatchCellReg/test_config_roundtrip.m`

- [ ] **Step 1: Write the failing test**

`tests/BatchCellReg/test_config_roundtrip.m`:

```matlab
function tests = test_config_roundtrip
    tests = functiontests(localfunctions);
end

function test_defaults_have_expected_keys(testCase)
    cfg = batch_default_config();
    verifyEqual(testCase, cfg.version, 1);
    verifyEqual(testCase, cfg.cellreg.microns_per_pixel, 1.6);
    verifyEqual(testCase, cfg.cellreg.alignment_type, 'Translations and Rotations');
    verifyEqual(testCase, cfg.cellreg.maximal_rotation, 5);
    verifyEqual(testCase, cfg.cellreg.reference_session_index, 1);
    verifyEqual(testCase, cfg.cellreg.maximal_distance_um, 30);
    verifyEqual(testCase, cfg.cellreg.registration_approach, 'Probabilistic');
    verifyEqual(testCase, cfg.cellreg.initial_registration_type, 'auto');
    verifyTrue(testCase, cfg.cellreg.use_parallel_processing);
    verifyEqual(testCase, cfg.cellreg.figures_visibility, 'off');
    verifyTrue(testCase, cfg.cellreg.write_to_file);
    verifyEqual(testCase, cfg.p_same_tuning.fpr_max, 0.03);
    verifyEqual(testCase, cfg.anomaly_thresholds.z_threshold, 2.0);
    verifyEqual(testCase, cfg.anomaly_thresholds.max_translation_px, 30);
    verifyEqual(testCase, cfg.anomaly_thresholds.min_xcorr, 0.3);
    verifyEqual(testCase, cfg.anomaly_thresholds.max_mse, 0.05);
end

function test_roundtrip_preserves_values(testCase)
    cfg = batch_default_config();
    cfg.cellreg.microns_per_pixel = 2.5;
    cfg.anomaly_thresholds.z_threshold = 2.5;
    tmp = [tempname '.json'];
    cleanup = onCleanup(@() delete(tmp));
    config_to_json(cfg, tmp);
    cfg2 = config_from_json(tmp);
    verifyEqual(testCase, cfg2.cellreg.microns_per_pixel, 2.5);
    verifyEqual(testCase, cfg2.anomaly_thresholds.z_threshold, 2.5);
end

function test_unknown_version_rejected(testCase)
    tmp = [tempname '.json'];
    cleanup = onCleanup(@() delete(tmp));
    fid = fopen(tmp, 'w'); fprintf(fid, '{"version": 999}'); fclose(fid);
    verifyError(testCase, @() config_from_json(tmp), ...
        'BatchCellReg:UnsupportedConfigVersion');
end
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
matlab -batch "addpath('BatchCellReg'); cd tests/BatchCellReg; runtests('test_config_roundtrip')"
```

Expected: `Failed 3` with "Undefined function `batch_default_config`".

- [ ] **Step 3: Implement `batch_default_config.m`**

`BatchCellReg/batch_default_config.m`:

```matlab
function cfg = batch_default_config()
%BATCH_DEFAULT_CONFIG Default parameters for the batch CellReg wrapper.
    cfg = struct();
    cfg.version = 1;

    cfg.cellreg = struct( ...
        'microns_per_pixel', 1.6, ...
        'alignment_type', 'Translations and Rotations', ...
        'maximal_rotation', 5, ...
        'reference_session_index', 1, ...
        'maximal_distance_um', 30, ...
        'registration_approach', 'Probabilistic', ...
        'initial_registration_type', 'auto', ...
        'use_parallel_processing', true, ...
        'figures_visibility', 'off', ...
        'write_to_file', true);

    cfg.p_same_tuning = struct('fpr_max', 0.03);

    cfg.anomaly_thresholds = struct( ...
        'z_threshold', 2.0, ...
        'max_translation_px', 30, ...
        'min_xcorr', 0.3, ...
        'max_mse', 0.05);

    cfg.io = struct( ...
        'input_folder', '', ...
        'output_subfolder_name', 'Matching');
end
```

- [ ] **Step 4: Implement `config_to_json.m`**

`BatchCellReg/config_to_json.m`:

```matlab
function config_to_json(cfg, path)
%CONFIG_TO_JSON Serialize config struct to a JSON file (pretty-printed).
    json = jsonencode(cfg, 'PrettyPrint', true);
    fid = fopen(path, 'w');
    if fid < 0
        error('BatchCellReg:ConfigWrite', 'Cannot open %s for writing', path);
    end
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', json);
end
```

- [ ] **Step 5: Implement `config_from_json.m`**

`BatchCellReg/config_from_json.m`:

```matlab
function cfg = config_from_json(path)
%CONFIG_FROM_JSON Load and validate a batch config JSON file.
    raw = fileread(path);
    cfg = jsondecode(raw);
    if ~isfield(cfg, 'version') || cfg.version ~= 1
        v = 'missing';
        if isfield(cfg, 'version'); v = num2str(cfg.version); end
        error('BatchCellReg:UnsupportedConfigVersion', ...
            'Config version %s is not supported (expected 1)', v);
    end
end
```

- [ ] **Step 6: Run tests to verify they pass**

```powershell
matlab -batch "addpath('BatchCellReg'); cd tests/BatchCellReg; runtests('test_config_roundtrip')"
```

Expected: `Totals: 3 Passed, 0 Failed`.

- [ ] **Step 7: Commit**

```bash
git add BatchCellReg/batch_default_config.m BatchCellReg/config_to_json.m BatchCellReg/config_from_json.m tests/BatchCellReg/test_config_roundtrip.m
git commit -m "feat(batch): add default config and JSON roundtrip"
```

---

## Task 2: Fixture generator

**Files:**
- Create: `tests/BatchCellReg/fixtures/make_fixtures.m`

Tests later need a deterministic flat folder. Generating it once via a function keeps fixtures out of git.

- [ ] **Step 1: Implement fixture generator**

`tests/BatchCellReg/fixtures/make_fixtures.m`:

```matlab
function flat_dir = make_fixtures()
%MAKE_FIXTURES Build a deterministic flat folder of synthetic session mats.
%   Returns the absolute path to the created folder.
    here = fileparts(mfilename('fullpath'));
    flat_dir = fullfile(here, 'flat_folder');
    if exist(flat_dir, 'dir'); rmdir(flat_dir, 's'); end
    mkdir(flat_dir);

    % Tiny but valid: 5 cells, 32x32 frame, one bright pixel per cell.
    Y = 32; X = 32; N = 5;
    rng(42);

    datasets = { ...
        struct('exp','BOWL','mouse','D01','sessions',{{'1D','2D','3D'}}, 'type','uint8'), ...
        struct('exp','BOWL','mouse','D03','sessions',{{'1D','2D'}},      'type','double'), ...
        struct('exp','BOWL','mouse','D05','sessions',{{'1D'}},            'type','uint8'), ...  % too few
    };

    for d = 1:numel(datasets)
        ds = datasets{d};
        for s = 1:numel(ds.sessions)
            A = zeros(N, Y, X, 'uint8');
            for c = 1:N
                yi = mod(c*5 + s, Y-3) + 2;
                xi = mod(c*7 + s*2, X-3) + 2;
                A(c, yi:yi+1, xi:xi+1) = 200;
            end
            if strcmp(ds.type, 'double')
                matrix_data = double(A); %#ok<NASGU>
                fname = sprintf('%s_%s_%s_converted.mat', ds.exp, ds.mouse, ds.sessions{s});
                save(fullfile(flat_dir, fname), 'matrix_data', '-v7.3');
            else
                fname = sprintf('%s_%s_%sD_filters.mat', ds.exp, ds.mouse, ds.sessions{s}(1));
                save(fullfile(flat_dir, fname), 'A');
            end
        end
    end

    % Add one unparseable file.
    fid = fopen(fullfile(flat_dir, 'README.mat'), 'w'); fclose(fid);
end
```

- [ ] **Step 2: Smoke-test the generator**

```powershell
matlab -batch "addpath('tests/BatchCellReg/fixtures'); d = make_fixtures(); disp(d); dir(d)"
```

Expected: directory listing with `BOWL_D01_1D_filters.mat`, `BOWL_D01_2D_filters.mat`, `BOWL_D01_3D_filters.mat`, `BOWL_D03_1D_converted.mat`, `BOWL_D03_2D_converted.mat`, `BOWL_D05_1D_filters.mat`, `README.mat`.

- [ ] **Step 3: Commit**

```bash
git add tests/BatchCellReg/fixtures/make_fixtures.m
git commit -m "test(batch): add deterministic fixture generator"
```

---

## Task 3: `scan_input_folder` — parsing and grouping

**Files:**
- Create: `BatchCellReg/scan_input_folder.m`
- Create: `tests/BatchCellReg/test_scan_input_folder.m`

- [ ] **Step 1: Write the failing test**

`tests/BatchCellReg/test_scan_input_folder.m`:

```matlab
function tests = test_scan_input_folder
    tests = functiontests(localfunctions);
end

function setupOnce(testCase)
    here = fileparts(mfilename('fullpath'));
    addpath(fullfile(here, 'fixtures'));
    testCase.TestData.flat_dir = make_fixtures();
end

function test_groups_datasets_by_exp_mouse(testCase)
    r = scan_input_folder(testCase.TestData.flat_dir);
    ids = {r.datasets.dataset_id};
    verifyTrue(testCase, ismember('BOWL_D01', ids));
    verifyTrue(testCase, ismember('BOWL_D03', ids));
    verifyTrue(testCase, ismember('BOWL_D05', ids));
end

function test_sessions_are_alphabetical(testCase)
    r = scan_input_folder(testCase.TestData.flat_dir);
    d01 = r.datasets(strcmp({r.datasets.dataset_id}, 'BOWL_D01'));
    session_ids = {d01.sessions.session_id};
    verifyEqual(testCase, session_ids, {'1D', '2D', '3D'});
end

function test_single_session_dataset_flagged(testCase)
    r = scan_input_folder(testCase.TestData.flat_dir);
    d05 = r.datasets(strcmp({r.datasets.dataset_id}, 'BOWL_D05'));
    verifyTrue(testCase, d05.skip);
    verifyMatches(testCase, d05.skip_reason, 'sessions');
end

function test_unparsed_files_listed(testCase)
    r = scan_input_folder(testCase.TestData.flat_dir);
    verifyTrue(testCase, any(contains(r.unparsed, 'README.mat')));
end

function test_duplicate_session_id_is_error(testCase)
    tmp = tempname; mkdir(tmp);
    cleanup = onCleanup(@() rmdir(tmp, 's'));
    A = uint8(zeros(2,4,4));
    save(fullfile(tmp, 'X_M01_1D_a.mat'), 'A');
    save(fullfile(tmp, 'X_M01_1D_b.mat'), 'A');
    r = scan_input_folder(tmp);
    d = r.datasets(strcmp({r.datasets.dataset_id}, 'X_M01'));
    verifyTrue(testCase, d.skip);
    verifyMatches(testCase, d.skip_reason, 'duplicate');
end
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
matlab -batch "addpath('BatchCellReg'); addpath('tests/BatchCellReg/fixtures'); cd tests/BatchCellReg; runtests('test_scan_input_folder')"
```

Expected: failures with "Undefined function `scan_input_folder`".

- [ ] **Step 3: Implement `scan_input_folder.m`**

`BatchCellReg/scan_input_folder.m`:

```matlab
function result = scan_input_folder(input_folder)
%SCAN_INPUT_FOLDER Group .mat session files by (experiment, mouse).
%
%   result.datasets(k).dataset_id           '<EXP>_<MOUSE>'
%   result.datasets(k).exp_id
%   result.datasets(k).mouse_id
%   result.datasets(k).sessions(j).session_id  '1D' / '1D_1T' / ...
%   result.datasets(k).sessions(j).file_path
%   result.datasets(k).skip                 logical
%   result.datasets(k).skip_reason          string
%   result.unparsed                         cellstr of filenames

    pattern = '^([A-Za-z0-9]+)_([A-Za-z]{1,2}\d{2})_(\dD|\dT)(_\dT)?.*\.mat$';

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
        sid = tok{3};
        if numel(tok) >= 4 && ~isempty(tok{4})
            sid = [sid tok{4}]; %#ok<AGROW>
        end
        parsed(end+1) = struct( ...
            'exp', tok{1}, 'mouse', tok{2}, 'session_id', sid, ...
            'file_path', fullfile(input_folder, name), 'name', name); %#ok<AGROW>
    end

    % Sort all parsed entries alphabetically by filename (drives session order).
    if ~isempty(parsed)
        [~, order] = sort({parsed.name});
        parsed = parsed(order);
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

    result = struct('datasets', datasets, 'unparsed', {unparsed});
end
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
matlab -batch "addpath('BatchCellReg'); addpath('tests/BatchCellReg/fixtures'); cd tests/BatchCellReg; runtests('test_scan_input_folder')"
```

Expected: `Totals: 5 Passed, 0 Failed`.

- [ ] **Step 5: Commit**

```bash
git add BatchCellReg/scan_input_folder.m tests/BatchCellReg/test_scan_input_folder.m
git commit -m "feat(batch): scan flat folder and group sessions by (exp, mouse)"
```

---

## Task 4: `prepare_session_files` — silent double conversion

**Files:**
- Create: `BatchCellReg/prepare_session_files.m`
- Create: `tests/BatchCellReg/test_prepare_session_files.m`

- [ ] **Step 1: Write the failing test**

`tests/BatchCellReg/test_prepare_session_files.m`:

```matlab
function tests = test_prepare_session_files
    tests = functiontests(localfunctions);
end

function test_uint8_is_converted_to_double(testCase)
    tmp = [tempname '.mat'];
    cleanup = onCleanup(@() delete(tmp));
    A = uint8(zeros(3, 8, 8));
    A(1, 2, 3) = 200;
    save(tmp, 'A');
    fp = prepare_session_files({tmp});
    verifyTrue(testCase, isa(fp{1}, 'double'));
    verifyEqual(testCase, size(fp{1}), [3 8 8]);
    verifyEqual(testCase, fp{1}(1, 2, 3), 200);
end

function test_double_passthrough_unchanged(testCase)
    tmp = [tempname '.mat'];
    cleanup = onCleanup(@() delete(tmp));
    matrix_data = rand(3, 8, 8);
    save(tmp, 'matrix_data');
    fp = prepare_session_files({tmp});
    verifyTrue(testCase, isa(fp{1}, 'double'));
    verifyEqual(testCase, fp{1}, matrix_data);
end

function test_takes_first_field_like_load_single_session(testCase)
    tmp = [tempname '.mat'];
    cleanup = onCleanup(@() delete(tmp));
    zzz = uint8(ones(2, 4, 4));
    save(tmp, 'zzz');
    fp = prepare_session_files({tmp});
    verifyEqual(testCase, fp{1}, double(zzz));
end
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
matlab -batch "addpath('BatchCellReg'); cd tests/BatchCellReg; runtests('test_prepare_session_files')"
```

Expected: failures with "Undefined function `prepare_session_files`".

- [ ] **Step 3: Implement `prepare_session_files.m`**

`BatchCellReg/prepare_session_files.m`:

```matlab
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
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
matlab -batch "addpath('BatchCellReg'); cd tests/BatchCellReg; runtests('test_prepare_session_files')"
```

Expected: `Totals: 3 Passed, 0 Failed`.

- [ ] **Step 5: Commit**

```bash
git add BatchCellReg/prepare_session_files.m tests/BatchCellReg/test_prepare_session_files.m
git commit -m "feat(batch): silent uint8->double session loader"
```

---

## Task 5: `choose_p_same_by_fpr` — single-pass selection

**Files:**
- Create: `BatchCellReg/choose_p_same_by_fpr.m`
- Create: `tests/BatchCellReg/test_choose_p_same_by_fpr.m`

- [ ] **Step 1: Write the failing test**

`tests/BatchCellReg/test_choose_p_same_by_fpr.m`:

```matlab
function tests = test_choose_p_same_by_fpr
    tests = functiontests(localfunctions);
end

function test_picks_smallest_psame_meeting_fpr(testCase)
    centers = [0.5 0.6 0.7 0.8 0.9];
    fpr     = [0.10 0.05 0.029 0.01 0.005];
    [p, f, unreach] = choose_p_same_by_fpr(centers, fpr, 0.03);
    verifyEqual(testCase, p, 0.7);
    verifyEqual(testCase, f, 0.029);
    verifyFalse(testCase, unreach);
end

function test_returns_best_achievable_when_unreachable(testCase)
    centers = [0.5 0.6 0.7 0.8 0.9];
    fpr     = [0.20 0.15 0.10 0.08 0.07];
    [p, f, unreach] = choose_p_same_by_fpr(centers, fpr, 0.03);
    verifyTrue(testCase, unreach);
    verifyEqual(testCase, f, 0.07);
    verifyEqual(testCase, p, 0.9);
end

function test_first_bin_already_meets(testCase)
    centers = [0.5 0.6 0.7];
    fpr     = [0.01 0.005 0.001];
    [p, f, unreach] = choose_p_same_by_fpr(centers, fpr, 0.03);
    verifyEqual(testCase, p, 0.5);
    verifyEqual(testCase, f, 0.01);
    verifyFalse(testCase, unreach);
end
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
matlab -batch "addpath('BatchCellReg'); cd tests/BatchCellReg; runtests('test_choose_p_same_by_fpr')"
```

Expected: failures with "Undefined function `choose_p_same_by_fpr`".

- [ ] **Step 3: Implement**

`BatchCellReg/choose_p_same_by_fpr.m`:

```matlab
function [p_same, fpr, unreachable] = choose_p_same_by_fpr(centers, fpr_vector, fpr_max)
%CHOOSE_P_SAME_BY_FPR Pick the minimum p_same threshold with FPR <= fpr_max.
%   Falls back to the best (lowest-FPR) threshold if the target is unreachable,
%   in which case `unreachable` is true.
    idx = find(fpr_vector <= fpr_max, 1, 'first');
    if isempty(idx)
        [~, idx] = min(fpr_vector);
        unreachable = true;
    else
        unreachable = false;
    end
    p_same = centers(idx);
    fpr    = fpr_vector(idx);
end
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
matlab -batch "addpath('BatchCellReg'); cd tests/BatchCellReg; runtests('test_choose_p_same_by_fpr')"
```

Expected: `Totals: 3 Passed, 0 Failed`.

- [ ] **Step 5: Commit**

```bash
git add BatchCellReg/choose_p_same_by_fpr.m tests/BatchCellReg/test_choose_p_same_by_fpr.m
git commit -m "feat(batch): single-pass P_same selection by FPR target"
```

---

## Task 6: `collect_match_stats` — per-dataset match statistics

**Files:**
- Create: `BatchCellReg/collect_match_stats.m`
- Create: `tests/BatchCellReg/test_collect_match_stats.m`

- [ ] **Step 1: Write the failing test**

`tests/BatchCellReg/test_collect_match_stats.m`:

```matlab
function tests = test_collect_match_stats
    tests = functiontests(localfunctions);
end

function test_counts_cells_present_in_k_sessions(testCase)
    % rows = cells, cols = sessions. Non-zero = present.
    cell_to_index_map = [ ...
        1 2 3;       % in all 3
        4 0 5;       % in 2
        6 0 0;       % in 1
        7 8 9;       % in all 3
        0 0 10];     % in 1
    s = collect_match_stats(cell_to_index_map);
    % match_stats(1) = total cells = 5
    % match_stats(2) = in all 3 = 2
    % match_stats(3) = in 2 = 1
    % match_stats(4) = in 1 = 2
    verifyEqual(testCase, s.match_stats, [5 2 1 2]);
    verifyEqual(testCase, s.n_cells_per_session, [4 2 4]);
    verifyEqual(testCase, s.pct_in_all, 2/5);
end
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
matlab -batch "addpath('BatchCellReg'); cd tests/BatchCellReg; runtests('test_collect_match_stats')"
```

Expected: "Undefined function `collect_match_stats`".

- [ ] **Step 3: Implement**

`BatchCellReg/collect_match_stats.m`:

```matlab
function s = collect_match_stats(cell_to_index_map)
%COLLECT_MATCH_STATS Per-dataset match statistics from cell_to_index_map.
%   match_stats(1) = total cells
%   match_stats(k+1) for k=1..S = number of cells found in (S - k + 1) sessions,
%                                 i.e. (2)=in all S, (3)=in S-1, ..., (S+1)=in 1.
    present = cell_to_index_map ~= 0;
    cells_per_session_count = sum(present, 2);
    S = size(cell_to_index_map, 2);
    total = size(cell_to_index_map, 1);

    match_stats = zeros(1, S + 1);
    match_stats(1) = total;
    for k = 1:S
        sessions_present = S - (k - 1);
        match_stats(k + 1) = sum(cells_per_session_count == sessions_present);
    end

    s = struct( ...
        'match_stats', match_stats, ...
        'n_cells_per_session', sum(present, 1), ...
        'pct_in_all', match_stats(2) / max(total, 1));
end
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
matlab -batch "addpath('BatchCellReg'); cd tests/BatchCellReg; runtests('test_collect_match_stats')"
```

Expected: `Totals: 1 Passed, 0 Failed`.

- [ ] **Step 5: Commit**

```bash
git add BatchCellReg/collect_match_stats.m tests/BatchCellReg/test_collect_match_stats.m
git commit -m "feat(batch): compute per-dataset match statistics"
```

---

## Task 7: `batch_logger` — two-channel logger

**Files:**
- Create: `BatchCellReg/batch_logger.m`
- Create: `tests/BatchCellReg/test_batch_logger.m`

- [ ] **Step 1: Write the failing test**

`tests/BatchCellReg/test_batch_logger.m`:

```matlab
function tests = test_batch_logger
    tests = functiontests(localfunctions);
end

function test_writes_to_file_and_live(testCase)
    tmp = [tempname '.txt'];
    cleanup = onCleanup(@() delete(tmp));
    captured = {};
    live = @(msg) (captured = [captured, {msg}]);
    log = batch_logger(tmp, live);
    log.info('GLOBAL', 'starting');
    log.warn('BOWL_D01', 'check this');
    log.error('BOWL_D03', 'failed: %s', 'x');
    log.close();

    text = fileread(tmp);
    verifyTrue(testCase, contains(text, 'INFO'));
    verifyTrue(testCase, contains(text, 'WARN'));
    verifyTrue(testCase, contains(text, 'ERROR'));
    verifyTrue(testCase, contains(text, 'starting'));
    verifyTrue(testCase, contains(text, 'failed: x'));
end

function test_no_live_callback_is_ok(testCase)
    tmp = [tempname '.txt'];
    cleanup = onCleanup(@() delete(tmp));
    log = batch_logger(tmp, []);
    log.info('GLOBAL', 'hello');
    log.close();
    verifyTrue(testCase, contains(fileread(tmp), 'hello'));
end
```

Note: capturing into a closure variable from a function handle in MATLAB requires the helper to be in a function with a `nested` scope, or use a `handle` container. To keep the test simple, rewrite using a small file-backed sink:

Replace test_writes_to_file_and_live with a version that uses a second file as the "live" channel:

```matlab
function test_writes_to_file_and_live(testCase)
    file_path = [tempname '.txt'];
    live_path = [tempname '.txt'];
    cleanup = onCleanup(@() cellfun(@delete, {file_path, live_path}));
    fid_live = fopen(live_path, 'w');
    live = @(msg) fprintf(fid_live, '%s\n', msg);
    log = batch_logger(file_path, live);
    log.info('GLOBAL', 'starting');
    log.warn('BOWL_D01', 'check this');
    log.error('BOWL_D03', 'failed: %s', 'x');
    log.close();
    fclose(fid_live);

    file_text = fileread(file_path);
    live_text = fileread(live_path);
    verifyTrue(testCase, contains(file_text, 'INFO'));
    verifyTrue(testCase, contains(file_text, 'WARN'));
    verifyTrue(testCase, contains(file_text, 'ERROR'));
    verifyTrue(testCase, contains(live_text, 'starting'));
    verifyTrue(testCase, contains(live_text, 'failed: x'));
end
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
matlab -batch "addpath('BatchCellReg'); cd tests/BatchCellReg; runtests('test_batch_logger')"
```

Expected: "Undefined function `batch_logger`".

- [ ] **Step 3: Implement**

`BatchCellReg/batch_logger.m`:

```matlab
function log = batch_logger(file_path, live_callback)
%BATCH_LOGGER Returns a struct of logging functions writing to file + live.
%   live_callback: function handle taking a single formatted string, or [].
    fid = fopen(file_path, 'w');
    if fid < 0
        error('BatchCellReg:LogOpen', 'Cannot open log file %s', file_path);
    end

    log.info  = @(tag, fmt, varargin) emit('INFO',  tag, fmt, varargin);
    log.warn  = @(tag, fmt, varargin) emit('WARN',  tag, fmt, varargin);
    log.error = @(tag, fmt, varargin) emit('ERROR', tag, fmt, varargin);
    log.close = @() do_close();

    function emit(level, tag, fmt, args)
        msg = sprintf(fmt, args{:});
        line = sprintf('[%s] [%s] %s: %s', datestr(now, 'HH:MM:SS'), level, tag, msg);
        fprintf(fid, '%s\n', line);
        if ~isempty(live_callback)
            live_callback(line);
        end
    end

    function do_close()
        if fid >= 0
            fclose(fid);
            fid = -1;
        end
    end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
matlab -batch "addpath('BatchCellReg'); cd tests/BatchCellReg; runtests('test_batch_logger')"
```

Expected: `Totals: 2 Passed, 0 Failed`.

- [ ] **Step 5: Commit**

```bash
git add BatchCellReg/batch_logger.m tests/BatchCellReg/test_batch_logger.m
git commit -m "feat(batch): file + live two-channel logger"
```

---

## Task 8: `detect_anomalies` — six anomaly checks

**Files:**
- Create: `BatchCellReg/detect_anomalies.m`
- Create: `tests/BatchCellReg/test_detect_anomalies.m`

- [ ] **Step 1: Write the failing test**

`tests/BatchCellReg/test_detect_anomalies.m`:

```matlab
function tests = test_detect_anomalies
    tests = functiontests(localfunctions);
end

function thresh = default_thresholds()
    thresh = struct( ...
        'z_threshold', 2.0, ...
        'max_translation_px', 30, ...
        'min_xcorr', 0.3, ...
        'max_mse', 0.05);
end

function r = make_result(id, sessions, ncells, mstats, xcorr, shift, mse, unreach, ref)
    r = struct( ...
        'dataset_id', id, ...
        'sessions', {sessions}, ...
        'n_cells_per_session', ncells, ...
        'match_stats', mstats, ...
        'maximal_cross_correlation', xcorr, ...
        'alignment_shift_px', shift, ...
        'reference_session_index', ref, ...
        'MSE_model', mse, ...
        'p_same_unreachable', unreach, ...
        'chosen_fpr', 0.02, ...
        'error', '');
end

function test_population_pct_match_outlier(testCase)
    % Three datasets at ~0.3, one at 0.05 (outlier).
    rs = [];
    for k = 1:3
        rs = [rs, make_result(sprintf('A%d',k), {'1D','2D'}, [10 10], [10 3 7], [0.5 0.5], [0 1], 0.005, false, 1)]; %#ok<AGROW>
    end
    rs = [rs, make_result('B', {'1D','2D'}, [10 10], [10 1 9], [0.5 0.5], [0 1], 0.005, false, 1)];
    a = detect_anomalies(rs, default_thresholds());
    flags = a.flags;
    verifyTrue(testCase, flags(strcmp({a.dataset_ids}, 'B')).W1);
    verifyFalse(testCase, flags(strcmp({a.dataset_ids}, 'A1')).W1);
end

function test_low_xcorr_hard(testCase)
    rs = make_result('A1', {'1D','2D'}, [10 10], [10 3 7], [1.0 0.25], [0 1], 0.005, false, 1);
    a = detect_anomalies(rs, default_thresholds());
    verifyTrue(testCase, a.flags.W3a);
end

function test_large_shift_hard_excludes_reference(testCase)
    rs = make_result('A1', {'1D','2D','3D'}, [10 10 10], [10 5 3 2], [1 0.6 0.6], [0 5 40], 0.005, false, 1);
    a = detect_anomalies(rs, default_thresholds());
    verifyTrue(testCase, a.flags.W5a);
end

function test_fpr_unreachable(testCase)
    rs = make_result('A1', {'1D','2D'}, [10 10], [10 3 7], [1 0.6], [0 5], 0.005, true, 1);
    a = detect_anomalies(rs, default_thresholds());
    verifyTrue(testCase, a.flags.W4);
end

function test_high_mse_hard(testCase)
    rs = make_result('A1', {'1D','2D'}, [10 10], [10 3 7], [1 0.6], [0 5], 0.08, false, 1);
    a = detect_anomalies(rs, default_thresholds());
    verifyTrue(testCase, a.flags.W6a);
end

function test_relative_check_skipped_when_too_few_samples(testCase)
    % 2 sessions => 1 non-reference shift => W5b should NOT flag.
    rs = make_result('A1', {'1D','2D'}, [10 10], [10 3 7], [1 0.6], [0 100], 0.005, false, 1);
    a = detect_anomalies(rs, default_thresholds());
    verifyFalse(testCase, a.flags.W5b);
    % But hard threshold still fires.
    verifyTrue(testCase, a.flags.W5a);
end
```

- [ ] **Step 2: Run test to verify it fails**

```powershell
matlab -batch "addpath('BatchCellReg'); cd tests/BatchCellReg; runtests('test_detect_anomalies')"
```

Expected: "Undefined function `detect_anomalies`".

- [ ] **Step 3: Implement**

`BatchCellReg/detect_anomalies.m`:

```matlab
function out = detect_anomalies(results, thresh)
%DETECT_ANOMALIES Six per-dataset anomaly checks against thresholds.
%   results: struct array (see run_single_dataset). Failed datasets (error nonempty)
%     are skipped — their flags struct is returned with all false.
%   thresh: struct with fields z_threshold, max_translation_px, min_xcorr, max_mse.
    n = numel(results);
    dataset_ids = {results.dataset_id};
    flags_template = struct('W1',false,'W2',false,'W3a',false,'W3b',false, ...
        'W4',false,'W5a',false,'W5b',false,'W6a',false,'W6b',false);
    flags = repmat(flags_template, 1, n);
    metrics = repmat(struct( ...
        'W3a_min_xcorr', NaN, 'W5a_max_shift', NaN, ...
        'W6a_mse', NaN, 'fpr', NaN, 'pct_in_all', NaN), 1, n);

    succeeded = arrayfun(@(r) isempty(r.error), results);

    % Batch-level vectors for population z-scores (W1, W6b).
    pct_in_all = nan(1, n);
    mse_vec    = nan(1, n);
    for k = find(succeeded)
        pct_in_all(k) = results(k).match_stats(2) / max(results(k).match_stats(1), 1);
        mse_vec(k)    = results(k).MSE_model;
        metrics(k).pct_in_all = pct_in_all(k);
        metrics(k).W6a_mse    = results(k).MSE_model;
        metrics(k).fpr        = results(k).chosen_fpr;
    end

    z1 = zscore_safe(pct_in_all);
    z6 = zscore_safe(mse_vec);

    for k = find(succeeded)
        r = results(k);

        % W1: pct_in_all population outlier (need >= 3 succeeded)
        if sum(succeeded) >= 3 && abs(z1(k)) > thresh.z_threshold
            flags(k).W1 = true;
        end

        % W2: n_cells_per_session intra-dataset outlier
        n_cells = r.n_cells_per_session;
        if numel(n_cells) >= 3
            z2 = zscore_safe(n_cells);
            if any(abs(z2) > thresh.z_threshold)
                flags(k).W2 = true;
            end
        end

        % W3a/W3b: cross-correlation
        xc = r.maximal_cross_correlation(:);
        if any(xc < thresh.min_xcorr)
            flags(k).W3a = true;
            metrics(k).W3a_min_xcorr = min(xc);
        end
        if numel(xc) >= 3
            z3 = zscore_safe(xc);
            if any(abs(z3) > thresh.z_threshold)
                flags(k).W3b = true;
            end
        end

        % W4: FPR unreachable
        if r.p_same_unreachable
            flags(k).W4 = true;
        end

        % W5a/W5b: alignment shift; exclude reference session.
        shifts = r.alignment_shift_px(:);
        ref = r.reference_session_index;
        non_ref = shifts; non_ref(ref) = [];
        if ~isempty(non_ref) && max(abs(non_ref)) > thresh.max_translation_px
            flags(k).W5a = true;
            metrics(k).W5a_max_shift = max(abs(non_ref));
        end
        if numel(non_ref) >= 3
            z5 = zscore_safe(non_ref);
            if any(abs(z5) > thresh.z_threshold)
                flags(k).W5b = true;
            end
        end

        % W6a/W6b: model MSE
        if r.MSE_model > thresh.max_mse
            flags(k).W6a = true;
        end
        if sum(succeeded) >= 3 && abs(z6(k)) > thresh.z_threshold
            flags(k).W6b = true;
        end
    end

    out = struct( ...
        'dataset_ids', {dataset_ids}, ...
        'flags', flags, ...
        'metrics', metrics);
end

function z = zscore_safe(v)
    v = v(:);
    mu = mean(v, 'omitnan');
    sd = std(v, 0, 'omitnan');
    if sd == 0 || isnan(sd)
        z = zeros(size(v));
    else
        z = (v - mu) / sd;
    end
end
```

- [ ] **Step 4: Run tests to verify they pass**

```powershell
matlab -batch "addpath('BatchCellReg'); cd tests/BatchCellReg; runtests('test_detect_anomalies')"
```

Expected: `Totals: 6 Passed, 0 Failed`.

- [ ] **Step 5: Commit**

```bash
git add BatchCellReg/detect_anomalies.m tests/BatchCellReg/test_detect_anomalies.m
git commit -m "feat(batch): six-check anomaly detector with hard + relative thresholds"
```

---

## Task 9: `run_single_dataset` — wrap demo.m stages 1–5

This is the integration heart of the engine. No new test class here — we'll add an end-to-end smoke test in Task 11 that exercises it through `batch_run`.

**Files:**
- Create: `BatchCellReg/run_single_dataset.m`

- [ ] **Step 1: Implement `run_single_dataset.m`**

`BatchCellReg/run_single_dataset.m`:

```matlab
function result = run_single_dataset(dataset, cfg, out_subdir, logger)
%RUN_SINGLE_DATASET Run CellReg Stages 1-5 on one (exp, mouse) dataset.
%
%   dataset: struct from scan_input_folder (one element of result.datasets).
%   cfg:     full batch config struct (see batch_default_config).
%   out_subdir: directory to write outputs into (created if missing).
%   logger: batch_logger handle.

    figures_dir = fullfile(out_subdir, 'Figures');
    if ~exist(figures_dir, 'dir'); mkdir(figures_dir); end
    fig_vis = cfg.cellreg.figures_visibility;

    tag = dataset.dataset_id;
    logger.info(tag, 'sessions: %s', strjoin({dataset.sessions.session_id}, ', '));

    file_paths = {dataset.sessions.file_path};
    spatial_footprints = prepare_session_files(file_paths);

    microns_per_pixel = cfg.cellreg.microns_per_pixel;
    alignment_type    = cfg.cellreg.alignment_type;
    use_parallel      = cfg.cellreg.use_parallel_processing;
    max_rot           = cfg.cellreg.maximal_rotation;
    ref_idx           = cfg.cellreg.reference_session_index;
    max_dist          = cfg.cellreg.maximal_distance_um;
    norm_max_dist     = max_dist / microns_per_pixel;
    p_same_certainty  = 0.95;

    logger.info(tag, 'stage 2: aligning');
    [normalized_spatial_footprints] = normalize_spatial_footprints(spatial_footprints);
    [adjusted_spatial_footprints, adjusted_FOV, ax, ay, adj_pad] = ...
        adjust_FOV_size(normalized_spatial_footprints);
    [adjusted_footprints_projections] = compute_footprints_projections(adjusted_spatial_footprints);
    [centroid_locations] = compute_centroid_locations(adjusted_spatial_footprints, microns_per_pixel);
    [centroid_projections] = compute_centroids_projections(centroid_locations, adjusted_spatial_footprints);

    sufficient_corr_centroids  = 0.2;
    sufficient_corr_footprints = 0.3;
    if strcmp(alignment_type, 'Translations and Rotations')
        [sfp_c, cl_c, fpr_c, cp_c, max_xcorr, alignment_translations, overlapping_FOV] = ...
            align_images(adjusted_spatial_footprints, centroid_locations, ...
                adjusted_footprints_projections, centroid_projections, adjusted_FOV, ...
                microns_per_pixel, ref_idx, alignment_type, ...
                sufficient_corr_centroids, sufficient_corr_footprints, use_parallel, max_rot);
    else
        [sfp_c, cl_c, fpr_c, cp_c, max_xcorr, alignment_translations, overlapping_FOV] = ...
            align_images(adjusted_spatial_footprints, centroid_locations, ...
                adjusted_footprints_projections, centroid_projections, adjusted_FOV, ...
                microns_per_pixel, ref_idx, alignment_type, ...
                sufficient_corr_centroids, sufficient_corr_footprints, use_parallel);
    end
    [all_proj_corr, n_cells_per_session] = evaluate_data_quality( ...
        sfp_c, cp_c, fpr_c, max_xcorr, alignment_translations, ref_idx, ...
        sufficient_corr_footprints, alignment_type);
    plot_alignment_results(adjusted_spatial_footprints, centroid_locations, sfp_c, cl_c, ...
        adjusted_footprints_projections, fpr_c, ref_idx, all_proj_corr, max_xcorr, ...
        alignment_translations, overlapping_FOV, alignment_type, n_cells_per_session, ...
        figures_dir, fig_vis);

    logger.info(tag, 'stage 3: probabilistic model');
    [n_bins, centers_of_bins] = estimate_number_of_bins(spatial_footprints, norm_max_dist);
    [a2a_idx, a2a_sc, a2a_cd, neighb_sc, neighb_cd, neighb_dx, neighb_dy, NN_sc, NNN_sc, NN_cd, NNN_cd] = ...
        compute_data_distribution(sfp_c, cl_c, norm_max_dist);

    [cd_pars, p_given_cd, cd_dist, cd_same, cd_diff, cd_wsum, MSE_cd, cd_intersect] = ...
        compute_centroid_distances_model(neighb_cd, microns_per_pixel, centers_of_bins);
    [sc_pars, p_given_sc, sc_dist, sc_same, sc_diff, sc_wsum, MSE_sc, sc_intersect] = ...
        compute_spatial_correlations_model(neighb_sc, centers_of_bins);

    [p_same_centers, unc_cd, cdf_cd, fpr_cd, tpr_cd, unc_sc, cdf_sc, fpr_sc, tpr_sc] = ...
        estimate_registration_accuracy(p_same_certainty, neighb_cd, cd_same, cd_diff, ...
            p_given_cd, centers_of_bins, neighb_sc, sc_same, sc_diff, p_given_sc);

    best_model = choose_best_model(MSE_cd, cd_same, cd_diff, p_given_cd, ...
        MSE_sc, sc_same, sc_diff, p_given_sc);

    [a2a_psame_cd, a2a_psame_sc] = compute_p_same(a2a_cd, p_given_cd, centers_of_bins, ...
        a2a_sc, p_given_sc);

    % --- auto P_same ---
    if strcmp(best_model, 'Spatial correlation')
        fpr_vec = fpr_sc; mse_val = MSE_sc;
    else
        fpr_vec = fpr_cd; mse_val = MSE_cd;
    end
    [p_same_thr, chosen_fpr, p_same_unreachable] = ...
        choose_p_same_by_fpr(p_same_centers, fpr_vec, cfg.p_same_tuning.fpr_max);
    logger.info(tag, 'chosen P_same=%.3f, FPR=%.4f [model=%s]', ...
        p_same_thr, chosen_fpr, best_model);
    if p_same_unreachable
        logger.warn(tag, 'FPR target %.3f unreachable; closest=%.4f', ...
            cfg.p_same_tuning.fpr_max, chosen_fpr);
    end

    logger.info(tag, 'stage 4: initial registration');
    if strcmp(best_model, 'Spatial correlation')
        if ~isempty(sc_intersect); init_thresh = sc_intersect; else; init_thresh = 0.65; end
        [cell_to_index_map, reg_sc, nonreg_sc] = ...
            initial_registration_spatial_correlations(norm_max_dist, init_thresh, sfp_c, cl_c);
    else
        if ~isempty(cd_intersect); init_thresh = cd_intersect; else; init_thresh = 5; end
        norm_dist_thresh = init_thresh / microns_per_pixel;
        [cell_to_index_map, reg_cd, nonreg_cd] = ...
            initial_registration_centroid_distances(norm_max_dist, norm_dist_thresh, cl_c);
    end

    logger.info(tag, 'stage 5: clustering');
    if strcmp(best_model, 'Spatial correlation')
        [opt_map, reg_centroids, cell_scores, cs_pos, cs_neg, cs_excl, p_same_pairs] = ...
            cluster_cells(cell_to_index_map, a2a_psame_sc, a2a_idx, norm_max_dist, ...
                p_same_thr, cl_c, 'Probabilistic', false);
    else
        [opt_map, reg_centroids, cell_scores, cs_pos, cs_neg, cs_excl, p_same_pairs] = ...
            cluster_cells(cell_to_index_map, a2a_psame_cd, a2a_idx, norm_max_dist, ...
                p_same_thr, cl_c, 'Probabilistic', false);
    end

    is_in_FOV = check_if_in_overlapping_FOV(reg_centroids, overlapping_FOV);
    plot_all_registered_projections(sfp_c, opt_map, figures_dir, fig_vis);

    % --- assemble and save vendor struct ---
    crs = struct();
    crs.cell_to_index_map = opt_map;
    crs.cell_scores = cell_scores';
    crs.true_positive_scores = cs_pos';
    crs.true_negative_scores = cs_neg';
    crs.exclusivity_scores = cs_excl';
    crs.p_same_registered_pairs = p_same_pairs';
    crs.is_cell_in_overlapping_FOV = is_in_FOV';
    crs.registered_cells_centroids = reg_centroids';
    crs.centroid_locations_corrected = cl_c';
    crs.spatial_footprints_corrected = sfp_c';
    crs.alignment_x_translations = alignment_translations(1, :);
    crs.alignment_y_translations = alignment_translations(2, :);
    if strcmp(alignment_type, 'Translations and Rotations')
        crs.alignment_rotations = alignment_translations(3, :);
    end
    crs.adjustment_x_zero_padding = adj_pad(1, :);
    crs.adjustment_y_zero_padding = adj_pad(2, :);

    stamp = datestr(clock, 'yyyymmdd_HHMMss');
    save(fullfile(out_subdir, ['cellRegistered_' stamp '.mat']), 'crs', '-v7.3');
    if strcmp(best_model, 'Spatial correlation')
        save_log_file(out_subdir, file_paths, microns_per_pixel, ax, ay, ...
            alignment_type, ref_idx, max_dist, n_bins, best_model, init_thresh, ...
            'Probabilistic', best_model, p_same_thr, opt_map, crs, '', ...
            unc_sc, fpr_sc, tpr_sc, MSE_sc);
    else
        save_log_file(out_subdir, file_paths, microns_per_pixel, ax, ay, ...
            alignment_type, ref_idx, max_dist, n_bins, best_model, init_thresh, ...
            'Probabilistic', best_model, p_same_thr, opt_map, crs, '', ...
            unc_cd, fpr_cd, tpr_cd, MSE_cd);
    end

    % --- result for anomaly detector ---
    stats = collect_match_stats(opt_map);
    shifts_px = sqrt(alignment_translations(1, :).^2 + alignment_translations(2, :).^2);

    result = struct();
    result.dataset_id = dataset.dataset_id;
    result.sessions = {dataset.sessions.session_id};
    result.n_cells_per_session = stats.n_cells_per_session;
    result.match_stats = stats.match_stats;
    result.maximal_cross_correlation = max_xcorr;
    result.alignment_translations = alignment_translations;
    result.alignment_shift_px = shifts_px;
    result.reference_session_index = ref_idx;
    result.MSE_model = mse_val;
    result.best_model_string = best_model;
    result.chosen_p_same = p_same_thr;
    result.chosen_fpr = chosen_fpr;
    result.p_same_unreachable = p_same_unreachable;
    result.error = '';
end
```

- [ ] **Step 2: Commit (no test yet — integration is exercised in Task 11)**

```bash
git add BatchCellReg/run_single_dataset.m
git commit -m "feat(batch): wrap CellReg stages 1-5 for one dataset"
```

---

## Task 10: `batch_run` — orchestrator

**Files:**
- Create: `BatchCellReg/batch_run.m`

- [ ] **Step 1: Implement**

`BatchCellReg/batch_run.m`:

```matlab
function summary = batch_run(input_folder, cfg, opts)
%BATCH_RUN Orchestrate scan -> per-dataset run -> anomaly detection.
%
%   input_folder: path scanned for session files.
%   cfg:         full batch config struct.
%   opts (struct, all optional):
%     .live_log_callback   function handle (msg) for GUI
%     .stop_check          function handle returning logical (set true to stop)
%     .selected_datasets   cell array of dataset_ids to run (default: all non-skip)
%
%   Returns summary struct: results, anomalies, output_dir, log_file, results_csv,
%   detail_csv, n_succeeded, n_failed, n_with_warnings, stopped.

    if nargin < 3; opts = struct(); end
    if ~isfield(opts, 'live_log_callback'); opts.live_log_callback = []; end
    if ~isfield(opts, 'stop_check'); opts.stop_check = @() false; end
    if ~isfield(opts, 'selected_datasets'); opts.selected_datasets = {}; end

    scan = scan_input_folder(input_folder);

    output_dir = fullfile(input_folder, cfg.io.output_subfolder_name);
    if ~exist(output_dir, 'dir'); mkdir(output_dir); end
    log_file = fullfile(output_dir, sprintf('_batch_log_%s.txt', datestr(now, 'yyyymmdd_HHMMSS')));
    logger = batch_logger(log_file, opts.live_log_callback);
    cleanup = onCleanup(@() logger.close());

    config_to_json(cfg, fullfile(output_dir, '_batch_config.json'));
    logger.info('GLOBAL', 'input=%s, output=%s, datasets=%d, unparsed=%d', ...
        input_folder, output_dir, numel(scan.datasets), numel(scan.unparsed));

    results = [];
    stopped = false;
    for k = 1:numel(scan.datasets)
        d = scan.datasets(k);
        if opts.stop_check()
            stopped = true;
            logger.info('GLOBAL', 'stop requested; %d datasets not processed', ...
                numel(scan.datasets) - k + 1);
            break
        end
        if d.skip
            logger.warn(d.dataset_id, 'skipped: %s', d.skip_reason);
            continue
        end
        if ~isempty(opts.selected_datasets) && ~ismember(d.dataset_id, opts.selected_datasets)
            logger.info(d.dataset_id, 'skipped: not selected');
            continue
        end
        sub = fullfile(output_dir, d.dataset_id);
        if ~exist(sub, 'dir'); mkdir(sub); end
        try
            r = run_single_dataset(d, cfg, sub, logger);
            logger.info(d.dataset_id, 'done (%d cells)', r.match_stats(1));
        catch ME
            r = struct();
            r.dataset_id = d.dataset_id;
            r.error = ME.message;
            logger.error(d.dataset_id, 'FAILED: %s', ME.message);
            logger.error(d.dataset_id, 'Stack: %s', getReport(ME, 'basic'));
        end
        results = [results, normalize_result(r)]; %#ok<AGROW>
    end

    anomalies = detect_anomalies(results, cfg.anomaly_thresholds);

    [results_csv, detail_csv] = export_results(results, anomalies, output_dir);

    n_succeeded = sum(arrayfun(@(r) isempty(r.error), results));
    n_failed    = numel(results) - n_succeeded;
    n_warned    = count_with_warnings(anomalies);
    logger.info('GLOBAL', 'summary: %d succeeded, %d failed, %d with warnings', ...
        n_succeeded, n_failed, n_warned);

    if cfg.cellreg.use_parallel_processing
        delete(gcp('nocreate'));
    end

    summary = struct( ...
        'results', results, ...
        'anomalies', anomalies, ...
        'output_dir', output_dir, ...
        'log_file', log_file, ...
        'results_csv', results_csv, ...
        'detail_csv', detail_csv, ...
        'n_succeeded', n_succeeded, ...
        'n_failed', n_failed, ...
        'n_with_warnings', n_warned, ...
        'stopped', stopped);
end

function r = normalize_result(r)
    defaults = struct( ...
        'sessions', {{}}, 'n_cells_per_session', [], 'match_stats', [0 0], ...
        'maximal_cross_correlation', [], 'alignment_translations', [], ...
        'alignment_shift_px', [], 'reference_session_index', 1, ...
        'MSE_model', NaN, 'best_model_string', '', 'chosen_p_same', NaN, ...
        'chosen_fpr', NaN, 'p_same_unreachable', false);
    fns = fieldnames(defaults);
    for k = 1:numel(fns)
        if ~isfield(r, fns{k})
            r.(fns{k}) = defaults.(fns{k});
        end
    end
    if ~isfield(r, 'error'); r.error = ''; end
end

function n = count_with_warnings(a)
    if isempty(a.flags); n = 0; return; end
    cnt = 0;
    fns = fieldnames(a.flags(1));
    for k = 1:numel(a.flags)
        if any(structfun(@(x) x, a.flags(k)))
            cnt = cnt + 1;
        end
    end
    n = cnt;
end

function [results_csv, detail_csv] = export_results(results, anomalies, output_dir)
    results_csv = fullfile(output_dir, '_batch_results.csv');
    detail_csv  = fullfile(output_dir, '_batch_warnings_detail.csv');

    rows = {};
    rows(end+1, :) = {'dataset_id', 'n_sessions', 'n_cells', 'pct_in_all', 'chosen_fpr', ...
        'W1','W2','W3a','W3b','W4','W5a','W5b','W6a','W6b', ...
        'W3a_min_xcorr', 'W5a_max_shift_px', 'W6a_mse', 'error'};
    for k = 1:numel(results)
        r = results(k);
        f = anomalies.flags(k); m = anomalies.metrics(k);
        rows(end+1, :) = { ...
            r.dataset_id, numel(r.sessions), maybe_first(r.match_stats), ...
            ratio(r.match_stats), r.chosen_fpr, ...
            f.W1, f.W2, f.W3a, f.W3b, f.W4, f.W5a, f.W5b, f.W6a, f.W6b, ...
            m.W3a_min_xcorr, m.W5a_max_shift, m.W6a_mse, r.error}; %#ok<AGROW>
    end
    write_cell_csv(rows, results_csv);

    detail = {'dataset_id', 'session', 'anomaly_type', 'value', 'threshold'};
    for k = 1:numel(results)
        r = results(k); f = anomalies.flags(k); m = anomalies.metrics(k);
        if ~isempty(r.error); continue; end
        if f.W3a
            [v, idx] = min(r.maximal_cross_correlation(:));
            detail(end+1, :) = {r.dataset_id, sess_at(r, idx), 'W3a_low_xcorr_hard', v, NaN}; %#ok<AGROW>
        end
        if f.W5a
            shifts = r.alignment_shift_px; shifts(r.reference_session_index) = NaN;
            [v, idx] = max(abs(shifts));
            detail(end+1, :) = {r.dataset_id, sess_at(r, idx), 'W5a_shift_hard', v, NaN}; %#ok<AGROW>
        end
        if f.W4
            detail(end+1, :) = {r.dataset_id, '-', 'W4_fpr_unreachable', r.chosen_fpr, NaN}; %#ok<AGROW>
        end
        if f.W6a
            detail(end+1, :) = {r.dataset_id, '-', 'W6a_mse_hard', r.MSE_model, NaN}; %#ok<AGROW>
        end
        if f.W1
            detail(end+1, :) = {r.dataset_id, '-', 'W1_pct_match_outlier', m.pct_in_all, NaN}; %#ok<AGROW>
        end
    end
    write_cell_csv(detail, detail_csv);
end

function s = sess_at(r, idx)
    if idx >= 1 && idx <= numel(r.sessions); s = r.sessions{idx}; else; s = '-'; end
end

function v = maybe_first(s)
    if isempty(s); v = 0; else; v = s(1); end
end

function v = ratio(s)
    if numel(s) < 2 || s(1) == 0; v = NaN; else; v = s(2)/s(1); end
end

function write_cell_csv(rows, path)
    fid = fopen(path, 'w');
    if fid < 0; error('BatchCellReg:CsvWrite', 'Cannot write %s', path); end
    cleanup = onCleanup(@() fclose(fid));
    for r = 1:size(rows, 1)
        line = '';
        for c = 1:size(rows, 2)
            v = rows{r, c};
            if islogical(v); s = ternary(v, '1', '0');
            elseif isnumeric(v) && isscalar(v); s = num2str(v);
            elseif ischar(v); s = strrep(v, ',', ';');
            else; s = ''; end
            if c == 1; line = s; else; line = [line ',' s]; end %#ok<AGROW>
        end
        fprintf(fid, '%s\n', line);
    end
end

function s = ternary(cond, a, b)
    if cond; s = a; else; s = b; end
end
```

- [ ] **Step 2: Commit**

```bash
git add BatchCellReg/batch_run.m
git commit -m "feat(batch): orchestrator with stop, error isolation, CSV export"
```

---

## Task 11: End-to-end smoke test on real `SampleData`

This test uses the vendor `SampleData/` from the repo to verify the full pipeline runs and produces non-empty output. It's slow (~minutes) and lives in a tag-marked file so it can be excluded from quick runs.

**Files:**
- Create: `tests/BatchCellReg/test_end_to_end_sample.m`

- [ ] **Step 1: Write the test**

`tests/BatchCellReg/test_end_to_end_sample.m`:

```matlab
function tests = test_end_to_end_sample
    tests = functiontests(localfunctions);
end

function test_runs_on_sample_data_our(testCase)
    repo_root = fullfile(fileparts(mfilename('fullpath')), '..', '..');
    sample_dir = fullfile(repo_root, 'SampleDataOur');
    if ~exist(sample_dir, 'dir')
        testCase.assumeFail('SampleDataOur not present');
    end
    addpath(genpath(fullfile(repo_root, 'CellReg')));
    addpath(genpath(fullfile(repo_root, 'Helper')));
    addpath(genpath(fullfile(repo_root, 'BatchCellReg')));

    out = fullfile(tempdir, ['BatchCellReg_smoke_' datestr(now,'HHMMSS')]);
    mkdir(out);
    % Mirror sample files into a clean dir so we control teardown.
    copyfile(fullfile(sample_dir, '*.mat'), out);
    cleanup = onCleanup(@() rmdir(out, 's'));

    cfg = batch_default_config();
    cfg.io.input_folder = out;
    cfg.cellreg.use_parallel_processing = false;
    cfg.cellreg.figures_visibility = 'off';

    summary = batch_run(out, cfg);
    verifyGreaterThan(testCase, summary.n_succeeded, 0);
    verifyTrue(testCase, exist(summary.results_csv, 'file') == 2);
    verifyTrue(testCase, exist(summary.log_file, 'file') == 2);
end
```

- [ ] **Step 2: Run the test**

```powershell
matlab -batch "addpath(genpath('CellReg')); addpath(genpath('Helper')); addpath(genpath('BatchCellReg')); cd tests/BatchCellReg; runtests('test_end_to_end_sample')"
```

Expected: PASS (or `Incomplete` if `SampleDataOur` is absent — that's intentional via `assumeFail`).

- [ ] **Step 3: Commit**

```bash
git add tests/BatchCellReg/test_end_to_end_sample.m
git commit -m "test(batch): end-to-end smoke run on SampleDataOur"
```

---

## Task 12: GUI shell — Setup tab

The GUI is built incrementally across Tasks 12–14. Each task adds one working tab and commits.

**Files:**
- Create: `BatchCellReg_GUI/BatchCellReg.m`

- [ ] **Step 1: Implement initial `uifigure` with Setup tab**

`BatchCellReg_GUI/BatchCellReg.m`:

```matlab
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

    save_app(app);
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

    save_app(app);  % helper that merges with whatever was set before
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
    save_app(app);
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
```

- [ ] **Step 2: Smoke-launch and verify the GUI opens**

```powershell
matlab -nodesktop -nosplash -r "addpath('BatchCellReg_GUI'); BatchCellReg; pause(2); close all force; exit"
```

Expected: clean exit, no errors. (`matlab -batch` cannot show `uifigure`s; use `-nodesktop -nosplash`.)

- [ ] **Step 3: Commit**

```bash
git add BatchCellReg_GUI/BatchCellReg.m
git commit -m "feat(batch-gui): Setup tab with folder picker and scan results"
```

---

## Task 13: GUI — Parameters tab

**Files:**
- Modify: `BatchCellReg_GUI/BatchCellReg.m` (replace `build_parameters_tab` body, add `bind_*` helpers)

- [ ] **Step 1: Replace the stub `build_parameters_tab`**

In `BatchCellReg_GUI/BatchCellReg.m`, replace the stub `build_parameters_tab` with:

```matlab
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
        'ButtonPushedFcn', @(s,e) on_load_cfg(app.fig));
    uibutton(t, 'Position', [150 20 120 24], 'Text', 'Save config as...', ...
        'ButtonPushedFcn', @(s,e) on_save_cfg(app.fig));
    uibutton(t, 'Position', [280 20 140 24], 'Text', 'Reset to defaults', ...
        'ButtonPushedFcn', @(s,e) on_reset_cfg(app.fig));
end

function y = section_header(t, label, y)
    uilabel(t, 'Position', [20 y 800 22], 'Text', label, 'FontWeight', 'bold');
    y = y - 28;
end

function y = add_num(t, label, path, y)
    uilabel(t, 'Position', [20 y 220 22], 'Text', label);
    f = uieditfield(t, 'numeric', 'Position', [250 y 100 22]);
    f.Tag = path;
    f.ValueChangedFcn = @(s,e) set_path(s.Parent.Parent.Parent, path, s.Value);
    sync_field_from_config(f);
    y = y - 26;
end

function y = add_bool(t, label, path, y)
    uilabel(t, 'Position', [20 y 220 22], 'Text', label);
    f = uicheckbox(t, 'Position', [250 y 200 22], 'Text', '');
    f.Tag = path;
    f.ValueChangedFcn = @(s,e) set_path(s.Parent.Parent.Parent, path, s.Value);
    sync_field_from_config(f);
    y = y - 26;
end

function y = add_drop(t, label, path, y, items)
    uilabel(t, 'Position', [20 y 220 22], 'Text', label);
    f = uidropdown(t, 'Position', [250 y 200 22], 'Items', items);
    f.Tag = path;
    f.ValueChangedFcn = @(s,e) set_path(s.Parent.Parent.Parent, path, s.Value);
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
```

- [ ] **Step 2: Smoke-launch and verify the tab renders**

```powershell
matlab -nodesktop -nosplash -r "addpath('BatchCellReg_GUI'); BatchCellReg; pause(3); close all force; exit"
```

Expected: clean exit, no errors.

- [ ] **Step 3: Commit**

```bash
git add BatchCellReg_GUI/BatchCellReg.m
git commit -m "feat(batch-gui): Parameters tab bound to config struct with load/save"
```

---

## Task 14: GUI — Run & Results tab

**Files:**
- Modify: `BatchCellReg_GUI/BatchCellReg.m` (replace `build_run_tab` body, add handlers)

- [ ] **Step 1: Replace the stub `build_run_tab`**

In `BatchCellReg_GUI/BatchCellReg.m`, replace `build_run_tab` with:

```matlab
function build_run_tab(app)
    t = uitab(app.tabs, 'Title', 'Run & Results');

    uibutton(t, 'Position', [20 540 80 24], 'Text', 'Run batch', ...
        'ButtonPushedFcn', @(s,e) on_run(app.fig));
    uibutton(t, 'Position', [110 540 80 24], 'Text', 'Stop', ...
        'ButtonPushedFcn', @(s,e) on_stop(app.fig));
    app.ui.progress_label = uilabel(t, 'Position', [200 540 400 24], 'Text', 'idle');

    app.ui.log_area = uitextarea(t, 'Position', [20 320 840 200], 'Editable', 'off');

    app.ui.results_table = uitable(t, 'Position', [20 80 840 230], ...
        'ColumnName', {'Dataset','Sess','Cells','%match','FPR', ...
                       'W1','W2','W3a','W3b','W4','W5a','W5b','W6a','W6b'}, ...
        'ColumnFormat', {'char','numeric','numeric','numeric','numeric', ...
                         'logical','logical','logical','logical','logical', ...
                         'logical','logical','logical','logical'});

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
    rows = cell(n, 14);
    for k = 1:n
        r = summary.results(k); f = summary.anomalies.flags(k);
        if numel(r.match_stats) >= 2; pct = r.match_stats(2)/max(r.match_stats(1),1);
        else; pct = NaN; end
        rows(k, :) = {r.dataset_id, numel(r.sessions), r.match_stats(1), pct, r.chosen_fpr, ...
            f.W1, f.W2, f.W3a, f.W3b, f.W4, f.W5a, f.W5b, f.W6a, f.W6b};
    end
    app.ui.results_table.Data = rows;
end

function on_export(fig, which)
    app = getappdata(fig, 'app');
    if ~isfield(app, 'last_summary')
        uialert(fig, 'No run results yet.', 'Export'); return;
    end
    if strcmp(which, 'results')
        [n, p] = uiputfile('*.csv', 'Save results', '_batch_results.csv');
        if isnumeric(n); return; end
        copyfile(app.last_summary.results_csv, fullfile(p, n));
    else
        [n, p] = uiputfile('*.txt', 'Save log', '_batch_log.txt');
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
```

- [ ] **Step 2: Manual end-to-end check**

```powershell
matlab -nodesktop -nosplash -r "addpath('BatchCellReg_GUI'); BatchCellReg"
```

Walk through manually:
1. Browse to `SampleDataOur`.
2. Click `Scan` — table fills.
3. Switch to `Parameters` — defaults visible; toggle one and verify it persists across tab switches.
4. Switch to `Run & Results`, click `Run batch`.
5. Watch log; verify Results table populates; click `Export results CSV` and verify the file matches `_batch_results.csv` content.

- [ ] **Step 3: Commit**

```bash
git add BatchCellReg_GUI/BatchCellReg.m
git commit -m "feat(batch-gui): Run & Results tab with live log, table, exports"
```

---

## Spec coverage check

| Spec section | Task(s) |
|---|---|
| §3 input parsing, grouping, validation | 3 |
| §3.3 silent conversion | 4 |
| §4 single-dataset pipeline | 9 |
| §5 auto P_same | 5 |
| §6 anomaly detection | 8 |
| §7.1 Setup tab | 12 |
| §7.2 Parameters tab | 13 |
| §7.3 Run & Results tab | 14 |
| §8 config JSON | 1 |
| §9 output layout | 9, 10 |
| §10.1 logger | 7 |
| §10.2 error isolation | 10 |
| §10.3 stop button | 10, 14 |
| §10.4 pool cleanup | 10 |

End-to-end coverage on real data: Task 11.
