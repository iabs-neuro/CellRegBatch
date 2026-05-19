function tests = test_config_roundtrip
    tests = functiontests(localfunctions);
end

function test_defaults_have_expected_keys(testCase)
    cfg = batch_default_config();
    verifyEqual(testCase, cfg.version, 1);
    verifyEqual(testCase, cfg.cellreg.microns_per_pixel, 1.6);
    verifyEqual(testCase, cfg.cellreg.alignment_type, 'Translations');
    verifyEqual(testCase, cfg.cellreg.maximal_rotation, 5);
    verifyEqual(testCase, cfg.cellreg.reference_session_index, 1);
    verifyEqual(testCase, cfg.cellreg.maximal_distance_um, 50);
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
    verifyEqual(testCase, cfg.anomaly_thresholds.z_threshold, 2.0);
    verifyEqual(testCase, cfg.anomaly_thresholds.max_translation_px, 30);
    verifyEqual(testCase, cfg.anomaly_thresholds.min_xcorr, 0.3);
    verifyEqual(testCase, cfg.anomaly_thresholds.max_mse, 0.1);
end

function test_roundtrip_preserves_values(testCase)
    cfg = batch_default_config();
    cfg.cellreg.microns_per_pixel = 2.5;
    cfg.anomaly_thresholds.z_threshold = 2.5;
    tmp = [tempname '.json'];
    cleanup = onCleanup(@() delete(tmp));
    config_to_json(cfg, tmp);
    cfg2 = config_from_json(tmp);
    verifyEqual(testCase, cfg2.cellreg.microns_per_pixel, 2.5);
    verifyEqual(testCase, cfg2.anomaly_thresholds.z_threshold, 2.5);
end

function test_unknown_version_rejected(testCase)
    tmp = [tempname '.json'];
    cleanup = onCleanup(@() delete(tmp));
    fid = fopen(tmp, 'w'); fprintf(fid, '{"version": 999}'); fclose(fid);
    verifyError(testCase, @() config_from_json(tmp), ...
        'BatchCellReg:UnsupportedConfigVersion');
end
