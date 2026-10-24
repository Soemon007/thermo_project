% main.m
% Thermodynamic feasibility of a solar-powered EV charging station
% Jodhpur, Bengaluru, Guwahati  |  CL207 Thermodynamics, final run
%
% PIPELINE (one city at a time, identical station design everywhere)
%   params -> load_weather -> simulate_station [pv_model -> ems_dispatch ->
%   battery_model, hour by hour] -> postprocess -> economics -> make_plots
%
%   1. Baseline: NASA POWER 2021-2023 run back to back; results are 3-year means
%   2. Year-by-year runs (weather variability)
%   3. One-at-a-time sensitivity (array, battery, irradiance, EV profile, model choices)
%   4. Monte Carlo over six inputs with defensible ranges (see uncertainty_inputs below)
%
% Only climate (weather files), tariff and grid emission factor differ between cities.
% Everything else is in src/params.m.  Runs in MATLAB R2016b+ and GNU Octave 6+.
%   >> main                        % main case, NASA POWER 2021-2023  (~25 min, Monte Carlo included)
%   >> source = 'ERA5'; main       % cross-check, PVGIS-ERA5 2023 only (~3 min, no Monte Carlo)

if ~exist('source', 'var'), clear; source = ''; end
clc; close all;
here = fileparts(mfilename('fullpath'));  if isempty(here), here = pwd; end
if exist(fullfile(here, 'params.m'), 'file')      % old flat layout would shadow src/
    error('Old top-level .m files found next to main.m. Run tidy_folder.command once (see README).');
end
addpath(fullfile(here, 'src'));
P0 = params();
if ~isempty(source), P0.cfg.source = source; end
cities = {'Jodhpur', 'Bengaluru', 'Guwahati'};
wdir = fullfile(here, 'data', 'weather');
switch P0.cfg.source
    case 'NASAPOWER'
        yrs = P0.cfg.years;
        P0.cfg.source_label = sprintf('NASA POWER %d-%d', yrs(1), yrs(end));
        files = @(c) arrayfun(@(y) fullfile(wdir, sprintf('NASAPOWER_%s_%d.csv', c, y)), yrs, 'UniformOutput', false);
        N_MC = 200;
    case 'ERA5'
        yrs = 2023;
        P0.cfg.source_label = 'PVGIS-ERA5 2023';
        files = @(c) {fullfile(wdir, sprintf('ERA5_%s_2023.csv', c))};
        N_MC = 0;
    otherwise, error('Unknown weather source %s', P0.cfg.source);
end
P0.cfg.outR = fullfile(here, 'results', P0.cfg.source);
P0.cfg.outF = fullfile(here, 'figures', P0.cfg.source);
if ~exist(P0.cfg.outR, 'dir'), mkdir(P0.cfg.outR); end
if ~exist(P0.cfg.outF, 'dir'), mkdir(P0.cfg.outF); end
fprintf('Weather source: %s | EV profile: %s\n', P0.cfg.source_label, P0.ev.profile);
run1 = @(W, P) postprocess(simulate_station(W, P), W, P);

%% 1. BASELINE: fixed design, three climates, all years back to back
R = struct();  Wx = struct();  SIM = struct();  Wy = struct();
for c = 1:numel(cities)
    city = cities{c};
    fl = files(city);
    W   = load_weather(fl, P0.cfg);
    sim = simulate_station(W, P0);
    r   = postprocess(sim, W, P0);
    r.econ = economics(r, P0, city);
    % PV-only variant (no battery): same economics layer, used to isolate the battery's cost
    Pnb = P0;  Pnb.batt.n_parallel = 0;  Pnb = update_params(Pnb);
    rnb = run1(W, Pnb);
    r.econ_pv = economics(rnb, Pnb, city);
    r.SCR_total_nobatt = rnb.SCR_total;
    assert(r.res_energy < 1e-8, 'First Law balance does not close for %s', city);
    assert(r.res_exergy < 1e-8, 'Exergy balance does not close for %s', city);
    assert(r.min_Ex_int >= -1e-9, 'Negative PV internal exergy destruction for %s', city);
    R.(city) = r;  Wx.(city) = W;  SIM.(city) = sim;
    for k = 1:numel(fl), Wy.(city){k} = load_weather(fl{k}, P0.cfg); end
