function tests = test_detect_anomalies
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', '..', 'BatchCellReg')));
end

% -------------------------------------------------------------------------
% Helpers
% -------------------------------------------------------------------------

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

% -------------------------------------------------------------------------
% Test 1: W3a hard check — low xcorr → severity 2 (red)
% -------------------------------------------------------------------------

function test_w3a_hard_is_red(testCase)
    rs = make_result('A1', {'1D','2D'}, [10 10], [10 3 7], [1.0 0.25], [0 1], 0.005, false, 1);
    a = detect_anomalies(rs, default_thresholds());
    verifyEqual(testCase, a.flags.W3a, 2);
end

% -------------------------------------------------------------------------
% Test 2: W5a hard check excludes reference, large non-ref shift → severity 2
% -------------------------------------------------------------------------

function test_w5a_hard_excludes_ref_is_red(testCase)
    % ref=1, session 1 shift=0, sessions 2&3 shifts 5 and 40 (>30 threshold)
    rs = make_result('A1', {'1D','2D','3D'}, [10 10 10], [10 5 3 2], [1 0.6 0.6], [0 5 40], 0.005, false, 1);
    a = detect_anomalies(rs, default_thresholds());
    verifyEqual(testCase, a.flags.W5a, 2);
end

% -------------------------------------------------------------------------
% Test 3: W4 unreachable p_same → severity 2
% -------------------------------------------------------------------------

function test_w4_unreachable_is_red(testCase)
    rs = make_result('A1', {'1D','2D'}, [10 10], [10 3 7], [1 0.6], [0 5], 0.005, true, 1);
    a = detect_anomalies(rs, default_thresholds());
    verifyEqual(testCase, a.flags.W4, 2);
end

% -------------------------------------------------------------------------
% Test 4: W6a hard MSE > threshold → severity 2
% -------------------------------------------------------------------------

function test_w6a_hard_is_red(testCase)
    rs = make_result('A1', {'1D','2D'}, [10 10], [10 3 7], [1 0.6], [0 5], 0.08, false, 1);
    a = detect_anomalies(rs, default_thresholds());
    verifyEqual(testCase, a.flags.W6a, 2);
end

% -------------------------------------------------------------------------
% Test 5: W2b_hard — ratio > 3 → 2, ratio <= 3 → 0
% -------------------------------------------------------------------------

function test_w2b_hard_ratio(testCase)
    % ratio = 100/10 = 10 > 3 => W2b_hard = 2
    rs_high = make_result('A1', {'1D','2D','3D'}, [10 10 100], [10 6 4], [0.8 0.8 0.8], [0 1 2], 0.005, false, 1);
    a_high = detect_anomalies(rs_high, default_thresholds());
    verifyEqual(testCase, a_high.flags.W2b_hard, 2);

    % ratio = 12/10 = 1.2 <= 3 => W2b_hard = 0
    rs_low = make_result('A2', {'1D','2D','3D'}, [10 10 12], [10 6 4], [0.8 0.8 0.8], [0 1 2], 0.005, false, 1);
    a_low = detect_anomalies(rs_low, default_thresholds());
    verifyEqual(testCase, a_low.flags.W2b_hard, 0);
end

% -------------------------------------------------------------------------
% Test 6: W1 red when 2-sigma low (outlier at pct=0 among 5 normals at pct=0.4)
% -------------------------------------------------------------------------

function test_w1_red_when_2sigma_low(testCase)
    % pct = match_stats(2)/match_stats(1)
    % normals: [10 4 6] => pct=4/10=0.4
    % outlier:  [10 0 10] => pct=0/10=0
    % mean=(5*0.4+0)/6=0.333, std~0.157, z(0 on bad side)=(0.333-0)/0.157~2.12 > 2 => red
    rs = [];
    for k = 1:5
        rs = [rs, make_result(sprintf('A%d',k), {'1D','2D'}, [10 10], [10 4 6], [0.5 0.5], [0 1], 0.005, false, 1)]; %#ok<AGROW>
    end
    rs = [rs, make_result('B', {'1D','2D'}, [10 10], [10 0 10], [0.5 0.5], [0 1], 0.005, false, 1)];
    a = detect_anomalies(rs, default_thresholds());
    verifyEqual(testCase, a.flags(strcmp(a.dataset_ids, 'B')).W1, 2);
    verifyEqual(testCase, a.flags(strcmp(a.dataset_ids, 'A1')).W1, 0);
end

