function P = params()
% params.m
% Every fixed, system-wide input in one place. Only climate (weather file),
% tariff and grid emission factor change between cities (see economics.m).
%
% Sources
%   PV  : Trina Solar Vertex N TSM-NE19R datasheet (DT-M-0093-B, 2024), 620 W bin
%   Batt: REPT BATTERO 280 Ah LFP cell, REPT ESS brochure (Sep 2026) +
%         supporting listing for internal resistance (<=0.30 mOhm)
%   Mounting: tilt 20 deg, azimuth 180 deg (due south), same for all cities
%             (matches the PVGIS download settings)

%% ---------------- PV array ----------------
pv.P_mod      = 620;                 % module STC rating [W]
pv.A_mod      = 2.382 * 1.134;       % module area [m^2] (2382 x 1134 mm)
pv.N_mod      = 80;                  % modules in the array (design choice, see report)
pv.A          = pv.N_mod * pv.A_mod; % total area [m^2]
pv.eta_ref    = pv.P_mod / (pv.A_mod * 1000);   % STC efficiency (= 0.230)
pv.beta       = 0.0029;              % Pmax temperature coefficient [1/K] (-0.29 %/K)
pv.NOCT       = 43;                  % datasheet NOCT [degC] (800 W/m2, 20 degC, 1 m/s)
pv.kWp        = pv.N_mod * pv.P_mod / 1000;     % array rating [kWp]
pv.tilt       = 20;                  % [deg], azimuth 180 (south)

% Optical (reflection) losses relative to STC normal incidence
pv.b0_iam     = 0.05;   % ASHRAE incidence-angle modifier for beam, IAM = 1 - b0(1/cos(theta)-1)
pv.iam_diff   = 0.95;   % effective IAM for sky-diffuse (approx., Martin & Ruiz 2001, 20 deg tilt)
pv.iam_grnd   = 0.65;   % effective IAM for ground-reflected
pv.alpha      = 0.90;   % fraction of transmitted irradiance absorbed by the laminate

% Thermal model: steady energy balance with convection + radiation (both faces)
pv.eps_front  = 0.84;   % glass emissivity
pv.eps_back   = 0.89;   % backsheet emissivity
pv.h_wind     = 3.0;    % forced-convection slope [W/m2K per m/s] (Watmuff-type)
pv.z_mount    = 3.0;    % module height above ground [m] (canopy-type station)
pv.T_sun      = 5778;   % sun blackbody temperature for Petela exergy [K]
% Free-convection term h_free [W/m2K] is calibrated so the balance reproduces
% the datasheet NOCT exactly (open circuit, 800 W/m2, 20 degC, 1 m/s):
pv.h_free     = calibrate_hfree(pv);

% Low-light efficiency (irradiance dependence), Huld et al. 2011, crystalline Si.
% Only the irradiance terms are used; the temperature dependence stays on the
% datasheet beta above (Huld's own temperature terms are fitted to older modules).
pv.k1_low = -0.017237;
pv.k2_low = -0.040465;

% Lumped DC wiring / mismatch loss (First Law "wiring" loss term)
pv.wiring_loss = 0.02;

%% ---------------- Battery (REPT 280 Ah LFP, 2 x Y52 modules = 1P104S) ----------------
batt.cell_Ah      = 280;
batt.cell_V       = 3.2;
batt.cell_R       = 0.30e-3;              % [Ohm]
batt.n_series     = 104;                  % 2 x Y52 (1P52S) modules in series
batt.n_parallel   = 1;
batt.V_nom        = batt.n_series * batt.cell_V;                        % 332.8 V
batt.capacity_kWh = batt.n_series * batt.n_parallel * batt.cell_Ah * batt.cell_V / 1000; % 93.2 kWh
batt.R_internal   = batt.n_series * batt.cell_R / batt.n_parallel;      % 31.2 mOhm
batt.SOC_min      = 0.10;                 % 10-90 % window (engineering assumption)
batt.SOC_max      = 0.90;
batt.SOC_init     = 0.50;
batt.C_rate_max   = 0.5;                  % standard current 140 A = 0.5C
batt.P_max_kW     = batt.C_rate_max * batt.capacity_kWh;
% Degradation: 8000 cycles (REPT brochure, 280 Ah) to 70 % SOH at 25 degC,
% Arrhenius temperature factor (Ea for LFP cycle ageing, Wang et al. 2011)
batt.cycle_life   = 8000;
batt.SOH_EOL      = 0.70;
batt.fade_per_EFC = (1 - batt.SOH_EOL) / batt.cycle_life;   % per equivalent full cycle
batt.Ea           = 31700;                % [J/mol]
batt.T_ref        = 298.15;               % [K]
% Lumped thermal model (assumptions: cell mass ~5.5 kg, cp ~1100 J/kgK,
% enclosure conductance 40 W/K)
batt.mass_kg      = 5.5 * batt.n_series * batt.n_parallel;
batt.cp           = 1100;
batt.UA           = 40;

%% ---------------- Power conversion ----------------
sys.nu_inv = 0.97;   % PV inverter (DC -> AC bus), fixed coefficient
sys.nu_pcs = 0.97;   % battery bidirectional converter, each direction

%% ---------------- EV load (fixed, identical for all cities, local time IST) ----------------
% Daily energy is fixed at 222 kWh/day (design demand). Only its hourly SHAPE comes from
% measured data: 45,700 charging sessions at Korean public, workplace and apartment chargers
% (Scientific Data 2024, CC BY 4.0), built by tools/make_ev_profile.py.
%   'public'      public area + public institution + public parking lot   -> main case
%   'workplace'   company chargers                                         -> sensitivity
%   'residential' apartment chargers                                       -> sensitivity
%   'synthetic'   Checkpoint-2 step profile 2/15/5 kW                       -> sensitivity
ev.daily_kWh = 222;
ev.profile   = 'public';
ev.daily     = ev_profile(ev.profile, ev.daily_kWh);   % [kW] x 24, IST hours 0..23

%% ---------------- Simulation options ----------------
cfg.tc_model  = 'balance';    % 'balance' (convection+radiation) or 'noct'
cfg.utc_shift = 6;            % rows are UTC hh:30 (hour mean) -> IST (hh+6):00
% Weather source. All files use the PVGIS column layout (data/weather/):
%   'NASAPOWER' : NASA POWER hourly 2021-2023 (CERES satellite irradiance), transposed to
%                 the 20 deg plane with Hay-Davies (tools/make_power_csv.py) -> main case
%   'ERA5'      : PVGIS-ERA5 hourly 2023 as downloaded from PVGIS             -> cross-check
cfg.source    = 'NASAPOWER';
cfg.years     = [2021 2022 2023];   % NASA POWER years, run back to back (3-year mean)
cfg.G_scale   = 1.0;          % irradiance multiplier (data-uncertainty sensitivity)
cfg.exergy_model = 'split';   % 'split' = beam Petela + diluted diffuse; 'petela' = Checkpoint-2 model
cfg.lowlight     = true;      % Huld low-light efficiency factor on/off

%% ---------------- Economics overrides (Monte Carlo) ----------------
econ = struct();              % fields set here replace econ_params() values, e.g. econ.batt_per_kWh

P = struct('pv', pv, 'batt', batt, 'sys', sys, 'ev', ev, 'cfg', cfg, 'econ', econ);
end
