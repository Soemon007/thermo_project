% main.m
% Thermodynamic feasibility of a solar-powered EV charging station
% Jodhpur, Bengaluru, Guwahati  |  CL207 Thermodynamics
%
% WHAT IT DOES
%   One fixed station (49.6 kWp PV + 93.2 kWh LFP battery, 222 kWh/day EV load) is
%   simulated hour by hour in three climates. Only the weather file changes between cities.
%
%   1. Baseline        NASA POWER 2021-2023 run back to back; results are 3-year means
%   2. Year by year    each weather year on its own (weather variability)
%   3. Sensitivity     one input changed at a time
%   4. Monte Carlo     200 draws over five physical inputs + the weather year
%   5. Print, save tables, make figures
%
% CALL CHAIN (per city)
%   params -> load_weather -> simulate_station [ pv_model -> ems_dispatch -> battery_model,
%   every hour ] -> postprocess -> export_tables / make_plots
%
% HOW TO RUN (MATLAB R2016b+ or GNU Octave 6+)
%   >> main                        % main case, NASA POWER 2021-2023  (~25 min incl. Monte Carlo)
%   >> source = 'ERA5'; main       % cross-check, PVGIS-ERA5 2023 only (~3 min, no Monte Carlo)

if ~exist('source', 'var'), clear; source = ''; end
clc; close all;
here = fileparts(mfilename('fullpath'));  if isempty(here), here = pwd; end
addpath(fullfile(here, 'src'));

%% 0. SET-UP
P0 = params();                                   % all fixed inputs (src/params.m)
if ~isempty(source), P0.cfg.source = source; end
cities = {'Jodhpur', 'Bengaluru', 'Guwahati'};
wdir   = fullfile(here, 'data', 'weather');
switch P0.cfg.source
    case 'NASAPOWER'                             % main case: three years
        yrs   = P0.cfg.years;
        P0.cfg.source_label = sprintf('NASA POWER %d-%d', yrs(1), yrs(end));
        files = @(c) arrayfun(@(y) fullfile(wdir, sprintf('NASAPOWER_%s_%d.csv', c, y)), yrs, 'UniformOutput', false);
        N_MC  = 200;
    case 'ERA5'                                  % cross-check: one year
        yrs   = 2023;
        P0.cfg.source_label = 'PVGIS-ERA5 2023';
        files = @(c) {fullfile(wdir, sprintf('ERA5_%s_2023.csv', c))};
        N_MC  = 0;
    otherwise
        error('Unknown weather source %s', P0.cfg.source);
end
P0.cfg.outR = fullfile(here, 'results', P0.cfg.source);
P0.cfg.outF = fullfile(here, 'figures', P0.cfg.source);
if ~exist(P0.cfg.outR, 'dir'), mkdir(P0.cfg.outR); end
if ~exist(P0.cfg.outF, 'dir'), mkdir(P0.cfg.outF); end
fprintf('Weather source: %s | EV profile: %s\n', P0.cfg.source_label, P0.ev.profile);

run1 = @(W, P) postprocess(simulate_station(W, P), W, P);   % one full simulation -> metrics

%% 1. BASELINE: same design, three climates, all years back to back
R = struct();  Wx = struct();  SIM = struct();  Wy = struct();
for c = 1:numel(cities)
    city = cities{c};
    fl   = files(city);
    W    = load_weather(fl, P0.cfg);             % joined multi-year weather
    sim  = simulate_station(W, P0);              % hourly simulation
    r    = postprocess(sim, W, P0);              % annual / monthly / seasonal metrics
    % The two laws must balance every hour, and the PV cell can never destroy negative exergy
    assert(r.res_energy < 1e-8,   'First Law balance does not close for %s', city);
    assert(r.res_exergy < 1e-8,   'Exergy balance does not close for %s', city);
    assert(r.min_Ex_int >= -1e-9, 'Negative PV internal exergy destruction for %s', city);
    R.(city) = r;  Wx.(city) = W;  SIM.(city) = sim;
    for k = 1:numel(fl), Wy.(city){k} = load_weather(fl{k}, P0.cfg); end   % each year alone
