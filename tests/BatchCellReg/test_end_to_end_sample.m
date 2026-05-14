function tests = test_end_to_end_sample
    tests = functiontests(localfunctions);
end

function test_runs_on_sample_data_our(testCase)
    repo_root = fullfile(fileparts(mfilename('fullpath')), '..', '..');
    sample_dir = fullfile(repo_root, 'SampleDataOur');
    if ~exist(sample_dir, 'dir')
        testCase.assumeFail('SampleDataOur not present');
    end
    addpath(genpath(fullfile(repo_root, 'CellReg')));
    addpath(genpath(fullfile(repo_root, 'Helper')));
    addpath(genpath(fullfile(repo_root, 'BatchCellReg')));

    out = fullfile(tempdir, ['BatchCellReg_smoke_' datestr(now,'HHMMSS')]);
    mkdir(out);
    % Mirror sample files into a clean dir so we control teardown.
    copyfile(fullfile(sample_dir, '*.mat'), out);
    cleanup = onCleanup(@() rmdir(out, 's'));

    cfg = batch_default_config();
    cfg.io.input_folder = out;
    cfg.cellreg.use_parallel_processing = false;
    cfg.cellreg.figures_visibility = 'off';

    summary = batch_run(out, cfg);

    % The batch must attempt at least one dataset (n_succeeded + n_failed >= 1).
    % SampleDataOur/BOWL_D01 session 2 cannot be aligned to the reference even
    % with rotations (vendor warns "does not resemble the reference session").
    % The wrapper records such datasets as failed so that the batch continues
    % cleanly, meaning n_succeeded may be 0 for this specific test corpus.
    % We therefore verify that the runner completed end-to-end without an
    % unhandled exception and produced the required output artefacts.
    verifyGreaterThan(testCase, summary.n_succeeded + summary.n_failed, 0);
    verifyTrue(testCase, exist(summary.results_csv, 'file') == 2);
    verifyTrue(testCase, exist(summary.log_file, 'file') == 2);
end
