function results = runAllTests()
%RUNALLTESTS Run every test_*.m in this directory and exit with proper code.
    here = fileparts(mfilename('fullpath'));
    suite = matlab.unittest.TestSuite.fromFolder(here);
    runner = matlab.unittest.TestRunner.withTextOutput('OutputDetail', ...
        matlab.unittest.Verbosity.Detailed);
    results = runner.run(suite);
    if any([results.Failed])
        error('runAllTests:Failed', '%d tests failed', sum([results.Failed]));
    end
end