% -------------------------------------------------------------------------
% Test 7: W1 yellow when in worst quartile but not 2-sigma.
% pcts: [0.50, 0.45, 0.40, 0.35, 0.30, 0.25, 0.20, 0.10]
% Sorted: [0.10 0.20 0.25 0.30 0.35 0.40 0.45 0.50]
% mean=0.3188, std=0.1335, z(0.10 on bad side)=(0.3188-0.10)/0.1335=1.639 < 2 => NOT red
% Q1~0.225 (interp between 0.20 and 0.25 at p=0.25), 0.10 < 0.225 => in worst quartile => yellow
% D1 (pct=0.50): bad-side z<0, not in worst quartile => 0
% -------------------------------------------------------------------------

function test_w1_yellow_when_worst_quartile_not_2sigma(testCase)
    % pct = mstats(2)/mstats(1); use mstats(1)=100, mstats(2)=round(pct*100)
    pcts = [0.50, 0.45, 0.40, 0.35, 0.30, 0.25, 0.20, 0.10];
    ids  = {'D1','D2','D3','D4','D5','D6','D7','D_low'};
    rs = [];
    for k = 1:numel(pcts)
        ms = [100, round(pcts(k)*100), round((1-pcts(k))*100)];
        rs = [rs, make_result(ids{k}, {'1D','2D'}, [10 10], ms, [0.5 0.5], [0 1], 0.005, false, 1)]; %#ok<AGROW>
    end
    a = detect_anomalies(rs, default_thresholds());
    w1_low = a.flags(strcmp(a.dataset_ids, 'D_low')).W1;  % pct=0.10, z~1.64 => yellow
    w1_d1  = a.flags(strcmp(a.dataset_ids, 'D1')).W1;     % pct=0.50, high end => 0
    % D_low: in worst quartile AND |z|<2 => yellow (1), not red (2)
    verifyEqual(testCase, w1_low, 1);
    % D1 at pct=0.50 is on the high (good) side => no flag
    verifyEqual(testCase, w1_d1, 0);
end

% -------------------------------------------------------------------------
% Test 8: W6b red when MSE 2-sigma high
% -------------------------------------------------------------------------

function test_w6b_red_when_mse_2sigma_high(testCase)
    % 5 datasets with MSE~0.006, one at 0.30
    % mean~(5*0.006+0.30)/6~0.055, std~0.118, z(0.30)=(0.30-0.055)/0.118~2.08 > 2 => red
    rs = [];
    for k = 1:5
        rs = [rs, make_result(sprintf('N%d',k), {'1D','2D'}, [10 10], [10 4 6], [0.5 0.5], [0 1], 0.006, false, 1)]; %#ok<AGROW>
    end
    rs = [rs, make_result('Hi', {'1D','2D'}, [10 10], [10 4 6], [0.5 0.5], [0 1], 0.30, false, 1)];
    a = detect_anomalies(rs, default_thresholds());
    verifyEqual(testCase, a.flags(strcmp(a.dataset_ids, 'Hi')).W6b, 2);
    verifyEqual(testCase, a.flags(strcmp(a.dataset_ids, 'N1')).W6b, 0);
end

% -------------------------------------------------------------------------
% Test 9: W7 session-count mismatch → severity 2; matching count → 0
% -------------------------------------------------------------------------

function test_w7_session_count_mismatch(testCase)
    % 4 sessions when expected 5 → W7 = 2
    sessions4 = {'1D','2D','3D','4D'};
    rs4 = make_result('S4', sessions4, [10 10 10 10], [10 4 6], [0.5 0.5 0.5 0.5], [0 1 2 3], 0.005, false, 1);
    thresh = default_thresholds();
    thresh.expected_n_sessions = 5;
    a4 = detect_anomalies(rs4, thresh);
    verifyEqual(testCase, a4.flags.W7, 2);

    % 5 sessions when expected 5 → W7 = 0
    sessions5 = {'1D','2D','3D','4D','5D'};
    rs5 = make_result('S5', sessions5, [10 10 10 10 10], [10 4 6], [0.5 0.5 0.5 0.5 0.5], [0 1 2 3 4], 0.005, false, 1);
    a5 = detect_anomalies(rs5, thresh);
    verifyEqual(testCase, a5.flags.W7, 0);
end

% -------------------------------------------------------------------------
% Test 10: Relative intra-dataset checks skipped for too-few samples
% -------------------------------------------------------------------------

function test_relative_intra_checks_skipped_few_samples(testCase)
    % 2 sessions => after ref exclusion, 1 non-ref shift => W5b skipped (numel<3)
    % but W5a (hard) fires because 100 > max_translation_px=30
    rs = make_result('A1', {'1D','2D'}, [10 10], [10 3 7], [1 0.6], [0 100], 0.005, false, 1);
    a = detect_anomalies(rs, default_thresholds());
    verifyEqual(testCase, a.flags.W5b, 0);
    verifyEqual(testCase, a.flags.W5a, 2);
