function tests = test_natural_order
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', '..', 'BatchCellReg')));
end

function test_numbers_compare_by_value(tc)
    s = {'10D', '2D', '1D_1T', '1D', 'M10', 'M9'};
    verifyEqual(tc, s(natural_order(s)), {'1D', '1D_1T', '2D', '10D', 'M9', 'M10'});
end

function test_plain_text_is_alphabetical(tc)
    s = {'day', 'Day', 'base'};
    verifyEqual(tc, s(natural_order(s)), sort(s));
end
