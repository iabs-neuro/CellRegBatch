function tests = test_anomaly_decode_map
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', '..', 'BatchCellReg')));
end

function test_has_all_codes(tc)
    [m, order] = anomaly_decode_map();
    verifyEqual(tc, order, {'session_count', 'few_cells', 'cell_drop', 'alignment', ...
        'model_fit', 'low_match'});
    verifyEqual(tc, sort(keys(m)), sort(order));
    for k = 1:numel(order)
        e = m(order{k});
        verifyNotEmpty(tc, e.short);
        verifyNotEmpty(tc, e.desc);
    end
end

function test_detector_uses_the_same_names(tc)
    [~, order] = anomaly_decode_map();
    cfg = batch_default_config();
    a = detect_anomalies(struct([]), cfg.anomaly_thresholds);
    verifyEqual(tc, fieldnames(a.flags)', order);
end
