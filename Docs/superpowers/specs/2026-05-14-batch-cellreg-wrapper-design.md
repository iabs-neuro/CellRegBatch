# Batch CellReg wrapper — design spec

**Date**: 2026-05-14
**Status**: Approved for planning
**Author**: brainstormed with Claude

## 1. Goal

Provide a MATLAB GUI shell around the existing CellReg pipeline (`CellReg/demo.m` logic) that:

1. Scans a flat folder of `.mat` files for groups of sessions belonging to the same `(experiment, mouse)`.
2. Silently converts session matrices to `double` when needed.
3. Runs all five CellReg stages on each dataset, auto-selecting `P_same` so that the false-positive rate stays at or below a user-configurable target.
4. Aggregates per-dataset match statistics and flags anomalies across the batch.
5. Persists configuration as JSON and exposes results in a scrollable, exportable table.

The vendor code under `CellReg/`, `GUI/`, and `Helper/` is not modified.

## 2. Architecture

```
BatchCellReg/                       (engine — no GUI)
├── batch_run.m                     entry point (callable from script or GUI)
├── batch_default_config.m          default params struct
├── config_to_json.m
├── config_from_json.m
├── scan_input_folder.m             glob + regex parse + grouping
├── prepare_session_files.m         silent uint8→double conversion in memory
├── run_single_dataset.m            wraps demo.m stages 1-5 for one dataset
├── choose_p_same_by_fpr.m          single-pass P_same selection
├── collect_match_stats.m           match statistics per dataset
├── detect_anomalies.m              six anomaly checks, batch-wide
└── batch_logger.m                  live-log callback + file logger

BatchCellReg_GUI/
└── BatchCellReg.m                  uifigure with three tabs
```

GUI only collects parameters, drives the engine, and displays output. All computation lives in `BatchCellReg/`. The engine can be invoked directly as `batch_run(input_folder, config_path)` without the GUI.

## 3. Input parsing and dataset grouping

### 3.1 Filename pattern

Regex (MATLAB syntax): `^([A-Za-z0-9]+)_([A-Za-z]{1,2}\d{2})_(\dD|\dT)(_\dT)?.*\.mat$`

Captures:
- group 1 — `EXP` (e.g., `BOWL`)
- group 2 — `MOUSE` (1–2 letters + 2 digits, e.g., `D01`)
- group 3 — day or trial code (`1D`, `2D`, `1T`, ...)
- group 4 — optional sub-trial (`_1T`, `_2T`, ...)

Files not matching the regex are listed under "unparsed" in the GUI Setup tab but do not block the run.

### 3.2 Grouping

- **Dataset id** = `<EXP>_<MOUSE>` (day intentionally NOT part of the id — registering across days is the point of the analysis).
- **Session id** = the matched session code, i.e. groups 3 + 4 concatenated (e.g., `1D`, `1D_1T`).
- **Session order**: alphabetical sort of the full filename. Reference session = first in this order.
- **Duplicate session_id** inside one dataset → that dataset fails validation with a clear error; the batch continues with other datasets.
- **<2 sessions** in a dataset → dataset is skipped with a warning.

### 3.3 Conversion

`prepare_session_files.m` loads a session file, reads its first field (mirroring `CellReg/load_single_session.m`), and converts to `double` in memory if the type differs. Nothing is written back to disk. No user-facing message is emitted on the happy path.

## 4. Single-dataset pipeline

`run_single_dataset.m` mirrors the structure of `CellReg/demo.m` with the following changes:

| Stage | Change |
|-------|--------|
| 1 — load | use `prepare_session_files` instead of `load_multiple_sessions`. |
| 2 — align | fixed `alignment_type='Translations and Rotations'` by default (configurable); record `alignment_translations`, `maximal_cross_correlation`. |
| 3 — model | record `MSE_*_model`, `false_positive_per_*_threshold`, `p_same_centers_of_bins`. |
| 3 → 4 — `P_same` selection | call `choose_p_same_by_fpr` (see §5). |
| 4 — initial reg | unchanged. |
| 5 — final reg | `registration_approach='Probabilistic'` by default. |
| Save | write `cellRegistered_<datestamp>.mat`, vendor log, figures into `Matching/<dataset_id>/`. |

Returned `result` struct carries every metric the anomaly detector needs:

```
result.dataset_id
result.sessions                       cell of filenames in load order
result.n_cells_per_session            vector
result.match_stats                    [total, in_all, ..., in_1]
result.maximal_cross_correlation      matrix or vector (one per non-ref session)
result.alignment_translations         vendor-format
result.MSE_model                      MSE of the selected model
result.best_model_string
result.chosen_p_same
result.chosen_fpr
result.p_same_unreachable             logical
result.error                          (empty on success; message on failure)
```

