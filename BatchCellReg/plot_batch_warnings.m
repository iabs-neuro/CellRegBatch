function plot_batch_warnings(results, anomalies, thresh, png_path)
%PLOT_BATCH_WARNINGS One-page picture of the batch warnings, saved as PNG.
%   Left: a grid of datasets x the six warnings (grey = none, yellow, red;
%   dark grey = the dataset failed). Right: for each dataset, the values
%   behind the warnings, with the yellow and red limits as dashed lines,
%   so the reader sees how far each dataset is from a limit.
%   results, anomalies: as in batch_run. thresh: the thresholds passed to
%   detect_anomalies.

    [info, names] = anomaly_decode_map();
    n = numel(results);
    row_px = 20;
    fig = figure('Visible', 'off', 'Color', 'w', 'Units', 'pixels', ...
        'Position', [50 50 1500 max(300, 170 + row_px * n)]);
    cleanup = onCleanup(@() delete(fig));
    W = fig.Position(3); H = fig.Position(4);
    px = @(x, y, w, h) [x / W, y / H, w / W, h / H];

    yellow = [1.00 0.80 0.15]; red = [0.85 0.15 0.15];
    none = [0.90 0.90 0.90]; failed = [0.45 0.45 0.45];

    if n == 0
        annotation(fig, 'textbox', px(20, H - 60, 800, 40), 'String', ...
            'No dataset was processed.', 'EdgeColor', 'none', 'FontSize', 12);
        print(fig, png_path, '-dpng', '-r100');
        return
    end

    ok = arrayfun(@(r) isempty(r.error), results);
    sev = zeros(n, numel(names));
    for k = 1:n
        for j = 1:numel(names); sev(k, j) = anomalies.flags(k).(names{j}); end
    end

    % --- header ---
    n_red = sum(ok' & any(sev == 2, 2));
    n_yellow = sum(ok' & any(sev == 1, 2) & ~any(sev == 2, 2));
    annotation(fig, 'textbox', px(20, H - 40, 1400, 30), 'EdgeColor', 'none', ...
        'FontSize', 12, 'FontWeight', 'bold', 'Interpreter', 'none', 'String', ...
        sprintf('Batch warnings: %d datasets, %d red, %d yellow only, %d failed', ...
        n, n_red, n_yellow, sum(~ok)));
    annotation(fig, 'textbox', px(20, 4, 1460, 22), 'EdgeColor', 'none', ...
        'FontSize', 8, 'Interpreter', 'none', 'String', ['Grid: grey = no warning, ' ...
        'yellow = check, red = problem, dark grey = dataset failed. Dot plots: dashed ' ...
        'lines = yellow and red limits; dot colour = how the value compares with them. ' ...
        'Match % = cells in all sessions / mean cells per session; solid line = batch median. ' ...
        'Details: _batch_warnings_detail.csv.']);

    top = H - 115; plot_h = row_px * n;
    y0 = top - plot_h;

    % --- grid of warnings ---
    C = repmat(reshape(none, 1, 1, 3), n, numel(names));
    for k = 1:n
        for j = 1:numel(names)
            if ~ok(k); c = failed;
            elseif sev(k, j) == 2; c = red;
            elseif sev(k, j) == 1; c = yellow;
            else; c = none; end
            C(k, j, :) = reshape(c, 1, 1, 3);
        end
    end
    ax = axes(fig, 'Units', 'normalized', 'Position', px(170, y0, 6 * 34, plot_h));
    image(ax, C);
    hold(ax, 'on');
    for j = 0.5:1:numel(names) + 0.5; plot(ax, [j j], [0.5 n + 0.5], 'w-', 'LineWidth', 2); end
    for k = 0.5:1:n + 0.5; plot(ax, [0.5 numel(names) + 0.5], [k k], 'w-', 'LineWidth', 2); end
    shorts = cellfun(@(nm) info(nm).short, names, 'UniformOutput', false);
    set(ax, 'XTick', 1:numel(names), 'XTickLabel', shorts, 'XAxisLocation', 'top', ...
        'XTickLabelRotation', 50, 'YTick', 1:n, 'YTickLabel', {results.dataset_id}, ...
        'TickLabelInterpreter', 'none', 'TickLength', [0 0], 'FontSize', 8, ...
        'YDir', 'reverse', 'XLim', [0.5 numel(names) + 0.5], 'YLim', [0.5 n + 0.5]);
    box(ax, 'off');

    % --- value panels ---
    m = anomalies.metrics;
    t = thresh;
    b = anomalies.batch;
    panels = {
        'Median cells per session', [m.median_cells], t.few_cells_yellow, t.few_cells_red, 'low', []
        'Worst session / median', [m.worst_session_ratio], t.cell_drop_yellow, t.cell_drop_red, 'low', []
        'Lowest cross-correlation', [m.min_xcorr], t.xcorr_yellow, t.xcorr_red, 'low', []
        'Largest shift (px)', [m.max_shift_px], t.shift_yellow_px, NaN, 'high', []
        'Model fit error (MSE)', [m.model_mse], t.mse_yellow, t.mse_red, 'high', []
        'Match % (all sessions)', [m.match_pct], 100 * b.match_yellow, ...
            100 * b.match_red, 'low', sev(:, strcmp(names, 'low_match'))'
        };
    x = 420; gap = 18;
    pw = (W - x - 20 - gap * (size(panels, 1) - 1)) / size(panels, 1);
    for p = 1:size(panels, 1)
        [ttl, v, ylw, rlim, bad, given] = panels{p, :};
        v(~ok) = NaN;
        ax = axes(fig, 'Units', 'normalized', 'Position', px(x, y0, pw, plot_h));
        hold(ax, 'on');
        for k = 1:n; plot(ax, [1e-9 1e9], [k k], '-', 'Color', [0.93 0.93 0.93]); end
        lim = [0, max([v(isfinite(v)), ylw, rlim, 0]) * 1.12];
        if lim(2) <= 0; lim(2) = 1; end
        if strcmp(ttl, 'Worst session / median') || strcmp(ttl, 'Lowest cross-correlation')
            lim = [0 max(1, lim(2))];
        end
        log_x = strcmp(ttl, 'Median cells per session');
        if log_x
            % Cell counts span 10 to 1000; on a linear axis the limits
            % (tens of cells) sit on top of each other.
            lim = [min([v(v > 0), ylw, rlim]) / 1.5, lim(2) * 1.3];
        end
        if ~isnan(rlim); plot(ax, [rlim rlim], [0.5 n + 0.5], '--', 'Color', red, 'LineWidth', 1.2); end
        if ~isnan(ylw); plot(ax, [ylw ylw], [0.5 n + 0.5], '--', 'Color', yellow, 'LineWidth', 1.2); end
        if p == size(panels, 1) && ~isnan(b.match_median)
            plot(ax, 100 * [b.match_median b.match_median], [0.5 n + 0.5], '-', 'Color', [0.4 0.4 0.4]);
        end
        if isempty(given)
            s = arrayfun(@(val) level(val, ylw, rlim, bad), v);
        else
            s = given;
        end
        colors = {[0.55 0.55 0.55], yellow, red};
        for lv = 0:2
            idx = find(s == lv & isfinite(v));
            if isempty(idx); continue; end
            plot(ax, v(idx), idx, 'o', 'MarkerSize', 6, 'MarkerFaceColor', colors{lv + 1}, ...
                'MarkerEdgeColor', 0.6 * colors{lv + 1});
        end
        set(ax, 'YDir', 'reverse', 'YLim', [0.5 n + 0.5], 'XLim', lim, 'YTick', [], ...
            'FontSize', 8, 'Box', 'on');
        if log_x
            ticks = [3 10 30 100 300 1000 3000];
            ticks = ticks(ticks >= lim(1) & ticks <= lim(2));
            set(ax, 'XScale', 'log', 'XTick', ticks, 'XTickLabel', arrayfun(@num2str, ticks, 'UniformOutput', false));
        end
        title(ax, ttl, 'FontSize', 9, 'FontWeight', 'normal', 'Interpreter', 'none');
        x = x + pw + gap;
    end

    print(fig, png_path, '-dpng', '-r100');
end

function s = level(v, yellow, red, bad)
    s = 0;
    if isnan(v); return; end
    if strcmp(bad, 'low')
        if v < red; s = 2; elseif v < yellow; s = 1; end
    else
        if v > red; s = 2; elseif v > yellow; s = 1; end
    end
end
