function kW = ev_profile(name, daily_kWh)
% ev_profile.m
% Hourly EV charging power [kW] for one day (IST hours 0..23) with the given daily energy.
% Measured shapes come from data/ev/ev_profiles.csv (tools/make_ev_profile.py).
    if strcmp(name, 'synthetic')                       % simple daytime step profile (sensitivity case)
        kW = [repmat(2, 6, 1); repmat(15, 12, 1); repmat(5, 6, 1)];
        kW = kW * daily_kWh / sum(kW);
        return
    end
    f = fullfile(fileparts(mfilename('fullpath')), '..', 'data', 'ev', 'ev_profiles.csv');
    fid = fopen(f, 'r');
    if fid < 0, error('Cannot open %s', f); end
    hdr = strsplit(fgetl(fid), ',');
    X = textscan(fid, repmat('%f', 1, numel(hdr)), 'Delimiter', ',');
    fclose(fid);
    col = find(strcmp(hdr, [name '_share']));
    if isempty(col), error('No EV profile "%s" in %s', name, f); end
    share = X{col};
    assert(numel(share) == 24 && abs(sum(share) - 1) < 1e-4, 'EV profile %s is not a 24-h share', name);
    kW = daily_kWh * share(:) / sum(share);
end
