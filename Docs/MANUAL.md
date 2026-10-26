# CellRegBatch Manual

This manual is the reference for the batch layer of CellRegBatch. It describes
what the code does, step by step, and every file and number it writes. For a
first run, read the [Guide](GUIDE.md) instead.

CellRegBatch does not change the registration method. The method is CellReg
(Sheintuch et al., 2017, *Cell Reports* 21:1102–1115,
[doi:10.1016/j.celrep.2017.10.013](https://doi.org/10.1016/j.celrep.2017.10.013)).
For the method itself, read that paper and the
[CellReg User Manual](User%20Manual.docx).

**Terms used in this manual**

| Term | Meaning |
|---|---|
| session | One imaging session. One input `.mat` file. |
| dataset | All sessions of one animal in one experiment, for example `CC_H02`. The batch registers each dataset separately. |
| batch | All datasets in one input folder. |
| reference session | The session that the other sessions are aligned to. |
| registered cell | One row of CellReg's `cell_to_index_map`: one cell tracked across sessions. |

## Contents

1. [Input files](#1-input-files)
2. [Running the batch](#2-running-the-batch)
3. [Parameters](#3-parameters)
4. [What happens to each dataset](#4-what-happens-to-each-dataset)
5. [Output files](#5-output-files)
6. [Quality warnings](#6-quality-warnings)
7. [Using the results](#7-using-the-results)
8. [Tests](#8-tests)
9. [Known limitations](#9-known-limitations)

---

## 1. Input files

### 1.1 File content

Each session is one `.mat` file. The batch loads the **first variable** in
the file. This variable must be a 3-D array of spatial footprints with size
N×Y×X: N cells, Y pixels in height, X pixels in width. This is the input
format of CellReg (see `CellReg/load_single_session.m`). Any numeric type is
accepted. The batch converts it to `double`.

To convert outputs of other tools to this format, use the CellReg helpers in
`Helper/`: `format_conversion_Suite2p_CNMF_e.m`,
`format_conversion_inscopix.m`, `s2pToCellReg.m`.

### 1.2 File names

The batch finds the experiment, the animal and the session in the file name.
The name must match this regular expression:

```
^([A-Za-z0-9]+)_([A-Za-z]{1,2}\d{2})_(\dD|\dT)(_\dT)?.*\.mat$
```

| Part | Rule | Examples |
|---|---|---|
| Experiment | Letters and digits. No underscore. | `CC`, `HOS`, `BOWL2` |
| Animal | 1 or 2 letters, then exactly 2 digits. | `H02`, `F54`, `JA07` |
| Session | 1 digit, then `D` (day) or `T` (trial). An optional second part `_<digit>T` follows. | `1D`, `5D`, `2T`, `1D_2T` |
| Rest | Any text before `.mat`. The batch ignores it. | `_filters`, `_converted` |

| File name | Result |
|---|---|
| `CC_H02_1D.mat` | dataset `CC_H02`, session `1D` |
| `CC_H02_3D_filters.mat` | dataset `CC_H02`, session `3D` |
| `NOF_F07_1D_2T_cnmf.mat` | dataset `NOF_F07`, session `1D_2T` |
| `CC_H2_1D.mat` | not parsed: the animal needs 2 digits |
| `CC_H02_10D.mat` | not parsed: the session has 1 digit only |
| `CC-H02-1D.mat` | not parsed: the separators must be `_` |

The batch reads only the files in the input folder itself, not in its
subfolders. It ignores files whose names do not match. The GUI shows how many
files it ignored (**Unparsed files**).

### 1.3 Session order and the reference session

The batch sorts the files of a dataset by the full file name, in alphabetical
order. This order is the session order. Session 1 is the first file. For
example: `1D` < `1D_2T` < `1T` < `2D`.

The reference session is session number `reference_session_index` in this
order (default 1, the first session).

### 1.4 Datasets that are skipped

The scan marks a dataset as skipped when:

- it has fewer than 2 sessions;
- two files give the same session (for example `CC_H02_1D_a.mat` and
  `CC_H02_1D_b.mat`).

A skipped dataset appears in the GUI table with **Run** cleared. The batch log
records the reason.

---

## 2. Running the batch

### 2.1 GUI

Start the GUI from the repository folder:

```matlab
run BatchCellReg_GUI/BatchCellReg.m
```

The GUI adds the folders `BatchCellReg`, `CellReg` and `Helper` to the MATLAB
path for the current session. It does not save the path.

**Setup tab**

![Setup tab](images/gui_setup.png)

| Control | Action |
|---|---|
| Input folder, **Browse...** | Select the folder with the session files. The output folder is shown below it. |
| **Scan** | Read the folder and fill the table. |
| Table | One row per dataset: **Run** (check box), dataset name, number of sessions, session list in session order. |
| Unparsed files | Number of `.mat` files with names that do not match the rule in 1.2. |

Clear **Run** for the datasets that you do not want to process. If you do not
click **Scan**, **Run batch** processes all datasets.

**Parameters tab**

![Parameters tab](images/gui_parameters.png)

The tab shows the most-used parameters. Section 3 describes all of them.

| Button | Action |
|---|---|
| **Load config...** | Load a JSON config file. All values change, also the values that are not shown in the GUI. |
| **Save config as...** | Save the current config to a JSON file. |
| **Reset to defaults** | Set all values to the defaults in `batch_default_config.m`. |

**Registration approach** and **Initial registration** are disabled. Section
4.4 explains why.

**Run & Results tab**

![Run & Results tab](images/gui_results.png)

| Control | Action |
|---|---|
| **Run batch** | Run all datasets that have **Run** set. MATLAB is busy until the batch ends. |
| **Stop** | Stop the batch before the next dataset starts. The current dataset finishes first. |
| **Load results CSV...** | Show a saved `_batch_results.csv` in the table. Use it to look at an earlier batch again. |
| Log area | The batch log, live. It keeps the last 500 lines. The full log is in the output folder. |
| Results table | One row per processed dataset. Columns: dataset, number of sessions, number of registered cells, fraction of registered cells found in all sessions (column **%match**, a fraction from 0 to 1), chosen FPR, then the 12 warning columns. Red cell = severity 2, yellow cell = severity 1. |
| Decode line | Click a warning cell. The line below the table explains the warning. |
| **Export results CSV** | Save a copy of `_batch_results.csv`. |
| **Export log TXT** | Save a copy of the batch log. It works after a run, not after **Load results CSV**. |
| **Open output folder** | Open the output folder in the file explorer (Windows only). |

### 2.2 Script

Use `batch_run` to run the batch without the GUI:

```matlab
addpath(genpath('CellReg')); addpath(genpath('Helper')); addpath(genpath('BatchCellReg'));

cfg = batch_default_config();             % or: cfg = config_from_json('my_config.json');
cfg.cellreg.microns_per_pixel = 1.6;      % set this for your microscope
summary = batch_run('D:\data\5_Filters', cfg);

% Run only some datasets:
opts = struct('selected_datasets', {{'CC_H02', 'CC_H03'}});
summary = batch_run('D:\data\5_Filters', cfg, opts);
```

`batch_run(input_folder, cfg, opts)` uses the `input_folder` argument. It
does not read `cfg.io.input_folder`.

| `opts` field | Meaning |
|---|---|
| `selected_datasets` | Cell array of dataset names to run. Empty (default) = all datasets that are not skipped. |
| `live_log_callback` | Function handle `@(line)`. It receives each log line. |
| `stop_check` | Function handle that returns `true` to stop before the next dataset. |

| `summary` field | Meaning |
|---|---|
| `results` | Struct array, one element per processed dataset (see 4.8). |
| `anomalies` | `.flags` (warning severities) and `.metrics` per dataset. |
| `output_dir`, `log_file`, `results_csv`, `detail_csv` | Paths of the output folder and files. |
| `n_succeeded`, `n_failed`, `n_with_warnings` | Counts. A dataset counts as "with warnings" if any warning is 1 or 2. |
| `stopped` | `true` if the batch stopped early. |

---

## 3. Parameters

The config is a MATLAB struct. `batch_default_config.m` sets the defaults.
`config_to_json` and `config_from_json` save and load it as JSON. Each run
saves the config it used as `_batch_config.json` in the output folder.

To change a parameter that the GUI does not show:

1. Click **Save config as...** and save a JSON file.
2. Open the file in a text editor and change the value.
3. Click **Load config...** and select the file.

| Parameter | GUI | Default | Meaning |
|---|---|---|---|
| `cellreg.microns_per_pixel` | yes | 1.6 | Pixel size of your images in µm. **Set it for your microscope.** All distances and the model use it. |
| `cellreg.alignment_type` | yes | `Translations` | First mode of the alignment cascade (4.3). `Translations and Rotations` starts at the second mode. `Non-rigid` uses only the last mode. |
| `cellreg.maximal_rotation` | yes | 5 | Rotation range in degrees for the second cascade mode. |
| `cellreg.reference_session_index` | yes | 1 | Number of the reference session in session order (1.3). |
| `cellreg.maximal_distance_um` | yes | 15 | CellReg "maximal distance": cell pairs with centroids farther apart are not compared. CellReg's `demo.m` uses 14. In our data a large value (50) made the spatial-correlation model fail on dense fields of view. |
| `cellreg.registration_approach` | disabled | `Probabilistic` | Not used. The batch always uses the probabilistic approach (4.4). |
| `cellreg.initial_registration_type` | disabled | `auto` | Not used. CellReg chooses the model (4.4). |
| `cellreg.use_parallel_processing` | yes | `true` | Use `parfor` in CellReg alignment. Needs the Parallel Computing Toolbox. Turn it off if you do not have the toolbox. |
| `cellreg.figures_visibility` | yes | `off` | `on` shows each CellReg figure while the batch runs. The figures are saved in both cases. |
| `cellreg.write_to_file` | yes | `true` | Write `cellRegistered_*.mat` and `logFile_*.txt` for each dataset. Figures and the batch tables are written in both cases. |
| `cellreg.alignment_min_xcorr` | JSON | 0.2 | Pass criterion for an alignment mode (4.3). |
| `cellreg.expected_n_sessions` | JSON | 5 | Number of sessions you expect per dataset. Used by warning W7. **Set it for your study.** |
| `cellreg.rotation_fallback_deg` | JSON | 90 | Rotation range in degrees for the third cascade mode. |
| `cellreg.nonrigid_smoothness` | JSON | 2 | Smoothness value for the non-rigid mode. CellReg passes it to `imregdemons` as `AccumulatedFieldSmoothing`. |
| `p_same_tuning.fpr_max` | yes | 0.03 | Target false-positive rate for the P_same threshold (4.5). |
| `anomaly_thresholds.z_threshold` | yes | 2.0 | z-score limit for the warnings that use z-scores (section 6). |
| `anomaly_thresholds.max_translation_px` | yes | 30 | Shift limit for W5a, in pixels. |
| `anomaly_thresholds.min_xcorr` | yes | 0.3 | Cross-correlation limit for W3a. |
| `anomaly_thresholds.max_mse` | yes | 0.1 | Model-error limit for W6a. |
| `io.input_folder` | yes | empty | The folder selected in the GUI. `batch_run` does not read it. |
| `io.output_subfolder_name` | JSON | `Matching` | Output folder, relative to the input folder. A path such as `..\6_Matched` is allowed. |
| `version` | – | 1 | Config format version. `config_from_json` refuses other values. |

Some values are fixed in the code:

| Value | Where | Why |
|---|---|---|
| `sufficient_correlation_footprints` = 0.2 and `sufficient_correlation_centroids` = 0.2 | `run_single_dataset.m` | The same values as the CellReg GUI (`GUI/CellReg.m`). CellReg's `demo.m` uses 0.3 for footprints. With 0.3, CellReg rejected rigid alignment for sessions that the CellReg GUI aligns. |
| P_same certainty level = 0.95 | `run_single_dataset.m` | Used by CellReg to estimate the fraction of uncertain cell pairs, as in `demo.m`. |
| W2b_hard ratio limit = 3 | `detect_anomalies.m` | See W2b_hard in section 6. |

---

## 4. What happens to each dataset

The batch processes the datasets one after another. If a dataset stops with
an error, the batch records the error and continues with the next dataset.
`BatchCellReg/run_single_dataset.m` contains all steps below. Except for 4.3
and 4.5, each step calls the same CellReg functions as `CellReg/demo.m`.

### 4.1 Load

`prepare_session_files` loads the first variable of each file (1.1).

### 4.2 Prepare the footprints (CellReg stage 1)

CellReg normalizes the footprints, pads all sessions to the same field of
view, and computes the projections and the centroids.

### 4.3 Align the sessions (CellReg stage 2) with a fallback cascade

The batch calls CellReg's `align_images` with up to four modes, in this order:

| Mode | CellReg alignment type | Parameter |
|---|---|---|
| 1 | `Translations` | – |
| 2 | `Translations and Rotations` | `maximal_rotation` (5°) |
| 3 | `Translations and Rotations` | `rotation_fallback_deg` (90°) |
| 4 | `Non-rigid` | `nonrigid_smoothness` (2) |

The cascade starts at the mode set by `alignment_type`. A mode **passes** when
both are true:

- no session other than the reference is empty after alignment;
- for every non-reference session, the maximal cross-correlation with the
  reference is at least `alignment_min_xcorr` (0.2).

The batch uses the first mode that passes. If a mode fails or stops with an
error, the batch tries the next mode.

If no mode passes, two cases are possible:

- At least one mode left no session empty. The batch uses the mode with the
  highest minimal cross-correlation and continues. The log and the result mark
  this mode as `(forced, low xcorr=...)`. Warning W3a is then always red,
  because the cross-correlation is below 0.2 and W3a fires below 0.3.
- Every mode left a session empty. The dataset fails with the error
  `All alignment modes failed ...`.

### 4.4 Model the cell-pair similarities (CellReg stage 3)

CellReg computes the distributions of centroid distances and spatial
correlations of neighboring cell pairs. It fits a model of same-cell and
different-cell pairs to each distribution and estimates the registration
accuracy.

CellReg's `choose_best_model` then chooses the centroid-distance model or the
spatial-correlation model. It takes the model with the lower sum of false
positives, false negatives and model error (MSE). The batch always uses the
chosen model and always uses the probabilistic approach. For this reason
**Registration approach** and **Initial registration** are disabled in the
GUI. See also the note on `choose_best_model` in section 9.

### 4.5 Choose the P_same threshold (batch layer)

P_same is the probability that two cells from different sessions are the same
cell. CellReg registers a pair when P_same is above a threshold. The CellReg
default threshold is 0.5. The batch chooses the threshold with this rule:

1. Compute the false-positive rate (FPR) at P_same = 0.5.
2. If FPR ≤ `fpr_max` (0.03), use 0.5.
3. If not, increase the threshold in steps of 0.001, up to 0.95. Use the
   first threshold with FPR ≤ `fpr_max`.
4. If no threshold up to 0.95 gives FPR ≤ `fpr_max`, use 0.95 and set
   warning W4.

The FPR is the value that CellReg writes to `logFile_*.txt` as "Fraction of
false positives". The batch computes it the same way as
`CellReg/save_log_file.m`: the cumulative false-positive fraction of the
chosen model, at the threshold rounded to 2 decimals. The batch stores the
value without the final rounding to 0.01 (column `chosen_fpr`).

The code is in `BatchCellReg/choose_p_same_by_fpr.m`.

### 4.6 Initial registration (CellReg stage 4)

CellReg makes an initial registration with the chosen model. The threshold is
the point where the same-cell and different-cell distributions cross. If
CellReg finds no crossing point, the batch uses the `demo.m` defaults: 0.65
for spatial correlation, 5 µm for centroid distance.

### 4.7 Final registration (CellReg stage 5)

CellReg clusters the cells with the probabilistic approach and the P_same
threshold from 4.5. This gives the final `cell_to_index_map` and the cell
scores.

### 4.8 Save

When `write_to_file` is on, the batch first deletes old `cellRegistered_*.mat`
and `logFile_*.txt` files in the dataset folder. Then it writes new ones. Each
dataset folder holds one result.

The result that the batch keeps for the warnings has these fields:
`dataset_id`, `sessions`, `n_cells_per_session`, `match_stats`,
`maximal_cross_correlation`, `alignment_translations`, `alignment_shift_px`,
`reference_session_index`, `MSE_model`, `best_model_string`, `chosen_p_same`,
`chosen_fpr`, `p_same_unreachable`, `alignment_mode`, `forced_low_xcorr`,
`error`. `match_stats(1)` is the number of registered cells.
`match_stats(k+1)` is the number of registered cells found in exactly S−k+1
of the S sessions, so `match_stats(2)` is the number found in all sessions.

The batch closes all figures it opened, also after an error. Without this,
hidden figures fill the memory during a long batch.

---

## 5. Output files

```
<input folder>/
└── Matching/                                  (io.output_subfolder_name)
    ├── _batch_config.json                     config of the last run
    ├── _batch_log_YYYYMMDD_HHMMSS.txt         one log per run
    ├── _batch_results.csv                     one row per processed dataset
    ├── _batch_warnings_detail.csv             one row per fired warning
    └── <dataset>/                             for example CC_H02/
        ├── cellRegistered_YYYYMMDD_HHMMSS.mat
        ├── logFile_YYYYMMDD_HHMMSS.txt
        └── Figures/                           CellReg figures, .fig and .png
```

Each run overwrites `_batch_config.json`, `_batch_results.csv` and
`_batch_warnings_detail.csv`. If a CSV file is open in another program (for
example Excel), the batch tries again 3 times. Then it writes a copy with a
time stamp in the name and gives a MATLAB warning.

### 5.1 `_batch_results.csv`

| Column | Meaning |
|---|---|
| `dataset_id` | Dataset name. |
| `n_sessions` | Number of sessions. |
| `n_cells` | Number of registered cells: rows of `cell_to_index_map`. A cell found in any session counts once. |
| `pct_in_all` | Registered cells found in all sessions ÷ `n_cells`. **A fraction from 0 to 1**, not percent. See 7.2 for another definition. |
| `chosen_fpr` | FPR at the chosen P_same threshold (4.5). |
| `W1` … `W7` | Warning severity: 0 = none, 1 = yellow, 2 = red. See section 6. |
| `W3a_min_xcorr` | Lowest cross-correlation, when W3a fired. Else `NaN`. |
| `W5a_max_shift_px` | Largest shift in pixels, when W5a fired. Else `NaN`. |
| `W6a_mse` | Model error (MSE) of the chosen model. |
| `W2b_ratio` | Largest ÷ smallest number of cells per session. |
| `error` | Error message if the dataset failed. Commas are replaced by `;`. |

A failed dataset has a message in `error`, `n_cells` = 0 and all warning
columns 0. **For a failed dataset, 0 does not mean "no problem".** The batch
does not compute warnings for failed datasets.

### 5.2 `_batch_warnings_detail.csv`

One row for each fired warning of these types: W1, W2b_hard, W2b_rel, W3a,
W4, W5a, W6a, W7. Columns: `dataset_id`, `session`, `anomaly_type`, `value`,
`threshold`, `severity`. Section 9 lists the known problems of this file.

### 5.3 Batch log

Each line has the form `[HH:MM:SS] [LEVEL] DATASET: message`. `LEVEL` is
`INFO`, `WARN` or `ERROR`. `GLOBAL` marks lines about the whole batch. The
log records the scan, each alignment mode that the batch tried, the chosen
P_same and FPR, each skipped figure, and the full error report of a failed
dataset.

### 5.4 Files for each dataset

- `cellRegistered_*.mat`: the CellReg registration result (7.1).
- `logFile_*.txt`: the CellReg log file, written by CellReg's
  `save_log_file` in the same format as the CellReg GUI: parameters, number of cells, FPR, FNR, scores, model error.
- `Figures/`: the CellReg figures of stages 1–5, as `.fig` and `.png`. The
  file names are CellReg's, for example `Stage 2 - pre vs post alignment` and
  `Stage 3 - model`. The non-rigid mode adds `Stage 1 - Non-rigid
  transformations`. If a figure fails, the batch writes a `WARN` line to the
  log and continues.

---

## 6. Quality warnings

After all datasets, `detect_anomalies.m` runs 12 checks on each dataset that
did not fail. Each check gives a severity: 0 = none, 1 = yellow, 2 = red.

There are three kinds of checks:

- **Fixed limit.** The value is compared with a fixed limit. Result: 2 or 0.
- **Within the dataset.** The values of the sessions of one dataset are
  converted to z-scores. If any |z| is above `z_threshold`, the result is 2.
  Else it is 0.
- **Compared with the batch.** The value of the dataset is compared with all
  datasets of the batch that did not fail. Red (2): the value is more than
  `z_threshold` standard deviations from the batch mean, on the bad side.
  Yellow (1): the value is in the worst quarter of the batch (below the first
  quartile or above the third quartile, on the bad side), but not red. These
  checks need at least 3 datasets that did not fail.

| Code | GUI header | Kind | Rule | What it can mean |
|---|---|---|---|---|
| W1 | `%match` | batch | `pct_in_all` low (bad side: low). | Few cells are tracked across all sessions, compared with the other datasets. Causes: a bad session, bad alignment, or a real difference. |
| W2 | `cells/sess` | within | Number of cells per session; any session with \|z\| > `z_threshold`. | One session has many more or many fewer cells than the others. |
| W2b_hard | `ratio>3` | fixed | Largest ÷ smallest cells per session > 3. A session with 0 cells counts as an infinite ratio. | Same as W2, with a fixed limit. |
| W2b_rel | `ratio rel` | batch | The same ratio, high (bad side: high). | Cell numbers per session vary more than in the other datasets. |
| W3a | `low xcorr` | fixed | Any non-reference session has maximal cross-correlation with the reference < `min_xcorr` (0.3). Always red after a forced alignment (4.3). | The alignment is probably bad. Look at `Stage 2 - pre vs post alignment`. |
| W3b | `xcorr rel` | within | Cross-correlations of the non-reference sessions; any \|z\| > `z_threshold`. | One session aligns worse than the others. |
| W4 | `FPR unreach` | fixed | No P_same threshold up to 0.95 gives FPR ≤ `fpr_max` (4.5). | The same-cell and different-cell distributions overlap too much. |
| W5a | `big shift` | fixed | Any non-reference session shift > `max_translation_px` (30 px). Shift = √(dx² + dy²) in pixels. | The field of view moved a lot. Check that the sessions show the same place. |
| W5b | `shift rel` | within | Shifts of the non-reference sessions; any \|z\| > `z_threshold`. | One session moved more than the others. |
| W6a | `bad MSE` | fixed | MSE of the chosen model > `max_mse` (0.1). CellReg itself warns above 0.1. | The model does not fit the data well. Look at `Stage 3 - model`. Datasets with few cells can have MSE > 0.1 from histogram noise while the fit looks good. |
| W6b | `MSE rel` | batch | MSE high (bad side: high). | The model fits worse than in the other datasets. |
| W7 | `sess count` | fixed | Number of sessions ≠ `expected_n_sessions`. | A session file is missing or extra. |

**Read yellow as relative.** In every batch, about one dataset in four is in
the worst quarter of each "batch" check, also when all datasets are good. A
yellow flag says "look if you have time". A red flag says "look before you use
this dataset".

**Small numbers limit the z-scores.** For n values, the largest possible
|z| is (n−1)/√n. This is 1.79 for n = 5 and 2.04 for n = 6. With the default
`z_threshold` = 2:

- W2 can fire only for datasets with 6 or more sessions.
- W3b and W5b can fire only for datasets with 7 or more sessions (they use
  the non-reference sessions only).
- W1, W2b_rel and W6b can be red only in a batch with 6 or more datasets that
  did not fail. Yellow needs 3 or more.

For a study with 5 sessions per animal, W2, W3b and W5b are always 0. Use the
fixed-limit checks (W2b_hard, W3a, W5a) for those cases.

The code is in `BatchCellReg/detect_anomalies.m`. The texts of the decode
line are in `BatchCellReg/anomaly_decode_map.m`.

---

## 7. Using the results

### 7.1 Load the registration

The batch saves the CellReg result struct under the variable name **`crs`**.
The CellReg GUI and `demo.m` save the same struct under the name
`cell_registered_struct`. The fields are the same. Code that must read both:

```matlab
f = dir(fullfile(out_dir, 'CC_H02', 'cellRegistered_*.mat'));
s = load(fullfile(f(1).folder, f(1).name));
if isfield(s, 'crs'); reg = s.crs; else; reg = s.cell_registered_struct; end
map = reg.cell_to_index_map;   % registered cells x sessions
```

`map(i, j)` is the index of registered cell `i` in session `j`, in the order
of the input footprints. 0 means that the cell was not found in that session.
The other fields (`cell_scores`, `p_same_registered_pairs`,
`spatial_footprints_corrected`, and so on) are described in the CellReg
User Manual.

### 7.2 Fraction of cells found in all sessions

`pct_in_all` in `_batch_results.csv` divides by the number of registered
cells. Some labs divide by the mean number of cells per session instead. The
second value is larger. Compute both from the map:

```matlab
in_all      = sum(all(map > 0, 2));
per_session = sum(map > 0, 1);
frac_of_registered = in_all / size(map, 1);        % = pct_in_all
frac_of_mean       = in_all / mean(per_session);
```

State in your methods which definition you use.

---

## 8. Tests

The tests use the MATLAB unit test framework. Run them from the repository
folder:

```matlab
results = runtests('tests/BatchCellReg');
```

or run `tests/BatchCellReg/runAllTests.m`. It stops with an error if a test
fails.

- The unit tests use small synthetic data. They take a few seconds.
- `test_runs_on_shipped_cellreg_sample_data` runs the full batch on
  `SampleData/` (5 sessions of one mouse). It takes 2–3 minutes.
- `test_runs_on_sample_data_our` needs a folder `SampleDataOur/` with our
  own data. This folder is not in the repository, so the test is reported as
  *Incomplete*. This is expected.

---

## 9. Known limitations

- **Names.** The animal ID must have 1–2 letters and exactly 2 digits. The
  session number has one digit, so a dataset can have at most 9 day sessions
  (`1D`–`9D`).
- **Selection.** If you clear **Run** for every dataset, the batch runs all
  datasets, because an empty selection means "all".
- **Fixed approach.** The registration approach is always probabilistic.
  You cannot choose the model or the simple-threshold approach in the batch.
  Use the CellReg GUI (`GUI/CellReg.m`) for one dataset when you need them.
- **Model choice in CellReg v1.6.0.** In `CellReg/choose_best_model.m`, lines
  28–29 compute the false positives and false negatives of the
  centroid-distance model at `ind_05_correlation` (the index of the
  spatial-correlation model). Line 27 computes `ind_05_distance`, but the code
  does not use it. So the choice between the two models (4.4) can be
  imperfect. We did not change this CellReg file.
- **Warnings detail file.** In `_batch_warnings_detail.csv`: the `threshold`
  column is always `NaN`; for W2b_rel the `value` column holds the severity,
  not the ratio (use `W2b_ratio` in `_batch_results.csv`); for W3a the
  `session` column can name the wrong session, because the cross-correlation
  list does not contain the reference session.
- **Figures.** The `.mat` result does not contain the model data, so you
  cannot remake the figures from it. Run the dataset again to get them.
- **Windows.** **Open output folder** uses `winopen` and works on Windows
  only. The rest of the code does not depend on the operating system, but we
  tested it on Windows only.
