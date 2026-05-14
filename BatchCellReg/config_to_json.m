function config_to_json(cfg, path)
%CONFIG_TO_JSON Serialize config struct to a JSON file (pretty-printed).
    json = jsonencode(cfg);  % PrettyPrint not available in R2020a
    fid = fopen(path, 'w');
    if fid < 0
        error('BatchCellReg:ConfigWrite', 'Cannot open %s for writing', path);
    end
    cleanup = onCleanup(@() fclose(fid));
    fprintf(fid, '%s', json);
end
