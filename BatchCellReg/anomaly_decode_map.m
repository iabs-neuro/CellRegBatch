function m = anomaly_decode_map()
%ANOMALY_DECODE_MAP code -> struct(short, desc) for results-table warnings.
%   short: 1-2 word column-header tag. desc: full click-to-decode sentence.
    e = @(s,d) struct('short', s, 'desc', d);
    m = containers.Map('KeyType','char','ValueType','any');
    m('W1')       = e('%match',     'W1 - %match population outlier: pct_in_all low vs batch (graded).');
    m('W2')       = e('cells/sess', 'W2 - cells/session intra-dataset z-outlier.');
    m('W2b_hard') = e('ratio>3',    'W2b_hard - max/min cells-per-session ratio > 3 (hard).');
    m('W2b_rel')  = e('ratio rel',  'W2b_rel - cells-per-session ratio high vs batch (graded).');
    m('W3a')      = e('low xcorr',  'W3a - low cross-correlation (hard): min(max_xcorr) < min_xcorr (0.3) = bad alignment.');
    m('W3b')      = e('xcorr rel',  'W3b - low cross-correlation relative: intra-dataset z of max_xcorr.');
    m('W4')       = e('FPR unreach','W4 - P_same FPR target unreachable (P_same capped at 0.95).');
    m('W5a')      = e('big shift',  'W5a - large alignment shift (hard): max |shift_px| > max_translation_px (30).');
    m('W5b')      = e('shift rel',  'W5b - large alignment shift relative: intra-dataset z of per-session shift.');
    m('W6a')      = e('bad MSE',    'W6a - bad model fit (hard): MSE_model > max_mse (0.1).');
    m('W6b')      = e('MSE rel',    'W6b - bad model fit relative: MSE high vs batch (graded).');
    m('W7')       = e('sess count', 'W7 - session count != expected_n_sessions.');
end
