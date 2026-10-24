function export_tables(R, S, Y, MC, U, sens, cities, yrs, P0)
% export_tables.m  -  CSV tables for the report (results/*.csv)
    % ---- Annual summary, one column per city ----
    names = {'POA irradiation [kWh/m2]','Mean ambient T [C]','Energy-weighted cell T [C]','Max cell T [C]', ...
        'Specific yield [kWh/kWp]','Performance ratio [-]','Low-light loss [%]','Temperature loss [%]', ...
        'Diffuse + ground share of irradiation [%]','Exergy content of sunlight Ex_in/E_in [-]', ...
        'eta_PV [%]','psi_PV [%]','eta_solar chain [%]','psi_solar chain [%]','psi_system incl grid [%]', ...
        'EV demand [kWh]','PV AC output [kWh]','PV->EV [kWh]','Battery->EV [kWh]','Grid import [kWh]','Grid export [kWh]', ...
        'SCR direct [%]','SCR total [%]','Grid dependency [%]','Self-consumption [%]', ...
        'Ex in (solar) [kWh]','Ex dest PV total [kWh]','  PV optical [kWh]','  PV heat rejection [kWh]','  PV internal [kWh]', ...
        'Ex dest wiring [kWh]','Ex dest inverter [kWh]','Ex dest PCS [kWh]','Ex dest battery [kWh]', ...
        'PV share of Ex dest [%]','Battery EFC [-]','Battery SOH end yr1 [-]','Max battery T rise [K]','Battery S_gen [kJ/K]', ...
        'Seasonal CoV of monthly SCR [-]', ...
        'Max hourly energy residual [kWh]','Max hourly exergy residual [kWh]'};
    M = zeros(numel(names), numel(cities));
    for c = 1:numel(cities)
        r = R.(cities{c});
        M(:,c) = [r.G_annual r.Ta_mean r.Tc_mean_prod r.Tc_max r.specific_yield r.PR 100*r.lowlight_loss 100*r.temp_loss ...
            100*r.diffuse_frac r.psi_sun ...
            100*r.eta_PV 100*r.psi_PV 100*r.eta_solar 100*r.psi_solar 100*r.psi_sys ...
            r.E_EV r.E_PV_ac r.E_PV_to_EV r.E_batt_to_EV r.E_import r.E_export ...
            100*r.SCR_direct 100*r.SCR_total 100*r.grid_dep 100*r.self_cons ...
            r.Ex_in_PV r.Ex_dest_PV r.Ex_PV_opt r.Ex_PV_heat r.Ex_PV_int ...
            r.Ex_dest_wir r.Ex_dest_inv r.Ex_dest_pcs r.Ex_dest_batt ...
            100*r.dest_split(1) r.EFC r.SOH_end r.dTb_max r.S_gen_batt r.s.SCR_cv ...
            r.res_energy r.res_exergy]';
    end
    write_csv(fullfile(P0.cfg.outR,'annual_summary.csv'), names, cities, M);

    % ---- Monthly ----
    fid = fopen(fullfile(P0.cfg.outR,'monthly.csv'), 'w');
    fprintf(fid, 'city,month,G_kWh_m2,Ta_C,Tc_prod_C,eta_PV,psi_PV,psi_sun,diffuse_share,SCR_total,import_kWh,export_kWh,Ex_dest_PV_kWh,Ex_dest_other_kWh\n');
    for c = 1:numel(cities)
        m = R.(cities{c}).m;
        for k = 1:12
            fprintf(fid, '%s,%d,%.2f,%.2f,%.2f,%.5f,%.5f,%.5f,%.4f,%.5f,%.1f,%.1f,%.1f,%.2f\n', cities{c}, k, m.G(k), m.Ta(k), ...
                m.Tc_prod(k), m.eta_PV(k), m.psi_PV(k), m.psi_sun(k), m.diffuse(k), ...
                m.SCR_total(k), m.import(k), m.export(k), m.dest_PV(k), m.dest_oth(k));
        end
    end
    fclose(fid);

    % ---- Seasonal ----
    fid = fopen(fullfile(P0.cfg.outR,'seasonal.csv'), 'w');
    fprintf(fid, 'city,season,G_kWh_m2_day,diffuse_share,psi_sun,eta_PV,psi_PV,SCR_total,grid_dependency\n');
    for c = 1:numel(cities)
        r = R.(cities{c});
        for k = 1:4
            fprintf(fid, '%s,%s,%.3f,%.4f,%.5f,%.5f,%.5f,%.5f,%.5f\n', cities{c}, r.season_names{k}, r.s.G_daily(k), ...
                r.s.diffuse(k), r.s.psi_sun(k), r.s.eta_PV(k), r.s.psi_PV(k), r.s.SCR_total(k), r.s.grid_dep(k));
        end
    end
    fclose(fid);

    % ---- Sensitivity ----
    fid = fopen(fullfile(P0.cfg.outR,'sensitivity.csv'), 'w');
    fprintf(fid, 'city,factor,value,SCR_total,metric2_name,metric2,metric3_name,metric3\n');
    for c = 1:numel(cities)
        city = cities{c};
        for i = 1:numel(sens.N_mod)
            x = S.pv.(city)(i,:);
            fprintf(fid, '%s,PV kWp,%.1f,%.5f,psi_solar,%.5f,export_fraction,%.5f\n', city, sens.N_mod(i)*P0.pv.P_mod/1000, x(1), x(2), x(3));
        end
        for i = 1:numel(sens.batt_f)
            x = S.batt.(city)(i,:);
            fprintf(fid, '%s,Battery kWh,%.1f,%.5f,psi_solar,%.5f,export_kWh,%.1f\n', city, sens.batt_f(i)*P0.batt.capacity_kWh, x(1), x(2), x(3));
        end
        for i = 1:numel(sens.G_scale)
            x = S.G.(city)(i,:);
            fprintf(fid, '%s,Irradiance scale,%.2f,%.5f,psi_PV,%.5f,specific_yield,%.1f\n', city, sens.G_scale(i), x(1), x(2), x(3));
        end
        x = S.tc.(city);
        fprintf(fid, '%s,Tc model NOCT vs balance,0,%.5f,yield_change_pct,%.3f,Tc_noct_minus_balance,%.3f\n', city, NaN, 100*(x(2)/x(1)-1), x(4)-x(3));
        x = S.R3.(city);
        fprintf(fid, '%s,Battery R x3,3,%.5f,Ex_dest_batt_kWh,%.1f,Ex_dest_batt_base_kWh,%.1f\n', city, x(4), x(2), x(1));
        for i = 1:numel(sens.ev)
            x = S.ev.(city)(i,:);
            fprintf(fid, '%s,EV profile %s,%d,%.5f,SCR_direct,%.5f,export_kWh,%.1f\n', city, sens.ev{i}, i, x(2), x(1), x(3));
        end
    end
    fclose(fid);

    % ---- EV load profiles used (kW, IST hour) ----
    fid = fopen(fullfile(P0.cfg.outR,'ev_profiles_used.csv'), 'w');
    fprintf(fid, 'hour');  fprintf(fid, ',%s_kW', sens.ev{:});  fprintf(fid, '\n');
    for h = 1:24, fprintf(fid, '%d', h-1); fprintf(fid, ',%.3f', S.ev_daily(h,:)); fprintf(fid, '\n'); end
    fclose(fid);

    % ---- Year by year ----
    fid = fopen(fullfile(P0.cfg.outR,'yearly.csv'), 'w');
    fprintf(fid, 'city,year,POA_kWh_m2,SCR_total,psi_PV,eta_PV,psi_sun,specific_yield,psi_PV_winter,psi_PV_premonsoon,psi_PV_monsoon,psi_PV_postmonsoon\n');
    for c = 1:numel(cities)
        for k = 1:numel(yrs)
            fprintf(fid, '%s,%d', cities{c}, yrs(k));  fprintf(fid, ',%.5f', Y.(cities{c})(k,:));  fprintf(fid, '\n');
        end
    end
    fclose(fid);

    % ---- Monte Carlo ----
    if MC.N > 0
        fid = fopen(fullfile(P0.cfg.outR,'uncertainty_inputs.csv'), 'w');
        fprintf(fid, 'input,low,high,justification\n');
        for k = 1:numel(U.name)
            fprintf(fid, '%s,%.6g,%.6g,"%s"\n', U.name{k}, U.lo(k), U.hi(k), U.why{k});
        end
        fprintf(fid, 'weather_year,%d,%d,"one of the NASA POWER years, equal probability"\n', yrs(1), yrs(end));
        fclose(fid);
        fid = fopen(fullfile(P0.cfg.outR,'monte_carlo_summary.csv'), 'w');
        fprintf(fid, 'city,metric,P5,P50,P95\n');
        mn = {'SCR_total_pct','psi_PV_pct'};
        for c = 1:numel(cities)
            for k = 1:2
                fprintf(fid, '%s,%s,%.4f,%.4f,%.4f\n', cities{c}, mn{k}, MC.summary.(cities{c})(k,:));
            end
            fprintf(fid, '%s,P(psi_PV monsoon > winter),%.3f,,\n', cities{c}, MC.p_monsoon_gt_winter.(cities{c}));
        end
        fprintf(fid, 'all,P(coverage Jodhpur > Bengaluru > Guwahati),%.3f,,\n', MC.p_cov_rank);
        fprintf(fid, 'all,P(psi_PV Jodhpur < Bengaluru),%.3f,,\n', MC.p_psi_JB);
        fprintf(fid, 'all,P(psi_PV Jodhpur < Guwahati),%.3f,,\n', MC.p_psi_JG);
        fclose(fid);
        fid = fopen(fullfile(P0.cfg.outR,'monte_carlo_draws.csv'), 'w');
        fprintf(fid, 'draw,year,G_scale,eta_ref_mult,NOCT,nu_inv,nu_pcs,cell_R_ohm');
        for c = 1:numel(cities)
            fprintf(fid, [repmat([',' cities{c} '_%s'], 1, 2)], 'SCR', 'psi_PV');
        end
        fprintf(fid, '\n');
        for i = 1:MC.N
            fprintf(fid, '%d,%d', i, yrs(MC.yr(i)));  fprintf(fid, ',%.6g', MC.X(i,:));
            for c = 1:numel(cities), fprintf(fid, ',%.5f', MC.(cities{c})(i,[1 2])); end
            fprintf(fid, '\n');
        end
        fclose(fid);
    end
end

function write_csv(file, rows, cols, M)
    fid = fopen(file, 'w');
    fprintf(fid, 'metric');  fprintf(fid, ',%s', cols{:});  fprintf(fid, '\n');
    for i = 1:numel(rows)
        fprintf(fid, '"%s"', rows{i});  fprintf(fid, ',%.6g', M(i,:));  fprintf(fid, '\n');
    end
    fclose(fid);
end
