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
    hdr = ['dataset_id,n_sessions,missing_sessions,n_cells,pct_in_all,pct_in_all_of_mean,' ...
        'chosen_p_same,chosen_fpr_pct,model,alignment_mode,session_count,few_cells,cell_drop,' ...
        'alignment,model_fit,low_match,median_cells,worst_session_ratio,min_xcorr,' ...
        'max_shift_px,model_mse,error'];
    p = tmpcsv({hdr, ...
        'HOS_F01,5,,795,40.881,58.306,0.5,0.611,Spatial correlation,Translations,0,0,0,0,0,0,557,0.9,0.5,10,0.07,', ...
        'HOS_F02,4,3D,300,20,30,0.6,2.5,Spatial correlation,Translations,2,0,1,0,0,0,80,0.5,0.4,12,0.09,'});
    r = parse_batch_results_csv(p);
    verifyTrue(tc, r.ok);
    verifyEqual(tc, numel(r.headers), 22);
    verifyEqual(tc, size(r.rows, 1), 2);
    verifyEqual(tc, r.rows{2, 1}, 'HOS_F02');
    verifyEqual(tc, r.rows{2, 3}, '3D');
    delete(p);
end

function test_missing_column(tc)
    p = tmpcsv({'dataset_id,n_sessions,n_cells,pct_in_all_of_mean,chosen_fpr_pct,session_count', 'X,1,2,0.1,0,0'});
    r = parse_batch_results_csv(p);
    verifyFalse(tc, r.ok);
    verifySubstring(tc, r.error, 'few_cells');
    delete(p);
end

function test_old_format_gets_a_clear_message(tc)
    p = tmpcsv({'dataset_id,n_sessions,n_cells,pct_in_all,chosen_fpr,W1,W2', 'X,1,2,0.1,0,0,0'});
    r = parse_batch_results_csv(p);
    verifyFalse(tc, r.ok);
    verifySubstring(tc, r.error, 'older version');
    delete(p);
end

function test_custom_required_columns(tc)
    p = tmpcsv({'dataset_id,session,warning', 'A,3D,cell_drop'});
    r = parse_batch_results_csv(p, {'dataset_id', 'warning'});
    verifyTrue(tc, r.ok);
    delete(p);
end

function test_bad_path(tc)
    r = parse_batch_results_csv('Z:/nope/none.csv');
    verifyFalse(tc, r.ok);
    verifyNotEmpty(tc, r.error);
end
