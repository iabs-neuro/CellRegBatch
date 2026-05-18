function tests = test_anomaly_decode_map
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', '..', 'BatchCellReg')));
end

function test_has_all_codes(tc)
    m = anomaly_decode_map();
    codes = {'W1','W2','W2b_hard','W2b_rel','W3a','W3b','W4','W5a','W5b','W6a','W6b','W7'};
    for k = 1:numel(codes)
        verifyTrue(tc, isKey(m, codes{k}), sprintf('missing %s', codes{k}));
        e = m(codes{k});
        verifyTrue(tc, isfield(e,'short') && isfield(e,'desc'));
        verifyNotEmpty(tc, e.short);
        verifyNotEmpty(tc, e.desc);
    end
end

function test_short_is_brief(tc)
    m = anomaly_decode_map();
    verifyEqual(tc, m('W3a').short, 'low xcorr');
    verifyEqual(tc, m('W6a').short, 'bad MSE');
end
