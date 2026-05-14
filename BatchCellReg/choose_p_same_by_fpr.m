function [p_same, fpr, unreachable] = choose_p_same_by_fpr(centers, fpr_vector, fpr_max)
%CHOOSE_P_SAME_BY_FPR Pick the minimum p_same threshold with FPR <= fpr_max.
%   Falls back to the best (lowest-FPR) threshold if the target is unreachable,
%   in which case `unreachable` is true.
    idx = find(fpr_vector <= fpr_max, 1, 'first');
    if isempty(idx)
        [~, idx] = min(fpr_vector);
        unreachable = true;
    else
        unreachable = false;
    end
    p_same = centers(idx);
    fpr    = fpr_vector(idx);
end
