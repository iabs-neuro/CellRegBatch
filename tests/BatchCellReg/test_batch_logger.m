function tests = test_batch_logger
    tests = functiontests(localfunctions);
end

function test_writes_to_file_and_live(testCase)
    file_path = [tempname '.txt'];
    live_path = [tempname '.txt'];
    cleanup = onCleanup(@() cellfun(@delete, {file_path, live_path}));
    fid_live = fopen(live_path, 'w');
    live = @(msg) fprintf(fid_live, '%s\n', msg);
    log = batch_logger(file_path, live);
    log.info('GLOBAL', 'starting');
    log.warn('BOWL_D01', 'check this');
    log.error('BOWL_D03', 'failed: %s', 'x');
    log.close();
    fclose(fid_live);

    file_text = fileread(file_path);
    live_text = fileread(live_path);
    verifyTrue(testCase, contains(file_text, 'INFO'));
    verifyTrue(testCase, contains(file_text, 'WARN'));
    verifyTrue(testCase, contains(file_text, 'ERROR'));
    verifyTrue(testCase, contains(live_text, 'starting'));
    verifyTrue(testCase, contains(live_text, 'failed: x'));
end

function test_no_live_callback_is_ok(testCase)
    tmp = [tempname '.txt'];
    cleanup = onCleanup(@() delete(tmp));
    log = batch_logger(tmp, []);
    log.info('GLOBAL', 'hello');
    log.close();
    verifyTrue(testCase, contains(fileread(tmp), 'hello'));
end
