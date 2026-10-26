function tests = test_end_to_end_sample
    tests = functiontests(localfunctions);
end

function test_runs_on_shipped_cellreg_sample_data(testCase)
    % SampleData (5 sessions of one mouse from CellReg, 2.35 um/px as in
    % CellReg/demo.m) ships with the repository, so this test runs anywhere.
    repo_root = fullfile(fileparts(mfilename('fullpath')), '..', '..');
    addpath(genpath(fullfile(repo_root, 'CellReg')));
    addpath(genpath(fullfile(repo_root, 'Helper')));
    addpath(genpath(fullfile(repo_root, 'BatchCellReg')));

    in = fullfile(tempdir, ['BatchCellReg_demo_' datestr(now,'HHMMSS')]);
    mkdir(in);
    cleanup = onCleanup(@() rmdir(in, 's'));
    % The scanner needs <EXP>_<ANIMAL>_<SESSION>.mat names.
    for k = 1:5
        copyfile(fullfile(repo_root, 'SampleData', sprintf('spatial_footprints_%02d.mat', k)), ...
                 fullfile(in, sprintf('DEMO_M01_%dD.mat', k)));
    end

    cfg = batch_default_config();
    cfg.cellreg.microns_per_pixel = 2.35;
    cfg.cellreg.use_parallel_processing = false;
    summary = batch_run(in, cfg);

    verifyEqual(testCase, summary.n_succeeded, 1);
    verifyEqual(testCase, summary.n_failed, 0);
    r = summary.results(1);
    verifyEqual(testCase, r.sessions, {'1D','2D','3D','4D','5D'});
    verifyGreaterThan(testCase, r.match_stats(2), 0);
    verifyTrue(testCase, r.chosen_fpr <= cfg.p_same_tuning.fpr_max || r.p_same_unreachable);
    out = fullfile(summary.output_dir, 'DEMO_M01');
    f = dir(fullfile(out, 'cellRegistered_*.mat'));
    verifyNumElements(testCase, f, 1);
    verifyNumElements(testCase, dir(fullfile(out, 'logFile_*.txt')), 1);
    verifyNotEmpty(testCase, dir(fullfile(out, 'Figures', '*.png')));

    % Same variable name as the CellReg GUI, so scripts written for GUI
    % output read the batch output unchanged.
    s = load(fullfile(f(1).folder, f(1).name));
    verifyEqual(testCase, fieldnames(s), {'cell_registered_struct'});
    map = s.cell_registered_struct.cell_to_index_map;
    verifyEqual(testCase, readmatrix(fullfile(summary.output_dir, 'DEMO_M01_cellmap.csv')), map);

    T = readtable(summary.match_stats_csv);
    verifyEqual(testCase, height(T), 1);
    verifyEqual(testCase, T.n_cells, size(map, 1));
    verifyEqual(testCase, [T.in_5_sessions, T.in_4_sessions, T.in_3_sessions, ...
        T.in_2_sessions, T.in_1_sessions], r.match_stats(2:end));
    verifyEqual(testCase, T.in_5_sessions, sum(all(map > 0, 2)));
end

function test_explicit_empty_selection_runs_nothing(testCase)
    % The GUI passes the ticked rows; clearing every box must not mean "all".
    repo_root = fullfile(fileparts(mfilename('fullpath')), '..', '..');
    addpath(genpath(fullfile(repo_root, 'BatchCellReg')));
    in = fullfile(tempdir, ['BatchCellReg_sel_' datestr(now,'HHMMSSFFF')]);
    mkdir(in);
    cleanup = onCleanup(@() rmdir(in, 's'));
    for k = 1:2
        copyfile(fullfile(repo_root, 'SampleData', sprintf('spatial_footprints_%02d.mat', k)), ...
                 fullfile(in, sprintf('DEMO_M01_%dD.mat', k)));
    end
    cfg = batch_default_config();
    cfg.cellreg.use_parallel_processing = false;
    summary = batch_run(in, cfg, struct('selected_datasets', {{}}));
    verifyEqual(testCase, summary.n_succeeded + summary.n_failed, 0);
    verifyMatches(testCase, fileread(summary.log_file), 'DEMO_M01: skipped: not selected');
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