`run_single_dataset` runs without internal try/catch; the outer `batch_run` wraps the whole dataset call in one try/catch and continues with the next dataset on failure.

## 5. Auto P_same selection

`fpr_vector` (either `false_positive_per_correlation_threshold` or `false_positive_per_distance_threshold`, depending on `best_model_string`) is monotonically non-increasing in `p_same`. Selection is a single pass:

```matlab
idx = find(fpr_vector <= fpr_max, 1, 'first');
if isempty(idx)
    [~, idx] = min(fpr_vector);   % closest achievable
    unreachable = true;
else
    unreachable = false;
end
p_same = p_same_centers_of_bins(idx);
fpr    = fpr_vector(idx);
```

Default `fpr_max = 0.03`, configurable in GUI.

## 6. Anomaly detection

`detect_anomalies.m` runs once after every dataset in the batch has been processed (or failed). Six checks:

| # | Name | Definition | Threshold |
|---|------|------------|-----------|
| W1 | %match population outlier | `pct_in_all = match_stats(2) / match_stats(1)`; z-score across batch | `abs(z) > z_threshold` (default 2.0) |
| W2 | N_cells session outlier | z-score of `n_cells_per_session` within own dataset | `abs(z) > z_threshold` |
| W3a | low cross-correlation (hard) | `min(maximal_cross_correlation)` | `< 0.3` (vendor's `sufficient_correlation_footprints`) |
| W3b | low cross-correlation (relative) | z-score of `maximal_cross_correlation` within own dataset | `abs(z) > z_threshold` |
| W4 | FPR unreachable | `p_same_unreachable == true` | flag, no extra threshold |
| W5a | large alignment shift (hard) | `max(abs(translation_xy))` in px per session | `> max_translation_px` (default 30) |
| W5b | large alignment shift (relative) | z-score of per-session shift magnitude within own dataset, **excluding reference session** (shift is 0 by construction) | `abs(z) > z_threshold` |
| W6a | bad model fit (hard) | `MSE_model` | `> max_mse` (default 0.05) |
| W6b | bad model fit (relative) | z-score of `MSE_model` across batch | `abs(z) > z_threshold` |

Rationale for `max_mse = 0.05`: CellReg MSE is the sum of squared deviations between the normalized empirical histogram and the modelled weighted sum (per `compute_*_model.m`). Realistic datasets land at ~0.001–0.01; the vendor `choose_best_model.m` ranks models by MSE but has no absolute threshold. `0.05` is a generous ceiling above which the same/different mixture clearly failed to separate, while the relative `z > 2` check catches dataset-specific drift.

All thresholds are surfaced in the GUI Parameters tab and serialized into `_batch_config.json`.

**Minimum sample size for intra-dataset z-score checks**: W2, W3b, and W5b require at least 3 measurements within a dataset to be meaningful. If a dataset has fewer measurements (e.g., a 2-session dataset has only 1 non-reference shift for W5b), the relative check is silently skipped — only the hard threshold variant applies.

### Output of `detect_anomalies`

A wide table aligned with the Results view:
```
dataset_id | sessions | n_cells | pct_match | chosen_fpr
         | W1 | W2 | W3a | W3b | W4 | W5a | W5b | W6a | W6b
         | W3a_min_xcorr_value | W5a_max_shift_px | W6a_mse_value | ...
```
Boolean flags + the raw metric that triggered each flag, so the CSV export is self-contained.

A detail table (`_batch_warnings_detail.csv`) lists individual offending sessions: `dataset_id, session, anomaly_type, value, threshold`.

## 7. GUI layout

`BatchCellReg.m` builds a `uifigure` with three tabs.

### Tab 1 — Setup

- Input folder picker (`uigetdir`).
- Read-only output path: `<input>/Matching/`.
- `Scan folder` button → fills a scrollable list of detected datasets, each with a checkbox (unchecked = skip), session count, and session-id summary.
- Unparsed-files counter with `Show details...` popup.

### Tab 2 — Parameters

Bound to `app.config`. Sections:

- **CellReg core**: `microns_per_pixel`, `alignment_type`, `maximal_rotation`, `reference_session_index`, `maximal_distance_um`, `registration_approach`, `initial_registration_type`.
- **P_same auto-tune**: `fpr_max`.
- **Anomaly thresholds**: `z_threshold`, `max_translation_px`, `min_xcorr`, `max_mse`.
- **I/O**: `write_to_file`, `figures_visibility`, `use_parallel_processing`.

Buttons: `Load config (JSON)...`, `Save config as...`, `Reset to defaults`.

At GUI startup, `<input>/Matching/_batch_config.json` is loaded if present, otherwise defaults from `batch_default_config.m`.

### Tab 3 — Run & Results

- `Run batch`, `Stop`, progress bar, live log (`uitextarea`).
- Scrollable results table with columns:
  `Dataset | Sess | Cells | %match | FPR | W1 | W2 | W3a | W3b | W4 | W5a | W5b | W6a | W6b`.
  Boolean columns shown as ✓ checkmarks. Click on a ✓ → popup with the per-session metric values and threshold.
- Buttons: `Export results CSV`, `Export log TXT`, `Open output folder`. CSV/log are also written automatically when the batch finishes.

## 8. Configuration file

`<input>/Matching/_batch_config.json`:

```json
{
  "version": 1,
  "cellreg": {
    "microns_per_pixel": 1.6,
    "alignment_type": "Translations and Rotations",
    "maximal_rotation": 5,
    "reference_session_index": 1,
    "maximal_distance_um": 30,
    "registration_approach": "Probabilistic",
    "initial_registration_type": "auto",
    "use_parallel_processing": true,
    "figures_visibility": "off",
    "write_to_file": true
  },
  "p_same_tuning": {
    "fpr_max": 0.03
  },
  "anomaly_thresholds": {
    "z_threshold": 2.0,
    "max_translation_px": 30,
    "min_xcorr": 0.3,
    "max_mse": 0.05
  },
  "io": {
    "input_folder": "...",
    "output_subfolder_name": "Matching"
  }
}
```

`version` is reserved for future schema changes; loader rejects unknown versions with a clear error.

## 9. Output directory layout

```
<input_folder>/
  <session files...>
  Matching/                                    created by wrapper
    _batch_config.json                         snapshot of this run's config
    _batch_log_<timestamp>.txt                 full text log
    _batch_results.csv                         the Tab 3 table + numeric metrics
    _batch_warnings_detail.csv                 per-session anomaly details
    <EXP>_<MOUSE>/
      cellRegistered_<timestamp>.mat           vendor name
      logFile_<timestamp>.txt                  from save_log_file.m
      Figures/                                 all vendor figures (Stages 1-5)
```

**Overwrite semantics**: each batch run always re-runs every checked dataset (no resume / skip-if-exists). The vendor save format embeds a timestamp in the filename (`cellRegistered_<yyyymmdd_HHMMss>.mat`), so a new run produces new files side-by-side with the previous ones. The most recent timestamp is the canonical result; older files are left untouched (manual cleanup if disk space matters). The top-level files (`_batch_config.json`, `_batch_results.csv`, `_batch_warnings_detail.csv`) ARE overwritten each run; only `_batch_log_<timestamp>.txt` is timestamped to preserve run history.

## 10. Logging and error handling

### Logger

`batch_logger.m` holds:
- a file handle to `_batch_log_<timestamp>.txt`,
- a live-log callback (`app.live_log_callback` from the GUI).

Each line: `[HH:MM:SS] <dataset_id|GLOBAL>: <text>`. Levels `INFO`, `WARN`, `ERROR`.

Vendor `disp` output is captured via `evalc` per stage and written to the file log only (not the live log) to keep the GUI readable.

### Error strategy

- One try/catch wraps the entire `run_single_dataset` call, not individual stages.
- On failure: `result.error = ME.message`; full stack via `getReport(ME, 'basic')` goes to the file log; batch continues.
- After all datasets: summary line `N total / N succeeded / N failed / N with warnings`.

### Stop button

`app.stop_requested` is checked **between** datasets; the currently running dataset always finishes. Log: `[INFO] GLOBAL: Stop requested after <dataset_id>; remaining <n> datasets not processed.`

### Parallel pool

`delete(gcp('nocreate'))` is called once at the very end of `batch_run`, not after each dataset, to avoid re-creating the pool for every dataset.

## 11. Out of scope (for this spec)

- Modifying any vendor code under `CellReg/`, `GUI/`, `Helper/`.
- Automatic deletion of previous `cellRegistered_*.mat` files.
- Anomaly thresholds learned from data (auto-tuning of `z_threshold`).
- CLI/scripted invocation beyond the existing `batch_run(input_folder, config_path)` entry point.
- Cross-batch comparisons (one batch run = one analysis).
