function tests = test_choose_p_same_by_fpr
    tests = functiontests(localfunctions);
end

function test_picks_smallest_psame_meeting_fpr(testCase)
    centers = [0.5 0.6 0.7 0.8 0.9];
    fpr     = [0.10 0.05 0.029 0.01 0.005];
    [p, f, unreach] = choose_p_same_by_fpr(centers, fpr, 0.03);
    verifyEqual(testCase, p, 0.7);
    verifyEqual(testCase, f, 0.029);
    verifyFalse(testCase, unreach);
end

function test_returns_best_achievable_when_unreachable(testCase)
    centers = [0.5 0.6 0.7 0.8 0.9];
    fpr     = [0.20 0.15 0.10 0.08 0.07];
    [p, f, unreach] = choose_p_same_by_fpr(centers, fpr, 0.03);
    verifyTrue(testCase, unreach);
    verifyEqual(testCase, f, 0.07);
    verifyEqual(testCase, p, 0.9);
end

function test_first_bin_already_meets(testCase)
    centers = [0.5 0.6 0.7];
    fpr     = [0.01 0.005 0.001];
    [p, f, unreach] = choose_p_same_by_fpr(centers, fpr, 0.03);
    verifyEqual(testCase, p, 0.5);
    verifyEqual(testCase, f, 0.01);
    verifyFalse(testCase, unreach);
end
