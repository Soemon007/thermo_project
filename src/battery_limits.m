function [P_c_max, P_d_max] = battery_limits(E, E_min, E_max, batt, dt)
% battery_limits.m
% Largest TERMINAL charge / discharge power allowed this hour [kW], limited by
% (i) the C-rate cap and (ii) remaining headroom / energy INCLUDING I^2R loss.
%   loss = k*P^2, k = R*1000/V^2 [kW per kW^2]   (I = P*1000/V)
%   charge   : stored gain  (P - kP^2)*dt = room   -> quadratic in P
%   discharge: stored drop  (P + kP^2)*dt = avail  -> quadratic in P
    k     = batt.R_internal * 1000 / batt.V_nom^2;
    room  = max(0, E_max - E);
    avail = max(0, E - E_min);
    if k > 0
        P_c_E = (1 - sqrt(max(0, 1 - 4*k*room/dt))) / (2*k);
        P_d_E = (-1 + sqrt(1 + 4*k*avail/dt)) / (2*k);
    else
        P_c_E = room/dt;  P_d_E = avail/dt;
    end
    P_c_max = min(batt.P_max_kW, P_c_E);
    P_d_max = min(batt.P_max_kW, P_d_E);
end
