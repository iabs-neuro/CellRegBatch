# Batch CellReg GUI — Load & Inspect Saved Results

**Date:** 2026-05-16
**Scope:** Single-file change to `BatchCellReg_GUI/BatchCellReg.m`. No engine
changes, no vendor changes.

## Goal

On the "Run & Results" tab, let the analyst load a previously-saved batch
(`_batch_results.csv`) without re-running, view it as the same colored
warnings table, and interactively decode any warning.

## Requirements

### R1 — Load results CSV

- New button **"Load results CSV…"** on the Run & Results tab, near *Run batch*.
- Opens `uigetfile('*.csv', ...)`; `refocus(fig)` after the dialog (consistent
  with the existing Java-dialog focus fix).
- Parses `_batch_results.csv` (header row + data rows). Expected columns:
  `dataset_id, n_sessions, n_cells, pct_in_all, chosen_fpr, W1, W2, W2b_hard,
  W2b_rel, W3a, W3b, W4, W5a, W5b, W6a, W6b, W7, W3a_min_xcorr,
  W5a_max_shift_px, W6a_mse, W2b_ratio, error`.
- Fills the existing `results_table` with the same column layout produced by a
  live run (`Dataset, Sess, Cells, %match, FPR, W1..W7`).
- Stores enough state that **Export results CSV** and **Open output folder**
  keep working: set `app.loaded_csv_path` and point exports at the loaded file
  / its folder. (Export log is disabled/greyed when there is no live run.)
- Robustness: if the header is missing required columns, show `uialert` and
  abort without touching the table.

### R2 — Two-line column headers (code + words)

`results_table.ColumnName` uses two-line labels (`sprintf('%s\n%s', code,
words)`):

| Col | Label |
|---|---|
| 1–5 | `Dataset`, `Sess`, `Cells`, `%match`, `FPR` |
| W1 | `W1` / `%match` |
| W2 | `W2` / `cells/sess` |
| W2b_hard | `W2b_h` / `ratio>3` |
| W2b_rel | `W2b_r` / `ratio rel` |
| W3a | `W3a` / `low xcorr` |
| W3b | `W3b` / `xcorr rel` |
| W4 | `W4` / `FPR unreach` |
| W5a | `W5a` / `big shift` |
| W5b | `W5b` / `shift rel` |
| W6a | `W6a` / `bad MSE` |
| W6b | `W6b` / `MSE rel` |
| W7 | `W7` / `sess count` |

### R3 — Severity coloring (shared)

Refactor the current inline coloring in `fill_results_table` into one helper
`apply_severity_styles(tbl, rows, wcols)` used by **both** the live-run path
and the loaded-CSV path. Cell value `2` → red `[1 .6 .6]`, `1` → yellow
`[1 1 .6]`, `0`/other → default. Wrapped in try/catch (uistyle availability).

### R4 — Click-to-decode panel

- A read-only single-row `uitextarea` under the table: `decode_line`
  (`Editable='off'`; wraps long decode text).
- `results_table.CellSelectionCallback`: if the selected column is a W-column,
  set `decode_line` to the full decode for that code, the clicked cell's
  severity word, and the row's dataset id, e.g.:
  `W3a — low cross-correlation (hard): min(max_xcorr) < 0.3 (bad alignment).
  [CC_H04] severity = 2 (RED)`.
- Non-W column or empty selection clears the line.
- Decode text is a static `containers.Map` (code → description) built from the
  spec §6 anomaly table; severity word map `0→none, 1→YELLOW, 2→RED`.

## Decode strings (R4 source of truth)

- W1: %match population outlier — `pct_in_all` low vs batch (graded)
- W2: cells/session intra-dataset z-outlier
- W2b_hard: max/min cells-per-session ratio > 3
- W2b_rel: cells-per-session ratio high vs batch (graded)
- W3a: low cross-correlation (hard) — min(max_xcorr) < min_xcorr (0.3)
- W3b: low cross-correlation relative — intra-dataset z of max_xcorr
- W4: P_same FPR target unreachable (capped at 0.95)
- W5a: large alignment shift (hard) — max |shift_px| > max_translation_px (30)
- W5b: large alignment shift relative — intra-dataset z of per-session shift
- W6a: bad model fit (hard) — MSE_model > max_mse (0.1)
- W6b: bad model fit relative — MSE high vs batch (graded)
- W7: session-count ≠ expected_n_sessions

## Non-goals

- No engine/vendor changes.
- CSV is the only load source (no folder picker, no `.mat` reconstruction).
- No true per-cell mouse-hover tooltip (unsupported by R2020a uitable).
- Loading does not recompute anomalies; values are taken as-is from the CSV.

## Testing

- Manual: launch GUI, Load the existing `CC/5_Filters/Matching/_batch_results.csv`,
  verify 16 rows, colors match severity, headers two-line, click W6a on a row
  shows the MSE decode, Export results copies the loaded CSV.
- Negative: pick an unrelated CSV → `uialert`, table untouched.
- Regression: a live `Run batch` still fills/colors the table via the shared
  helper.
