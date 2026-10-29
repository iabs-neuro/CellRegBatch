function out = detect_anomalies(results, thresh)
%DETECT_ANOMALIES Six named warnings per dataset, each none / yellow / red.
%   results: struct array (see run_single_dataset). Failed datasets (error
%     nonempty) get no warnings.
%   thresh: cfg.anomaly_thresholds plus expected_n_sessions and fpr_max;
%     optional alignment_min_xcorr (reported when alignment was forced).
%
%   Warnings (fields of out.flags, in pipeline order):
%     session_count  session count differs from expected_n_sessions    red
%     few_cells      median cells per session is low                    yellow/red
%     cell_drop      worst session has far fewer cells than the median  yellow/red
%     alignment      low cross-correlation or forced alignment (red),
%                    large shift (yellow)                               yellow/red
%     model_fit      high model MSE; FPR target not reached (red)       yellow/red
%     low_match      no cell found in all sessions (red); one session
%                    whose cells are rarely found in the other sessions;
%                    match % far below the batch median (robust z)      yellow/red
%   Severity codes: 0 = none, 1 = yellow, 2 = red.
%
%   The batch comparison of low_match uses median and MAD, so one bad
%   dataset cannot hide itself by widening the spread. It needs at least
%   MIN_BATCH datasets with the expected session count, and most of them
%   must be good. The session-link rule needs no batch: it compares the
%   sessions of one dataset (3 or more sessions).
%
%   out.details: one element per fired rule: dataset_id, session ('-' when
%   the rule is about the whole dataset), warning, rule, value, threshold
%   (the limit the value crossed, same units), severity ('yellow'/'red').
%   out.metrics: the value behind each warning, for tables and figures.
%   out.batch: median and limits of the match comparison (NaN when the
%   batch is too small), for the warnings figure.

    MIN_BATCH = 5;

    n = numel(results);
    dataset_ids = {};
    % struct([]) (no dataset processed) has no fields to index.
    if n > 0; dataset_ids = {results.dataset_id}; end
    [~, names] = anomaly_decode_map();
    flags = repmat(cell2struct(num2cell(zeros(1, numel(names))), names, 2), 1, n);
    metrics = repmat(struct('median_cells', NaN, 'worst_session_ratio', NaN, ...
        'min_xcorr', NaN, 'max_shift_px', NaN, 'model_mse', NaN, ...
        'match_pct', NaN, 'match_z', NaN, 'worst_link_ratio', NaN), 1, n);
    details = struct('dataset_id', {}, 'session', {}, 'warning', {}, 'rule', {}, ...
        'value', {}, 'threshold', {}, 'severity', {});

    t = thresh;
    has_expected = isfield(t, 'expected_n_sessions') && ~isempty(t.expected_n_sessions);
    fpr_max = NaN;
    if isfield(t, 'fpr_max'); fpr_max = t.fpr_max; end
    gate = NaN;
    if isfield(t, 'alignment_min_xcorr'); gate = t.alignment_min_xcorr; end

    succeeded = false(1, n);
    comparable = false(1, n);
    match = nan(1, n);
    for k = 1:n
        r = results(k);
        succeeded(k) = isempty(r.error);
        if ~succeeded(k); continue; end
        match(k) = r.match_stats(2) / max(mean(r.n_cells_per_session), 1);
        % A dataset with missing sessions has a higher "in all sessions"
        % share by construction, so it is not a fair member of the batch.
        comparable(k) = ~has_expected || numel(r.sessions) == t.expected_n_sessions;
    end

    batch = struct('match_median', NaN, 'match_yellow', NaN, 'match_red', NaN, ...
        'n_compared', sum(comparable));
    match_scale = NaN;
    if sum(comparable) >= MIN_BATCH
        v = match(comparable);
        med = median(v);
        mad = median(abs(v - med));
        if mad > 0
            % MAD / 0.6745 estimates the SD for normal data (Iglewicz and
            % Hoaglin modified z-score).
            match_scale = mad / 0.6745;
            batch.match_median = med;
            batch.match_yellow = med - t.match_z_yellow * match_scale;
            batch.match_red = med - t.match_z_red * match_scale;
        end
    end

    for k = find(succeeded)
        r = results(k);
        id = r.dataset_id;
        nc = r.n_cells_per_session(:)';

        % --- session_count ---
        n_sess = numel(r.sessions);
        if has_expected && n_sess ~= t.expected_n_sessions
            if n_sess < t.expected_n_sessions
                rule = 'fewer sessions than expected';
            else
                rule = 'more sessions than expected';
            end
            sess = '-';
            if isfield(r, 'missing_sessions') && ~isempty(r.missing_sessions)
                sess = strjoin(r.missing_sessions, ' ');
            end
            [flags(k), details] = fire(flags(k), details, id, sess, 'session_count', ...
                rule, n_sess, t.expected_n_sessions, 2);
        end

        % --- few_cells ---
        m = median(nc);
        metrics(k).median_cells = m;
        [sev, b] = level(m, t.few_cells_yellow, t.few_cells_red, 'low');
        if sev
            [flags(k), details] = fire(flags(k), details, id, '-', 'few_cells', ...
                'median cells per session', m, b, sev);
        end

        % --- cell_drop ---
        if m > 0
            [mn, i] = min(nc);
            ratio = mn / m;
            metrics(k).worst_session_ratio = ratio;
            [sev, b] = level(ratio, t.cell_drop_yellow, t.cell_drop_red, 'low');
            if sev
                [flags(k), details] = fire(flags(k), details, id, session_name(r, i), ...
                    'cell_drop', 'cells in worst session / median session', ratio, b, sev);
            end
        end

        % --- alignment ---
        xc = r.maximal_cross_correlation(:)';
        if ~isempty(xc)
            [v, i] = min(xc);
            metrics(k).min_xcorr = v;
            [sev, b] = level(v, t.xcorr_yellow, t.xcorr_red, 'low');
            if sev
                [flags(k), details] = fire(flags(k), details, id, ...
                    session_name(r, xcorr_session_index(r, i)), 'alignment', ...
                    'lowest cross-correlation with the reference', v, b, sev);
            end
            if isfield(r, 'forced_low_xcorr') && r.forced_low_xcorr
                [flags(k), details] = fire(flags(k), details, id, ...
                    session_name(r, xcorr_session_index(r, i)), 'alignment', ...
                    'no alignment mode passed the gate', v, gate, 2);
            end
        end
        shifts = r.alignment_shift_px(:)';
        non_ref = setdiff(1:numel(shifts), r.reference_session_index);
        if ~isempty(non_ref)
            [v, i] = max(shifts(non_ref));
            metrics(k).max_shift_px = v;
            if v > t.shift_yellow_px
                [flags(k), details] = fire(flags(k), details, id, ...
                    session_name(r, non_ref(i)), 'alignment', ...
                    'largest alignment shift (px)', v, t.shift_yellow_px, 1);
            end
        end

        % --- model_fit ---
        metrics(k).model_mse = r.MSE_model;
        [sev, b] = level(r.MSE_model, t.mse_yellow, t.mse_red, 'high');
        if sev
            [flags(k), details] = fire(flags(k), details, id, '-', 'model_fit', ...
                'model fit error (MSE)', r.MSE_model, b, sev);
        end
        if r.p_same_unreachable
            [flags(k), details] = fire(flags(k), details, id, '-', 'model_fit', ...
                'FPR target not reached at P_same 0.95', r.chosen_fpr, fpr_max, 2);
        end

        % --- low_match ---
        metrics(k).match_pct = 100 * match(k);
        if comparable(k) && ~isnan(match_scale)
            metrics(k).match_z = (match(k) - batch.match_median) / match_scale;
        end
        % A session whose cells rarely appear in any other session is
        % usually misaligned or shows another field of view. With two
        % sessions both have the same linked cells, so the rule needs three.
        lf = [];
        if isfield(r, 'linked_fraction'); lf = r.linked_fraction(:)'; end
        if numel(lf) >= 3 && median(lf, 'omitnan') > 0
            [v, i] = min(lf);
            ratio = v / median(lf, 'omitnan');
            metrics(k).worst_link_ratio = ratio;
            [sev, b] = level(ratio, t.session_link_yellow, t.session_link_red, 'low');
            if sev
                [flags(k), details] = fire(flags(k), details, id, session_name(r, i), ...
                    'low_match', 'cells found in other sessions, worst session / median', ...
                    ratio, b, sev);
            end
        end
        if r.match_stats(2) == 0
            [flags(k), details] = fire(flags(k), details, id, '-', 'low_match', ...
                'cells found in all sessions (needs at least 1)', 0, 1, 2);
        elseif ~isnan(metrics(k).match_z)
            [sev, b] = level(match(k), batch.match_yellow, batch.match_red, 'low');
            if sev
                [flags(k), details] = fire(flags(k), details, id, '-', 'low_match', ...
                    'match % below the batch median', 100 * match(k), 100 * b, sev);
            end
        end
    end

    out = struct( ...
        'dataset_ids', {dataset_ids}, ...
        'flags', flags, ...
        'metrics', metrics, ...
        'details', details, ...
        'batch', batch);
end

% =========================================================================
% Local helpers
% =========================================================================

function [sev, bound] = level(v, yellow, red, bad)
%LEVEL 2 when v is past the red limit, 1 when past the yellow one, else 0.
%   bad = 'low' or 'high' says which side is bad. bound is the crossed limit.
    sev = 0; bound = NaN;
    if isnan(v); return; end
    if strcmp(bad, 'low')
        if v < red; sev = 2; bound = red; elseif v < yellow; sev = 1; bound = yellow; end
    else
        if v > red; sev = 2; bound = red; elseif v > yellow; sev = 1; bound = yellow; end
    end
end

function [f, d] = fire(f, d, id, session, name, rule, value, threshold, severity)
    f.(name) = max(f.(name), severity);
    words = {'yellow', 'red'};
    d(end+1) = struct('dataset_id', id, 'session', session, 'warning', name, ...
        'rule', rule, 'value', value, 'threshold', threshold, 'severity', words{severity});
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
