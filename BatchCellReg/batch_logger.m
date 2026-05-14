function log = batch_logger(file_path, live_callback)
%BATCH_LOGGER Returns a struct of logging functions writing to file + live.
%   live_callback: function handle taking a single formatted string, or [].
    fid = fopen(file_path, 'w');
    if fid < 0
        error('BatchCellReg:LogOpen', 'Cannot open log file %s', file_path);
    end

    log.info  = @(tag, fmt, varargin) emit('INFO',  tag, fmt, varargin);
    log.warn  = @(tag, fmt, varargin) emit('WARN',  tag, fmt, varargin);
    log.error = @(tag, fmt, varargin) emit('ERROR', tag, fmt, varargin);
    log.close = @() do_close();

    function emit(level, tag, fmt, args)
        msg = sprintf(fmt, args{:});
        line = sprintf('[%s] [%s] %s: %s', datestr(now, 'HH:MM:SS'), level, tag, msg);
        fprintf(fid, '%s\n', line);
        if ~isempty(live_callback)
            live_callback(line);
        end
    end

    function do_close()
        if fid >= 0
            fclose(fid);
            fid = -1;
        end
    end
end