end

% -------------------------------------------------------------------------
% Test 11: details name the right session for W3a
% CellReg gives one xcorr per non-reference session, so with reference 1 the
% values [0.6 0.25] belong to sessions 2D and 3D, not 1D and 2D.
% -------------------------------------------------------------------------

function test_details_w3a_session_skips_reference(testCase)
    rs = make_result('A1', {'1D','2D','3D'}, [10 10 10], [10 5 3 2], [0.6 0.25], [0 3 4], 0.005, false, 1);
    a = detect_anomalies(rs, default_thresholds());
    d = a.details(strcmp({a.details.anomaly_type}, 'W3a_low_xcorr_hard'));
    verifyEqual(testCase, d.session, '3D');
    verifyEqual(testCase, d.value, 0.25);
    verifyEqual(testCase, d.threshold, 0.3);
end

% -------------------------------------------------------------------------
% Test 12: W2b_rel detail holds the ratio and the crossed limit, not the severity
% ratios [1 1 1 1 1 2.5]: mean 1.25, std 0.612, z(2.5) = 2.04 > 2 => red
% -------------------------------------------------------------------------

function test_details_w2b_rel_reports_ratio_and_bound(testCase)
    rs = [];
    for k = 1:5
        rs = [rs, make_result(sprintf('N%d',k), {'1D','2D'}, [10 10], [10 4 6], 0.5, [0 1], 0.005, false, 1)]; %#ok<AGROW>
    end
    rs = [rs, make_result('R', {'1D','2D'}, [10 25], [25 4 21], 0.5, [0 1], 0.005, false, 1)];
    a = detect_anomalies(rs, default_thresholds());
    d = a.details(strcmp({a.details.dataset_id}, 'R') & strcmp({a.details.anomaly_type}, 'W2b_rel'));
    verifyEqual(testCase, d.severity, 2);
    verifyEqual(testCase, d.value, 2.5);
    ratios = [1 1 1 1 1 2.5];
    verifyEqual(testCase, d.threshold, mean(ratios) + 2 * std(ratios), 'AbsTol', 1e-12);
end

% -------------------------------------------------------------------------
% Test 13: every fired flag has exactly one detail row with the same severity
% Dataset 'Bad' has 7 sessions so the within-dataset checks can reach |z| > 2.
% -------------------------------------------------------------------------

function test_details_cover_every_fired_flag(testCase)
    rs = [];
    for k = 1:5
        rs = [rs, make_result(sprintf('N%d',k), {'1D','2D','3D','4D','5D'}, [10 10 10 10 10], ...
            [10 4 2 2 1 1], [0.8 0.8 0.8 0.8], [0 1 1 1 1], 0.005, false, 1)]; %#ok<AGROW>
    end
    rs = [rs, make_result('Bad', {'1D','2D','3D','4D','5D','6D','7D'}, [100 100 100 100 100 100 10], ...
        [100 5 0 0 0 0 0 95], [0.8 0.8 0.8 0.8 0.8 0.1], [0 1 1 1 1 1 50], 0.2, true, 1)];
    thresh = default_thresholds();
    thresh.expected_n_sessions = 5;
    thresh.fpr_max = 0.03;
    a = detect_anomalies(rs, thresh);

    bad = a.flags(strcmp(a.dataset_ids, 'Bad'));
    codes = fieldnames(bad);
    verifyTrue(testCase, all(cellfun(@(c) bad.(c) > 0, codes)), 'all 12 checks should fire for Bad');

    types = {a.details.anomaly_type};
    detail_codes = regexp(types, '^W\d+[ab]?(_hard|_rel)?', 'match', 'once');
    for k = 1:numel(a.flags)
        for c = 1:numel(codes)
            sel = strcmp({a.details.dataset_id}, a.dataset_ids{k}) & strcmp(detail_codes, codes{c});
            sev = a.flags(k).(codes{c});
            verifyEqual(testCase, sum(sel), double(sev > 0), sprintf('%s %s', a.dataset_ids{k}, codes{c}));
            if sev > 0
                verifyEqual(testCase, a.details(sel).severity, sev);
                verifyFalse(testCase, isnan(a.details(sel).threshold), ...
                    sprintf('%s %s threshold', a.dataset_ids{k}, codes{c}));
            end
        end
    end
end

% -------------------------------------------------------------------------
% Test 14: no processed dataset (every dataset skipped or not selected)
% -------------------------------------------------------------------------

function test_empty_results(testCase)
    a = detect_anomalies(struct([]), default_thresholds());
    verifyEmpty(testCase, a.dataset_ids);
    verifyEmpty(testCase, a.flags);
    verifyEmpty(testCase, a.details);
end
