function [p_same, fpr, unreachable] = choose_p_same_by_fpr(centers, fpr_vector, fpr_max)
%CHOOSE_P_SAME_BY_FPR Prefer P_same=0.5; ascend toward 0.95 only if the
%   CUMULATIVE FPR at 0.5 exceeds fpr_max. FPR at a P_same threshold p is
%   cumsum(fpr_vector)(round(N*(1-p))), matching CellReg save_log_file.m
%   (lines 92-94) so the gate and the written logFile agree exactly.
    centers = centers(:); fpr_vector = fpr_vector(:);
    N = numel(fpr_vector);
    cum = cumsum(fpr_vector);
    fpr_at = @(p) cum( max(1, min(N, round(N*(1-p)))) );

    [~, i50] = min(abs(centers - 0.5));
    if fpr_at(centers(i50)) <= fpr_max
        p_same = centers(i50); fpr = fpr_at(centers(i50)); unreachable = false; return
    end
    [~, i95] = min(abs(centers - 0.95));
    cand = (i50+1:i95)';
    cand = cand(arrayfun(@(k) fpr_at(centers(k)) <= fpr_max, cand));
    if ~isempty(cand)
        idx = cand(1); unreachable = false;       % smallest P_same>0.5 meeting FPR
    else
        idx = i95; unreachable = true;            % cap at 0.95, flag
    end
    p_same = centers(idx); fpr = fpr_at(centers(idx));
end
