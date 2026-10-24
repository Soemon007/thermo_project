function q = prctile_(x, p)
% prctile_.m  -  percentile by linear interpolation between order statistics (no toolbox needed)
    x = sort(x(:));  n = numel(x);
    pts = [0; (0.5:n)'/n*100; 100];
    q = interp1(pts, [x(1); x; x(end)], p);
end
