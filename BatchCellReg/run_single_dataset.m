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

    sufficient_corr_centroids  = 0.2;
    sufficient_corr_footprints = 0.3;
    if strcmp(alignment_type, 'Translations and Rotations')
        [sfp_c, cl_c, fpr_c, cp_c, max_xcorr, alignment_translations, overlapping_FOV] = ...
            align_images(adjusted_spatial_footprints, centroid_locations, ...
                adjusted_footprints_projections, centroid_projections, adjusted_FOV, ...
                microns_per_pixel, ref_idx, alignment_type, ...
                sufficient_corr_centroids, sufficient_corr_footprints, use_parallel, max_rot);
    else
        [sfp_c, cl_c, fpr_c, cp_c, max_xcorr, alignment_translations, overlapping_FOV] = ...
            align_images(adjusted_spatial_footprints, centroid_locations, ...
                adjusted_footprints_projections, centroid_projections, adjusted_FOV, ...
                microns_per_pixel, ref_idx, alignment_type, ...
                sufficient_corr_centroids, sufficient_corr_footprints, use_parallel);
    end
    [all_proj_corr, n_cells_per_session] = evaluate_data_quality( ...
        sfp_c, cp_c, fpr_c, max_xcorr, alignment_translations, ref_idx, ...
        sufficient_corr_footprints, alignment_type);
    plot_alignment_results(adjusted_spatial_footprints, centroid_locations, sfp_c, cl_c, ...
        adjusted_footprints_projections, fpr_c, ref_idx, all_proj_corr, max_xcorr, ...
        alignment_translations, overlapping_FOV, alignment_type, n_cells_per_session, ...
        figures_dir, fig_vis);

    logger.info(tag, 'stage 3: probabilistic model');
    [n_bins, centers_of_bins] = estimate_number_of_bins(spatial_footprints, norm_max_dist);
    [a2a_idx, a2a_sc, a2a_cd, neighb_sc, neighb_cd, neighb_dx, neighb_dy, NN_sc, NNN_sc, NN_cd, NNN_cd] = ...
        compute_data_distribution(sfp_c, cl_c, norm_max_dist);

    [cd_pars, p_given_cd, cd_dist, cd_same, cd_diff, cd_wsum, MSE_cd, cd_intersect] = ...
        compute_centroid_distances_model(neighb_cd, microns_per_pixel, centers_of_bins);
    [sc_pars, p_given_sc, sc_dist, sc_same, sc_diff, sc_wsum, MSE_sc, sc_intersect] = ...
        compute_spatial_correlations_model(neighb_sc, centers_of_bins);

    [p_same_centers, unc_cd, cdf_cd, fpr_cd, tpr_cd, unc_sc, cdf_sc, fpr_sc, tpr_sc] = ...
        estimate_registration_accuracy(p_same_certainty, neighb_cd, cd_same, cd_diff, ...
            p_given_cd, centers_of_bins, neighb_sc, sc_same, sc_diff, p_given_sc);

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
    else
        if ~isempty(cd_intersect); init_thresh = cd_intersect; else; init_thresh = 5; end
        norm_dist_thresh = init_thresh / microns_per_pixel;
        [cell_to_index_map, reg_cd, nonreg_cd] = ...
            initial_registration_centroid_distances(norm_max_dist, norm_dist_thresh, cl_c);
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
    plot_all_registered_projections(sfp_c, opt_map, figures_dir, fig_vis);

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

    stamp = datestr(clock, 'yyyymmdd_HHMMss');
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

    % --- result for anomaly detector ---
    stats = collect_match_stats(opt_map);
    shifts_px = sqrt(alignment_translations(1, :).^2 + alignment_translations(2, :).^2);

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
    result.error = '';
end
