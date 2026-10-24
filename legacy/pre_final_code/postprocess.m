function r = postprocess(sim, W, P)
% postprocess.m
% Annual, monthly and seasonal metrics from the hourly log. Nothing here
% averages weather inputs: every number is a sum (or ratio of sums) of hourly
% outputs, so the nonlinearity in eta(Tc) and Ex(G,T) is preserved.
    pvo = sim.pv;
    S = @(x) sum(x);

    % ---------------- Annual energy (First Law) [kWh] ----------------
    r.E_EV       = S(sim.P_EV);
    r.E_inc      = S(pvo.E_inc);
    r.E_opt      = S(pvo.E_opt);
    r.Q_heat     = S(pvo.Q_heat);
    r.E_PV_raw   = S(pvo.P_raw);
    r.E_wiring   = S(sim.wiring);
    r.E_PV_dc    = S(sim.P_dc);
    r.E_inv      = S(sim.inv);
    r.E_PV_ac    = S(sim.P_ac);
    r.E_PV_to_EV = S(sim.PV_to_EV);
    r.E_batt_in  = S(sim.batt_c);
    r.E_batt_out = S(sim.batt_d);
    r.E_batt_to_EV = S(sim.batt_to_EV);
    r.E_pcs      = S(sim.pcs_loss);
    r.E_batt_loss= S(sim.batt_loss);
    r.E_export   = S(sim.export);
    r.E_import   = S(sim.import);
    r.dE_stored  = sim.E(end) - sim.E(1);

    r.specific_yield = r.E_PV_raw / P.pv.kWp;                 % kWh/kWp (module DC)
    r.PR             = r.E_PV_ac / (P.pv.kWp * S(W.G)/1000);  % performance ratio (AC)
    r.eta_PV         = r.E_PV_raw / r.E_inc;                  % First Law, cell
    r.psi_PV         = r.E_PV_raw / S(pvo.Ex_in);             % Second Law, cell
    E_stc  = S(P.pv.eta_ref*P.pv.A*pvo.G_eff/1000 .* (W.G>0));            % at 25 degC, full-light efficiency
    E_lowl = S(P.pv.eta_ref*P.pv.A*pvo.G_eff.*pvo.f_low/1000 .* (W.G>0)); % with low-light factor only
    r.lowlight_loss  = 1 - E_lowl / E_stc;                    % share lost to weak light
    r.temp_loss      = 1 - r.E_PV_raw / E_lowl;               % share lost to cell temperature
    r.psi_sun        = S(pvo.Ex_in) / S(pvo.E_inc);           % exergy content of the sunlight received
    r.diffuse_frac   = S(W.Gd + W.Gr) / S(W.G);               % diffuse + ground share of irradiation
    prod = pvo.P_raw > 0.05*P.pv.kWp;
    r.Tc_mean_prod   = sum(pvo.Tc(prod).*pvo.P_raw(prod)) / sum(pvo.P_raw(prod)); % energy-weighted
    r.Tc_max         = max(pvo.Tc);
    r.Ta_mean        = mean(W.Ta);
    r.G_annual       = S(W.G)/1000;                           % kWh/m2 on plane

    % Coverage & grid metrics
    r.SCR_direct  = r.E_PV_to_EV / r.E_EV;                        % PV -> EV directly
    r.SCR_total   = (r.E_PV_to_EV + r.E_batt_to_EV) / r.E_EV;     % incl. via battery
    r.grid_dep    = r.E_import / r.E_EV;
    r.self_cons   = (r.E_PV_to_EV + S(sim.ac_to_batt)) / r.E_PV_ac;   % PV used on site
    r.batt_RTE    = r.E_batt_to_EV / max(S(sim.ac_to_batt) - r.dE_stored, eps); % AC-AC round trip (approx.)
    r.EFC         = sim.b_final.EFC;
    r.SOH_end     = sim.b_final.SOH;
    r.S_gen_batt  = sim.b_final.S_gen;                            % kJ/K
    r.Tb_mean     = mean(sim.Tb);   r.Tb_max = max(sim.Tb);
    r.dTb_max     = max(sim.Tb - W.Ta);

    % ---------------- Annual exergy (Second Law) [kWh] ----------------
    r.Ex_in_PV    = S(pvo.Ex_in);
    r.Ex_PV_opt   = S(pvo.Ex_opt);
    r.Ex_PV_heat  = S(pvo.Ex_Q);
    r.Ex_PV_int   = S(pvo.Ex_int);
    r.Ex_dest_PV  = S(pvo.Ex_dest);
    r.Ex_dest_wir = r.E_wiring;
    r.Ex_dest_inv = r.E_inv;
    r.Ex_dest_pcs = r.E_pcs;
    r.Ex_dest_batt= r.E_batt_loss;
    r.Ex_dest_tot = r.Ex_dest_PV + r.Ex_dest_wir + r.Ex_dest_inv + r.Ex_dest_pcs + r.Ex_dest_batt;
    r.dest_split  = [r.Ex_dest_PV r.Ex_dest_wir r.Ex_dest_inv r.Ex_dest_pcs r.Ex_dest_batt] / r.Ex_dest_tot;
    r.dest_split_nonPV = [r.Ex_dest_wir r.Ex_dest_inv r.Ex_dest_pcs r.Ex_dest_batt] / ...
                         (r.Ex_dest_tot - r.Ex_dest_PV);

    % Station efficiencies
    useful = r.E_EV - r.E_import + r.E_export + r.dE_stored;   % solar-origin useful output
    r.eta_solar = useful / r.E_inc;                            % First Law, solar chain
    r.psi_solar = useful / r.Ex_in_PV;                         % Second Law, solar chain
    r.eta_sys   = (r.E_EV + r.E_export + r.dE_stored) / (r.E_inc + r.E_import);
    r.psi_sys   = (r.E_EV + r.E_export + r.dE_stored) / (r.Ex_in_PV + r.E_import);
    % Subsystem exergy efficiencies
    r.psi_inv  = r.E_PV_ac / r.E_PV_dc;
    r.psi_batt = (r.E_batt_out) / max(r.E_batt_in - r.dE_stored, eps);   % DC-DC
    r.psi_pcs  = 1 - r.E_pcs / max(S(sim.ac_to_batt) + r.E_batt_out, eps);

    % Closures
    r.res_energy = max(abs(sim.res_energy));
    r.res_exergy = max(abs(sim.res_exergy));
    r.min_Ex_int = min(pvo.Ex_int);

    % ---------------- Monthly and seasonal ----------------
    m = W.month;
    ms = @(x) accumarray(m, x, [12 1]);
    r.m.G         = ms(W.G)/1000;
    r.m.E_EV      = ms(sim.P_EV);
    r.m.PV_raw    = ms(pvo.P_raw);
    r.m.Ex_in     = ms(pvo.Ex_in);
    r.m.eta_PV    = ms(pvo.P_raw) ./ max(ms(pvo.E_inc), eps);
    r.m.psi_PV    = ms(pvo.P_raw) ./ max(ms(pvo.Ex_in), eps);
    r.m.psi_sun   = ms(pvo.Ex_in) ./ max(ms(pvo.E_inc), eps);
    r.m.diffuse   = ms(W.Gd + W.Gr) ./ max(ms(W.G), eps);
    r.m.SCR_total = (ms(sim.PV_to_EV) + ms(sim.batt_to_EV)) ./ ms(sim.P_EV);
    r.m.import    = ms(sim.import);
    r.m.export    = ms(sim.export);
    r.m.Tc_prod   = ms(pvo.Tc.*pvo.P_raw) ./ max(ms(pvo.P_raw), eps);
    r.m.Ta        = ms(W.Ta) ./ ms(ones(size(W.Ta)));
    r.m.dest_PV   = ms(pvo.Ex_dest);
    r.m.dest_oth  = ms(sim.wiring + sim.inv + sim.pcs_loss + sim.batt_loss);

    % IMD seasons: Winter Dec-Feb, Pre-monsoon Mar-May, Monsoon Jun-Sep, Post-monsoon Oct-Nov
    seas = {[12 1 2], [3 4 5], [6 7 8 9], [10 11]};
    r.season_names = {'Winter (DJF)','Pre-monsoon (MAM)','Monsoon (JJAS)','Post-monsoon (ON)'};
    for k = 1:4
        mk = ismember(m, seas{k});
        r.s.SCR_total(k) = (sum(sim.PV_to_EV(mk)) + sum(sim.batt_to_EV(mk))) / sum(sim.P_EV(mk));
        r.s.psi_PV(k)    = sum(pvo.P_raw(mk)) / sum(pvo.Ex_in(mk));
        r.s.eta_PV(k)    = sum(pvo.P_raw(mk)) / sum(pvo.E_inc(mk));
        r.s.psi_sun(k)   = sum(pvo.Ex_in(mk)) / sum(pvo.E_inc(mk));
        r.s.diffuse(k)   = sum(W.Gd(mk) + W.Gr(mk)) / sum(W.G(mk));
        r.s.grid_dep(k)  = sum(sim.import(mk)) / sum(sim.P_EV(mk));
        r.s.G_daily(k)   = sum(W.G(mk))/1000 / (sum(mk)/24);
    end
    r.s.SCR_cv = std(r.m.SCR_total)/mean(r.m.SCR_total);       % seasonal flatness (CoV)

    % Average daily profile (for plots)
    hr = W.hour + 1;
    hs = @(x) accumarray(hr, x, [24 1]) / 365;
    r.d.PV_ac = hs(sim.P_ac);  r.d.EV = hs(sim.P_EV);  r.d.import = hs(sim.import);
    r.d.batt_to_EV = hs(sim.batt_to_EV);  r.d.PV_to_EV = hs(sim.PV_to_EV);  r.d.export = hs(sim.export);
end
