function b = battery_model(b, P_c, P_d, Ta, batt, dt)
% battery_model.m
% Lumped-parameter LFP pack, one time step.
%  State b: E [kWh stored], Tb [degC], SOH [-], S_gen [kJ/K cumulative]
%
%  Electrical (First Law):  loss = I^2 R,  I = P/V_nom
%     charge   : E <- E + (P_c - loss)*dt
%     discharge: E <- E - (P_d + loss)*dt
%  Thermal (First Law, lumped mass):  m*cp*dTb/dt = Q_gen - UA*(Tb - Ta)
%     solved exactly over the step for constant Q_gen
%  Second Law: Joule heat is generated at Tb and finally rejected to the
%     environment at T0, so over the step S_gen = Q/T0 and Ex_dest = T0*S_gen = I^2R
%     (internal generation Q/Tb + heat-transfer generation Q(1/T0 - 1/Tb)).
%  Ageing: capacity fade per equivalent full cycle, Arrhenius in Tb.
    P_term = P_c + P_d;                         % only one is non-zero
    I      = P_term*1000 / batt.V_nom;          % [A]
    loss   = I^2 * batt.R_internal / 1000;      % [kW]
    b.E    = b.E + (P_c - P_d - loss)*dt;

    Q   = loss*1000;                            % [W]
    tau = batt.mass_kg*batt.cp / batt.UA;       % [s]
    Tss = Ta + Q/batt.UA;
    b.Tb = Tss + (b.Tb - Tss)*exp(-dt*3600/tau);

    T0 = Ta + 273.15;
    b.loss  = loss;
    b.Ex_dest = loss;                           % [kWh] per 1 h step
    b.S_gen = b.S_gen + loss*3600/T0;           % [kJ/K]

    EFC = P_d*dt / batt.capacity_kWh;
    kT  = exp(batt.Ea/8.314 * (1/batt.T_ref - 1/(b.Tb + 273.15)));
    b.SOH = b.SOH - batt.fade_per_EFC * kT * EFC;
    b.EFC = b.EFC + EFC;
end
