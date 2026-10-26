function tests = test_choose_p_same_by_fpr
%TEST_CHOOSE_P_SAME_BY_FPR Locks the CUMULATIVE, vendor-aligned FPR-gate
%   contract. FPR at a P_same threshold p must equal
%   cumsum(fpr_vector)(round(N*(1-p))) with index guarded to [1,N], matching
%   CellReg/save_log_file.m lines 92-94. Vectors here use the real vendor
%   shape: N=1000 bin centers, centers(k)=k/1000.
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', '..', 'BatchCellReg')));
end

function c = centers1000()
    c = (1:1000)' / 1000;          % vendor: 1000 bins, centers(k)=k/1000
end

function f = fpr_at_ref(fpr_vector, p)
    % Reference re-implementation of the vendor index mapping, INCLUDING the
    % save_log_file.m:82 rounding decision_thresh = round(100*p)/100 applied
    % before the line-94 index. The gate must agree with this exactly.
    v = fpr_vector(:); N = numel(v); cum = cumsum(v);
    dt = round(100*p)/100;
    f = cum(max(1, min(N, round(N*(1-dt)))));
end

function test_keeps_half_when_cumulative_fpr_ok(tc)
    % Uniform density 4e-5: cumulative FPR at p=0.5 (index 500) = 0.02 <= 0.03.
    ct = centers1000();
    fpr = repmat(4e-5, 1000, 1);
    [p, f, u] = choose_p_same_by_fpr(ct, fpr, 0.03);
    verifyEqual(tc, p, 0.5, 'AbsTol', 1e-9);
    verifyEqual(tc, f, fpr_at_ref(fpr, 0.5), 'AbsTol', 1e-12);
    verifyEqual(tc, f, 0.02, 'AbsTol', 1e-9);
    verifyFalse(tc, u);
end

function test_ascends_to_min_p_meeting_cumulative_fpr(tc)
    % Uniform density 1e-4: cumulative FPR at p=0.5 = 0.05 > 0.03, so ascend.
    % Vendor rounds the threshold to 2 decimals before indexing
    % (save_log_file.m:82), so the smallest center meeting the bound is
    % p=0.695 -> round to 0.70 -> index round(1000*(1-0.70))=300 -> cum=0.03.
    % (p=0.694 -> 0.69 -> index 310 -> cum=0.031 > 0.03.)
    ct = centers1000();
    fpr = repmat(1e-4, 1000, 1);
    [p, f, u] = choose_p_same_by_fpr(ct, fpr, 0.03);
    verifyEqual(tc, p, 0.695, 'AbsTol', 1e-9);
    verifyEqual(tc, f, fpr_at_ref(fpr, p), 'AbsTol', 1e-12);
    verifyLessThanOrEqual(tc, f, 0.03 + 1e-9);
    verifyFalse(tc, u);
end

function test_caps_at_095_and_flags_when_unreachable(tc)
    % Uniform density 1e-3: even at p=0.95 (index 50) cum=0.05 > 0.03, and no
    % bin in (0.5,0.95] meets -> cap at 0.95, unreachable=true.
    ct = centers1000();
    fpr = repmat(1e-3, 1000, 1);
    [p, f, u] = choose_p_same_by_fpr(ct, fpr, 0.03);
    verifyEqual(tc, p, 0.95, 'AbsTol', 1e-9);
    verifyEqual(tc, f, fpr_at_ref(fpr, 0.95), 'AbsTol', 1e-12);
    verifyTrue(tc, u);
end

function test_never_exceeds_095_and_index_guarded(tc)
    % Density only tiny at the very top bins so only p near 1.0 could satisfy;
    % the selector must still cap at 0.95 (never return >0.95) and must not
    % error on the round(N*(1-p)) -> 0 guard at p=1.0.
    ct = centers1000();
    fpr = repmat(2e-3, 1000, 1);     % cum at index 50 (p=0.95) = 0.1 > 0.03
    [p, f, u] = choose_p_same_by_fpr(ct, fpr, 0.03);
    verifyLessThanOrEqual(tc, p, 0.95 + 1e-9);
    verifyTrue(tc, u);
    verifyEqual(tc, f, fpr_at_ref(fpr, p), 'AbsTol', 1e-12);
end

function test_uses_vendor_rounded_threshold_index(tc)
    % Regression for the residual p-rounding bug: the vendor rounds P_same to
    % 2 decimals before indexing, so the gate must too. Build fpr so the
    % selector ascends to a non-0.01 center where the rounded vs unrounded
    % index give different cumulative FPR; the returned fpr must equal the
    % ROUNDED-index value (what the logFile actually reports), and must be
    % the quantity bounded by fpr_max.
    ct = centers1000();                       % centers(k)=k/1000
    fpr = repmat(1e-4, 1000, 1);
    [p, f, u] = choose_p_same_by_fpr(ct, fpr, 0.03);
    v = fpr(:); N = numel(v); cum = cumsum(v);
    dt = round(100*p)/100;
    idx_round   = max(1, min(N, round(N*(1-dt))));
    f_rounded   = cum(idx_round);
    verifyEqual(tc, f, f_rounded, 'AbsTol', 1e-12);     % matches vendor bin
    if ~u
        verifyLessThanOrEqual(tc, f, 0.03 + 1e-9);      % the bound holds at THAT bin
    end
end

function test_matches_vendor_formula_on_nonuniform(tc)
    % Non-uniform density: returned fpr must equal the vendor cumulative value
    % at round(N*(1-p)) for whatever p the selector picks.
    ct = centers1000();
    fpr = zeros(1000, 1);
    fpr(1:200)   = 5e-4;             % builds large cumsum at low indices
    fpr(201:end) = 1e-5;
    [p, f, u] = choose_p_same_by_fpr(ct, fpr, 0.03);
    verifyEqual(tc, f, fpr_at_ref(fpr, p), 'AbsTol', 1e-12);
    if ~u
        verifyLessThanOrEqual(tc, f, 0.03 + 1e-9);
    end
    verifyLessThanOrEqual(tc, p, 0.95 + 1e-9);
end
