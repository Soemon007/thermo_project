function ec = economics(r, pv, batt, sys, city)
% economics.m
% Economic and CO2 reporting layer for the solar EV charging station.
% This is a REPORTING layer on top of the simulation, not an optimiser.
%
% Call (from main.m, after the annual results struct r is built):
%     r.econ = economics(r, pv, batt, sys, city);
%
% INPUTS
%   r    : annual results from main.m. Fields used [kWh/yr]:
%          E_PV_to_EV, E_batt_to_EV, E_export, E_PV_dc, dE_stored
%   pv, batt, sys : parameter structs from main.m
%   city : 'Jodhpur' | 'Bengaluru' | 'Guwahati'
%
% OUTPUT  ec (struct), money in INR, real terms (constant prices)
%   capex, LCOE_system, LCOE_PV_only, tariff, NPV, payback, CO2 avoided ...
%
% METHOD
%   LCOE = ( Capex + sum_y (O&M_y + Replacement_y)/(1+d)^y )
%          / sum_y ( E_solar_y /(1+d)^y )
%   Capex at t = 0; all other flows at the END of year y = 1..L.
%   E_solar_y = E_solar_1 * (1 - degradation)^(y-1).
%
% ALL COST / TARIFF / EMISSION NUMBERS IN econ_params() ARE PLACEHOLDERS.
% Replace them with sourced values (vendor quotes, DISCOM tariff orders,
% CEA CO2 Baseline Database) before reporting any result.

    p = econ_params(city);
    L = p.life_years;
    y = (1:L)';                                   % year index (column)
    disc = (1 + p.discount_rate) .^ (-y);         % discount factors

    %% 1. CAPEX [INR] -------------------------------------------------------
    capex.pv    = pv.kWp * p.pv_per_kWp;               % PV modules + mounting
    capex.batt  = batt.capacity_kWh * p.batt_per_kWh;  % LFP pack + BMS
    capex.conv  = pv.kWp * p.conv_per_kW;              % converter sized to PV kWp
    capex.equip = capex.pv + capex.batt + capex.conv;
    capex.bos   = p.bos_frac * capex.equip;            % installation, wiring, civil
    capex.total = capex.equip + capex.bos;

    % PV-only variant (no battery) for comparison: shows the cost of the battery
    capex.total_pv_only = (capex.pv + capex.conv) * (1 + p.bos_frac);

    %% 2. ANNUAL SOLAR ENERGY, YEAR 1 [kWh] ---------------------------------
    % Solar energy that reached a useful end point:
    %   served to EV  = PV->EV + battery->EV + net change in stored energy
    %   exported      = surplus sent to grid
    % The dE_stored term removes the start-of-year battery charge, which is a
    % carry-over and not solar energy produced this year (and adds any net gain).
    E_served = r.E_PV_to_EV + r.E_batt_to_EV + r.dE_stored;
    E_export = r.E_export;
    E_solar  = E_served + E_export;
    assert(E_solar > 0, 'No useful solar energy for %s: check simulation output.', city);

    % PV-only variant: all usable AC energy from the converter output
    E_solar_pv_only = sys.nu * r.E_PV_dc;

    degf = (1 - p.degradation) .^ (y - 1);        % PV output degradation factor

    %% 3. RECURRING AND REPLACEMENT COSTS [INR] -----------------------------
    om_y  = p.om_frac * capex.total * ones(L, 1);          % O&M each year (real)
    rep_y = replacement_schedule(L, [ ...
        p.batt_life, p.batt_repl_frac * capex.batt; ...
        p.conv_life, p.conv_repl_frac * capex.conv]);

    om_pv_y  = p.om_frac * capex.total_pv_only * ones(L, 1);
    rep_pv_y = replacement_schedule(L, [p.conv_life, p.conv_repl_frac * capex.conv]);

    %% 4. LCOE [INR/kWh] ----------------------------------------------------
    PV_energy       = sum(E_solar .* degf .* disc);          % discounted kWh
    PV_energy_pv    = sum(E_solar_pv_only .* degf .* disc);
    PV_cost         = capex.total + sum((om_y + rep_y) .* disc);
    PV_cost_pv_only = capex.total_pv_only + sum((om_pv_y + rep_pv_y) .* disc);

    ec.LCOE_system  = PV_cost / PV_energy;                   % PV + battery + converter
    ec.LCOE_PV_only = PV_cost_pv_only / PV_energy_pv;        % PV + converter only
    ec.tariff       = p.tariff;
    ec.export_credit = p.export_credit;
    % Threshold metric: station beats the grid if LCOE < state tariff
    ec.LCOE_below_tariff        = ec.LCOE_system  < p.tariff;
    ec.LCOE_PV_only_below_tariff = ec.LCOE_PV_only < p.tariff;

    %% 5. CASH FLOWS, NPV, PAYBACK -----------------------------------------
    % Savings vs a grid-only station: EV energy not bought + export revenue.
    esc = (1 + p.tariff_escalation) .^ (y - 1);
    savings_y = degf .* esc .* (E_served * p.tariff + E_export * p.export_credit);
    cf_y = savings_y - om_y - rep_y;                         % net cash flow, years 1..L

    ec.NPV = -capex.total + sum(cf_y .* disc);               % [INR]
    ec.payback_simple     = payback_years(capex.total, cf_y);
    ec.payback_discounted = payback_years(capex.total, cf_y .* disc);
    ec.payback_vs_life    = ec.payback_simple < L;           % threshold metric

    %% 6. CO2 AVOIDED -------------------------------------------------------
    % Each solar kWh (served or exported) displaces one grid kWh.
    ec.CO2_avoided_t_per_yr = E_solar * p.grid_ef / 1000;                % tonnes, year 1
    ec.CO2_avoided_t_life   = sum(E_solar .* degf) * p.grid_ef / 1000;   % tonnes, lifetime

    %% 7. SUMMARY FIELDS ----------------------------------------------------
    ec.capex = capex;
    ec.E_solar_kWh_yr1 = E_solar;
    ec.E_served_kWh_yr1 = E_served;
    ec.E_export_kWh_yr1 = E_export;
    ec.annual_om = om_y(1);
    ec.params = p;
