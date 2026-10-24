function d = ems_dispatch(P_ac, P_EV, E, E_min, E_max, batt, sys, dt)
% ems_dispatch.m
% Priority rule on the AC bus (not an optimiser):
%   1. PV (AC) serves the EV
%   2. PV surplus charges the battery through the PCS, the rest is exported
%   3. EV deficit is met by the battery through the PCS, the rest is imported
% Battery is charged from PV only (never from the grid).
% Battery powers are TERMINAL (DC) powers; PCS losses sit between bus and battery.
    [P_c_max, P_d_max] = battery_limits(E, E_min, E_max, batt, dt);
    d.PV_to_EV = min(P_ac, P_EV);
    surplus = P_ac - d.PV_to_EV;
    deficit = P_EV - d.PV_to_EV;
    d.batt_c = 0; d.batt_d = 0; d.ac_to_batt = 0; d.batt_to_EV = 0;
    d.export = 0; d.import = 0;

    if surplus > 0
        d.batt_c     = min(surplus*sys.nu_pcs, P_c_max);   % DC into battery
        d.ac_to_batt = d.batt_c / sys.nu_pcs;              % AC drawn from bus
        d.export     = surplus - d.ac_to_batt;
    end
    if deficit > 0
        d.batt_d     = min(deficit/sys.nu_pcs, P_d_max);   % DC out of battery
        d.batt_to_EV = d.batt_d * sys.nu_pcs;              % AC delivered to EV
        d.import     = deficit - d.batt_to_EV;
    end
    d.pcs_loss = (d.ac_to_batt - d.batt_c) + (d.batt_d - d.batt_to_EV);
end
