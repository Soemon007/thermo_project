function P = update_params(P)
% update_params.m
% Recompute derived quantities after a sensitivity run changes a base value
% (module count, battery parallel strings, cell resistance, NOCT, EV profile).
    P.pv.A   = P.pv.N_mod * P.pv.A_mod;
    P.pv.kWp = P.pv.N_mod * P.pv.P_mod / 1000;
    P.pv.h_free = calibrate_hfree(P.pv);
    P.ev.daily  = ev_profile(P.ev.profile, P.ev.daily_kWh);
    b = P.batt;
    b.V_nom        = b.n_series * b.cell_V;
    b.capacity_kWh = b.n_series * b.n_parallel * b.cell_Ah * b.cell_V / 1000;
    if b.n_parallel > 0
        b.R_internal = b.n_series * b.cell_R / b.n_parallel;
    else
        b.R_internal = 0;
    end
    b.P_max_kW = b.C_rate_max * b.capacity_kWh;
    b.mass_kg  = max(5.5 * b.n_series * b.n_parallel, 1);
    P.batt = b;
end
