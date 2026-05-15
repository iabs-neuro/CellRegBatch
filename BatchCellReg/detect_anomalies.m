function out = detect_anomalies(results, thresh)
%DETECT_ANOMALIES Per-dataset anomaly checks with 3-level severity model.
%   results: struct array (see run_single_dataset). Failed datasets (error nonempty)
%     are skipped — their flags struct is returned with all zeros.
%   thresh: struct with fields z_threshold, max_translation_px, min_xcorr, max_mse.
%
%   Severity codes (double): 0=none, 1=yellow, 2=red.
%
%   Batch-distribution checks (W1, W6b, W2b_rel): graded severity via batch_severity.
%   All other checks (W2, W2b_hard, W3a, W3b, W4, W5a, W5b, W6a): binary — 2 if
%     triggered, 0 otherwise.

    n = numel(results);
    dataset_ids = {results.dataset_id};
    flags_template = struct( ...
        'W1',    0, 'W2',    0, 'W2b_hard', 0, 'W2b_rel', 0, ...
        'W3a',   0, 'W3b',   0, 'W4',       0, ...
        'W5a',   0, 'W5b',   0, ...
        'W6a',   0, 'W6b',   0);
    flags = repmat(flags_template, 1, n);
    metrics = repmat(struct( ...
        'W3a_min_xcorr', NaN, 'W5a_max_shift', NaN, ...
        'W6a_mse', NaN, 'fpr', NaN, 'pct_in_all', NaN, ...
        'W2b_ratio', NaN), 1, n);

    succeeded = arrayfun(@(r) isempty(r.error), results);

    % --- Precompute batch-level vectors over succeeded datasets ---
    pct_in_all_vec = nan(1, n);
    mse_vec        = nan(1, n);
    ratio_vec      = nan(1, n);

    for k = find(succeeded)
        r = results(k);
        pct_in_all_vec(k) = r.match_stats(2) / max(r.match_stats(1), 1);
        mse_vec(k)        = r.MSE_model;
        nc = r.n_cells_per_session;
        mn = min(nc);
        if mn <= 0
            ratio_vec(k) = Inf;
        else
            ratio_vec(k) = max(nc) / mn;
        end
        metrics(k).pct_in_all = pct_in_all_vec(k);
        metrics(k).W6a_mse    = r.MSE_model;
        metrics(k).fpr        = r.chosen_fpr;
        metrics(k).W2b_ratio  = ratio_vec(k);
    end

    z = thresh.z_threshold;
    ns = sum(succeeded);

    % Extract finite batch vectors for population checks (need >=3 succeeded)
    pct_finite = pct_in_all_vec(succeeded & ~isinf(pct_in_all_vec) & ~isnan(pct_in_all_vec));
    mse_finite = mse_vec(succeeded & ~isinf(mse_vec) & ~isnan(mse_vec));
    ratio_finite = ratio_vec(succeeded & ~isinf(ratio_vec) & ~isnan(ratio_vec));

    for k = find(succeeded)
        r = results(k);

        % --- W1: pct_in_all batch-distribution check (bad=LOW), needs >=3 ---
        if ns >= 3
            flags(k).W1 = batch_severity(pct_in_all_vec(succeeded), pct_in_all_vec(k), false, z);
        end

        % --- W2: n_cells_per_session intra-dataset outlier (binary) ---
        n_cells = r.n_cells_per_session;
        if numel(n_cells) >= 3
            z2 = zscore_safe(n_cells);
            if any(abs(z2) > z)
                flags(k).W2 = 2;
            end
        end

        % --- W2b_hard: ratio > 3 (binary, red) ---
        if ratio_vec(k) > 3
            flags(k).W2b_hard = 2;
        end

        % --- W2b_rel: ratio batch-distribution check (bad=HIGH), needs >=3 ---
        if ns >= 3
            flags(k).W2b_rel = batch_severity(ratio_vec(succeeded), ratio_vec(k), true, z);
        end

        % --- W3a/W3b: cross-correlation ---
        xc = r.maximal_cross_correlation(:);
        if any(xc < thresh.min_xcorr)
            flags(k).W3a = 2;
            metrics(k).W3a_min_xcorr = min(xc);
        end
        if numel(xc) >= 3
            z3 = zscore_safe(xc);
            if any(abs(z3) > z)
                flags(k).W3b = 2;
            end
        end

        % --- W4: FPR unreachable (binary) ---
        if r.p_same_unreachable
            flags(k).W4 = 2;
        end

        % --- W5a/W5b: alignment shift; exclude reference session ---
        shifts = r.alignment_shift_px(:);
        ref = r.reference_session_index;
        non_ref = shifts; non_ref(ref) = [];
        if ~isempty(non_ref) && max(abs(non_ref)) > thresh.max_translation_px
            flags(k).W5a = 2;
            metrics(k).W5a_max_shift = max(abs(non_ref));
        end
        if numel(non_ref) >= 3
            z5 = zscore_safe(non_ref);
            if any(abs(z5) > z)
                flags(k).W5b = 2;
            end
        end

        % --- W6a/W6b: model MSE ---
        if r.MSE_model > thresh.max_mse
            flags(k).W6a = 2;
        end
        % W6b: batch-distribution check (bad=HIGH), needs >=3
        if ns >= 3
            flags(k).W6b = batch_severity(mse_vec(succeeded), mse_vec(k), true, z);
        end
    end

    out = struct( ...
        'dataset_ids', {dataset_ids}, ...
        'flags', flags, ...
        'metrics', metrics);
end

% =========================================================================
% Local helpers
% =========================================================================

function sev = batch_severity(values, this_value, bad_is_high, z_threshold)
%BATCH_SEVERITY 2=red if |z|>z_threshold on bad side, 1=yellow if in worst
%   batch quartile on bad side, else 0. NaN/Inf-safe; needs >=3 finite values.
    v = values(:);
    v = v(~isnan(v) & ~isinf(v));
    if numel(v) < 3 || isnan(this_value) || isinf(this_value)
        sev = 0; return
    end
    mu = mean(v);
    sd = std(v);
    if sd == 0 || isnan(sd)
        sev = 0; return
    end
    if ~bad_is_high
        % bad = LOW: larger positive z means worse (further below mean)
        z = (mu - this_value) / sd;
        q = quantile_safe(v, 0.25);   % worst quartile = strictly below Q1
        in_worst_q = this_value < q;
    else
        % bad = HIGH
        z = (this_value - mu) / sd;
        q = quantile_safe(v, 0.75);   % worst quartile = strictly above Q3
        in_worst_q = this_value > q;
    end
    if z > z_threshold
        sev = 2;
    elseif in_worst_q
        sev = 1;
    else
        sev = 0;
    end
end

function q = quantile_safe(v, p)
%QUANTILE_SAFE Compute quantile without requiring Statistics Toolbox.
%   Uses sort + linear interpolation matching MATLAB's quantile convention.
    v = sort(v(:));
    n = numel(v);
    % Positions: (0.5, 1.5, ..., n-0.5) / n
    positions = ((1:n) - 0.5) / n;
    q = interp1(positions, v, p, 'linear', 'extrap');
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
