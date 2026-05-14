function cfg = config_from_json(path)
%CONFIG_FROM_JSON Load and validate a batch config JSON file.
    raw = fileread(path);
    cfg = jsondecode(raw);
    if ~isfield(cfg, 'version') || cfg.version ~= 1
        v = 'missing';
        if isfield(cfg, 'version'); v = num2str(cfg.version); end
        error('BatchCellReg:UnsupportedConfigVersion', ...
            'Config version %s is not supported (expected 1)', v);
    end
end
