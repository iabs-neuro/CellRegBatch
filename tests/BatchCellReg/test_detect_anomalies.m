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
    % Five datasets at pct=0.4, one at pct=0 (outlier).
    % mean = (5*0.4+0)/6 = 0.333, std ~ 0.157, z(0) = -2.12 => W1 fires.
    rs = [];
    for k = 1:5
        rs = [rs, make_result(sprintf('A%d',k), {'1D','2D'}, [10 10], [10 4 6], [0.5 0.5], [0 1], 0.005, false, 1)]; %#ok<AGROW>
    end
    rs = [rs, make_result('B', {'1D','2D'}, [10 10], [10 0 10], [0.5 0.5], [0 1], 0.005, false, 1)];
    a = detect_anomalies(rs, default_thresholds());
    flags = a.flags;
    verifyTrue(testCase, flags(strcmp(a.dataset_ids, 'B')).W1);
    verifyFalse(testCase, flags(strcmp(a.dataset_ids, 'A1')).W1);
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
