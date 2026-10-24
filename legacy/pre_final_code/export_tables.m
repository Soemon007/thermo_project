function export_tables(R, S, sens, cities, P0)
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
        'Tariff [INR/kWh]','LCOE system [INR/kWh]','LCOE PV-only [INR/kWh]','NPV [lakh INR]','Simple payback [yr]', ...
        'PV-only: LCOE [INR/kWh]','PV-only: NPV [lakh INR]','PV-only: simple payback [yr]','PV-only: SCR [%]', ...
        'Grid-only cost [lakh INR/yr]','Station grid cost net [lakh INR/yr]','Grid-only CO2 [t/yr]','Station CO2 [t/yr]','CO2 avoided [t/yr]', ...
        'Max hourly energy residual [kWh]','Max hourly exergy residual [kWh]'};
    M = zeros(numel(names), numel(cities));
    for c = 1:numel(cities)
        r = R.(cities{c});  e = r.econ;
        M(:,c) = [r.G_annual r.Ta_mean r.Tc_mean_prod r.Tc_max r.specific_yield r.PR 100*r.lowlight_loss 100*r.temp_loss ...
            100*r.diffuse_frac r.psi_sun ...
            100*r.eta_PV 100*r.psi_PV 100*r.eta_solar 100*r.psi_solar 100*r.psi_sys ...
            r.E_EV r.E_PV_ac r.E_PV_to_EV r.E_batt_to_EV r.E_import r.E_export ...
            100*r.SCR_direct 100*r.SCR_total 100*r.grid_dep 100*r.self_cons ...
            r.Ex_in_PV r.Ex_dest_PV r.Ex_PV_opt r.Ex_PV_heat r.Ex_PV_int ...
            r.Ex_dest_wir r.Ex_dest_inv r.Ex_dest_pcs r.Ex_dest_batt ...
            100*r.dest_split(1) r.EFC r.SOH_end r.dTb_max r.S_gen_batt r.s.SCR_cv ...
            e.tariff e.LCOE_system e.LCOE_PV_only e.NPV/1e5 e.payback_simple ...
            r.econ_pv.LCOE_system r.econ_pv.NPV/1e5 r.econ_pv.payback_simple 100*r.SCR_total_nobatt ...
            e.base.cost/1e5 e.stn.cost/1e5 e.base.CO2_t e.stn.CO2_t e.CO2_avoided_t_per_yr ...
            r.res_energy r.res_exergy]';
    end
    write_csv(fullfile(P0.cfg.outR,'annual_summary.csv'), names, cities, M);

    % ---- Monthly ----
    fid = fopen(fullfile(P0.cfg.outR,'monthly.csv'), 'w');
    fprintf(fid, 'city,month,G_kWh_m2,Ta_C,Tc_prod_C,eta_PV,psi_PV,psi_PV_checkpoint2_model,psi_sun,diffuse_share,SCR_total,import_kWh,export_kWh,Ex_dest_PV_kWh,Ex_dest_other_kWh\n');
    for c = 1:numel(cities)
        m = R.(cities{c}).m;
        for k = 1:12
            fprintf(fid, '%s,%d,%.2f,%.2f,%.2f,%.5f,%.5f,%.5f,%.5f,%.4f,%.5f,%.1f,%.1f,%.1f,%.2f\n', cities{c}, k, m.G(k), m.Ta(k), ...
                m.Tc_prod(k), m.eta_PV(k), m.psi_PV(k), S.model_m_old.(cities{c})(k), m.psi_sun(k), m.diffuse(k), ...
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

    % ---- PV model variants ----
    fid = fopen(fullfile(P0.cfg.outR,'model_comparison.csv'), 'w');
    fprintf(fid, 'city,model,psi_PV,eta_PV,psi_sun,specific_yield,SCR_total,psi_PV_winter,psi_PV_premonsoon,psi_PV_monsoon,psi_PV_postmonsoon\n');
    vn = {'Checkpoint 2 (Petela all light; no low-light)','Split exergy only','Low-light only','Final (split exergy + low-light)'};
    for c = 1:numel(cities)
        for v = 1:4
            fprintf(fid, '%s,%s', cities{c}, vn{v});  fprintf(fid, ',%.5f', S.model.(cities{c})(v,:));  fprintf(fid, '\n');
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
    end
    fclose(fid);
end

function write_csv(file, rows, cols, M)
    fid = fopen(file, 'w');
    fprintf(fid, 'metric');  fprintf(fid, ',%s', cols{:});  fprintf(fid, '\n');
    for i = 1:numel(rows)
        fprintf(fid, '"%s"', rows{i});  fprintf(fid, ',%.6g', M(i,:));  fprintf(fid, '\n');
    end
    fclose(fid);
end
