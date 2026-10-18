function result = run_single_dataset(dataset, cfg, out_subdir, logger)
%RUN_SINGLE_DATASET Run CellReg Stages 1-5 on one (exp, mouse) dataset.
%
%   dataset: struct from scan_input_folder (one element of result.datasets).
%   cfg:     full batch config struct (see batch_default_config).
%   out_subdir: directory to write outputs into (created if missing).
%   logger: batch_logger handle.

    figures_dir = fullfile(out_subdir, 'Figures');
    if ~exist(figures_dir, 'dir'); mkdir(figures_dir); end
    fig_vis = cfg.cellreg.figures_visibility;

    tag = dataset.dataset_id;
    logger.info(tag, 'sessions: %s', strjoin({dataset.sessions.session_id}, ', '));

    file_paths = {dataset.sessions.file_path};
    spatial_footprints = prepare_session_files(file_paths);

    microns_per_pixel = cfg.cellreg.microns_per_pixel;
    alignment_type    = cfg.cellreg.alignment_type;
    use_parallel      = cfg.cellreg.use_parallel_processing;
    max_rot           = cfg.cellreg.maximal_rotation;
    ref_idx           = cfg.cellreg.reference_session_index;
    max_dist          = cfg.cellreg.maximal_distance_um;
    norm_max_dist     = max_dist / microns_per_pixel;
    p_same_certainty  = 0.95;

    logger.info(tag, 'stage 2: aligning');
    [normalized_spatial_footprints] = normalize_spatial_footprints(spatial_footprints);
    [adjusted_spatial_footprints, adjusted_FOV, ax, ay, adj_pad] = ...
        adjust_FOV_size(normalized_spatial_footprints);
    [adjusted_footprints_projections] = compute_footprints_projections(adjusted_spatial_footprints);
    [centroid_locations] = compute_centroid_locations(adjusted_spatial_footprints, microns_per_pixel);
    [centroid_projections] = compute_centroids_projections(centroid_locations, adjusted_spatial_footprints);

    % Match the standalone CellReg GUI (GUI/CellReg.m:732-733), which is the
    % user's validated manual workflow: footprints threshold is 0.2, NOT
    % demo.m's 0.3. With 0.3 the vendor accept test (align_images.m:326,
    % max_xcorr > median + threshold) rejects rigid alignment for cross-day
    % sessions that the GUI accepts, spuriously forcing Non-rigid.
    sufficient_corr_centroids  = 0.2;
    sufficient_corr_footprints = 0.2;

    % --- 4-stage alignment fallback cascade ---
    % Note: vendor align_images has a real bug in its spatial-footprint rotation block
    % (CellReg/align_images.m lines ~349-366): the branch on use_parallel_processing
    % is inverted — `if use_parallel_processing` runs a plain `for`, while the `else`
    % branch runs `parfor`. When this code path is hit on a session that actually needs
    % rotation (abs(best_rotation) > minimal_rotation) AND no parallel pool exists,
    % the parfor in the else branch errors during pool bootstrap. Passing `true` for
    % rotation stages matches demo.m's default and keeps the bug dormant.
    stages = {};
    stages{end+1} = struct('label', 'Translations', ...
        'type', 'Translations', 'extra', [], 'par', use_parallel);
    stages{end+1} = struct('label', sprintf('Translations and Rotations@%g', cfg.cellreg.maximal_rotation), ...
        'type', 'Translations and Rotations', 'extra', cfg.cellreg.maximal_rotation, 'par', true);
    stages{end+1} = struct('label', sprintf('Translations and Rotations@%g', cfg.cellreg.rotation_fallback_deg), ...
        'type', 'Translations and Rotations', 'extra', cfg.cellreg.rotation_fallback_deg, 'par', true);
    stages{end+1} = struct('label', sprintf('Non-rigid@%g', cfg.cellreg.nonrigid_smoothness), ...
        'type', 'Non-rigid', 'extra', cfg.cellreg.nonrigid_smoothness, 'par', use_parallel);

    % Determine which stage to start from based on configured alignment_type.
    switch alignment_type
        case 'Translations';               start_i = 1;
        case 'Translations and Rotations'; start_i = 2;
        case 'Non-rigid';                  start_i = 4;
        otherwise;                         start_i = 1;
    end

    won = 0; displacement_fields = []; last_reason = 'none'; won_label = '';
    sfp_c = {}; cl_c = {}; fpr_c = {}; cp_c = {};
    max_xcorr = []; alignment_translations = []; overlapping_FOV = [];
    % Best downstream-viable (no empty slots) candidate seen so far, used as a
    % flagged fallback if no mode clears the alignment_min_xcorr gate.
    best_cand = struct('score', -Inf);

    for si = start_i:numel(stages)
        s = stages{si};
        logger.info(tag, 'stage 2: trying alignment mode %s', s.label);
        try
            if isempty(s.extra)
                % Translations — no extra arg
                [sfp_c, cl_c, fpr_c, cp_c, max_xcorr, alignment_translations, overlapping_FOV] = ...
                    align_images(adjusted_spatial_footprints, centroid_locations, ...
                        adjusted_footprints_projections, centroid_projections, adjusted_FOV, ...
                        microns_per_pixel, ref_idx, s.type, ...
                        sufficient_corr_centroids, sufficient_corr_footprints, s.par);
                df = [];
            elseif strcmp(s.type, 'Non-rigid')
                % Non-rigid — capture 8th output (displacement_fields)
                [sfp_c, cl_c, fpr_c, cp_c, max_xcorr, alignment_translations, overlapping_FOV, df] = ...
                    align_images(adjusted_spatial_footprints, centroid_locations, ...
                        adjusted_footprints_projections, centroid_projections, adjusted_FOV, ...
                        microns_per_pixel, ref_idx, s.type, ...
                        sufficient_corr_centroids, sufficient_corr_footprints, s.par, s.extra);
            else
                % Translations and Rotations — pass maximal_rotation as extra arg
                [sfp_c, cl_c, fpr_c, cp_c, max_xcorr, alignment_translations, overlapping_FOV] = ...
                    align_images(adjusted_spatial_footprints, centroid_locations, ...
                        adjusted_footprints_projections, centroid_projections, adjusted_FOV, ...
                        microns_per_pixel, ref_idx, s.type, ...
                        sufficient_corr_centroids, sufficient_corr_footprints, s.par, s.extra);
                df = [];
            end

            % --- Per-stage failure test ---
            % Check for empty corrected sessions (excluding reference).
            fe = find(cellfun(@isempty, sfp_c));
            fe(fe == ref_idx) = [];
            % Check for low cross-correlation in non-reference sessions.
            % max_xcorr is a vector of length (n_sessions-1); it does NOT include
            % the reference entry, so we do NOT drop ref_idx from it.
            mx = max_xcorr(:)';
            if numel(mx) == numel(sfp_c)
                % Defensive: if vendor ever returns a full-length vector, drop ref.
                mx(ref_idx) = [];
            end
            low = any(mx < cfg.cellreg.alignment_min_xcorr);

            if ~isempty(fe) || low
                last_reason = sprintf('empty=%s lowxcorr=%d', mat2str(fe), low);
                logger.warn(tag, 'stage 2: mode %s failed (%s), trying next', s.label, last_reason);
                % Remember the best downstream-viable candidate (no empty
                % slots). If every mode misses the xcorr gate we fall back to
                % this one and flag it RED rather than dropping the dataset.
                if isempty(fe)
                    cand_score = min(mx);
                    if cand_score > best_cand.score
                        best_cand = struct('score', cand_score, ...
                            'sfp_c', {sfp_c}, 'cl_c', {cl_c}, 'fpr_c', {fpr_c}, ...
                            'cp_c', {cp_c}, 'max_xcorr', max_xcorr, ...
                            'alignment_translations', alignment_translations, ...
                            'overlapping_FOV', overlapping_FOV, 'df', df, ...
                            'type', s.type, 'label', s.label);
                    end
                end
                continue
            end

            % Stage succeeded.
            won = si;
            displacement_fields = df;
            alignment_type = s.type;   % effective mode for downstream branches
            won_label = s.label;
            logger.info(tag, 'stage 2: alignment OK with %s', s.label);
            break

        catch ME
            last_reason = ME.message;
            logger.warn(tag, 'stage 2: mode %s errored (%s), trying next', s.label, ME.message);
            continue
        end
    end

    forced_low_xcorr = false;
    if won == 0
        if isfinite(best_cand.score)
            % No mode cleared the gate, but at least one produced non-empty
            % footprints for every session. Use the best of those, run the
            % full pipeline, and let the anomaly detector flag it RED (W3a).
            forced_low_xcorr = true;
            sfp_c = best_cand.sfp_c; cl_c = best_cand.cl_c;
            fpr_c = best_cand.fpr_c; cp_c = best_cand.cp_c;
            max_xcorr = best_cand.max_xcorr;
            alignment_translations = best_cand.alignment_translations;
            overlapping_FOV = best_cand.overlapping_FOV;
            displacement_fields = best_cand.df;
            alignment_type = best_cand.type;
            won_label = sprintf('%s (forced, low xcorr=%.3f)', ...
                best_cand.label, best_cand.score);
            logger.warn(tag, ['stage 2: no mode cleared xcorr gate %.2f; ' ...
                'forcing best mode %s (xcorr=%.3f) - will be flagged'], ...
                cfg.cellreg.alignment_min_xcorr, best_cand.label, best_cand.score);
        else
            % Every mode left an empty session footprint: downstream stages
            % cannot run. This dataset is unregisterable.
            error('BatchCellReg:AlignmentFailed', ...
                ['All alignment modes failed for %s (Translations, Rotations@%g, ' ...
                 'Rotations@%g, Non-rigid) with empty session footprints. Last: %s'], ...
                dataset.dataset_id, cfg.cellreg.maximal_rotation, ...
                cfg.cellreg.rotation_fallback_deg, last_reason);
        end
    end

    [all_proj_corr, n_cells_per_session] = evaluate_data_quality( ...
        sfp_c, cp_c, fpr_c, max_xcorr, alignment_translations, ref_idx, ...
        sufficient_corr_footprints, alignment_type);
    if strcmp(alignment_type, 'Non-rigid')
        plot_alignment_results(adjusted_spatial_footprints, centroid_locations, sfp_c, cl_c, ...
            adjusted_footprints_projections, fpr_c, ref_idx, all_proj_corr, max_xcorr, ...
            alignment_translations, overlapping_FOV, alignment_type, n_cells_per_session, ...
            figures_dir, fig_vis, displacement_fields);
    else
        plot_alignment_results(adjusted_spatial_footprints, centroid_locations, sfp_c, cl_c, ...
            adjusted_footprints_projections, fpr_c, ref_idx, all_proj_corr, max_xcorr, ...
            alignment_translations, overlapping_FOV, alignment_type, n_cells_per_session, ...
            figures_dir, fig_vis);
    end

    % Stage 1 figure: per-session footprint projections.
    safe_plot(logger, tag, 'all_sessions_projections', @() ...
        plot_all_sessions_projections(adjusted_footprints_projections, figures_dir, fig_vis));

    logger.info(tag, 'stage 3: probabilistic model');
    [n_bins, centers_of_bins] = estimate_number_of_bins(spatial_footprints, norm_max_dist);
    [a2a_idx, a2a_sc, a2a_cd, neighb_sc, neighb_cd, neighb_dx, neighb_dy, NN_sc, NNN_sc, NN_cd, NNN_cd] = ...
        compute_data_distribution(sfp_c, cl_c, norm_max_dist);

    % Stage 3a figure: (x,y) displacement distribution.
    safe_plot(logger, tag, 'x_y_displacements', @() ...
        plot_x_y_displacements(neighb_dx, neighb_dy, microns_per_pixel, ...
            norm_max_dist, n_bins, centers_of_bins, figures_dir, fig_vis));

    [cd_pars, p_given_cd, cd_dist, cd_same, cd_diff, cd_wsum, MSE_cd, cd_intersect] = ...
        compute_centroid_distances_model(neighb_cd, microns_per_pixel, centers_of_bins);
    [sc_pars, p_given_sc, sc_dist, sc_same, sc_diff, sc_wsum, MSE_sc, sc_intersect] = ...
        compute_spatial_correlations_model(neighb_sc, centers_of_bins);

    [p_same_centers, unc_cd, cdf_cd, fpr_cd, tpr_cd, unc_sc, cdf_sc, fpr_sc, tpr_sc] = ...
        estimate_registration_accuracy(p_same_certainty, neighb_cd, cd_same, cd_diff, ...
            p_given_cd, centers_of_bins, neighb_sc, sc_same, sc_diff, p_given_sc);

    % Stage 3b figures: probabilistic models + estimated registration accuracy.
    safe_plot(logger, tag, 'models', @() ...
        plot_models(cd_pars, NN_cd, NNN_cd, cd_dist, cd_same, cd_diff, cd_wsum, ...
            cd_intersect, centers_of_bins, microns_per_pixel, norm_max_dist, ...
            figures_dir, fig_vis, sc_pars, NN_sc, NNN_sc, sc_dist, sc_same, ...
            sc_diff, sc_wsum, sc_intersect));
    safe_plot(logger, tag, 'estimated_registration_accuracy', @() ...
        plot_estimated_registration_accuracy(p_same_centers, p_same_certainty, ...
            p_given_cd, cd_dist, cdf_cd, unc_cd, tpr_cd, fpr_cd, centers_of_bins, ...
            norm_max_dist, microns_per_pixel, figures_dir, fig_vis, p_given_sc, ...
            sc_dist, cdf_sc, unc_sc, tpr_sc, fpr_sc));

    best_model = choose_best_model(MSE_cd, cd_same, cd_diff, p_given_cd, ...
        MSE_sc, sc_same, sc_diff, p_given_sc);

    [a2a_psame_cd, a2a_psame_sc] = compute_p_same(a2a_cd, p_given_cd, centers_of_bins, ...
        a2a_sc, p_given_sc);

    % --- auto P_same ---
    if strcmp(best_model, 'Spatial correlation')
        fpr_vec = fpr_sc; mse_val = MSE_sc;
    else
        fpr_vec = fpr_cd; mse_val = MSE_cd;
    end
    [p_same_thr, chosen_fpr, p_same_unreachable] = ...
        choose_p_same_by_fpr(p_same_centers, fpr_vec, cfg.p_same_tuning.fpr_max);
    logger.info(tag, 'chosen P_same=%.3f, FPR=%.4f [model=%s]', ...
        p_same_thr, chosen_fpr, best_model);
    if p_same_unreachable
        logger.warn(tag, 'FPR target %.3f unreachable; closest=%.4f', ...
            cfg.p_same_tuning.fpr_max, chosen_fpr);
    end

    logger.info(tag, 'stage 4: initial registration');
    if strcmp(best_model, 'Spatial correlation')
        if ~isempty(sc_intersect); init_thresh = sc_intersect; else; init_thresh = 0.65; end
        [cell_to_index_map, reg_sc, nonreg_sc] = ...
            initial_registration_spatial_correlations(norm_max_dist, init_thresh, sfp_c, cl_c);
        % Stage 4 figure (spatial-correlation initial registration).
        safe_plot(logger, tag, 'initial_registration', @() ...
            plot_initial_registration(cell_to_index_map, n_bins, sfp_c, ...
                'Spatial correlation', figures_dir, fig_vis, reg_sc, nonreg_sc));
    else
        if ~isempty(cd_intersect); init_thresh = cd_intersect; else; init_thresh = 5; end
        norm_dist_thresh = init_thresh / microns_per_pixel;
        [cell_to_index_map, reg_cd, nonreg_cd] = ...
            initial_registration_centroid_distances(norm_max_dist, norm_dist_thresh, cl_c);
        % Stage 4 figure (centroid-distance initial registration).
        safe_plot(logger, tag, 'initial_registration', @() ...
            plot_initial_registration(cell_to_index_map, n_bins, sfp_c, ...
                'Centroid distance', figures_dir, fig_vis, reg_cd, nonreg_cd, ...
                microns_per_pixel, norm_max_dist));
    end

    logger.info(tag, 'stage 5: clustering');
    if strcmp(best_model, 'Spatial correlation')
        [opt_map, reg_centroids, cell_scores, cs_pos, cs_neg, cs_excl, p_same_pairs] = ...
            cluster_cells(cell_to_index_map, a2a_psame_sc, a2a_idx, norm_max_dist, ...
                p_same_thr, cl_c, 'Probabilistic', false);
    else
        [opt_map, reg_centroids, cell_scores, cs_pos, cs_neg, cs_excl, p_same_pairs] = ...
            cluster_cells(cell_to_index_map, a2a_psame_cd, a2a_idx, norm_max_dist, ...
                p_same_thr, cl_c, 'Probabilistic', false);
    end

    is_in_FOV = check_if_in_overlapping_FOV(reg_centroids, overlapping_FOV);
    % Stage 5 figures: cell scores + final registered projections.
    safe_plot(logger, tag, 'cell_scores', @() ...
        plot_cell_scores(cs_pos, cs_neg, cs_excl, cell_scores, p_same_pairs, ...
            figures_dir, fig_vis));
    safe_plot(logger, tag, 'all_registered_projections', @() ...
        plot_all_registered_projections(sfp_c, opt_map, figures_dir, fig_vis));

    % --- assemble and save vendor struct ---
    crs = struct();
    crs.cell_to_index_map = opt_map;
    crs.cell_scores = cell_scores';
    crs.true_positive_scores = cs_pos';
    crs.true_negative_scores = cs_neg';
    crs.exclusivity_scores = cs_excl';
    crs.p_same_registered_pairs = p_same_pairs';
    crs.is_cell_in_overlapping_FOV = is_in_FOV';
    crs.registered_cells_centroids = reg_centroids';
    crs.centroid_locations_corrected = cl_c';
    crs.spatial_footprints_corrected = sfp_c';
    crs.alignment_x_translations = alignment_translations(1, :);
    crs.alignment_y_translations = alignment_translations(2, :);
    if strcmp(alignment_type, 'Translations and Rotations')
        crs.alignment_rotations = alignment_translations(3, :);
    end
    crs.adjustment_x_zero_padding = adj_pad(1, :);
    crs.adjustment_y_zero_padding = adj_pad(2, :);

    stamp = datestr(now, 'yyyymmdd_HHMMss');
    if cfg.cellreg.write_to_file
        % Always-overwrite semantics: drop stale registration files and vendor
        % log files from prior runs so each dataset folder holds exactly one
        % cellRegistered_*.mat and one logFile_*.txt.
        stale = [dir(fullfile(out_subdir, 'cellRegistered_*.mat')); ...
                 dir(fullfile(out_subdir, 'logFile_*.txt'))];
        for oi = 1:numel(stale)
            delete(fullfile(out_subdir, stale(oi).name));
        end
        save(fullfile(out_subdir, ['cellRegistered_' stamp '.mat']), 'crs', '-v7.3');
        if strcmp(best_model, 'Spatial correlation')
            save_log_file(out_subdir, file_paths, microns_per_pixel, ax, ay, ...
                alignment_type, ref_idx, max_dist, n_bins, best_model, init_thresh, ...
                'Probabilistic', best_model, p_same_thr, opt_map, crs, '', ...
                unc_sc, fpr_sc, tpr_sc, MSE_sc);
        else
            save_log_file(out_subdir, file_paths, microns_per_pixel, ax, ay, ...
                alignment_type, ref_idx, max_dist, n_bins, best_model, init_thresh, ...
                'Probabilistic', best_model, p_same_thr, opt_map, crs, '', ...
                unc_cd, fpr_cd, tpr_cd, MSE_cd);
        end
    end

    % --- result for anomaly detector ---
    stats = collect_match_stats(opt_map);
    % Vendor translations are in microns (align_images.m:428); W5a compares
    % against max_translation_px, so convert to pixels.
    shifts_px = hypot(alignment_translations(1, :), alignment_translations(2, :)) ...
        / microns_per_pixel;

    result = struct();
    result.dataset_id = dataset.dataset_id;
    result.sessions = {dataset.sessions.session_id};
    result.n_cells_per_session = stats.n_cells_per_session;
    result.match_stats = stats.match_stats;
    result.maximal_cross_correlation = max_xcorr;
    result.alignment_translations = alignment_translations;
    result.alignment_shift_px = shifts_px;
    result.reference_session_index = ref_idx;
    result.MSE_model = mse_val;
    result.best_model_string = best_model;
    result.chosen_p_same = p_same_thr;
    result.chosen_fpr = chosen_fpr;
    result.p_same_unreachable = p_same_unreachable;
    result.alignment_mode = won_label;
    result.forced_low_xcorr = forced_low_xcorr;
    result.error = '';
end

function safe_plot(logger, tag, name, fn)
%SAFE_PLOT Run a vendor plotting call, swallowing any failure.
%   Figures are secondary output: a plotting error (e.g. degenerate data,
%   missing toolbox) must never abort an otherwise-successful dataset.
    try
        fn();
    catch ME
        logger.warn(tag, 'figure %s skipped: %s', name, ME.message);
    end
end
