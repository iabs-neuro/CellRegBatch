function out = detect_anomalies(results, thresh)
%DETECT_ANOMALIES Six per-dataset anomaly checks against thresholds.
%   results: struct array (see run_single_dataset). Failed datasets (error nonempty)
%     are skipped — their flags struct is returned with all false.
%   thresh: struct with fields z_threshold, max_translation_px, min_xcorr, max_mse.
    n = numel(results);
    dataset_ids = {results.dataset_id};
    flags_template = struct('W1',false,'W2',false,'W3a',false,'W3b',false, ...
        'W4',false,'W5a',false,'W5b',false,'W6a',false,'W6b',false);
    flags = repmat(flags_template, 1, n);
    metrics = repmat(struct( ...
        'W3a_min_xcorr', NaN, 'W5a_max_shift', NaN, ...
        'W6a_mse', NaN, 'fpr', NaN, 'pct_in_all', NaN), 1, n);

    succeeded = arrayfun(@(r) isempty(r.error), results);

    % Batch-level vectors for population z-scores (W1, W6b).
    pct_in_all = nan(1, n);
    mse_vec    = nan(1, n);
    for k = find(succeeded)
        pct_in_all(k) = results(k).match_stats(2) / max(results(k).match_stats(1), 1);
        mse_vec(k)    = results(k).MSE_model;
        metrics(k).pct_in_all = pct_in_all(k);
        metrics(k).W6a_mse    = results(k).MSE_model;
        metrics(k).fpr        = results(k).chosen_fpr;
    end

    z1 = zscore_safe(pct_in_all);
    z6 = zscore_safe(mse_vec);

    for k = find(succeeded)
        r = results(k);

        % W1: pct_in_all population outlier (need >= 3 succeeded)
        if sum(succeeded) >= 3 && abs(z1(k)) > thresh.z_threshold
            flags(k).W1 = true;
        end

        % W2: n_cells_per_session intra-dataset outlier
        n_cells = r.n_cells_per_session;
        if numel(n_cells) >= 3
            z2 = zscore_safe(n_cells);
            if any(abs(z2) > thresh.z_threshold)
                flags(k).W2 = true;
            end
        end

        % W3a/W3b: cross-correlation
        xc = r.maximal_cross_correlation(:);
        if any(xc < thresh.min_xcorr)
            flags(k).W3a = true;
            metrics(k).W3a_min_xcorr = min(xc);
        end
        if numel(xc) >= 3
            z3 = zscore_safe(xc);
            if any(abs(z3) > thresh.z_threshold)
                flags(k).W3b = true;
            end
        end

        % W4: FPR unreachable
        if r.p_same_unreachable
            flags(k).W4 = true;
        end

        % W5a/W5b: alignment shift; exclude reference session.
        shifts = r.alignment_shift_px(:);
        ref = r.reference_session_index;
        non_ref = shifts; non_ref(ref) = [];
        if ~isempty(non_ref) && max(abs(non_ref)) > thresh.max_translation_px
            flags(k).W5a = true;
            metrics(k).W5a_max_shift = max(abs(non_ref));
        end
        if numel(non_ref) >= 3
            z5 = zscore_safe(non_ref);
            if any(abs(z5) > thresh.z_threshold)
                flags(k).W5b = true;
            end
        end

        % W6a/W6b: model MSE
        if r.MSE_model > thresh.max_mse
            flags(k).W6a = true;
        end
        if sum(succeeded) >= 3 && abs(z6(k)) > thresh.z_threshold
            flags(k).W6b = true;
        end
    end

    out = struct( ...
        'dataset_ids', {dataset_ids}, ...
        'flags', flags, ...
        'metrics', metrics);
end

function z = zscore_safe(v)
    v = v(:);
    mu = mean(v, 'omitnan');
    sd = std(v, 0, 'omitnan');
    if sd == 0 || isnan(sd)
        z = zeros(size(v));
    else
        z = (v - mu) / sd;
    end
end
