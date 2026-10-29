function cfg = config_from_json(path)
%CONFIG_FROM_JSON Load and validate a batch config JSON file.
%   Values from the file replace the defaults of batch_default_config.
%   Fields the file does not have keep their defaults, so a file saved by
%   an older version still loads. Fields this version does not know are
%   ignored with a warning.
    raw = jsondecode(fileread(path));
    if ~isfield(raw, 'version') || ~ismember(raw.version, [1 2])
        v = 'missing';
        if isfield(raw, 'version'); v = num2str(raw.version); end
        error('BatchCellReg:UnsupportedConfigVersion', ...
            'Config version %s is not supported (expected 1 or 2)', v);
    end
    raw = rename_legacy_thresholds(raw);
    defaults = batch_default_config();
    cfg = merge_known(defaults, rmfield(raw, 'version'), '');
    cfg.version = defaults.version;
end

function raw = rename_legacy_thresholds(raw)
% Version 1 files name three thresholds that still exist under new names.
% z_threshold has no successor: the batch comparison now uses robust z.
    if ~isfield(raw, 'anomaly_thresholds'); return; end
    a = raw.anomaly_thresholds;
    pairs = {'min_xcorr', 'xcorr_yellow'; 'max_mse', 'mse_yellow'; ...
             'max_translation_px', 'shift_yellow_px'};
    for k = 1:size(pairs, 1)
        if isfield(a, pairs{k, 1})
            if ~isfield(a, pairs{k, 2}); a.(pairs{k, 2}) = a.(pairs{k, 1}); end
            a = rmfield(a, pairs{k, 1});
        end
    end
    if isfield(a, 'z_threshold'); a = rmfield(a, 'z_threshold'); end
    raw.anomaly_thresholds = a;
end

function out = merge_known(defaults, loaded, prefix)
    out = defaults;
    fns = fieldnames(loaded);
    for k = 1:numel(fns)
        name = fns{k};
        if ~isfield(defaults, name)
            warning('BatchCellReg:ConfigUnknownField', ...
                'Config field %s%s is not used by this version; ignored.', prefix, name);
        elseif isstruct(defaults.(name)) && isstruct(loaded.(name))
            out.(name) = merge_known(defaults.(name), loaded.(name), [prefix name '.']);
        else
            out.(name) = loaded.(name);
        end
    end
end
