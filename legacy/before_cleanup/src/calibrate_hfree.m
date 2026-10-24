function h_free = calibrate_hfree(pv)
% Solve the steady cell energy balance at NOCT test conditions for h_free.
%   alpha*G = 2*h*(Tc - Ta) + eps_f*sigma*(Tc^4 - Tsky^4) + eps_b*sigma*(Tc^4 - Ta^4)
% with G = 800, Ta = 20 degC, wind at module = 1 m/s, open circuit (P = 0).
    sigma = 5.670374e-8;
    Ta = 293.15;  Tc = pv.NOCT + 273.15;  G = 800;  v = 1.0;
    Tsky = 0.0552 * Ta^1.5;                       % Swinbank clear-sky temperature
    q_rad = pv.eps_front*sigma*(Tc^4 - Tsky^4) + pv.eps_back*sigma*(Tc^4 - Ta^4);
    h = (pv.alpha*G - q_rad) / (2*(Tc - Ta));     % per-face convection coefficient
    h_free = h - pv.h_wind*v;
end
