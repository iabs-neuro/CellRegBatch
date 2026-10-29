function tests = test_detect_anomalies
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', '..', 'BatchCellReg')));
end

% -------------------------------------------------------------------------
% Helpers
% -------------------------------------------------------------------------

function t = thresholds()
    cfg = batch_default_config();
    t = cfg.anomaly_thresholds;
    t.expected_n_sessions = 5;
    t.fpr_max = 0.03;
    t.alignment_min_xcorr = 0.2;
end

function r = good(id)
    % A healthy 5-session dataset: ~200 cells per session, 50 in all
    % sessions (match = 50 / 200 = 25 %), good alignment and fit.
    r = struct( ...
        'dataset_id', id, ...
        'sessions', {{'1D', '2D', '3D', '4D', '5D'}}, ...
        'missing_sessions', {{}}, ...
        'n_cells_per_session', [200 210 190 205 195], ...
        'match_stats', [400 50 40 60 100 150], ...
        'maximal_cross_correlation', [0.6 0.55 0.5 0.6], ...
        'alignment_shift_px', [0 5 8 6 4], ...
        'reference_session_index', 1, ...
        'MSE_model', 0.07, ...
        'p_same_unreachable', false, ...
        'chosen_fpr', 0.02, ...
        'forced_low_xcorr', false, ...
        'linked_fraction', [0.9 0.85 0.88 0.9 0.87], ...
        'error', '');
end

function d = details_of(a, id, warning_name)
    d = a.details(strcmp({a.details.dataset_id}, id) & strcmp({a.details.warning}, warning_name));
end

% -------------------------------------------------------------------------
% Tests
% -------------------------------------------------------------------------

function test_healthy_dataset_has_no_warning(tc)
    a = detect_anomalies(good('A'), thresholds());
    verifyEqual(tc, cell2mat(struct2cell(a.flags))', zeros(1, 6));
    verifyEmpty(tc, a.details);
end

function test_flag_names_and_order(tc)
    a = detect_anomalies(good('A'), thresholds());
    verifyEqual(tc, fieldnames(a.flags)', {'session_count', 'few_cells', 'cell_drop', ...
        'alignment', 'model_fit', 'low_match'});
end

function test_missing_session_is_red_and_named(tc)
    r = good('A');
    r.sessions = {'1D', '2D', '4D', '5D'};
    r.missing_sessions = {'3D'};
    r.n_cells_per_session = [200 210 205 195];
    r.match_stats = [380 60 60 110 150];
    r.maximal_cross_correlation = [0.6 0.5 0.6];
    r.alignment_shift_px = [0 5 6 4];
    a = detect_anomalies(r, thresholds());
    verifyEqual(tc, a.flags.session_count, 2);
    d = details_of(a, 'A', 'session_count');
    verifyEqual(tc, d.session, '3D');
    verifyEqual(tc, [d.value d.threshold], [4 5]);
    verifyEqual(tc, d.severity, 'red');
end

function test_no_expected_count_means_no_session_check(tc)
    t = rmfield(thresholds(), 'expected_n_sessions');
    r = good('A'); r.sessions = r.sessions(1:4);
    a = detect_anomalies(r, t);
    verifyEqual(tc, a.flags.session_count, 0);
end

function test_few_cells_levels(tc)
    r = good('A'); r.n_cells_per_session = [50 52 48 55 51];   % median 51
    a = detect_anomalies(r, thresholds());
    verifyEqual(tc, a.flags.few_cells, 1);
    d = details_of(a, 'A', 'few_cells');
    verifyEqual(tc, [d.value d.threshold], [51 60]);
    r.n_cells_per_session = [20 25 22 28 21];                 % median 22
    a = detect_anomalies(r, thresholds());
    verifyEqual(tc, a.flags.few_cells, 2);
end

function test_cell_drop_names_the_worst_session(tc)
    % Works with 5 sessions, where a within-dataset z-score never could:
    % its largest possible |z| is (n-1)/sqrt(n) = 1.79.
    r = good('A'); r.n_cells_per_session = [200 210 60 205 195];   % 60/200 = 0.3
    a = detect_anomalies(r, thresholds());
    verifyEqual(tc, a.flags.cell_drop, 2);
    d = details_of(a, 'A', 'cell_drop');
    verifyEqual(tc, d.session, '3D');
    verifyEqual(tc, d.value, 0.3, 'AbsTol', 1e-12);
    verifyEqual(tc, d.threshold, 0.4);
    r.n_cells_per_session = [200 210 100 205 195];               % 0.5
    a = detect_anomalies(r, thresholds());
    verifyEqual(tc, a.flags.cell_drop, 1);
end

function test_low_xcorr_session_skips_reference(tc)
    % One cross-correlation per non-reference session: with reference 2,
    % the values belong to sessions 1, 3, 4, 5.
    r = good('A'); r.reference_session_index = 2;
    r.maximal_cross_correlation = [0.6 0.2 0.5 0.6];
    a = detect_anomalies(r, thresholds());
    verifyEqual(tc, a.flags.alignment, 2);
    d = details_of(a, 'A', 'alignment');
    verifyEqual(tc, d.session, '3D');
    verifyEqual(tc, d.threshold, 0.25);
    r.maximal_cross_correlation = [0.6 0.28 0.5 0.6];
    a = detect_anomalies(r, thresholds());
    verifyEqual(tc, a.flags.alignment, 1);
end