end

%% 2. YEAR BY YEAR (same design, each weather year on its own)
%   columns: POA [kWh/m2] | SCR | psi_PV | eta_PV | psi_sun | yield | psi_PV by season (4)
Y = struct();
for c = 1:numel(cities)
    city = cities{c};
    for k = 1:numel(yrs)
        r = run1(Wy.(city){k}, P0);
        Y.(city)(k,:) = [r.G_annual r.SCR_total r.psi_PV r.eta_PV r.psi_sun r.specific_yield r.s.psi_PV];
    end
end

%% 3. SENSITIVITY (one input at a time; everything else at baseline)
sens.N_mod   = [40 60 80 100 120];          % PV array size [modules]
sens.batt_f  = [0 0.5 1 1.5 2];             % battery size, x baseline (93.2 kWh)
sens.G_scale = [0.8 0.9 1.0 1.1 1.2 1.3];   % irradiance data uncertainty
sens.ev      = {'public', 'workplace', 'residential', 'synthetic'};   % EV timing (same 222 kWh/day)
for c = 1:numel(cities)
    city = cities{c};  W0 = Wx.(city);
    for i = 1:numel(sens.N_mod)                                       % PV size
        P = P0;  P.pv.N_mod = sens.N_mod(i);  P = update_params(P);
        r = run1(W0, P);
        S.pv.(city)(i,:) = [r.SCR_total r.psi_solar r.E_export/r.E_PV_ac r.Ex_dest_tot];
    end
    for i = 1:numel(sens.batt_f)                                      % battery size
        P = P0;  P.batt.n_parallel = sens.batt_f(i);  P = update_params(P);
        r = run1(W0, P);
        S.batt.(city)(i,:) = [r.SCR_total r.psi_solar r.E_export r.Ex_dest_batt + r.Ex_dest_pcs];
    end
    for i = 1:numel(sens.G_scale)                                     % irradiance
        r = run1(scale_weather(W0, sens.G_scale(i)), P0);
        S.G.(city)(i,:) = [r.SCR_total r.psi_PV r.specific_yield];
    end
    for i = 1:numel(sens.ev)                                          % EV timing
        P = P0;  P.ev.profile = sens.ev{i};  P = update_params(P);
        r = run1(W0, P);
        S.ev.(city)(i,:) = [r.SCR_direct r.SCR_total r.E_export r.psi_solar];
        S.ev_daily(:,i) = P.ev.daily;
    end
    % Cell temperature: simple NOCT correlation instead of the energy balance
    P = P0;  P.cfg.tc_model = 'noct';
    r = run1(W0, P);
    S.tc.(city) = [R.(city).E_PV_raw r.E_PV_raw R.(city).Tc_mean_prod r.Tc_mean_prod R.(city).psi_PV r.psi_PV];
    % Battery resistance x3 (DC resistance is typically above the 1 kHz AC value)
    P = P0;  P.batt.cell_R = 3*P0.batt.cell_R;  P = update_params(P);
    r = run1(W0, P);
    S.R3.(city) = [R.(city).Ex_dest_batt r.Ex_dest_batt R.(city).SCR_total r.SCR_total];
end
% Self-check: the baseline point of each sweep must reproduce the baseline run
for c = 1:numel(cities)
    city = cities{c};
    assert(abs(S.pv.(city)(sens.N_mod == P0.pv.N_mod, 1) - R.(city).SCR_total) < 1e-12);
    assert(abs(S.batt.(city)(sens.batt_f == 1, 1)         - R.(city).SCR_total) < 1e-12);
    assert(abs(S.G.(city)(sens.G_scale == 1, 1)           - R.(city).SCR_total) < 1e-12);
    assert(abs(S.ev.(city)(1, 2)                          - R.(city).SCR_total) < 1e-12);
end

