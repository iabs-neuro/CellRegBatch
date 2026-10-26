function out = detect_anomalies(results, thresh)
%DETECT_ANOMALIES Per-dataset anomaly checks with 3-level severity model.
%   results: struct array (see run_single_dataset). Failed datasets (error nonempty)
%     are skipped — their flags struct is returned with all zeros.
%   thresh: struct with fields z_threshold, max_translation_px, min_xcorr, max_mse;
%     optional expected_n_sessions (W7) and fpr_max (reported for W4).
%
%   Severity codes (double): 0=none, 1=yellow, 2=red.
%
%   Batch-distribution checks (W1, W6b, W2b_rel): graded severity via batch_severity.
%   All other checks (W2, W2b_hard, W3a, W3b, W4, W5a, W5b, W6a): binary — 2 if
%     triggered, 0 otherwise.
%
%   out.details has one element per fired warning: dataset_id, session ('-' for
%   dataset-level checks), anomaly_type, value, threshold (the limit the value
%   crossed, in the same units), severity.

    n = numel(results);
    dataset_ids = {};
    % struct([]) (no dataset processed) has no fields to index.
    if n > 0; dataset_ids = {results.dataset_id}; end
    flags_template = struct( ...
        'W1',    0, 'W2',    0, 'W2b_hard', 0, 'W2b_rel', 0, ...
        'W3a',   0, 'W3b',   0, 'W4',       0, ...
        'W5a',   0, 'W5b',   0, ...
        'W6a',   0, 'W6b',   0, 'W7',       0);
    flags = repmat(flags_template, 1, n);
    metrics = repmat(struct( ...
        'W3a_min_xcorr', NaN, 'W5a_max_shift', NaN, ...
        'W6a_mse', NaN, 'fpr', NaN, 'pct_in_all', NaN, ...
        'W2b_ratio', NaN, 'n_sessions', NaN), 1, n);
    details = struct('dataset_id', {}, 'session', {}, 'anomaly_type', {}, ...
        'value', {}, 'threshold', {}, 'severity', {});

    fpr_max = NaN;
    if isfield(thresh, 'fpr_max'); fpr_max = thresh.fpr_max; end

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
        metrics(k).pct_in_all  = pct_in_all_vec(k);
        metrics(k).W6a_mse     = r.MSE_model;
        metrics(k).fpr         = r.chosen_fpr;
        metrics(k).W2b_ratio   = ratio_vec(k);
        metrics(k).n_sessions  = numel(r.sessions);
    end

    z = thresh.z_threshold;
    ns = sum(succeeded);

    for k = find(succeeded)
        r = results(k);
        id = r.dataset_id;

        % --- W1: pct_in_all batch-distribution check (bad=LOW), needs >=3 ---
        if ns >= 3
            [flags(k).W1, b] = batch_severity(pct_in_all_vec(succeeded), pct_in_all_vec(k), false, z);
            if flags(k).W1
                details = add_detail(details, id, '-', 'W1_pct_match_outlier', ...
                    pct_in_all_vec(k), b, flags(k).W1);
            end
        end

        % --- W2: n_cells_per_session intra-dataset outlier (binary) ---
        n_cells = r.n_cells_per_session;
        if numel(n_cells) >= 3
            [hit, i, b] = zscore_outlier(n_cells, z);
            if hit
                flags(k).W2 = 2;
                details = add_detail(details, id, session_name(r, i), 'W2_cells_outlier', ...
                    n_cells(i), b, 2);
            end
        end

        % --- W2b_hard: ratio > 3 (binary, red) ---
        if ratio_vec(k) > 3
            flags(k).W2b_hard = 2;
            details = add_detail(details, id, '-', 'W2b_hard_ratio', ratio_vec(k), 3, 2);
        end

        % --- W2b_rel: ratio batch-distribution check (bad=HIGH), needs >=3 ---
        if ns >= 3
            [flags(k).W2b_rel, b] = batch_severity(ratio_vec(succeeded), ratio_vec(k), true, z);
            if flags(k).W2b_rel
                details = add_detail(details, id, '-', 'W2b_rel', ratio_vec(k), b, flags(k).W2b_rel);
            end
        end

        % --- W3a/W3b: cross-correlation ---
        xc = r.maximal_cross_correlation(:);
        if any(xc < thresh.min_xcorr)
            flags(k).W3a = 2;
            [v, i] = min(xc);
            metrics(k).W3a_min_xcorr = v;
            details = add_detail(details, id, session_name(r, xcorr_session_index(r, i)), ...
                'W3a_low_xcorr_hard', v, thresh.min_xcorr, 2);
        end
        if numel(xc) >= 3
            [hit, i, b] = zscore_outlier(xc, z);
            if hit
                flags(k).W3b = 2;
                details = add_detail(details, id, session_name(r, xcorr_session_index(r, i)), ...
                    'W3b_xcorr_outlier', xc(i), b, 2);
            end
        end

        % --- W4: FPR unreachable (binary) ---
        if r.p_same_unreachable
            flags(k).W4 = 2;
            details = add_detail(details, id, '-', 'W4_fpr_unreachable', r.chosen_fpr, fpr_max, 2);
        end

        % --- W5a/W5b: alignment shift; exclude reference session ---
        shifts = r.alignment_shift_px(:);
        non_ref_idx = setdiff(1:numel(shifts), r.reference_session_index);
        non_ref = shifts(non_ref_idx);
        if ~isempty(non_ref) && max(abs(non_ref)) > thresh.max_translation_px
            flags(k).W5a = 2;
            [v, i] = max(abs(non_ref));
            metrics(k).W5a_max_shift = v;
            details = add_detail(details, id, session_name(r, non_ref_idx(i)), ...
                'W5a_shift_hard', v, thresh.max_translation_px, 2);
        end
        if numel(non_ref) >= 3
            [hit, i, b] = zscore_outlier(non_ref, z);
            if hit
                flags(k).W5b = 2;
                details = add_detail(details, id, session_name(r, non_ref_idx(i)), ...
                    'W5b_shift_outlier', non_ref(i), b, 2);
            end
        end

        % --- W6a/W6b: model MSE ---
        if r.MSE_model > thresh.max_mse
            flags(k).W6a = 2;
            details = add_detail(details, id, '-', 'W6a_mse_hard', r.MSE_model, thresh.max_mse, 2);
        end
        % W6b: batch-distribution check (bad=HIGH), needs >=3
        if ns >= 3
            [flags(k).W6b, b] = batch_severity(mse_vec(succeeded), mse_vec(k), true, z);
            if flags(k).W6b
                details = add_detail(details, id, '-', 'W6b_mse_rel', r.MSE_model, b, flags(k).W6b);
            end
        end

        % --- W7: session-count mismatch (binary red) ---
        if isfield(thresh, 'expected_n_sessions') && numel(r.sessions) ~= thresh.expected_n_sessions
            flags(k).W7 = 2;
            details = add_detail(details, id, '-', 'W7_session_count', ...
                numel(r.sessions), thresh.expected_n_sessions, 2);
        end
    end

    out = struct( ...
        'dataset_ids', {dataset_ids}, ...
        'flags', flags, ...
        'metrics', metrics, ...
        'details', details);
