function tests = test_plot_batch_warnings
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', '..', 'BatchCellReg')));
end

function r = result(id, ncells, in_all, err)
    r = struct('dataset_id', id, 'sessions', {{'1D', '2D', '3D'}}, ...
        'missing_sessions', {{}}, 'n_cells_per_session', ncells, ...
        'match_stats', [sum(ncells) in_all 0 0], ...
        'maximal_cross_correlation', [0.5 0.4], 'alignment_shift_px', [0 3 4], ...
        'reference_session_index', 1, 'MSE_model', 0.07, 'p_same_unreachable', false, ...
        'chosen_fpr', 0.01, 'forced_low_xcorr', false, 'error', err);
end

function t = thresholds()
    cfg = batch_default_config();
    t = cfg.anomaly_thresholds;
    t.expected_n_sessions = 3;
    t.fpr_max = 0.03;
end

function test_writes_png_with_failed_and_flagged_rows(tc)
    rs = [result('M_A01', [200 210 190], 50, ''), result('M_A02', [20 25 5], 0, ''), ...
          result('M_A03', [], 0, 'alignment failed')];
    a = detect_anomalies(rs, thresholds());
    png = [tempname '.png'];
    cleanup = onCleanup(@() delete(png));
    figs_before = findall(groot, 'Type', 'figure');
    plot_batch_warnings(rs, a, thresholds(), png);
    verifyEqual(tc, exist(png, 'file'), 2);
    info = imfinfo(png);
    verifyGreaterThan(tc, info.Width, 1000);
    % A batch must not leave hidden figures behind (they hold memory).
    verifyEmpty(tc, setdiff(findall(groot, 'Type', 'figure'), figs_before));
end

function test_empty_batch_still_writes_png(tc)
    a = detect_anomalies(struct([]), thresholds());
    png = [tempname '.png'];
    cleanup = onCleanup(@() delete(png));
    plot_batch_warnings(struct([]), a, thresholds(), png);
    verifyEqual(tc, exist(png, 'file'), 2);
end