%% 4. MONTE CARLO UNCERTAINTY PROPAGATION
% Only inputs whose range can be defended from a datasheet, the project brief or a published
% source. Each draw picks one weather year at random, samples the inputs uniformly, and applies
% the SAME draw to all three cities (paired), so city-vs-city comparisons use identical assumptions.
U = struct( ...
  'name', {{'G_scale', 'eta_ref', 'NOCT', 'nu_inv', 'nu_pcs', 'cell_R'}}, ...
  'lo',   [0.93, 0.97, 41, 0.96, 0.96, 0.30e-3], ...
  'hi',   [1.07, 1.03, 45, 0.98, 0.98, 0.90e-3], ...
  'why',  {{'NASA POWER GHI: ~0 % network bias vs BSRN, +/-7 % kept for the 1 deg grid cell and Hay-Davies transposition', ...
            'Trina NE19R datasheet: Pmax measuring tolerance +/-3 % (multiplier on eta_ref)', ...
            'Trina NE19R datasheet: NOCT 43 +/- 2 degC (h_free recalibrated each draw)', ...
            'Project brief: inverter efficiency 96-98 %', ...
            'Project brief: battery converter (PCS) efficiency 96-98 %', ...
            'REPT: 0.30 mOhm AC (1 kHz); DC resistance 2-3x AC, so 0.30-0.90 mOhm'}});
MC = struct('N', N_MC);
if N_MC > 0
    if exist('OCTAVE_VERSION', 'builtin'), rand('state', 2026); else, rng(2026, 'twister'); end
    % Random numbers are drawn in the same order as the run reported, so the draws match it:
    % 6 columns (the 6th is not used), then the PCS column, then the weather year.
    u  = rand(N_MC, 6);
    u  = [u(:, [1 2 3 4]) rand(N_MC, 1) u(:, 5)];   % -> G_scale, eta_ref, NOCT, nu_inv, nu_pcs, cell_R
    X  = repmat(U.lo, N_MC, 1) + u .* repmat(U.hi - U.lo, N_MC, 1);
    yr = ceil(rand(N_MC, 1) * numel(yrs));       % weather year index for each draw
    MC.X = X;  MC.yr = yr;
    fprintf('Monte Carlo: %d draws x %d cities ', N_MC, numel(cities));
    for i = 1:N_MC
        P = P0;
        P.pv.eta_ref  = P0.pv.eta_ref * X(i,2);
        P.pv.NOCT     = X(i,3);
        P.sys.nu_inv  = X(i,4);
        P.sys.nu_pcs  = X(i,5);
        P.batt.cell_R = X(i,6);
        P = update_params(P);
        for c = 1:numel(cities)
            city = cities{c};
            r = run1(scale_weather(Wy.(city){yr(i)}, X(i,1)), P);
            % columns: 1 SCR | 2 psi_PV | 3 eta_PV | 4-7 psi_PV by season | 8 battery Ex_dest
            MC.(city)(i,:) = [r.SCR_total r.psi_PV r.eta_PV r.s.psi_PV r.Ex_dest_batt];
        end
        if mod(i, 20) == 0, fprintf('.'); end
    end
    fprintf('\n');
    % Questions the Monte Carlo answers
    q = @(x) [prctile_(x, 5) prctile_(x, 50) prctile_(x, 95)];
    for c = 1:numel(cities)
        city = cities{c};  M = MC.(city);
        MC.summary.(city) = [q(100*M(:,1)); q(100*M(:,2))];          % SCR, psi_PV [%]
        MC.p_monsoon_gt_winter.(city) = mean(M(:,6) > M(:,4));      % psi_PV monsoon > winter
    end
    J = MC.Jodhpur;  B = MC.Bengaluru;  G = MC.Guwahati;
    MC.p_cov_rank = mean(J(:,1) > B(:,1) & B(:,1) > G(:,1));       % coverage J > B > G
    MC.p_psi_JB   = mean(J(:,2) < B(:,2));                          % psi_PV Jodhpur below Bengaluru
    MC.p_psi_JG   = mean(J(:,2) < G(:,2));                          % psi_PV Jodhpur below Guwahati
end

