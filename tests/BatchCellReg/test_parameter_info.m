function tests = test_parameter_info
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', '..', 'BatchCellReg')));
end

function test_every_gui_parameter_has_help(tc)
    % The GUI shows these config paths; each "?" button needs a text.
    gui = {'cellreg.expected_n_sessions', 'cellreg.microns_per_pixel', ...
        'cellreg.alignment_type', 'cellreg.maximal_rotation', ...
        'cellreg.reference_session_index', 'cellreg.maximal_distance_um', ...
        'cellreg.alignment_min_xcorr', 'cellreg.initial_registration_type', ...
        'cellreg.registration_approach', 'p_same_tuning.fpr_max', ...
        'cellreg.write_to_file', 'cellreg.figures_visibility', ...
        'cellreg.use_parallel_processing', 'anomaly_thresholds.few_cells_yellow', ...
        'anomaly_thresholds.cell_drop_yellow', 'anomaly_thresholds.xcorr_yellow', ...
        'anomaly_thresholds.shift_yellow_px', 'anomaly_thresholds.mse_yellow', ...
        'anomaly_thresholds.match_z_yellow', 'anomaly_thresholds.session_link_yellow', ...
        'input_folder', 'warnings'};
    m = parameter_info();
    for k = 1:numel(gui)
        verifyTrue(tc, isKey(m, gui{k}), gui{k});
    end
end

function test_help_keys_are_real_config_paths(tc)
    cfg = batch_default_config();
    m = parameter_info();
    topics = {'input_folder', 'warnings'};
    ks = keys(m);
    for k = 1:numel(ks)
        if ismember(ks{k}, topics); continue; end
        parts = strsplit(ks{k}, '.');
        verifyTrue(tc, isfield(cfg, parts{1}) && isfield(cfg.(parts{1}), parts{2}), ks{k});
    end
end