end

%% 2. YEAR BY YEAR (same design, each weather year on its own)
%   columns: POA [kWh/m2] | SCR | psi_PV | eta_PV | psi_sun | yield | LCOE | NPV [lakh] | psi_PV by season (4)
Y = struct();
for c = 1:numel(cities)
    city = cities{c};
    for k = 1:numel(yrs)
        r = run1(Wy.(city){k}, P0);  e = economics(r, P0, city);
        Y.(city)(k,:) = [r.G_annual r.SCR_total r.psi_PV r.eta_PV r.psi_sun r.specific_yield ...
                         e.LCOE_system e.NPV/1e5 r.s.psi_PV];
    end
end

%% 3. SENSITIVITY (one factor at a time, same simulate_station as baseline)
sens.N_mod   = [40 60 80 100 120];          % PV array size [modules]
sens.batt_f  = [0 0.5 1 1.5 2];             % battery size, x baseline (93.2 kWh)
sens.G_scale = [0.8 0.9 1.0 1.1 1.2 1.3];   % irradiance data uncertainty
sens.ev      = {'public', 'workplace', 'residential', 'synthetic'};   % EV timing (same 222 kWh/day)
for c = 1:numel(cities)
    city = cities{c};  W0 = Wx.(city);
    for i = 1:numel(sens.N_mod)
        P = P0;  P.pv.N_mod = sens.N_mod(i);  P = update_params(P);
        r = run1(W0, P);
        S.pv.(city)(i,:) = [r.SCR_total r.psi_solar r.E_export/r.E_PV_ac r.Ex_dest_tot];
    end
    for i = 1:numel(sens.batt_f)
        P = P0;  P.batt.n_parallel = sens.batt_f(i);  P = update_params(P);
        r = run1(W0, P);
        S.batt.(city)(i,:) = [r.SCR_total r.psi_solar r.E_export r.Ex_dest_batt + r.Ex_dest_pcs];
    end
    for i = 1:numel(sens.G_scale)
        r = run1(scale_weather(W0, sens.G_scale(i)), P0);
        S.G.(city)(i,:) = [r.SCR_total r.psi_PV r.specific_yield];
    end
    for i = 1:numel(sens.ev)
        P = P0;  P.ev.profile = sens.ev{i};  P = update_params(P);
        r = run1(W0, P);  e = economics(r, P, city);
        S.ev.(city)(i,:) = [r.SCR_direct r.SCR_total r.E_export e.LCOE_system e.NPV/1e5 r.psi_solar];
        S.ev_daily(:,i) = P.ev.daily;
    end
    % PV model variants: Checkpoint-2 model vs each improvement vs both (final)
    %   rows: 1 petela + no low-light | 2 split exergy only | 3 low-light only | 4 both (baseline)
    variants = {'petela', false; 'split', false; 'petela', true; 'split', true};
    for v = 1:4
        P = P0;  P.cfg.exergy_model = variants{v,1};  P.cfg.lowlight = variants{v,2};
        r = run1(W0, P);
        S.model.(city)(v,:) = [r.psi_PV r.eta_PV r.psi_sun r.specific_yield r.SCR_total r.s.psi_PV];
        if v == 1, S.model_m_old.(city) = r.m.psi_PV; end
    end
    % Cell-temperature model: NOCT correlation vs convection-radiation balance
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
    assert(abs(S.pv.(city)(sens.N_mod == P0.pv.N_mod, 1)  - R.(city).SCR_total) < 1e-12);
    assert(abs(S.batt.(city)(sens.batt_f == 1, 1)          - R.(city).SCR_total) < 1e-12);
    assert(abs(S.G.(city)(sens.G_scale == 1, 1)            - R.(city).SCR_total) < 1e-12);
    assert(abs(S.ev.(city)(1, 2)                           - R.(city).SCR_total) < 1e-12);
    assert(abs(S.model.(city)(4, 1)                        - R.(city).psi_PV)    < 1e-12);
