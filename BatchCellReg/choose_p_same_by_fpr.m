function [p_same, fpr, unreachable] = choose_p_same_by_fpr(centers, fpr_vector, fpr_max)
%CHOOSE_P_SAME_BY_FPR Prefer P_same=0.5; ascend to 0.95 only if FPR(0.5)>fpr_max.
%   Rule: keep the bin nearest 0.5 if its FPR<=fpr_max. Otherwise pick the
%   smallest bin center in (0.5-bin, 0.95] whose FPR<=fpr_max. If none, set
%   unreachable=true and return the bin nearest 0.95.
    centers = centers(:); fpr_vector = fpr_vector(:);
    [~, i50] = min(abs(centers - 0.5));
    if fpr_vector(i50) <= fpr_max
        p_same = centers(i50); fpr = fpr_vector(i50); unreachable = false; return
    end
    [~, i95] = min(abs(centers - 0.95));
    cand = (1:numel(centers))';
    cand = cand(cand > i50 & cand <= i95 & fpr_vector <= fpr_max);
    if ~isempty(cand)
        idx = cand(1);              % smallest center meeting FPR
        unreachable = false;
    else
        idx = i95;                  % cap at 0.95, flag
        unreachable = true;
    end
    p_same = centers(idx); fpr = fpr_vector(idx);
end
