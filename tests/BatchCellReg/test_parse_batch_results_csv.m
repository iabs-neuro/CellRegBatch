function tests = test_parse_batch_results_csv
    tests = functiontests(localfunctions);
end

function setupOnce(~)
    addpath(genpath(fullfile(fileparts(mfilename('fullpath')), '..', '..', 'BatchCellReg')));
end

function p = tmpcsv(lines)
    p = [tempname '.csv'];
    fid = fopen(p,'w'); for i=1:numel(lines); fprintf(fid,'%s\n',lines{i}); end; fclose(fid);
end

function test_parses_valid(tc)
    hdr = 'dataset_id,n_sessions,n_cells,pct_in_all,chosen_fpr,W1,W2,W2b_hard,W2b_rel,W3a,W3b,W4,W5a,W5b,W6a,W6b,W7,W3a_min_xcorr,W5a_max_shift_px,W6a_mse,W2b_ratio,error';
    p = tmpcsv({hdr, 'CC_H01,2,236,0.22,0,0,0,0,0,0,0,0,0,0,2,0,2,0.5,1,0.12,1.1,', ...
                     'CC_H04,2,237,0.13,0,0,0,2,1,2,0,0,0,0,2,0,2,0.29,2,0.13,3.2,'});
    r = parse_batch_results_csv(p);
    verifyTrue(tc, r.ok);
    verifyEqual(tc, numel(r.headers), 22);
    verifyEqual(tc, size(r.rows,1), 2);
    verifyEqual(tc, r.rows{2,1}, 'CC_H04');
    delete(p);
end

function test_missing_column(tc)
    p = tmpcsv({'dataset_id,n_sessions,n_cells,pct_in_all,chosen_fpr,W1', 'X,1,2,0.1,0,0'});
    r = parse_batch_results_csv(p);
    verifyFalse(tc, r.ok);
    verifySubstring(tc, r.error, 'W2');
    delete(p);
end

function test_bad_path(tc)
    r = parse_batch_results_csv('Z:/nope/none.csv');
    verifyFalse(tc, r.ok);
    verifyNotEmpty(tc, r.error);
end