end

function p = econ_params(city)
% PLACEHOLDER INPUTS. Every value here must be replaced with a sourced one.
% Money in INR, real (constant) prices.

    % --- Capital cost (assumed same in every city: only climate varies) ---
    p.pv_per_kWp   = 45000;    % INR per kWp, PV modules + mounting      [PLACEHOLDER]
    p.batt_per_kWh = 20000;    % INR per kWh, installed LFP + BMS        [PLACEHOLDER]
    p.conv_per_kW  = 8000;     % INR per kW of PV kWp, converter         [PLACEHOLDER]
    p.bos_frac     = 0.15;     % installation/wiring/civil as fraction of equipment [PLACEHOLDER]

    % --- Operation, lifetime, finance ---
    p.om_frac          = 0.015; % annual O&M as fraction of total capex   [PLACEHOLDER]
    p.life_years       = 25;    % project life [years]                    [PLACEHOLDER]
    p.discount_rate    = 0.08;  % REAL discount rate                      [PLACEHOLDER]
    p.degradation      = 0.005; % PV output loss per year                 [PLACEHOLDER]
    p.tariff_escalation = 0.0;  % real tariff growth per year (0 = flat)  [PLACEHOLDER]

    % --- Component replacement (cost as fraction of ORIGINAL component capex) ---
    p.batt_life      = 15;      % battery life [years]                    [PLACEHOLDER]
    p.batt_repl_frac = 0.60;    % future pack price vs today              [PLACEHOLDER]
    p.conv_life      = 12;      % converter life [years]                  [PLACEHOLDER]
    p.conv_repl_frac = 1.00;    %                                         [PLACEHOLDER]

    % --- State-level inputs (DISCOM EV/commercial tariff, CEA emission factor) ---
    switch city
        case 'Jodhpur'          % Rajasthan
            p.tariff = 7.0;  p.export_credit = 3.0;  p.grid_ef = 0.72;
        case 'Bengaluru'        % Karnataka
            p.tariff = 6.0;  p.export_credit = 3.0;  p.grid_ef = 0.72;
        case 'Guwahati'         % Assam
            p.tariff = 6.5;  p.export_credit = 3.0;  p.grid_ef = 0.72;
        otherwise
            error('Unknown city: %s', city);
    end
    % tariff        : INR/kWh, EV/commercial tariff, avoided when solar serves the EV
    % export_credit : INR/kWh, payment for exported energy
    % grid_ef       : kg CO2 per kWh, replace with state-level CEA value
end

function rep = replacement_schedule(L, comps)
% Replacement cost per year [INR], length-L column vector.
% comps: rows of [life_years, replacement_cost].
% A component is replaced at years life, 2*life, ... that fall before the end of
% the project, and ONLY if at least half of its life would still be used
% (no replacing a converter one year before decommissioning).
    rep = zeros(L, 1);
    for k = 1:size(comps, 1)
        life = comps(k, 1);
        cost = comps(k, 2);
        ys = life : life : (L - 1);
        ys = ys((L - ys) >= 0.5 * life);
        rep(ys) = rep(ys) + cost;
    end
end

function n = payback_years(capex, cf)
% Years until cumulative cash flow covers capex, linearly interpolated within
% the crossing year. Inf if it never pays back within the project life.
    cum  = cumsum(cf);
    prev = [0; cum(1:end-1)];
    k = find(cum >= capex, 1, 'first');
    if isempty(k)
        n = Inf;
    else
        n = (k - 1) + (capex - prev(k)) / cf(k);
    end
end
