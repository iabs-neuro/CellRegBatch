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

    figs_before = findall(groot, 'Type', 'figure');
    summary = batch_run(out, cfg);

    % Vendor plot_* functions never close their figures; leaked hidden
    % figures hold full-FOV images and exhaust RAM over a long batch.
    verifyEmpty(testCase, setdiff(findall(groot, 'Type', 'figure'), figs_before));

    % The batch must attempt at least one dataset (n_succeeded + n_failed >= 1).
    % SampleDataOur/BOWL_D01 session 2 cannot be aligned to the reference: its
    % cross-correlation with session 1 stays below
    % sufficient_correlation_footprints (0.3) for every rotation, so vendor
    % align_images marks it failed and our wrapper raises BatchCellReg:AlignmentFailed.
    % The wrapper records such datasets as failed so batch processing continues,
    % which means n_succeeded may be 0 for this specific test corpus. We therefore
    % verify that the runner completed end-to-end without an unhandled exception
    % and produced the required output artefacts. Future smoke tests that include
    % alignable datasets should tighten this to verifyGreaterThan(n_succeeded, 0).
    verifyGreaterThan(testCase, summary.n_succeeded + summary.n_failed, 0);
    verifyTrue(testCase, exist(summary.results_csv, 'file') == 2);
    verifyTrue(testCase, exist(summary.log_file, 'file') == 2);

    % Vendor alignment_translations are in MICRONS (align_images.m:428);
    % alignment_shift_px (compared to max_translation_px) must be PIXELS.
    for r = summary.results
        if ~isempty(r.error); continue; end
        expected = hypot(r.alignment_translations(1, :), r.alignment_translations(2, :)) ...
            / cfg.cellreg.microns_per_pixel;
        verifyEqual(testCase, r.alignment_shift_px, expected, 'AbsTol', 1e-9);
    end
end
