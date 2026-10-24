function W = scale_weather(W, g)
% scale_weather.m  -  multiply all plane-of-array irradiance components by g
% (irradiance-data uncertainty; temperature and wind are left unchanged).
    W.Gb = W.Gb*g;  W.Gd = W.Gd*g;  W.Gr = W.Gr*g;  W.G = W.Gb + W.Gd + W.Gr;
end