function test_forced_alignment_is_red(tc)
    r = good('A'); r.forced_low_xcorr = true;
    a = detect_anomalies(r, thresholds());
    verifyEqual(tc, a.flags.alignment, 2);
    d = details_of(a, 'A', 'alignment');
    verifyEqual(tc, d.rule, 'no alignment mode passed the gate');
    verifyEqual(tc, d.threshold, 0.2);
end

function test_large_shift_is_yellow_and_skips_reference(tc)
    r = good('A'); r.alignment_shift_px = [90 5 45 6 4];   % reference 1 is ignored
    a = detect_anomalies(r, thresholds());
    verifyEqual(tc, a.flags.alignment, 1);
    d = details_of(a, 'A', 'alignment');
    verifyEqual(tc, d.session, '3D');
    verifyEqual(tc, [d.value d.threshold], [45 30]);
end

function test_model_fit_levels_and_unreachable_fpr(tc)
    r = good('A'); r.MSE_model = 0.12;
    a = detect_anomalies(r, thresholds());
    verifyEqual(tc, a.flags.model_fit, 1);
    r.MSE_model = 0.2;
    a = detect_anomalies(r, thresholds());
    verifyEqual(tc, a.flags.model_fit, 2);
    r = good('A'); r.p_same_unreachable = true; r.chosen_fpr = 0.05;
    a = detect_anomalies(r, thresholds());
    verifyEqual(tc, a.flags.model_fit, 2);
    d = details_of(a, 'A', 'model_fit');
    verifyEqual(tc, [d.value d.threshold], [0.05 0.03]);
end

function test_no_cell_in_all_sessions_is_red_in_any_batch(tc)
    r = good('A'); r.match_stats = [400 0 40 60 150 150];
    a = detect_anomalies(r, thresholds());
    verifyEqual(tc, a.flags.low_match, 2);
end

function test_low_match_uses_median_and_mad(tc)
    % Matches 25,26,24,25,27,23,25 % and one bad dataset at 5 %. A mean/SD
    % rule would let the bad dataset widen the SD; median/MAD ignores it.
    pct = [25 26 24 25 27 23 25 5];
    rs = arrayfun(@(k) good(sprintf('D%d', k)), 1:numel(pct));
    for k = 1:numel(pct); rs(k).match_stats(2) = 2 * pct(k); end   % mean cells = 200
    a = detect_anomalies(rs, thresholds());
    verifyEqual(tc, [a.flags.low_match], [0 0 0 0 0 0 0 2]);
    verifyEqual(tc, a.batch.match_median, 0.25, 'AbsTol', 1e-12);
    d = details_of(a, 'D8', 'low_match');
    verifyEqual(tc, d.value, 5, 'AbsTol', 1e-9);
    verifyLessThan(tc, d.threshold, 25);
end

function test_low_match_needs_five_comparable_datasets(tc)
    % Four datasets, or datasets with another session count, are not a
    % batch to compare with.
    pct = [25 26 24 5];
    rs = arrayfun(@(k) good(sprintf('D%d', k)), 1:numel(pct));
    for k = 1:numel(pct); rs(k).match_stats(2) = 2 * pct(k); end
    a = detect_anomalies(rs, thresholds());
    verifyEqual(tc, [a.flags.low_match], [0 0 0 0]);
    verifyTrue(tc, isnan(a.batch.match_median));
end

function test_isolated_session_is_found_in_a_batch_of_one(tc)
    % Session 5D: only 18 % of its cells appear in another session, against
    % ~90 % for the others (a mirrored session in the demo batch).
    r = good('A'); r.linked_fraction = [0.92 0.95 0.94 0.89 0.18];
    a = detect_anomalies(r, thresholds());
    verifyEqual(tc, a.flags.low_match, 2);
    d = details_of(a, 'A', 'low_match');
    verifyEqual(tc, d.session, '5D');
    verifyEqual(tc, d.value, 0.18 / 0.92, 'AbsTol', 1e-12);
    verifyEqual(tc, d.threshold, 0.4);
    r.linked_fraction = [0.92 0.95 0.94 0.89 0.5];
    a = detect_anomalies(r, thresholds());
    verifyEqual(tc, a.flags.low_match, 1);
end

function test_session_link_needs_three_sessions(tc)
    r = good('A'); r.sessions = {'1D', '2D'}; r.linked_fraction = [0.9 0.2];
    t = thresholds(); t.expected_n_sessions = 2;
    a = detect_anomalies(r, t);
    verifyEqual(tc, a.flags.low_match, 0);
end

function test_failed_dataset_gets_no_warning(tc)
    r = good('A'); r.error = 'alignment failed';
    a = detect_anomalies(r, thresholds());
    verifyEqual(tc, cell2mat(struct2cell(a.flags))', zeros(1, 6));
end

function test_empty_results(tc)
    a = detect_anomalies(struct([]), thresholds());
    verifyEmpty(tc, a.flags);
    verifyEmpty(tc, a.details);
end

function test_every_fired_flag_has_a_detail(tc)
    r = good('Bad');
    r.sessions = {'1D', '2D', '3D', '4D'}; r.missing_sessions = {'5D'};
    r.n_cells_per_session = [25 26 5 27];
    r.match_stats = [60 0 5 10 45];
    r.maximal_cross_correlation = [0.2 0.5 0.5];
    r.alignment_shift_px = [0 40 1 1];
    r.MSE_model = 0.3;
    a = detect_anomalies(r, thresholds());
    names = fieldnames(a.flags);
    for k = 1:numel(names)
        verifyEqual(tc, a.flags.(names{k}), 2, names{k});
        verifyNotEmpty(tc, details_of(a, 'Bad', names{k}), names{k});
    end
end
