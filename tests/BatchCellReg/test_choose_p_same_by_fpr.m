function tests = test_choose_p_same_by_fpr
    tests = functiontests(localfunctions);
end

function test_keeps_half_when_fpr_ok(testCase)
    centers = [0.3 0.5 0.7 0.9 0.95];
    fpr     = [0.10 0.02 0.01 0.005 0.001];   % FPR at 0.5 = 0.02 <= 0.03
    [p,f,u] = choose_p_same_by_fpr(centers, fpr, 0.03);
    verifyEqual(testCase, p, 0.5);
    verifyEqual(testCase, f, 0.02);
    verifyFalse(testCase, u);
end

function test_ascends_to_min_meeting_fpr(testCase)
    centers = [0.3 0.5 0.7 0.9 0.95];
    fpr     = [0.20 0.08 0.025 0.01 0.005];   % 0.5 too high; 0.7 first ok
    [p,f,u] = choose_p_same_by_fpr(centers, fpr, 0.03);
    verifyEqual(testCase, p, 0.7);
    verifyEqual(testCase, f, 0.025);
    verifyFalse(testCase, u);
end

function test_caps_at_095_and_flags_when_unreachable(testCase)
    centers = [0.3 0.5 0.7 0.9 0.95];
    fpr     = [0.30 0.20 0.15 0.10 0.07];     % never <=0.03
    [p,f,u] = choose_p_same_by_fpr(centers, fpr, 0.03);
    verifyEqual(testCase, p, 0.95);
    verifyEqual(testCase, f, 0.07);
    verifyTrue(testCase, u);
end

function test_does_not_exceed_095_even_if_higher_bin_better(testCase)
    centers = [0.5 0.9 0.95 0.99];
    fpr     = [0.10 0.05 0.04 0.01];          % only 0.99 meets, but >0.95
    [p,f,u] = choose_p_same_by_fpr(centers, fpr, 0.03);
    verifyEqual(testCase, p, 0.95);            % capped
    verifyTrue(testCase, u);
end
