function ec = economics(r, P, city)
% economics.m
% Economic and CO2 REPORTING layer (not an optimiser), plus the grid-only
% baseline: same EV load, same city, 100 % grid supplied.
%
% LCOE = ( Capex + sum_y (O&M_y + Replacement_y)/(1+d)^y ) / sum_y ( E_solar_y/(1+d)^y )
% Capex at t = 0, other flows at the end of year y = 1..L, real (constant) INR.
% Energy charge only: fixed/demand charges are the same with or without PV
% (the evening EV peak still sets the contract demand) and are left out.
    p = econ_params(city);
    L = p.life_years;  y = (1:L)';
    disc = (1 + p.discount_rate) .^ (-y);
    pv = P.pv; batt = P.batt;

    %% Capex [INR]
    capex.pv    = pv.kWp * p.pv_per_kWp;
    capex.batt  = batt.capacity_kWh * p.batt_per_kWh;
    capex.conv  = pv.kWp * p.conv_per_kW + batt.P_max_kW * p.pcs_per_kW;
    capex.equip = capex.pv + capex.batt + capex.conv;
    capex.bos   = p.bos_frac * capex.equip;
    capex.total = capex.equip + capex.bos;
    capex.total_pv_only = (capex.pv + pv.kWp*p.conv_per_kW) * (1 + p.bos_frac);

    %% Year-1 solar energy reaching a useful end point [kWh]
    E_served = r.E_EV - r.E_import;               % EV energy not bought from the grid
    E_export = r.E_export;
    E_solar  = E_served + E_export;
    E_solar_pv_only = r.E_PV_ac;                  % PV-only variant: all inverter output

    degf = [1; (1 - p.degr_first) * (1 - p.degr_annual).^((1:L-1)')];   % datasheet warranty curve

    %% Recurring and replacement costs
    om_y  = p.om_frac * capex.total * ones(L,1);
    rep_y = replacement_schedule(L, [p.batt_life, p.batt_repl_frac*capex.batt; ...
                                     p.conv_life, capex.conv]);
    om_pv  = p.om_frac * capex.total_pv_only * ones(L,1);
    rep_pv = replacement_schedule(L, [p.conv_life, pv.kWp*p.conv_per_kW]);

    %% LCOE
    ec.LCOE_system  = (capex.total + sum((om_y + rep_y).*disc)) / sum(E_solar*degf.*disc);
    ec.LCOE_PV_only = (capex.total_pv_only + sum((om_pv + rep_pv).*disc)) / sum(E_solar_pv_only*degf.*disc);
    ec.tariff = p.tariff;  ec.export_credit = p.export_credit;  ec.grid_ef = p.grid_ef;
    ec.LCOE_below_tariff = ec.LCOE_system < p.tariff;

    %% Cash flows vs grid-only baseline
    savings_y = degf .* (E_served*p.tariff + E_export*p.export_credit);
    cf_y = savings_y - om_y - rep_y;
    ec.NPV = -capex.total + sum(cf_y.*disc);
    ec.payback_simple     = payback_years(capex.total, cf_y);
    ec.payback_discounted = payback_years(capex.total, cf_y.*disc);
    ec.payback_vs_life    = ec.payback_simple < L;

    %% Grid-only baseline vs station, year 1
    ec.base.cost   = r.E_EV * p.tariff;                         % INR/yr
    ec.base.CO2_t  = r.E_EV * p.grid_ef / 1000;                 % t/yr
    ec.stn.cost    = r.E_import*p.tariff - E_export*p.export_credit;
    ec.stn.CO2_t   = r.E_import * p.grid_ef / 1000;
    ec.CO2_avoided_t_per_yr = (E_served + E_export) * p.grid_ef / 1000;   % export displaces grid kWh too
    ec.CO2_avoided_t_life   = sum((E_served + E_export)*degf) * p.grid_ef / 1000;
    ec.CO2_reduction_onsite = 1 - ec.stn.CO2_t / ec.base.CO2_t;           % on-site EV supply only

    ec.capex = capex;  ec.E_solar = E_solar;  ec.E_served = E_served;  ec.params = p;
end

function p = econ_params(city)
% Sourced where possible; remaining items are labelled ASSUMPTION.
    p.pv_per_kWp   = 40000;   % INR/kWp modules + structure, C&I scale        ASSUMPTION (2025 market, ~INR 38-45k)
    p.conv_per_kW  = 6000;    % INR/kW PV string inverter                     ASSUMPTION
    p.pcs_per_kW   = 8000;    % INR/kW battery PCS                            ASSUMPTION
    p.batt_per_kWh = 18000;   % INR/kWh installed LFP + BMS (C&I quotes INR 16-25k/kWh, 2026)
    p.bos_frac     = 0.15;    % installation, cabling, civil                  ASSUMPTION
    p.om_frac      = 0.015;   % annual O&M, fraction of capex                 ASSUMPTION
    p.life_years   = 25;      % = module power guarantee (Trina datasheet)
    p.degr_first   = 0.01;    % first-year degradation (Trina datasheet)
    p.degr_annual  = 0.004;   % annual degradation thereafter (Trina datasheet)
    p.discount_rate= 0.08;    % real                                          ASSUMPTION
    p.batt_life    = 15;      % calendar-limited pack life                    ASSUMPTION
    p.batt_repl_frac = 0.60;  % future pack price vs today                    ASSUMPTION
    p.conv_life    = 12;      % = Trina product warranty period, used for converters  ASSUMPTION
    p.export_credit= 3.0;     % INR/kWh for exported energy (APPC-level)      ASSUMPTION
    % CEA CO2 Baseline Database v21: one integrated national grid, so a single
    % weighted-average factor applies in every state (2024-25: 0.710 tCO2/MWh).
    p.grid_ef = 0.710;
    switch city
        case 'Jodhpur'    % Rajasthan, RERC EV/LT-8 public charging, energy charge
            p.tariff = 6.00;
        case 'Bengaluru'  % Karnataka, KERC 2025 order, LT-6(c) EV charging, energy charge
            p.tariff = 4.50;
        case 'Guwahati'   % Assam, AERC/APDCL FY2026-27, LT-X EV charging station
            p.tariff = 8.72;
        otherwise
            error('Unknown city: %s', city);
    end
end

function rep = replacement_schedule(L, comps)
% Replacement cost per year [INR]; replaced at life, 2*life, ... only if at
% least half of the new unit's life is used before the project ends.
    rep = zeros(L,1);
    for k = 1:size(comps,1)
        life = comps(k,1);  cost = comps(k,2);
        ys = life:life:(L-1);
        ys = ys((L - ys) >= 0.5*life);
        rep(ys) = rep(ys) + cost;
    end
end

function n = payback_years(capex, cf)
    cum = cumsum(cf);  prev = [0; cum(1:end-1)];
    k = find(cum >= capex, 1, 'first');
    if isempty(k), n = Inf; else, n = (k-1) + (capex - prev(k))/cf(k); end
end
