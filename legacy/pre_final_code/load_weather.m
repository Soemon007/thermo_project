function W = load_weather(file, cfg)
% load_weather.m
% Reads a PVGIS hourly time-series CSV (plane-of-array components), converts
% the UTC timestamps to Indian Standard Time and runs basic sanity checks.
%
% Output W (all 8760x1 unless noted)
%   Gb, Gd, Gr : beam / diffuse / ground-reflected irradiance on the plane [W/m2]
%   G          : total plane-of-array irradiance [W/m2]
%   Ta         : 2 m air temperature [degC]
%   ws10       : 10 m wind speed [m/s]
%   Hsun       : sun height from PVGIS [deg]
%   doy_utc, hr_utc : day of year and decimal UTC hour of each PVGIS stamp
%   hour, month: IST hour-of-day (0..23) and month (1..12) after the shift
%   lat, lon   : scalars from the file header

    fid = fopen(file, 'r');
    if fid < 0, error('Cannot open %s', file); end
    lat = NaN; lon = NaN;
    line = fgetl(fid);
    while ischar(line)
        if strncmp(line, 'Latitude', 8),  lat = sscanf(line(strfind(line, ':')+1:end), '%f'); end
        if strncmp(line, 'Longitude', 9), lon = sscanf(line(strfind(line, ':')+1:end), '%f'); end
        if strncmp(line, 'time,', 5), break; end
        line = fgetl(fid);
    end
    C = textscan(fid, '%s %f %f %f %f %f %f %f', 'Delimiter', ',');
    fclose(fid);

    stamp = C{1};
    ok = cellfun(@(s) numel(s) == 13 && s(9) == ':', stamp);   % drop footer lines
    n = find(ok, 1, 'last');
    if n < 8760, error('%s: only %d hourly rows', file, n); end
    idx = 1:8760;
    stamp = stamp(idx);

    Gb = C{2}(idx); Gd = C{3}(idx); Gr = C{4}(idx);
    Hsun = C{5}(idx); Ta = C{6}(idx); ws = C{7}(idx);

    % UTC time of each stamp: yyyymmdd:hhmm
    yr  = cellfun(@(s) str2double(s(1:4)), stamp);
    mo  = cellfun(@(s) str2double(s(5:6)), stamp);
    dy  = cellfun(@(s) str2double(s(7:8)), stamp);
    hh  = cellfun(@(s) str2double(s(10:11)), stamp);
    mm  = cellfun(@(s) str2double(s(12:13)), stamp);
    cum = [0 31 59 90 120 151 181 212 243 273 304 334];
    doy_utc = cum(mo)' + dy;
    hr_utc  = hh + mm/60;

    % --- Sanity checks (gate before any physics) ---
    X = [Gb Gd Gr Ta ws];
    assert(~any(isnan(X(:))), '%s: NaN values in weather data', file);
    assert(all(Gb >= 0 & Gd >= 0 & Gr >= 0), '%s: negative irradiance', file);
    assert(all(Ta > -10 & Ta < 55), '%s: implausible temperature', file);
    assert(all(ws >= 0 & ws < 40), '%s: implausible wind speed', file);
    assert(all(yr == yr(1)), '%s: more than one year in file', file);

    % --- UTC -> IST. Row k (UTC hh:30) becomes IST (hh+6):00. Shift so row 1 = IST 00:00 Jan 1.
    %     The first 6 IST hours of Jan 1 take the last 6 UTC rows of Dec 31 (night, G = 0).
    s = cfg.utc_shift;
    sh = @(x) circshift(x, s);
    W.Gb = sh(Gb) * cfg.G_scale;  W.Gd = sh(Gd) * cfg.G_scale;  W.Gr = sh(Gr) * cfg.G_scale;
    W.G  = W.Gb + W.Gd + W.Gr;
    W.Ta = sh(Ta);  W.ws10 = sh(ws);  W.Hsun = sh(Hsun);
    W.doy_utc = sh(doy_utc);  W.hr_utc = sh(hr_utc);

    W.hour  = mod((0:8759)', 24);
    day_ist = floor((0:8759)'/24) + 1;
    edges = [0 cumsum([31 28 31 30 31 30 31 31 30 31 30 31])];
    W.month = zeros(8760, 1);
    for m = 1:12
        W.month(day_ist > edges(m) & day_ist <= edges(m+1)) = m;
    end
    W.lat = lat;  W.lon = lon;  W.year = yr(1);
end
