function flat_dir = make_fixtures()
%MAKE_FIXTURES Build a deterministic flat folder of synthetic session mats.
%   Returns the absolute path to the created folder.
    here = fileparts(mfilename('fullpath'));
    flat_dir = fullfile(here, 'flat_folder');
    if exist(flat_dir, 'dir'); rmdir(flat_dir, 's'); end
    mkdir(flat_dir);

    % Tiny but valid: 5 cells, 32x32 frame, one bright pixel per cell.
    Y = 32; X = 32; N = 5;
    rng(42);

    datasets = { ...
        struct('exp','BOWL','mouse','D01','sessions',{{'1D','2D','3D'}}, 'type','uint8'), ...
        struct('exp','BOWL','mouse','D03','sessions',{{'1D','2D'}},      'type','double'), ...
        struct('exp','BOWL','mouse','D05','sessions',{{'1D'}},            'type','uint8'), ...  % too few
    };

    for d = 1:numel(datasets)
        ds = datasets{d};
        for s = 1:numel(ds.sessions)
            A = zeros(N, Y, X, 'uint8');
            for c = 1:N
                yi = mod(c*5 + s, Y-3) + 2;
                xi = mod(c*7 + s*2, X-3) + 2;
                A(c, yi:yi+1, xi:xi+1) = 200;
            end
            if strcmp(ds.type, 'double')
                matrix_data = double(A); %#ok<NASGU>
                fname = sprintf('%s_%s_%s_converted.mat', ds.exp, ds.mouse, ds.sessions{s});
                save(fullfile(flat_dir, fname), 'matrix_data', '-v7.3');
            else
                fname = sprintf('%s_%s_%sD_filters.mat', ds.exp, ds.mouse, ds.sessions{s}(1));
                save(fullfile(flat_dir, fname), 'A');
            end
        end
    end

    % Add one unparseable file.
    fid = fopen(fullfile(flat_dir, 'README.mat'), 'w'); fclose(fid);
end