end

%% 4. MONTE CARLO UNCERTAINTY PROPAGATION
% Only inputs whose realistic range can be defended from a datasheet, the project brief or a
% published source. Each draw: one weather year picked at random, the six inputs sampled
% uniformly, and the SAME draw applied to all three cities (paired), so city-vs-city
% comparisons see identical assumptions. Design, tariffs and emission factor are not sampled.
U = struct( ...
  'name',  {{'G_scale', 'eta_ref', 'NOCT', 'nu_conv', 'cell_R', 'batt_price'}}, ...
  'lo',    [0.93, 0.97, 41, 0.96, 0.30e-3, 16000], ...
  'hi',    [1.07, 1.03, 45, 0.98, 0.90e-3, 25000], ...
  'why',   {{'NASA POWER GHI: ~0 % network bias vs BSRN, +/-7 % kept for the 1 deg grid cell and Hay-Davies transposition', ...
             'Trina NE19R datasheet: Pmax measuring tolerance +/-3 % (multiplier on eta_ref)', ...
             'Trina NE19R datasheet: NOCT 43 +/- 2 degC (h_free recalibrated each draw)', ...
             'Project brief: inverter and PCS efficiency 96-98 % (each drawn separately)', ...
             'REPT: 0.30 mOhm AC (1 kHz); DC resistance 2-3x AC, so 0.30-0.90 mOhm', ...
             'C&I LFP quotes INR 16-25k/kWh installed (economics only)'}});
MC = struct('N', N_MC);
if N_MC > 0
    if exist('OCTAVE_VERSION', 'builtin'), rand('state', 2026); else, rng(2026, 'twister'); end
    X  = repmat(U.lo, N_MC, 1) + rand(N_MC, numel(U.lo)) .* repmat(U.hi - U.lo, N_MC, 1);
    X(:, end+1) = rand(N_MC, 1);                       % second converter (PCS) efficiency, same range
    X(:, end)   = U.lo(4) + X(:, end)*(U.hi(4) - U.lo(4));
    yr = ceil(rand(N_MC, 1) * numel(yrs));             % weather year index
    MC.X = X;  MC.yr = yr;
    fprintf('Monte Carlo: %d draws x %d cities ', N_MC, numel(cities));
    for i = 1:N_MC
        P = P0;
        P.pv.eta_ref = P0.pv.eta_ref * X(i,2);
        P.pv.NOCT    = X(i,3);
        P.sys.nu_inv = X(i,4);  P.sys.nu_pcs = X(i,7);
        P.batt.cell_R = X(i,5);
        P.econ.batt_per_kWh = X(i,6);
        P = update_params(P);
        for c = 1:numel(cities)
            city = cities{c};
            r = run1(scale_weather(Wy.(city){yr(i)}, X(i,1)), P);
            e = economics(r, P, city);
            MC.(city)(i,:) = [r.SCR_total r.psi_PV r.eta_PV r.s.psi_PV e.LCOE_system e.NPV/1e5 r.Ex_dest_batt];
        end
        if mod(i, 20) == 0, fprintf('.'); end
    end
    fprintf('\n');
    % Questions the Monte Carlo answers
    q = @(x) [prctile_(x, 5) prctile_(x, 50) prctile_(x, 95)];
    for c = 1:numel(cities)
        city = cities{c};  M = MC.(city);
        MC.summary.(city) = [q(100*M(:,1)); q(100*M(:,2)); q(M(:,8)); q(M(:,9))];   % SCR, psi_PV, LCOE, NPV
        MC.p_monsoon_gt_winter.(city) = mean(M(:,6) > M(:,4));      % psi_PV monsoon > winter
        MC.p_npv_pos.(city)           = mean(M(:,9) > 0);
    end
    J = MC.Jodhpur;  B = MC.Bengaluru;  G = MC.Guwahati;
    MC.p_cov_rank = mean(J(:,1) > B(:,1) & B(:,1) > G(:,1));       % coverage J > B > G
    MC.p_psi_JB   = mean(J(:,2) < B(:,2));                          % psi_PV Jodhpur below Bengaluru
    MC.p_psi_JG   = mean(J(:,2) < G(:,2));                          % psi_PV Jodhpur below Guwahati
    MC.p_npv_G_best = mean(G(:,9) > J(:,9) & G(:,9) > B(:,9));      % Guwahati best NPV