end

% =========================================================================
% Local helpers
% =========================================================================

function [sev, bound] = batch_severity(values, this_value, bad_is_high, z_threshold)
%BATCH_SEVERITY 2=red if |z|>z_threshold on bad side, 1=yellow if in worst
%   batch quartile on bad side, else 0. NaN/Inf-safe; needs >=3 finite values.
%   bound is the limit that was crossed (mean -+ z*SD for red, the quartile
%   for yellow), NaN when sev is 0.
    sev = 0; bound = NaN;
    v = values(:);
    v = v(~isnan(v) & ~isinf(v));
    if numel(v) < 3 || isnan(this_value) || isinf(this_value)
        return
    end
    mu = mean(v);
    sd = std(v);
    if sd == 0 || isnan(sd)
        return
    end
    if ~bad_is_high
        % bad = LOW: larger positive z means worse (further below mean)
        z = (mu - this_value) / sd;
        q = quantile_safe(v, 0.25);   % worst quartile = strictly below Q1
        in_worst_q = this_value < q;
        red_bound = mu - z_threshold * sd;
    else
        % bad = HIGH
        z = (this_value - mu) / sd;
        q = quantile_safe(v, 0.75);   % worst quartile = strictly above Q3
        in_worst_q = this_value > q;
        red_bound = mu + z_threshold * sd;
    end
    if z > z_threshold
        sev = 2; bound = red_bound;
    elseif in_worst_q
        sev = 1; bound = q;
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

function [hit, i, bound] = zscore_outlier(v, z_threshold)
%ZSCORE_OUTLIER Element of v with the largest |z|. hit when that |z| exceeds
%   z_threshold; bound is mean +- z_threshold*SD on the side of that element.
    hit = false; i = NaN; bound = NaN;
    v = v(:);
    mu = mean(v, 'omitnan');
    sd = std(v, 0, 'omitnan');
    if sd == 0 || isnan(sd); return; end
    zv = (v - mu) / sd;
    [m, i] = max(abs(zv));
    hit = m > z_threshold;
    bound = mu + sign(zv(i)) * z_threshold * sd;
end

function idx = xcorr_session_index(r, i)
%XCORR_SESSION_INDEX Session index of the i-th cross-correlation value.
%   CellReg returns one value per non-reference session, in the order of
%   setdiff(1:n, reference) (align_images.m, registration_order).
    n = numel(r.sessions);
    if numel(r.maximal_cross_correlation) == n - 1
        order = setdiff(1:n, r.reference_session_index);
        idx = order(i);
    else
        idx = i;
    end
end

function s = session_name(r, idx)
    if idx >= 1 && idx <= numel(r.sessions); s = r.sessions{idx}; else; s = '-'; end
end

function d = add_detail(d, id, session, type, value, threshold, severity)
    d(end+1) = struct('dataset_id', id, 'session', session, 'anomaly_type', type, ...
        'value', value, 'threshold', threshold, 'severity', severity);
end
