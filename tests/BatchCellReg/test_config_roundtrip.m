function tests = test_config_roundtrip
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', '..', 'BatchCellReg')));
end

function test_defaults_have_expected_keys(testCase)
    cfg = batch_default_config();
    verifyEqual(testCase, cfg.version, 2);
    verifyEqual(testCase, cfg.cellreg.microns_per_pixel, 1.6);
    verifyEqual(testCase, cfg.cellreg.alignment_type, 'Translations');
    verifyEqual(testCase, cfg.cellreg.maximal_rotation, 5);
    verifyEqual(testCase, cfg.cellreg.reference_session_index, 1);
    verifyEqual(testCase, cfg.cellreg.maximal_distance_um, 15);
    verifyEqual(testCase, cfg.cellreg.registration_approach, 'Probabilistic');
    verifyEqual(testCase, cfg.cellreg.initial_registration_type, 'auto');
    verifyTrue(testCase, cfg.cellreg.use_parallel_processing);
    verifyEqual(testCase, cfg.cellreg.figures_visibility, 'off');
    verifyTrue(testCase, cfg.cellreg.write_to_file);
    verifyEqual(testCase, cfg.cellreg.alignment_min_xcorr, 0.2);
    verifyEqual(testCase, cfg.cellreg.expected_n_sessions, 5);
    verifyEqual(testCase, cfg.cellreg.rotation_fallback_deg, 90);
    verifyEqual(testCase, cfg.cellreg.nonrigid_smoothness, 2);
    verifyEqual(testCase, cfg.p_same_tuning.fpr_max, 0.03);
    a = cfg.anomaly_thresholds;
    verifyEqual(testCase, [a.few_cells_red, a.few_cells_yellow], [30 60]);
    verifyEqual(testCase, [a.cell_drop_red, a.cell_drop_yellow], [0.4 0.6]);
    verifyEqual(testCase, [a.xcorr_red, a.xcorr_yellow], [0.25 0.3]);
    verifyEqual(testCase, a.shift_yellow_px, 30);
    verifyEqual(testCase, [a.mse_red, a.mse_yellow], [0.15 0.1]);
    verifyEqual(testCase, [a.match_z_red, a.match_z_yellow], [3 2]);
end

function test_roundtrip_preserves_values(testCase)
    cfg = batch_default_config();
    cfg.cellreg.microns_per_pixel = 2.5;
    cfg.anomaly_thresholds.match_z_yellow = 2.5;
    cfg.cellreg.initial_registration_type = 'Centroid distance';
    tmp = [tempname '.json'];
    cleanup = onCleanup(@() delete(tmp));
    config_to_json(cfg, tmp);
    cfg2 = config_from_json(tmp);
    verifyEqual(testCase, cfg2.cellreg.microns_per_pixel, 2.5);
    verifyEqual(testCase, cfg2.anomaly_thresholds.match_z_yellow, 2.5);
    verifyEqual(testCase, cfg2.cellreg.initial_registration_type, 'Centroid distance');
end

function test_version_1_file_still_loads(testCase)
    % A file saved before the warnings review: old threshold names, no new
    % fields. Renamed thresholds keep their values, the rest get defaults.
    tmp = [tempname '.json'];
    cleanup = onCleanup(@() delete(tmp));
    fid = fopen(tmp, 'w');
    fprintf(fid, ['{"version":1,"cellreg":{"microns_per_pixel":2,"expected_n_sessions":4},' ...
        '"anomaly_thresholds":{"z_threshold":2,"max_translation_px":40,"min_xcorr":0.35,"max_mse":0.12}}']);
    fclose(fid);
    cfg = config_from_json(tmp);
    verifyEqual(testCase, cfg.version, 2);
    verifyEqual(testCase, cfg.cellreg.microns_per_pixel, 2);
    verifyEqual(testCase, cfg.cellreg.expected_n_sessions, 4);
    verifyEqual(testCase, cfg.cellreg.alignment_type, 'Translations');
    verifyEqual(testCase, cfg.anomaly_thresholds.shift_yellow_px, 40);
    verifyEqual(testCase, cfg.anomaly_thresholds.xcorr_yellow, 0.35);
    verifyEqual(testCase, cfg.anomaly_thresholds.mse_yellow, 0.12);
    verifyEqual(testCase, cfg.anomaly_thresholds.xcorr_red, 0.25);
    verifyFalse(testCase, isfield(cfg.anomaly_thresholds, 'z_threshold'));
end

function test_unknown_field_warns_and_is_dropped(testCase)
    tmp = [tempname '.json'];
    cleanup = onCleanup(@() delete(tmp));
    fid = fopen(tmp, 'w'); fprintf(fid, '{"version":2,"cellreg":{"no_such_field":1}}'); fclose(fid);
    cfg = verifyWarning(testCase, @() config_from_json(tmp), 'BatchCellReg:ConfigUnknownField');
    verifyFalse(testCase, isfield(cfg.cellreg, 'no_such_field'));
end

function test_unknown_version_rejected(testCase)
    tmp = [tempname '.json'];
    cleanup = onCleanup(@() delete(tmp));
    fid = fopen(tmp, 'w'); fprintf(fid, '{"version": 999}'); fclose(fid);
    verifyError(testCase, @() config_from_json(tmp), ...
        'BatchCellReg:UnsupportedConfigVersion');
end