end

%% 5. PRINT RESULTS
fprintf('=== STATION: %.1f kWp (%d x %d W, %.0f m2), %.1f kWh LFP (%.0f V), EV %.0f kWh/day ===\n', ...
    P0.pv.kWp, P0.pv.N_mod, P0.pv.P_mod, P0.pv.A, P0.batt.capacity_kWh, P0.batt.V_nom, sum(P0.ev.daily));
fprintf('Cell-temperature model calibrated to NOCT: h_free = %.2f W/m2K\n', P0.pv.h_free);
for c = 1:numel(cities)
    city = cities{c};  r = R.(city);  e = r.econ;
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
    fprintf('LCOE %.2f INR/kWh vs tariff %.2f | NPV %.1f lakh | payback %.1f yr | CO2 avoided %.1f t/yr\n', ...
        e.LCOE_system, e.tariff, e.NPV/1e5, e.payback_simple, e.CO2_avoided_t_per_yr);
    e = r.econ_pv;
    fprintf('PV-only: LCOE %.2f INR/kWh | NPV %.1f lakh | payback %.1f yr | SCR %.1f %%\n', ...
        e.LCOE_system, e.NPV/1e5, e.payback_simple, 100*r.SCR_total_nobatt);
    for k = 1:numel(yrs)
        fprintf('  %d: POA %.0f | SCR %.1f %% | psi_PV %.2f %% | NPV %.1f lakh\n', yrs(k), ...
            Y.(city)(k,1), 100*Y.(city)(k,2), 100*Y.(city)(k,3), Y.(city)(k,8));
    end
    fprintf('  EV profile (SCR %%): %s\n', mat2str(round(1000*S.ev.(city)(:,2)')/10));
    if N_MC > 0
        s = MC.summary.(city);
        fprintf('  MC 5/50/95: SCR %.1f/%.1f/%.1f %% | psi_PV %.2f/%.2f/%.2f %% | NPV %.1f/%.1f/%.1f lakh\n', s(1,:), s(2,:), s(4,:));
        fprintf('  P(psi monsoon > winter) %.2f | P(NPV > 0) %.2f\n', MC.p_monsoon_gt_winter.(city), MC.p_npv_pos.(city));
    end
end
if N_MC > 0
    fprintf('\nP(coverage J>B>G) %.2f | P(psi_J < psi_B) %.2f | P(psi_J < psi_G) %.2f | P(Guwahati best NPV) %.2f\n', ...
        MC.p_cov_rank, MC.p_psi_JB, MC.p_psi_JG, MC.p_npv_G_best);
end

%% 6. SAVE + PLOTS
save(fullfile(P0.cfg.outR, 'results.mat'), 'R', 'S', 'Y', 'MC', 'U', 'sens', 'P0', 'yrs', '-v7');
export_tables(R, S, Y, MC, U, sens, cities, yrs, P0);
make_plots(R, S, Y, MC, sens, cities, yrs, Wx, SIM, P0);
fprintf('\nDone. Tables in %s, figures in %s.\n', P0.cfg.outR, P0.cfg.outF);
clear source;
