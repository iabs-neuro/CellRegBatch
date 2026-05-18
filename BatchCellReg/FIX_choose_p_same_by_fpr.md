# HANDOFF: fix FPR gate bug in `choose_p_same_by_fpr.m`

> Self-contained instructions for a fresh Claude session. Diagnosis already done
> (systematic-debugging, Phase 1–3 complete). Your job: Phase 4 — implement the
> single fix + verify. Do NOT re-investigate from scratch; do confirm the
> evidence below still holds before editing.

## TL;DR

`BatchCellReg/choose_p_same_by_fpr.m` compares `fpr_max` against the **wrong
quantity**: it reads a single element of `fpr_sc`/`fpr_cd` (a per-bin
false-positive *density*), but the real false-positive *rate* at a P_same
threshold is the **cumulative sum** of that vector — exactly as the CellReg
vendor computes it for the logFile. Result: the per-bin value near P_same=0.5
is ≈0.0000, always ≤ fpr_max, so the FPR gate never fires and P_same is pinned
at 0.5 for every dataset. The FPR reported in each `logFile_*.txt` (vendor,
correct) is therefore higher than the gate "thought" (e.g. CC_H02: gate saw
0.0000, logFile says 0.05 > fpr_max 0.03).

## Evidence (verify these still hold; do not skip)

1. Config used: `H:\Dataset\CalciumData\CC\5_Filters\Matching\_batch_config.json`
   → `p_same_tuning.fpr_max = 0.03`.
2. Run log: `..\Matching\_batch_log_20260516_155524.txt` contains
   `CC_H02: chosen P_same=0.500, FPR=0.0000 [model=Spatial correlation]`.
3. `..\Matching\_batch_results.csv` row `CC_H02` → `chosen_fpr = 0`.
4. `..\Matching\CC_H02\logFile_*.txt` → `Fraction of false positives - 0.05`,
   `P_same threshold - 0.5`, `Final registration type - Spatial correlations`.
5. Vendor truth — `CellReg/save_log_file.m` lines 92–94:
   ```matlab
   cumsum_false_positive = cumsum(false_positive);
   false_positives = round(100*cumsum_false_positive( round(num_bins_p_same*(1-decision_thresh)) ))/100;
   ```
   `num_bins_p_same = length(true_positive) = 1000`; for P_same=0.5 index =
   `round(1000*(1-0.5)) = 500`; reported FPR = `cumsum(fpr)(500)`.
6. `CellReg/estimate_registration_accuracy.m` lines 35–36, 60, 66:
   `p_same_centers_of_bins` = 1000 points, `centers(k) = k/1000`;
   `false_positive_per_*_threshold(n)` is a **per-bin** sum (density), NOT
   cumulative.
7. Buggy code — `BatchCellReg/choose_p_same_by_fpr.m` line 8:
   `if fpr_vector(i50) <= fpr_max` — single element, not `cumsum`.

Call site: `BatchCellReg/run_single_dataset.m` ~lines 237–243 — passes
`fpr_vec` (= `fpr_sc` or `fpr_cd`) and `p_same_centers` (length 1000) into
`choose_p_same_by_fpr`. Same vectors the vendor uses. Lengths match → index 500
both sides. The ONLY difference is cumulative vs per-bin.

## The fix (single change, one file)

Replace the body of `BatchCellReg/choose_p_same_by_fpr.m` so it gates on the
**cumulative** FPR using the *identical* index mapping as the vendor
(`round(N*(1-p))`), for both models (vendor formula is model-agnostic; this fix
must stay model-agnostic too — applies equally to `fpr_sc` and `fpr_cd`):

```matlab
function [p_same, fpr, unreachable] = choose_p_same_by_fpr(centers, fpr_vector, fpr_max)
%CHOOSE_P_SAME_BY_FPR Prefer P_same=0.5; ascend toward 0.95 only if the
%   CUMULATIVE FPR at 0.5 exceeds fpr_max. FPR at a P_same threshold p is
%   cumsum(fpr_vector)(round(N*(1-p))), matching CellReg save_log_file.m
%   (lines 92-94) so the gate and the written logFile agree exactly.
    centers = centers(:); fpr_vector = fpr_vector(:);
    N = numel(fpr_vector);
    cum = cumsum(fpr_vector);
    fpr_at = @(p) cum( max(1, min(N, round(N*(1-p)))) );

    [~, i50] = min(abs(centers - 0.5));
    if fpr_at(centers(i50)) <= fpr_max
        p_same = centers(i50); fpr = fpr_at(centers(i50)); unreachable = false; return
    end
    [~, i95] = min(abs(centers - 0.95));
    cand = (i50+1:i95)';
    cand = cand(arrayfun(@(k) fpr_at(centers(k)) <= fpr_max, cand));
    if ~isempty(cand)
        idx = cand(1); unreachable = false;       % smallest P_same>0.5 meeting FPR
    else
        idx = i95; unreachable = true;            % cap at 0.95, flag
    end
    p_same = centers(idx); fpr = fpr_at(centers(idx));
end
```