%% 5. PRINT RESULTS
fprintf('=== STATION: %.1f kWp (%d x %d W, %.0f m2), %.1f kWh LFP (%.0f V), EV %.0f kWh/day ===\n', ...
    P0.pv.kWp, P0.pv.N_mod, P0.pv.P_mod, P0.pv.A, P0.batt.capacity_kWh, P0.batt.V_nom, sum(P0.ev.daily));
fprintf('Cell-temperature model calibrated to NOCT: h_free = %.2f W/m2K\n', P0.pv.h_free);
for c = 1:numel(cities)
    city = cities{c};  r = R.(city);
    fprintf('\n--- %s (%s mean) ---\n', city, P0.cfg.source_label);
    fprintf('POA irradiation %.0f kWh/m2 | mean Ta %.1f C | energy-weighted Tc %.1f C (max %.1f)\n', ...
        r.G_annual, r.Ta_mean, r.Tc_mean_prod, r.Tc_max);
    fprintf('Specific yield %.0f kWh/kWp | PR %.3f | low-light loss %.1f %% | temperature loss %.1f %%\n', ...
        r.specific_yield, r.PR, 100*r.lowlight_loss, 100*r.temp_loss);
    fprintf('Sunlight exergy content %.3f (diffuse share %.1f %%) | psi_PV by season %s\n', ...
        r.psi_sun, 100*r.diffuse_frac, mat2str(round(1e4*r.s.psi_PV)/100));
    fprintf('eta_PV %.2f %% | psi_PV %.2f %% | eta_solar %.2f %% | psi_solar %.2f %% | psi_sys %.1f %%\n', ...
        100*r.eta_PV, 100*r.psi_PV, 100*r.eta_solar, 100*r.psi_solar, 100*r.psi_sys);
    fprintf('SCR direct %.1f %% | SCR total %.1f %% | grid dependency %.1f %% | export %.0f kWh\n', ...
        100*r.SCR_direct, 100*r.SCR_total, 100*r.grid_dep, r.E_export);
    fprintf('Ex destroyed [kWh/yr]: PV %.0f (opt %.0f, heat %.0f, internal %.0f) | wiring %.0f | inverter %.0f | PCS %.0f | battery %.0f\n', ...
        r.Ex_dest_PV, r.Ex_PV_opt, r.Ex_PV_heat, r.Ex_PV_int, r.Ex_dest_wir, r.Ex_dest_inv, r.Ex_dest_pcs, r.Ex_dest_batt);
    fprintf('Battery: %.0f EFC/yr, SOH after 1 yr %.4f, max Tb rise %.1f K\n', r.EFC, r.SOH_end, r.dTb_max);
    for k = 1:numel(yrs)
        fprintf('  %d: POA %.0f | SCR %.1f %% | psi_PV %.2f %%\n', yrs(k), ...
            Y.(city)(k,1), 100*Y.(city)(k,2), 100*Y.(city)(k,3));
    end
    fprintf('  EV profile (SCR %%): %s\n', mat2str(round(1000*S.ev.(city)(:,2)')/10));
    if N_MC > 0
        s = MC.summary.(city);
        fprintf('  MC 5/50/95: SCR %.1f/%.1f/%.1f %% | psi_PV %.2f/%.2f/%.2f %%\n', s(1,:), s(2,:));
        fprintf('  P(psi monsoon > winter) %.2f\n', MC.p_monsoon_gt_winter.(city));
    end
end
if N_MC > 0
    fprintf('\nP(coverage J>B>G) %.2f | P(psi_J < psi_B) %.2f | P(psi_J < psi_G) %.2f\n', ...
        MC.p_cov_rank, MC.p_psi_JB, MC.p_psi_JG);
end

%% 6. SAVE TABLES AND FIGURES
save(fullfile(P0.cfg.outR, 'results.mat'), 'R', 'S', 'Y', 'MC', 'U', 'sens', 'P0', 'yrs', '-v7');
export_tables(R, S, Y, MC, U, sens, cities, yrs, P0);
make_plots(R, S, Y, MC, sens, cities, yrs, Wx, SIM, P0);
fprintf('\nDone. Tables in %s, figures in %s.\n', P0.cfg.outR, P0.cfg.outF);
clear source;
