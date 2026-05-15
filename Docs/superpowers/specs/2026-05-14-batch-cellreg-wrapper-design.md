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
| 2 — align | 4-stage fallback cascade (see §4.1); record `alignment_translations`, `maximal_cross_correlation`. |
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
result.alignment_shift_px             per-session Euclidean shift in pixels
result.reference_session_index        integer
result.MSE_model                      MSE of the selected model
result.best_model_string
result.chosen_p_same
result.chosen_fpr
result.p_same_unreachable             logical
result.alignment_mode                 label of winning alignment stage (string)
result.error                          (empty on success; message on failure)
```

`run_single_dataset` runs without internal try/catch; the outer `batch_run` wraps the whole dataset call in one try/catch and continues with the next dataset on failure.

### 4.1 Alignment fallback cascade

Stage 2 attempts up to four alignment modes in order, stopping at the first that succeeds:

| Stage | Mode | Notes |
|-------|------|-------|
| 1 | Translations | Always attempted first (or the configured `alignment_type`). |
| 2 | Translations and Rotations @ `maximal_rotation` (default 5°) | Skipped if start mode > Translations. |
| 3 | Translations and Rotations @ `rotation_fallback_deg` (default 90°) | Wider search when 5° fails. |
| 4 | Non-rigid @ `nonrigid_smoothness` (default 2) | Last resort. |

**Start stage**: determined by `cfg.cellreg.alignment_type`. `'Translations'` → stage 1; `'Translations and Rotations'` → stage 2; `'Non-rigid'` → stage 4.

**Failure criteria** (either triggers next stage):
- Any non-reference aligned footprint is empty.
- Any non-reference `max_xcorr < cfg.cellreg.alignment_min_xcorr` (default 0.3).
- Vendor `align_images` throws an error.

**All fail**: raises `BatchCellReg:AlignmentFailed`; `batch_run` catches it and marks the dataset failed.

**Success**: `result.alignment_mode` records the winning stage label (e.g., `'Translations and Rotations@5'`). `alignment_type` and `displacement_fields` (Non-rigid only) are correctly set for all downstream stages.

## 5. Auto P_same selection

`fpr_vector` (either `false_positive_per_correlation_threshold` or `false_positive_per_distance_threshold`, depending on `best_model_string`) is monotonically non-increasing in `p_same`. Selection rule:

1. **Default P_same = 0.5.** Find the bin whose center is nearest 0.5 (`i50`).
2. If `FPR(i50) <= fpr_max` → return that bin. `unreachable = false`.
3. Otherwise **ascend**: among bins with center > `centers(i50)` and center ≤ 0.95, find the smallest center whose FPR ≤ `fpr_max`.
   - If found → return it. `unreachable = false`.
   - If not found → return the bin nearest 0.95. `unreachable = true`.

The cap at 0.95 prevents the algorithm from drifting into the near-1 region where the same/different populations are trivially separated but biologically meaningless thresholds result.

Default `fpr_max = 0.03`, configurable in GUI.

## 6. Anomaly detection

`detect_anomalies.m` runs once after every dataset in the batch has been processed (or failed).

### 6.1 Severity model

Each flag is a numeric severity code (double), not a boolean:

| Code | Meaning | Display |
|------|---------|---------|
| 0 | No anomaly | — |
| 1 | Yellow — dataset is in the worst quartile of the batch on the bad side, but z-score is below threshold | Yellow cell in GUI table |
| 2 | Red — z-score exceeds `z_threshold` (batch-relative checks) or hard limit exceeded (binary checks) | Red cell in GUI table |

Severity 1 (yellow) is only produced by **graded** batch-distribution checks (W1, W6b, W2b_rel). All other checks are **binary-red**: they produce 0 or 2 only.

### 6.2 Anomaly table

| # | Name | Type | Definition | Threshold / condition |
|---|------|------|------------|----------------------|
| W1 | %match population outlier | graded | `pct_in_all = match_stats(2)/match_stats(1)`; batch distribution (bad=low) | `z > z_threshold` → 2; worst quartile → 1; needs ≥3 succeeded |
| W2 | N_cells session outlier | binary | z-score of `n_cells_per_session` within own dataset | `abs(z) > z_threshold` → 2; needs ≥3 sessions |
| W2b_hard | cells-per-session ratio (hard) | binary | `max(n_cells)/min(n_cells) > 3` | ratio > 3 → 2 |
| W2b_rel | cells-per-session ratio (relative) | graded | batch distribution of ratio (bad=high) | `z > z_threshold` → 2; worst quartile → 1; needs ≥3 succeeded |
| W3a | low cross-correlation (hard) | binary | `min(maximal_cross_correlation)` | `< min_xcorr` (default 0.3) → 2 |
| W3b | low cross-correlation (relative) | binary | z-score of `maximal_cross_correlation` within own dataset | `abs(z) > z_threshold` → 2; needs ≥3 sessions |
| W4 | FPR unreachable | binary | `p_same_unreachable == true` | flag → 2 |
| W5a | large alignment shift (hard) | binary | `max(abs(shift_px))` over non-reference sessions | `> max_translation_px` (default 30) → 2 |
| W5b | large alignment shift (relative) | binary | z-score of per-session shift within own dataset, **excluding reference session** | `abs(z) > z_threshold` → 2; needs ≥3 non-ref sessions |
| W6a | bad model fit (hard) | binary | `MSE_model` | `> max_mse` (default 0.1) → 2 |
| W6b | bad model fit (relative) | graded | batch distribution of `MSE_model` (bad=high) | `z > z_threshold` → 2; worst quartile → 1; needs ≥3 succeeded |
| W7 | session count mismatch | binary | `numel(sessions) != expected_n_sessions` | mismatch → 2; only checked if `expected_n_sessions` set in config |

Rationale for `max_mse = 0.1`: CellReg MSE is the sum of squared deviations between the normalized empirical histogram and the modelled weighted sum (per `compute_*_model.m`). Manual inspection of a 39-dataset corpus shows healthy datasets cluster in the 0.05–0.11 range; `0.1` is the recalibrated hard backstop above which the same/different mixture has clearly failed to separate.

All thresholds are surfaced in the GUI Parameters tab and serialized into `_batch_config.json`.

**Minimum sample size for intra-dataset z-score checks**: W2, W3b, and W5b require at least 3 measurements within a dataset (or 3 non-reference sessions for W5b) to be meaningful; the check is silently skipped otherwise.

**Minimum batch size for batch-distribution checks**: W1, W6b, W2b_rel require at least 3 succeeded datasets; skipped otherwise.

### 6.3 Session-count normalization note

W7 is a reporting-only flag. The wrapper passes the actual session files as-is to CellReg; it does not inject stub sessions to pad to `expected_n_sessions`. W7 merely alerts the analyst that a dataset deviated from the expected session count, which can indicate missing data collection or file-naming inconsistencies.

### 6.4 Output of `detect_anomalies`

Fields: `dataset_ids` (cell), `flags` (struct array with one element per result, fields W1–W7 as severity codes), `metrics` (struct array with numeric values for triggered checks).

CSV exports (`_batch_results.csv`): includes W1, W2, W2b_hard, W2b_rel, W3a, W3b, W4, W5a, W5b, W6a, W6b, W7 as numeric severity codes, plus W3a_min_xcorr, W5a_max_shift_px, W6a_mse, W2b_ratio.

Detail CSV (`_batch_warnings_detail.csv`): `dataset_id, session, anomaly_type, value, threshold, severity` — one row per triggered check.

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

- `Run batch`, `Stop`, progress label, live log (`uitextarea`).
- Scrollable results table with 17 columns:
  `Dataset | Sess | Cells | %match | FPR | W1 | W2 | W2b_h | W2b_r | W3a | W3b | W4 | W5a | W5b | W6a | W6b | W7`.
  All W columns carry numeric severity codes (0/1/2). Cell background is red for severity 2, yellow for severity 1, styled via `uistyle` / `addStyle` inside a try/catch (degrades gracefully if the MATLAB version lacks table styling).
- Buttons: `Export results CSV`, `Export log TXT`, `Open output folder`. CSV/log are also written automatically when the batch finishes.

## 8. Configuration file

`<input>/Matching/_batch_config.json`:

```json
{
  "version": 1,
  "cellreg": {
    "microns_per_pixel": 1.6,
    "alignment_type": "Translations",
    "maximal_rotation": 5,
    "reference_session_index": 1,
    "maximal_distance_um": 15,
    "registration_approach": "Probabilistic",
    "initial_registration_type": "auto",
    "use_parallel_processing": true,
    "figures_visibility": "off",
    "write_to_file": true,
    "alignment_min_xcorr": 0.3,
    "expected_n_sessions": 5,
    "rotation_fallback_deg": 90,
    "nonrigid_smoothness": 2
  },
  "p_same_tuning": {
    "fpr_max": 0.03
  },
  "anomaly_thresholds": {
    "z_threshold": 2.0,
    "max_translation_px": 30,
    "min_xcorr": 0.3,
    "max_mse": 0.1
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

Vendor `disp` output is allowed to print to the MATLAB Command Window; future work may capture it via per-stage `evalc` if needed.

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
- Padding datasets to `expected_n_sessions` with stubs (W7 is reporting only).

## 12. Revision history

| Rev | Date | Summary |
|-----|------|---------|
| R0 | 2026-05-14 | Initial spec (approved for planning). |
| R1 | 2026-05-15 | P_same rule: prefer 0.5, ascend to 0.95+flag. Recalibrated defaults (`maximal_distance_um=15`, `alignment_type='Translations'`, `max_mse=0.1`). New cfg fields: `alignment_min_xcorr`, `expected_n_sessions`, `rotation_fallback_deg`, `nonrigid_smoothness`. Updated §5, §8. |
| R2 | 2026-05-15 | 3-level severity model (0/1/2) for all anomaly flags. New checks: W2b_hard (ratio>3), W2b_rel (batch-relative ratio). Updated §6. |
| R3 | 2026-05-15 | Alignment fallback cascade: Translations → Rot@5° → Rot@90° → Non-rigid. `result.alignment_mode` added. Updated §4, new §4.1. |
| R4 | 2026-05-15 | W7 session-count flag. CSV and GUI surface severity codes, W2b_hard/W2b_rel, W7. Results table is 17 columns with severity coloring. Updated §6, §7. |
