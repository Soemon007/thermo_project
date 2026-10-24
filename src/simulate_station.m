function sim = simulate_station(W, P)
% simulate_station.m
% Full-year hourly simulation for ONE city and ONE station design.
% Used by the baseline AND every sensitivity run, so they cannot diverge.
%
% Station boundary: PV array, DC wiring, PV inverter, battery + PCS.
% Crossing the boundary: solar radiation in, grid import in, EV supply out,
% grid export out, heat to ambient. Grid and EV are boundary conditions.
    pv = P.pv; batt = P.batt; sys = P.sys; dt = 1;
    N  = numel(W.G);
    P_EV = repmat(P.ev.daily, N/24, 1);

    % ---- PV (weather-driven only -> vectorised) ----
    pvo     = pv_model(W, pv, P.cfg);
    P_dc    = pvo.P_raw * (1 - pv.wiring_loss);         % after DC wiring
    wiring  = pvo.P_raw - P_dc;
    P_ac    = P_dc * sys.nu_inv;                          % after inverter
    inv     = P_dc - P_ac;

    z = zeros(N,1);
    L = struct('PV_to_EV',z,'batt_c',z,'batt_d',z,'ac_to_batt',z,'batt_to_EV',z, ...
               'export',z,'import',z,'pcs_loss',z,'batt_loss',z,'E',zeros(N+1,1), ...
               'Tb',z,'SOH',z,'SOC',z);

    b.E = batt.SOC_init*batt.capacity_kWh;  b.Tb = W.Ta(1);  b.SOH = 1;
    b.S_gen = 0;  b.EFC = 0;
    L.E(1) = b.E;
    E_nom = batt.capacity_kWh;
    for t = 1:N
        cap   = E_nom * b.SOH;
        E_min = batt.SOC_min*cap;  E_max = batt.SOC_max*cap;
        if E_nom > 0
            d = ems_dispatch(P_ac(t), P_EV(t), b.E, E_min, E_max, batt, sys, dt);
            b = battery_model(b, d.batt_c, d.batt_d, W.Ta(t), batt, dt);
        else                                              % no-battery variant
            d = ems_dispatch(P_ac(t), P_EV(t), 0, 0, 0, batt, sys, dt);
            b.loss = 0;
        end
        L.PV_to_EV(t) = d.PV_to_EV;   L.batt_c(t) = d.batt_c;   L.batt_d(t) = d.batt_d;
        L.ac_to_batt(t) = d.ac_to_batt; L.batt_to_EV(t) = d.batt_to_EV;
        L.export(t) = d.export;       L.import(t) = d.import;   L.pcs_loss(t) = d.pcs_loss;
        L.batt_loss(t) = b.loss;      L.E(t+1) = b.E;           L.Tb(t) = b.Tb;
        L.SOH(t) = b.SOH;             L.SOC(t) = b.E / max(cap, eps);
    end
    dE = diff(L.E);

    % ---- Hourly closures ----
    % First Law: A*G + import = EV + export + dE + (optical + heat + wiring + inv + pcs + batt)
    L.res_energy = (pvo.E_inc + L.import) - (P_EV + L.export + dE ...
        + pvo.E_opt + pvo.Q_heat + wiring + inv + L.pcs_loss + L.batt_loss);
    % Second Law: Ex_in + import = EV + export + dE + sum(Ex_dest)
    L.res_exergy = (pvo.Ex_in + L.import) - (P_EV + L.export + dE ...
        + pvo.Ex_dest + wiring + inv + L.pcs_loss + L.batt_loss);

    sim = L;
    sim.pv = pvo;  sim.P_EV = P_EV;  sim.P_dc = P_dc;  sim.P_ac = P_ac;
    sim.wiring = wiring;  sim.inv = inv;  sim.dE = dE;
    sim.b_final = b;
end
