% main.m
% Thermodynamic Optimization of a Solar-Powered EV Charging Station
% Feasibility study: Jodhpur, Bengaluru, Guwahati  (CL207, Checkpoint 2)
%
% WHAT THIS SCRIPT DOES
%   For each city it runs an 8760-hour (1 timestep = 1 h) simulation of
%   PV -> converter -> EMS -> battery / EV / grid, and logs First Law
%   (energy) and Second Law (exergy) flows. Annual and monthly numbers come
%   from post-processing the hourly output, never from averaged inputs
%   (PV efficiency and exergy are nonlinear in G and T -> Jensen's inequality).
%
% SYSTEM BOUNDARY (exergy balance, closed hour by hour):
%   IN  : PV solar exergy (Petela) + grid import
%   OUT : electricity delivered to EV + grid export
%   DEST: PV cell + converter + battery (I^2R)
%   STORED: change in battery stored energy (electrical exergy = energy)
%   Closure per hour:  In - Out - Dest - dE_batt = 0   (checked below)
%
% ASSUMPTIONS (state these in the report)
%   - Converter sits only in the PV path (PV -> AC bus). Grid import and
%     export are lossless. Battery is charged from PV surplus only.
%   - Battery is on the AC bus side of the converter (no 2nd conversion loss).
%   - Battery loss is I^2R only; charge/discharge efficiency follows from it.
%   - Weather below is SYNTHETIC. Replace with PVGIS/NSRDB for real results.
%
% Requires MATLAB R2016b+ (local functions in scripts) and economics.m in the
% same folder.

clear; clc; close all;

%% 1. SYSTEM PARAMETERS (fixed system-wide; only climate varies)
% --- PV array ---
pv.A        = 50;       % total PV area [m^2]
pv.eta_ref  = 0.20;     % reference efficiency at STC (25 degC, 1000 W/m^2)
pv.beta     = 0.004;    % efficiency temperature coefficient [1/degC]
pv.NOCT     = 45;       % nominal operating cell temperature [degC]
pv.T_sun    = 5778;     % effective sun temperature for Petela exergy [K]
pv.kWp      = pv.eta_ref * pv.A * 1.0;   % rated DC power at 1 kW/m^2 [kWp]

% --- Battery (representative LFP pack) ---
batt.capacity_kWh = 100;    % nameplate energy capacity [kWh]
batt.V_nom        = 400;    % nominal DC voltage [V]
batt.R_internal   = 0.05;   % lumped internal resistance [Ohm]
batt.SOC_min      = 0.10;   % lower SOC limit
batt.SOC_max      = 0.95;   % upper SOC limit
batt.SOC_init     = 0.50;   % initial SOC
batt.C_rate_max   = 0.5;    % max charge/discharge power = C_rate * capacity [1/h]  (assumption)
batt.P_max_kW     = batt.C_rate_max * batt.capacity_kWh;   % terminal power limit [kW]
batt.fade_per_EFC = 5e-5;   % capacity fade per equivalent full cycle (empirical, assumption)

% --- Converter / inverter (lumped, from datasheet) ---
sys.nu = 0.97;          % fixed efficiency, typically 0.96-0.98

% --- Weather source ---
cfg.use_real_weather = false;   % true -> read PVGIS hourly CSVs (see read_pvgis)
cfg.pvgis_file = @(city) [lower(city) '_pvgis.csv'];

cities = {'Jodhpur', 'Bengaluru', 'Guwahati'};
month_names = {'Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'};
N = 8760;
mon = month_index(N);           % month (1..12) of every hour

%% 2. BASELINE RUN: 8760-h SIMULATION PER CITY
results = struct();
weather = struct();
for c = 1:numel(cities)
    city = cities{c};

    % Hourly irradiance G [W/m^2], ambient T [degC], EV load [kW]
    [G, Ta, P_EV] = load_weather_and_demand(city, cfg);
    weather.(city) = struct('G', G, 'Ta', Ta, 'P_EV', P_EV);

    % Full hourly simulation (PV -> converter -> EMS -> battery)
    sim = simulate_station(G, Ta, P_EV, pv, batt, sys);

    % --- Post-processing: annual totals [kWh]; dt = 1 h so kW -> kWh ---
    r.E_EV          = sum(P_EV);
    r.E_PV_dc       = sum(sim.P_PV);
    r.E_PV_to_EV    = sum(sim.P_PV_to_EV);
    r.E_batt_to_EV  = sum(sim.P_batt_discharge);
    r.E_import      = sum(sim.P_grid_import);
    r.E_export      = sum(sim.P_grid_export);
    r.Ex_in_PV      = sum(sim.Ex_in_PV);
    r.Ex_dest_PV    = sum(sim.Ex_dest_PV);
    r.Ex_dest_conv  = sum(sim.Ex_dest_conv);
    r.Ex_dest_batt  = sum(sim.Ex_dest_batt);
    r.Ex_dest_total = r.Ex_dest_PV + r.Ex_dest_conv + r.Ex_dest_batt;
    r.dE_stored     = sim.E_batt(end) - sim.E_batt(1);

    % Solar coverage ratio, SCR = E(PV->EV) / E(EV,total)  (project definition)
    r.SCR_direct = r.E_PV_to_EV / r.E_EV;
    % Same, but also counting solar energy that went via the battery
    % (battery is charged from PV only, so its discharge is solar-origin).
    r.SCR_total  = (r.E_PV_to_EV + r.E_batt_to_EV) / r.E_EV;
    r.grid_dependency = r.E_import / r.E_EV;

    % System exergy efficiency: useful exergy out (EV + export + stored) / exergy in.
    % NOTE: grid import passes through losslessly, so a grid-heavy city
    % gets pulled toward 100%. Use psi_solar to compare solar performance.
    r.psi_system = (r.E_EV + r.E_export + r.dE_stored) / (r.Ex_in_PV + r.E_import);
    % Solar-chain exergy efficiency: fraction of solar exergy NOT destroyed.
    r.psi_solar  = 1 - r.Ex_dest_total / r.Ex_in_PV;
    % PV cell only, psi_PV = Ex_out / Ex_in (compare to literature 12-20%)
    r.psi_PV     = r.E_PV_dc / r.Ex_in_PV;

    % Validation gates
    r.yield_kWh_per_kWp = r.E_PV_dc / pv.kWp;        % compare to PVGIS (~10%)
    r.balance_residual  = max(abs(sim.residual));    % must be ~0 [kWh in any hour]

    % Monthly breakdown (accumarray sums hourly values by month)
    msum = @(x) accumarray(mon, x, [12 1]);
    r.m_SCR_direct = msum(sim.P_PV_to_EV) ./ msum(P_EV);
    r.m_psi_PV     = msum(sim.P_PV) ./ max(msum(sim.Ex_in_PV), eps);
    r.m_import     = msum(sim.P_grid_import);
    r.m_dest_PV    = msum(sim.Ex_dest_PV);
    r.m_dest_conv  = msum(sim.Ex_dest_conv);
    r.m_dest_batt  = msum(sim.Ex_dest_batt);

    r.SOH_end  = sim.SOH_end;
    r.T_c_max  = max(sim.T_c);

    % Economics + CO2 reporting layer (economics.m, must be in the same folder)
    r.econ = economics(r, pv, batt, sys, city);
    results.(city) = r;
    clear r;
end

%% 3. SENSITIVITY: PV AREA (all cities, same simulate_station as baseline)
test_areas = [30, 50, 70, 90];                 % [m^2]
sens = struct();
for c = 1:numel(cities)
    city = cities{c};
    w = weather.(city);                        % reuse the SAME weather as baseline
    s_SCR = zeros(numel(test_areas), 1);
    s_psi = zeros(numel(test_areas), 1);
    s_psiS = zeros(numel(test_areas), 1);
    for i = 1:numel(test_areas)
        pv_i = pv;  pv_i.A = test_areas(i);
        sim_i = simulate_station(w.G, w.Ta, w.P_EV, pv_i, batt, sys);
        dest_i = sum(sim_i.Ex_dest_PV) + sum(sim_i.Ex_dest_conv) + sum(sim_i.Ex_dest_batt);
        dE_i   = sim_i.E_batt(end) - sim_i.E_batt(1);
        s_SCR(i)  = sum(sim_i.P_PV_to_EV) / sum(w.P_EV);
        s_psi(i)  = (sum(w.P_EV) + sum(sim_i.P_grid_export) + dE_i) / ...
                    (sum(sim_i.Ex_in_PV) + sum(sim_i.P_grid_import));
        s_psiS(i) = 1 - dest_i / sum(sim_i.Ex_in_PV);
    end
    sens.(city) = struct('SCR', s_SCR, 'psi_system', s_psi, 'psi_solar', s_psiS);
end

% Self-check: the 50 m^2 sensitivity point must equal the baseline exactly
for c = 1:numel(cities)
    city = cities{c};
    i50 = find(test_areas == pv.A, 1);
    if ~isempty(i50)
        assert(abs(sens.(city).SCR(i50) - results.(city).SCR_direct) < 1e-12, ...
            'Sensitivity baseline mismatch for %s', city);
    end
end

%% 4. DISPLAY RESULTS
disp('--- BASELINE FEASIBILITY RESULTS (fixed station design) ---');
fprintf('PV: %.1f kWp (%.0f m^2) | Battery: %.0f kWh | EV load: %.0f kWh/day\n', ...
    pv.kWp, pv.A, batt.capacity_kWh, sum(weather.Jodhpur.P_EV)/365);
for c = 1:numel(cities)
    city = cities{c};  r = results.(city);
    fprintf('\nCity: %s\n', city);
    fprintf('  Specific yield (DC):        %.0f kWh/kWp/yr\n', r.yield_kWh_per_kWp);
    fprintf('  SCR direct (PV->EV):        %.1f %%\n', 100*r.SCR_direct);
    fprintf('  SCR incl. battery:          %.1f %%\n', 100*r.SCR_total);
    fprintf('  Grid dependency:            %.1f %%\n', 100*r.grid_dependency);
    fprintf('  psi_PV (cell):              %.1f %%\n', 100*r.psi_PV);
    fprintf('  psi_solar (PV+conv+batt):   %.1f %%\n', 100*r.psi_solar);
    fprintf('  psi_system (incl. grid):    %.1f %%\n', 100*r.psi_system);
    fprintf('  Ex_dest PV:                 %.0f kWh (%.1f %%)\n', r.Ex_dest_PV,   100*r.Ex_dest_PV  /r.Ex_dest_total);
    fprintf('  Ex_dest Converter:          %.0f kWh (%.1f %%)\n', r.Ex_dest_conv, 100*r.Ex_dest_conv/r.Ex_dest_total);
    fprintf('  Ex_dest Battery:            %.0f kWh (%.1f %%)\n', r.Ex_dest_batt, 100*r.Ex_dest_batt/r.Ex_dest_total);
    fprintf('  Grid export:                %.0f kWh | Peak cell T: %.1f degC | SOH end: %.4f\n', ...
        r.E_export, r.T_c_max, r.SOH_end);
    fprintf('  Max hourly balance residual: %.2e kWh\n', r.balance_residual);
    assert(r.balance_residual < 1e-9, 'Exergy balance does not close for %s', city);

    % --- Economics (placeholder inputs, see economics.m) ---
    e = r.econ;
    fprintf('  Capex (total):              INR %.2f lakh (battery %.0f %%)\n', ...
        e.capex.total/1e5, 100*e.capex.batt/e.capex.equip);
    fprintf('  LCOE, PV+batt+converter:    INR %.2f /kWh  (state tariff %.2f)\n', e.LCOE_system,  e.tariff);
    fprintf('  LCOE, PV+converter only:    INR %.2f /kWh\n', e.LCOE_PV_only);
    fprintf('  NPV (%d yr):                INR %.2f lakh\n', e.params.life_years, e.NPV/1e5);
    fprintf('  Payback simple / discounted: %.1f / %.1f yr\n', e.payback_simple, e.payback_discounted);
    fprintf('  CO2 avoided:                %.1f t/yr (%.0f t lifetime)\n', ...
        e.CO2_avoided_t_per_yr, e.CO2_avoided_t_life);
end

fprintf('\n--- SENSITIVITY: PV AREA ---\n');
for c = 1:numel(cities)
    city = cities{c};
    fprintf('%s\n', city);
    for i = 1:numel(test_areas)
        fprintf('  A = %2d m^2 (%.0f kWp) | SCR: %.1f %% | psi_solar: %.1f %% | psi_system: %.1f %%\n', ...
            test_areas(i), pv.eta_ref*test_areas(i), 100*sens.(city).SCR(i), ...
            100*sens.(city).psi_solar(i), 100*sens.(city).psi_system(i));
    end
end

%% 5. PLOTS (seasonal behaviour + exergy destruction split)
figure('Name', 'Monthly SCR');
hold on; grid on;
for c = 1:numel(cities), plot(1:12, 100*results.(cities{c}).m_SCR_direct, '-o', 'LineWidth', 1.5); end
set(gca, 'XTick', 1:12, 'XTickLabel', month_names);
ylabel('Direct solar coverage ratio [%]'); legend(cities, 'Location', 'best');
title('Monthly SCR by city');

figure('Name', 'Monthly psi_PV');
hold on; grid on;
for c = 1:numel(cities), plot(1:12, 100*results.(cities{c}).m_psi_PV, '-o', 'LineWidth', 1.5); end
set(gca, 'XTick', 1:12, 'XTickLabel', month_names);
ylabel('PV cell exergy efficiency [%]'); legend(cities, 'Location', 'best');
title('Monthly psi_{PV} (cell-temperature de-rating visible in hot months)');

figure('Name', 'Exergy destruction split');
D = zeros(numel(cities), 3);
for c = 1:numel(cities)
    D(c, :) = [results.(cities{c}).Ex_dest_PV, results.(cities{c}).Ex_dest_conv, results.(cities{c}).Ex_dest_batt];
end
bar(D, 'stacked'); set(gca, 'XTickLabel', cities);
ylabel('Annual exergy destroyed [kWh]'); legend({'PV cell','Converter','Battery'}, 'Location', 'best');
title('Exergy destruction by subsystem');

%% ================= LOCAL FUNCTIONS =================

function sim = simulate_station(G, Ta, P_EV, pv, batt, sys)
% One full-year simulation for ONE city and ONE station design.
% Used for both the baseline and the sensitivity sweep so they cannot diverge.
% Inputs : G [W/m^2], Ta [degC], P_EV [kW], parameter structs
% Outputs: struct of hourly arrays (kW == kWh because dt = 1 h)
    dt = 1;                                    % timestep [h]
    N  = numel(G);

    % --- A. PV SUBSYSTEM (depends only on weather -> vectorised) ---
    [P_PV, Ex_in_PV, Ex_dest_PV, T_c] = pv_model(G, Ta, pv);

    % --- B. CONVERTER: fixed lumped efficiency on the PV path ---
    P_usable      = sys.nu * P_PV;             % AC power available to the EMS [kW]
    Ex_dest_conv  = (1 - sys.nu) * P_PV;       % electrical exergy lost = (1-nu)*P_in [kW]

    % Preallocate hourly logs
    P_PV_to_EV = zeros(N,1);  P_batt_charge = zeros(N,1);  P_batt_discharge = zeros(N,1);
    P_grid_export = zeros(N,1);  P_grid_import = zeros(N,1);
    Ex_dest_batt = zeros(N,1);  residual = zeros(N,1);
    E_batt = zeros(N+1,1);  SOC = zeros(N,1);

    E_batt(1)  = batt.SOC_init * batt.capacity_kWh;   % stored energy [kWh]
    discharged = 0;                                   % cumulative battery discharge [kWh]

    for t = 1:N
        % --- State of health: capacity fades with equivalent full cycles ---
        EFC = discharged / batt.capacity_kWh;
        SOH = 1 - batt.fade_per_EFC * EFC;
        cap = batt.capacity_kWh * SOH;                % usable capacity this hour [kWh]
        E_min = batt.SOC_min * cap;
        E_max = batt.SOC_max * cap;

        % --- C. EMS DISPATCH (priority rule, not optimised) ---
        %  PV -> EV first, surplus -> battery, remaining surplus -> grid export.
        %  Deficit: battery first, remaining deficit -> grid import.
        [P_PV_to_EV(t), P_batt_charge(t), P_batt_discharge(t), P_grid_export(t), P_grid_import(t)] = ...
            ems_dispatch(P_usable(t), P_EV(t), E_batt(t), E_min, E_max, batt, dt);

        % --- D. BATTERY: update stored energy and I^2R exergy destruction ---
        [E_batt(t+1), Ex_dest_batt(t)] = ...
            battery_model(E_batt(t), P_batt_charge(t), P_batt_discharge(t), batt, dt);

        discharged = discharged + P_batt_discharge(t) * dt;
        SOC(t) = E_batt(t+1) / cap;

        % --- Hourly exergy closure: In - Out - Destroyed - dE_stored = 0 ---
        ex_in   = Ex_in_PV(t) + P_grid_import(t);
        ex_out  = P_EV(t) + P_grid_export(t);           % EV is always fully served
        ex_dest = Ex_dest_PV(t) + Ex_dest_conv(t) + Ex_dest_batt(t);
        residual(t) = (ex_in - ex_out - ex_dest) * dt - (E_batt(t+1) - E_batt(t));
    end

    sim = struct('P_PV',P_PV, 'T_c',T_c, 'Ex_in_PV',Ex_in_PV, 'Ex_dest_PV',Ex_dest_PV, ...
        'Ex_dest_conv',Ex_dest_conv, 'Ex_dest_batt',Ex_dest_batt, ...
        'P_PV_to_EV',P_PV_to_EV, 'P_batt_charge',P_batt_charge, ...
        'P_batt_discharge',P_batt_discharge, 'P_grid_export',P_grid_export, ...
        'P_grid_import',P_grid_import, 'E_batt',E_batt, 'SOC',SOC, ...
        'residual',residual, 'SOH_end',SOH);
end

function [P_out, Ex_in, Ex_dest, T_c] = pv_model(G, Ta, pv)
% PV subsystem: First Law power and Second Law (Petela) exergy. Vectorised.
% G [W/m^2], Ta [degC]  ->  P_out, Ex_in, Ex_dest [kW], T_c [degC]
    sun = G > 0;                                   % night mask

    % 1. Cell temperature, linearised around NOCT: Tc = Ta + (NOCT-20)/800 * G
    T_c = Ta + ((pv.NOCT - 20) / 800) .* G;

    % 2. Efficiency de-rating: eta = eta_ref * [1 - beta*(Tc - 25)]
    eta = max(0, pv.eta_ref * (1 - pv.beta * (T_c - 25)));

    % 3. First Law: P_out = eta * A * G   (W -> kW)
    P_out = eta .* pv.A .* G / 1000;

    % 4. Second Law: Petela exergy of blackbody radiation, T0 = local ambient [K]
    %    Ex_in = A*G*[1 - (4/3)(T0/Tsun) + (1/3)(T0/Tsun)^4]
    r = (Ta + 273.15) / pv.T_sun;
    Ex_in = pv.A .* G .* (1 - (4/3)*r + (1/3)*r.^4) / 1000;   % kW

    % 5. Gouy-Stodola closure: electrical exergy out = P_out, rest is destroyed
    Ex_dest = max(0, Ex_in - P_out);

    % Night: no sun -> no output, no exergy; cell sits at ambient
    P_out(~sun) = 0;  Ex_in(~sun) = 0;  Ex_dest(~sun) = 0;  T_c(~sun) = Ta(~sun);
end

function [P_c_max, P_d_max] = battery_limits(E, E_min, E_max, batt, dt)
% Largest TERMINAL charge / discharge power allowed this hour [kW], limited by
% (i) the C-rate cap and (ii) remaining headroom/energy INCLUDING I^2R loss.
%   loss = k*P^2 with k = R*1000/V^2  [kW per kW^2]  (I = P*1000/V)
%   charge   : stored gain  = (P - k P^2)*dt = room   -> solve quadratic for P
%   discharge: stored drop  = (P + k P^2)*dt = avail  -> solve quadratic for P
    k     = batt.R_internal * 1000 / batt.V_nom^2;
    room  = max(0, E_max - E);                     % energy that can still be stored [kWh]
    avail = max(0, E - E_min);                     % energy that can still be drawn [kWh]
    if k > 0
        P_c_E = (1 - sqrt(max(0, 1 - 4*k*room/dt))) / (2*k);
        P_d_E = (-1 + sqrt(1 + 4*k*avail/dt)) / (2*k);
    else
        P_c_E = room/dt;  P_d_E = avail/dt;
    end
    P_c_max = min(batt.P_max_kW, P_c_E);
    P_d_max = min(batt.P_max_kW, P_d_E);
end

function [P_to_EV, P_to_batt, P_from_batt, P_to_grid, P_from_grid] = ...
        ems_dispatch(P_usable, P_EV, E, E_min, E_max, batt, dt)
% Priority-based EMS (not an optimiser). All powers are terminal powers [kW].
    [P_c_max, P_d_max] = battery_limits(E, E_min, E_max, batt, dt);
    P_to_batt = 0;  P_from_batt = 0;  P_to_grid = 0;  P_from_grid = 0;

    % Step 1: PV serves the EV directly
    P_to_EV = min(P_usable, P_EV);
    surplus = P_usable - P_to_EV;                  % PV left over
    deficit = P_EV - P_to_EV;                      % EV demand not met by PV

    % Step 2-3: surplus charges battery, remainder is exported
    if surplus > 0
        P_to_batt = min(surplus, P_c_max);
        P_to_grid = surplus - P_to_batt;
    end

    % Step 4-5: deficit drawn from battery, remainder imported
    % (surplus > 0 and deficit > 0 never happen in the same hour)
    if deficit > 0
        P_from_batt = min(deficit, P_d_max);
        P_from_grid = deficit - P_from_batt;
    end
end

function [E_new, Ex_dest_batt] = battery_model(E, P_charge, P_discharge, batt, dt)
% Lumped battery: stored-energy update with I^2R loss and exergy destruction.
%   Charge   : stored energy rises by (P_c - loss)
%   Discharge: stored energy falls by (P_d + loss)
% Joule heat is rejected at T0, so S_gen = I^2R/T0 and
% Ex_dest = T0*S_gen = I^2R  (T0 cancels).
    P_term = P_charge + P_discharge;               % only one is non-zero per hour
    I      = (P_term * 1000) / batt.V_nom;         % current [A]
    loss   = (I^2 * batt.R_internal) / 1000;       % I^2R [kW]

    E_new  = E + (P_charge - P_discharge - loss) * dt;
    Ex_dest_batt = loss;                           % [kW] -> kWh per 1-h step
end

function [G, Ta, P_EV] = load_weather_and_demand(city, cfg)
% Returns 8760x1 irradiance [W/m^2], ambient temperature [degC], EV load [kW].
    if cfg.use_real_weather
        [G, Ta] = read_pvgis(cfg.pvgis_file(city));
    else
        [G, Ta] = synthetic_weather(city);
    end

    % EV load: ONE deterministic 24-value daily curve, identical for all cities
    % hours 0-5: 2 kW | hours 6-17: 15 kW | hours 18-23: 5 kW
    daily_load = [repmat(2, 6, 1); repmat(15, 12, 1); repmat(5, 6, 1)];
    P_EV = repmat(daily_load, 365, 1);
end

function [G, Ta] = read_pvgis(file)
% Reads a PVGIS hourly TMY CSV (8760 rows). Check the header-line count and
% column names against YOUR download; PVGIS formats vary slightly by tool.
%   Expected columns: time, G(i), H_sun, T2m, WS10m, ...
    T  = readtable(file, 'NumHeaderLines', 10);
    T  = T(1:8760, :);                             % drop footer text
    G  = T.G_i_;                                   % irradiance on plane [W/m^2]
    Ta = T.T2m;                                    % 2 m air temperature [degC]
end

function [G, Ta] = synthetic_weather(city)
% Synthetic but physically structured weather (placeholder for PVGIS/NSRDB):
%   clear-sky irradiance from solar geometry x monthly clearness x daily cloud
%   noise; temperature = monthly mean + diurnal cosine peaking at 15:00.
% Fixed seed per city -> reproducible and identical across runs.
    N = 8760;
    switch city
        case 'Jodhpur'      % hot-arid, high clearness, mild monsoon dip
            lat = 26.3;  seed = 1;  sig = 0.08;  amp = 8;
            tau = [0.95 0.95 0.94 0.93 0.88 0.78 0.66 0.68 0.82 0.94 0.95 0.95];
            Tm  = [16.5 19.5 25 30.5 34 33.5 30.5 29 29.5 27 21.5 17.5];
        case 'Bengaluru'    % moderate temperature, moderate clearness
            lat = 13.0;  seed = 2;  sig = 0.15;  amp = 5;
            tau = [0.92 0.93 0.90 0.85 0.78 0.62 0.58 0.60 0.68 0.70 0.75 0.85];
            Tm  = [22 24.5 27 28.5 27 24.5 23.5 23.5 24 24 22.5 21.5];
        case 'Guwahati'     % humid, heavy monsoon cloud (Jun-Sep)
            lat = 26.2;  seed = 3;  sig = 0.20;  amp = 4.5;
            tau = [0.80 0.80 0.72 0.65 0.62 0.50 0.48 0.50 0.52 0.68 0.82 0.82];
            Tm  = [17.5 20 23.5 25.5 26.5 28 28.5 28.5 28 26.5 22.5 18.5];
        otherwise
            error('Unknown city: %s', city);
    end
    rng(seed);

    hrs = (0:N-1)';
    h   = mod(hrs, 24);                            % hour of day (0..23)
    d   = floor(hrs/24) + 1;                       % day of year (1..365)
    mon = month_index(N);

    % Solar geometry (local solar time, no longitude/equation-of-time correction)
    delta = 23.45 * sin(2*pi*(284 + d)/365);       % declination [deg]
    omega = 15 * (h + 0.5 - 12);                   % hour angle at mid-hour [deg]
    cosZ  = sind(lat)*sind(delta) + cosd(lat)*cosd(delta).*cosd(omega);
    cosZ  = max(cosZ, 0);                          % zero when the sun is down
    G_clear = 1000 * cosZ.^1.2;                    % clear-sky irradiance [W/m^2]

    % Cloudiness: monthly mean transmittance + daily random + small hourly flicker
    tau_m = tau(mon(1:24:end));  tau_m = tau_m(:); % per-day monthly mean (365x1)
    tau_d = min(1, max(0.05, tau_m + sig*randn(365,1)));
    flick = min(1.1, max(0.6, 1 + 0.08*randn(N,1)));
    G = G_clear .* tau_d(d) .* flick;              % night stays exactly 0
    G = min(G, 1100);

    % Temperature: monthly mean + diurnal wave (peak 15:00); cloudy days are cooler
    Ta = Tm(mon)' + amp*cos(2*pi*(h - 15)/24) - 5*(tau_m(d) - tau_d(d));
end

function mon = month_index(N)
% Month number (1..12) for each hour of a 365-day year.
    dim   = [31 28 31 30 31 30 31 31 30 31 30 31];
    edges = [0 cumsum(dim)];
    day   = floor((0:N-1)'/24) + 1;
    mon   = zeros(N, 1);
    for m = 1:12
        mon(day > edges(m) & day <= edges(m+1)) = m;
    end
end
