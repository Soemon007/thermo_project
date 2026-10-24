function pvo = pv_model(W, pv, cfg)
% pv_model.m
% PV subsystem, vectorised over all 8760 hours.
%
% FIRST LAW (control volume = PV laminate, quasi-steady, dU/dt ~ 0 at 1 h steps)
%   A*G = optical loss + P_elec + Q_heat
%   optical loss = reflection beyond normal incidence (IAM) + non-absorbed fraction
%   Q_heat = alpha*A*G_eff - P_elec, rejected by convection + radiation:
%   alpha*G_eff - P/A = 2*h(v)*(Tc-Ta) + eps_f*sig*(Tc^4-Tsky^4) + eps_b*sig*(Tc^4-Ta^4)
%   eta = eta_ref * f_low(G') * [1 - beta*(Tc - 25)],  P = eta*A*G_eff
%   f_low = 1 + k1 ln G' + k2 (ln G')^2, G' = G_eff/1000   (Huld et al. 2011 low-light terms)
%
% SECOND LAW (dead state T0 = hourly ambient)
%   Each irradiance component gets its own exergy factor:
%     Ex_in = A*[ Gb*psi_P + Gd*psi(eps_d) + Gr*psi(eps_r) ]
%     psi_P    = 1 - 4/3 (T0/Ts) + 1/3 (T0/Ts)^4              (Petela, direct beam)
%     psi(eps) = 1 - 4/3 (T0/Ts) X(eps)                        (diluted radiation, see
%                radiation_exergy_factor.m); eps = radiance of the sky (or ground) seen by
%                the module / radiance of the sun's surface = G_comp / (sigma Ts^4 * view factor)
%   Ex_opt = exergy of the radiation reflected or not absorbed, per component
%   Ex_Q   = Q_heat*(1 - T0/Tc)                               (exergy of rejected heat)
%   Ex_int = Ex_in - P - Ex_opt - Ex_Q = T0*S_gen,internal   (Gouy-Stodola)
%   Total PV exergy loss  Ex_dest_PV = Ex_in - P  (= Ex_opt + Ex_Q + Ex_int)
%
% All power-type outputs in kW (= kWh per 1 h step).

    sigma = 5.670374e-8;
    A  = pv.A;
    T0 = W.Ta + 273.15;
    sun = W.G > 0;

    % ---- 1. Optical: incidence-angle modifier on each component ----
    [cos_aoi, ~] = solar_geometry(W, pv.tilt, W.lat);
    iam_b = zeros(size(cos_aoi));
    c = cos_aoi > 0.05;
    iam_b(c) = max(0, 1 - pv.b0_iam*(1./cos_aoi(c) - 1));
    G_eff = W.Gb.*iam_b + W.Gd*pv.iam_diff + W.Gr*pv.iam_grnd;     % [W/m2]

    % ---- 1b. Low-light efficiency factor (irradiance dependence) ----
    lg    = log(max(G_eff, 1) / 1000);
    f_low = max(0, 1 + pv.k1_low*lg + pv.k2_low*lg.^2);

    % ---- 2. Cell temperature ----
    v_mod = W.ws10 * (pv.z_mount/10)^(1/7);                          % wind at module height
    switch cfg.tc_model
        case 'noct'
            Tc = W.Ta + (pv.NOCT - 20)/800 .* G_eff;
        case 'balance'
            Tc = cell_temp_balance(G_eff, f_low, W.Ta, v_mod, pv, sigma);
        otherwise
            error('Unknown tc_model %s', cfg.tc_model);
    end
    Tc(~sun) = W.Ta(~sun);

    % ---- 3. Electrical output ----
    eta   = max(0, pv.eta_ref * f_low .* (1 - pv.beta*(Tc - 25)));
    P_raw = eta .* A .* G_eff / 1000;                                 % [kW] at module terminals

    % ---- 4. Energy split ----
    E_inc  = A .* W.G / 1000;                                         % incident [kW]
    E_opt  = E_inc - pv.alpha * A .* G_eff / 1000;                    % reflected + not absorbed
    Q_heat = pv.alpha * A .* G_eff / 1000 - P_raw;                    % heat rejected

    % ---- 5. Exergy split ----
    r     = T0 / pv.T_sun;
    psi_P = 1 - (4/3)*r + (1/3)*r.^4;                                 % Petela factor, direct beam (~0.93)
    sTs4  = sigma * pv.T_sun^4;                                       % radiance of the sun's surface
    vf_s  = (1 + cosd(pv.tilt))/2;                                    % sky view factor
    vf_g  = (1 - cosd(pv.tilt))/2;                                    % ground view factor
    psi_d = radiation_exergy_factor(W.Gd ./ (sTs4*vf_s), T0, pv.T_sun);   % diffuse sky light
    psi_r = radiation_exergy_factor(W.Gr ./ (sTs4*vf_g), T0, pv.T_sun);   % ground-reflected light
    Ex_in  = A .* (W.Gb.*psi_P + W.Gd.*psi_d + W.Gr.*psi_r) / 1000;
    Ex_opt = A .* (W.Gb.*(1 - pv.alpha*iam_b).*psi_P + W.Gd.*(1 - pv.alpha*pv.iam_diff).*psi_d ...
                 + W.Gr.*(1 - pv.alpha*pv.iam_grnd).*psi_r) / 1000;
    TcK    = Tc + 273.15;
    Ex_Q   = Q_heat .* max(0, 1 - T0./TcK);
    Ex_int = Ex_in - P_raw - Ex_opt - Ex_Q;

    z = ~sun;
    E_inc(z)=0; E_opt(z)=0; Q_heat(z)=0; Ex_in(z)=0; Ex_opt(z)=0; Ex_Q(z)=0; Ex_int(z)=0; P_raw(z)=0;

    pvo = struct('G_eff', G_eff, 'Tc', Tc, 'eta', eta, 'P_raw', P_raw, 'f_low', f_low, ...
        'E_inc', E_inc, 'E_opt', E_opt, 'Q_heat', Q_heat, 'psi_petela', psi_P, ...
        'Ex_in', Ex_in, 'Ex_opt', Ex_opt, 'Ex_Q', Ex_Q, 'Ex_int', Ex_int, ...
        'Ex_dest', Ex_in - P_raw, 'v_mod', v_mod, 'cos_aoi', cos_aoi);
end

function Tc = cell_temp_balance(G_eff, f_low, Ta, v, pv, sigma)
% Newton solve of the steady cell energy balance, all hours at once.
% Electrical output is coupled: P/A = eta(Tc)*G_eff.
    TaK  = Ta + 273.15;
    Tsky = 0.0552 * TaK.^1.5;                     % Swinbank sky temperature [K]
    h    = pv.h_free + pv.h_wind .* v;            % per-face convection [W/m2K]
    T    = TaK + (pv.NOCT - 20)/800 .* G_eff;     % NOCT estimate as start
    for it = 1:30
        eta  = pv.eta_ref*f_low.*(1 - pv.beta*(T - 298.15));
        f    = pv.alpha*G_eff - eta.*G_eff - 2*h.*(T - TaK) ...
               - pv.eps_front*sigma*(T.^4 - Tsky.^4) - pv.eps_back*sigma*(T.^4 - TaK.^4);
        dfdT = pv.eta_ref*pv.beta*f_low.*G_eff - 2*h - 4*sigma*(pv.eps_front + pv.eps_back)*T.^3;
        dT   = -f ./ dfdT;
        T    = T + dT;
        if max(abs(dT)) < 1e-8, break; end
    end
    Tc = T - 273.15;
end