Direction check (must hold, don't change): higher P_same → higher `centers` →
higher candidate index, but `fpr_at` uses `round(N*(1-p))` so higher p → lower
cumsum index → lower FPR. Ascending `i50+1:i95` therefore monotonically lowers
FPR. Correct.

## Constraints / do-not

- This is research code; the fix **changes scientific outputs (P_same, cell
  counts) for every dataset across NOF/RFC/CC/FOF**. Before editing, the human
  must confirm they want this applied. If running unattended, make the edit but
  STATE prominently that all prior Matching outputs are now invalid and must be
  regenerated.
- ONE change, this one file. No "while I'm here" refactors of
  `run_single_dataset.m` or vendor code. Vendor `CellReg/*` stays untouched.
- Do not "round to match vendor 0.01" — compare the unrounded cumulative value
  to `fpr_max`; that is intentionally stricter and correct.

## Verification (Phase 4 — REQUIRED before claiming done)

You almost certainly cannot run MATLAB in-session. Do NOT claim the bug fixed
without one of these:

**Option A (preferred — has MATLAB):** write a throwaway harness that loads a
saved dataset and re-runs only the selector + vendor formula, asserting they
agree:
```matlab
% needs the variables estimate_registration_accuracy produced for CC_H02.
% Re-run stage 3 for CC_H02, OR instrument run_single_dataset to dump
% p_same_centers + fpr_sc to a .mat once, then:
[p,fpr,unr] = choose_p_same_by_fpr(p_same_centers, fpr_sc, 0.03);
N = numel(fpr_sc); cum = cumsum(fpr_sc);
vendor_fpr = round(100*cum(round(N*(1-p))))/100;   % must == logFile value
assert(fpr <= 0.03 || unr, 'gate must satisfy fpr_max or flag unreachable');
fprintf('p_same=%.3f chosen_fpr=%.4f vendor_logfile_fpr=%.2f unreachable=%d\n',...
        p, fpr, vendor_fpr, unr);
```
Expected for CC_H02: `p_same` > 0.5, `chosen_fpr` ≈ vendor cumulative ≤ 0.03
(or `unreachable=1` with p_same≈0.95). The pre-fix value was p_same=0.5,
chosen_fpr=0.0000 while logFile=0.05 — that discrepancy must disappear.

**Option B (no MATLAB):** do a dry numeric check in Python using the saved
`cellRegistered_*.mat` is NOT sufficient (it lacks fpr vectors). Instead
instruct the human to re-run the batch on a few datasets and confirm: every
`logFile_*.txt` "Fraction of false positives" is now ≤ 0.03 OR the run log
marks `FPR target ... unreachable`. Spot-check CC_H02 specifically.

After fix + a full batch re-run, re-extract the summary tables (the user has a
parser pattern: folder name + Initial reg type/threshold, Registration
approach, Final reg type, P_same threshold, FP, FN; plus Alignment Type for CC)
for `H:\Dataset\CalciumData\{RFC,CC}\5_Filters\Matching` and confirm P_same is
no longer uniformly 0.5 and all FP ≤ 0.03 (or flagged).

## Edge cases to keep correct

- Centroid-distance model: `fpr_vec = fpr_cd`, same `p_same_centers` (1000,
  0..1). Vendor `save_log_file` uses the same cumsum formula → the fix is
  uniform, no model branch needed. Verify on a centroid dataset too (RFC_F05,
  F07, F19, F53 used Centroid distance).
- `unreachable=true` path must still cap at the 0.95 bin and set the flag so
  the anomaly detector / W-columns behave as before.
- `round(N*(1-p))` can hit 0 at p=1.0 — guarded by `max(1,...)`. Keep the
  guard.

## RESOLUTION (2026-05-16) — supersedes the "do not round" note above

The cumsum fix was necessary but NOT sufficient, and the explicit
"Do not round to match vendor 0.01" instruction in *Constraints* was
**disproven by evidence**. `CellReg/save_log_file.m:82` does
`decision_thresh = round(100*final_threshold)/100` BEFORE the line-94
index. So for any ascended (non-0.01) P_same the gate (unrounded index)
bounded a different, lower bin than the vendor actually reports/uses.

Proof (CC_H03): selector p=0.5735 → gate idx round(1000*(1-0.5735))=427,
cum=0.0280 ≤ 0.03 (accepted), but vendor rounds p→0.57 → idx 430,
cum=0.0481 → logFile "Fraction of false positives - 0.05" > 0.03.
Pattern held across all datasets: discrepancy ONLY for ascended P_same;
P_same=0.5 datasets (round(0.5)=0.5, identical index) always agreed.

Final fix (commit after 9a878a7): `fpr_at` applies the vendor rounding —
`cum( round(N*(1-(round(100*p)/100))) )` — so the gate evaluates the
EXACT bin save_log_file writes. Now chosen_fpr == logFile FP and every
selected dataset's logFile FP ≤ fpr_max (or W4/unreachable flagged).
Tests rewritten to lock the rounded contract (test_choose_p_same_by_fpr,
incl. test_uses_vendor_rounded_threshold_index). Do NOT revert to an
unrounded index.

## Apply the memory note

A prior session recorded related project memory. After fixing, update
memory: the "P_same uniformly 0.5" observation in the dataset tables was a
**bug artifact**, not a real optimum — any analysis/paper text relying on those
P_same/cell-count numbers must be regenerated post-fix.
