function make_plots(R, S, sens, cities, Wx, SIM, P0)
% make_plots.m  -  all report figures, saved to figures/*.png
% City colours are fixed by entity (never by rank).
    col.Jodhpur   = [235 104  52]/255;
    col.Bengaluru = [ 27 175 122]/255;
    col.Guwahati  = [ 42 120 214]/255;
    ink = [0.32 0.32 0.31];
    mn = {'J','F','M','A','M','J','J','A','S','O','N','D'};
    fs = 11;
    if exist('OCTAVE_VERSION', 'builtin'), dg = char([194 176]); else, dg = char(176); end   % degree sign

    %% F1 - monthly climate inputs
    f = newfig(1000, 380);
    subplot(1,2,1); hold on;
    for c = 1:3, plot(1:12, R.(cities{c}).m.G, '-o', 'Color', col.(cities{c}), 'LineWidth', 2, 'MarkerSize', 5, 'MarkerFaceColor', col.(cities{c})); end
    style(gca, fs, mn); ylabel('Plane-of-array irradiation [kWh/m^2/month]'); title(['Solar resource (' P0.cfg.source_label ', 20' dg ' tilt)']);
    legend(cities, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend boxoff;
    subplot(1,2,2); hold on;
    for c = 1:3, plot(1:12, R.(cities{c}).m.Ta, '-o', 'Color', col.(cities{c}), 'LineWidth', 2, 'MarkerSize', 5, 'MarkerFaceColor', col.(cities{c})); end
    style(gca, fs, mn); ylabel(['Mean ambient temperature [' dg 'C]']); title('Ambient temperature');
    legend(cities, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend boxoff;
    save_fig(f, P0.cfg.outF, 'fig01_climate');

    %% F2 - monthly eta_PV and psi_PV (cell-temperature de-rating)
    f = newfig(1000, 380);
    subplot(1,2,1); hold on;
    for c = 1:3, plot(1:12, 100*R.(cities{c}).m.eta_PV, '-o', 'Color', col.(cities{c}), 'LineWidth', 2, 'MarkerSize', 5, 'MarkerFaceColor', col.(cities{c})); end
    style(gca, fs, mn); ylabel('\eta_{PV} = P / (A G)  [%]'); title('First Law efficiency of the PV cell');
    legend(cities, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend boxoff;
    subplot(1,2,2); hold on;
    for c = 1:3, plot(1:12, 100*R.(cities{c}).m.psi_PV, '-o', 'Color', col.(cities{c}), 'LineWidth', 2, 'MarkerSize', 5, 'MarkerFaceColor', col.(cities{c})); end
    style(gca, fs, mn); ylabel('\psi_{PV} = P / Ex_{in}  [%]'); title('Second Law (exergy) efficiency of the PV cell');
    legend(cities, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend boxoff;
    save_fig(f, P0.cfg.outF, 'fig02_monthly_eta_psi');

    %% F3 - monthly cell temperature vs ambient
    f = newfig(620, 400); hold on;
    for c = 1:3
        plot(1:12, R.(cities{c}).m.Tc_prod, '-o', 'Color', col.(cities{c}), 'LineWidth', 2, 'MarkerSize', 5, 'MarkerFaceColor', col.(cities{c}));
    end
    for c = 1:3, plot(1:12, R.(cities{c}).m.Ta, '--', 'Color', col.(cities{c}), 'LineWidth', 1.2); end
    style(gca, fs, mn); ylabel(['Temperature [' dg 'C]']);
    title('Energy-weighted cell temperature (solid) vs ambient (dashed)');
    legend(cities, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend boxoff;
    save_fig(f, P0.cfg.outF, 'fig03_cell_temperature');

    %% F4 - monthly solar coverage
    f = newfig(620, 400); hold on;
    for c = 1:3, plot(1:12, 100*R.(cities{c}).m.SCR_total, '-o', 'Color', col.(cities{c}), 'LineWidth', 2, 'MarkerSize', 5, 'MarkerFaceColor', col.(cities{c})); end
    style(gca, fs, mn); ylabel('Solar coverage of EV demand [%]'); ylim([0 100]);
    title('Monthly solar coverage ratio (PV direct + via battery)');
    legend(cities, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend boxoff;
    save_fig(f, P0.cfg.outF, 'fig04_monthly_SCR');

    %% F5 - fate of the solar exergy (system-level exergy flow, % of Ex_in)
    lab = {'PV optical loss','PV heat rejection','PV internal destruction','DC wiring','Inverter', ...
           'Battery + PCS','Delivered to EV','Exported to grid'};
    cmap = [0.80 0.80 0.78; 0.93 0.63 0.00; 0.89 0.29 0.28; 0.38 0.31 0.84; 0.91 0.48 0.64; ...
            0.00 0.51 0.00; 0.16 0.47 0.84; 0.11 0.69 0.48];
    X = zeros(3, 8);
    for c = 1:3
        r = R.(cities{c});
        X(c,:) = [r.Ex_PV_opt r.Ex_PV_heat r.Ex_PV_int r.Ex_dest_wir r.Ex_dest_inv ...
                  r.Ex_dest_pcs + r.Ex_dest_batt (r.E_EV - r.E_import) r.E_export] / r.Ex_in_PV * 100;
    end
    f = newfig(1000, 360);
    h = barh(1:3, X, 'stacked');
    for k = 1:8, set(h(k), 'FaceColor', cmap(k,:), 'EdgeColor', 'w'); end
    set(gca, 'YTick', 1:3, 'YTickLabel', cities, 'FontSize', fs, 'XColor', ink, 'YColor', ink, 'Box', 'off');
    xlabel('Share of incident solar exergy (Petela) [%]'); xlim([0 100]);
    title('Where the solar exergy goes (annual)');
    legend(lab, 'Location', 'southoutside', 'Orientation', 'horizontal', 'NumColumns', 4); legend boxoff;
    save_fig(f, P0.cfg.outF, 'fig05_exergy_fate');

    %% F6 - exergy destruction by subsystem
    f = newfig(1000, 400);
    subplot(1,2,1);
    Y = zeros(3,3);
    for c = 1:3, r = R.(cities{c}); Y(c,:) = [r.Ex_PV_opt r.Ex_PV_heat r.Ex_PV_int]/1000; end
    h = bar(1:3, Y, 'stacked');
    pc = [0.80 0.80 0.78; 0.93 0.63 0.00; 0.89 0.29 0.28];
    for k = 1:3, set(h(k), 'FaceColor', pc(k,:), 'EdgeColor', 'w'); end
    set(gca, 'XTickLabel', cities, 'FontSize', fs, 'Box', 'off', 'XColor', ink, 'YColor', ink);
    ylabel('Exergy destroyed / lost [MWh/yr]'); title('PV cell (~98 % of total)');
    legend({'Optical','Heat rejection','Internal'}, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend boxoff;
    subplot(1,2,2);
    Z = zeros(3,4);
    for c = 1:3, r = R.(cities{c}); Z(c,:) = [r.Ex_dest_inv r.Ex_dest_wir r.Ex_dest_pcs r.Ex_dest_batt]; end
    h = bar(1:3, Z);
    zc = [0.91 0.48 0.64; 0.38 0.31 0.84; 0.00 0.51 0.00; 0.16 0.47 0.84];
    for k = 1:4, set(h(k), 'FaceColor', zc(k,:), 'EdgeColor', 'w'); end
    set(gca, 'XTickLabel', cities, 'FontSize', fs, 'Box', 'off', 'XColor', ink, 'YColor', ink);
    ylabel('Exergy destroyed [kWh/yr]'); title('Balance of system (~2 % of total)');
    legend({'Inverter','DC wiring','Battery PCS','Battery I^2R'}, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend boxoff;
    save_fig(f, P0.cfg.outF, 'fig06_exergy_destruction');

    %% F7 - average daily dispatch
    f = newfig(1100, 360);
    for c = 1:3
        d = R.(cities{c}).d;
        subplot(1,3,c); hold on;
        h = area(0:23, [d.PV_to_EV d.batt_to_EV d.import]);
        ac = [0.93 0.63 0.00; 0.11 0.69 0.48; 0.62 0.62 0.60];
        for k = 1:3, set(h(k), 'FaceColor', ac(k,:), 'EdgeColor', 'none'); end
        plot(0:23, d.PV_ac, 'k-', 'LineWidth', 1.5);
        set(gca, 'FontSize', fs-1, 'XTick', 0:6:24, 'Box', 'off', 'XColor', ink, 'YColor', ink); xlim([0 23]); ylim([0 40]);
        xlabel('Hour of day (IST)'); if c == 1, ylabel('Average power [kW]'); end
        title(cities{c}); grid on;
        if c == 2
            legend({'PV \rightarrow EV','Battery \rightarrow EV','Grid \rightarrow EV','PV AC output'}, ...
                'Location', 'southoutside', 'Orientation', 'horizontal'); legend boxoff;
        end
    end
    save_fig(f, P0.cfg.outF, 'fig07_daily_dispatch');

    %% F8 - sensitivity
    f = newfig(1100, 380);
    subplot(1,3,1); hold on;
    for c = 1:3, plot(sens.N_mod*P0.pv.P_mod/1000, 100*S.pv.(cities{c})(:,1), '-o', 'Color', col.(cities{c}), 'LineWidth', 2, 'MarkerFaceColor', col.(cities{c})); end
    xlabel('PV array [kWp]'); ylabel('Solar coverage [%]'); title('PV size'); ylim([0 100]); grid on; set(gca, 'FontSize', fs-1, 'Box', 'off');
    subplot(1,3,2); hold on;
    for c = 1:3, plot(sens.batt_f*P0.batt.capacity_kWh, 100*S.batt.(cities{c})(:,1), '-o', 'Color', col.(cities{c}), 'LineWidth', 2, 'MarkerFaceColor', col.(cities{c})); end
    xlabel('Battery [kWh]'); title('Battery size'); ylim([0 100]); grid on; set(gca, 'FontSize', fs-1, 'Box', 'off');
    legend(cities, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend boxoff;
    subplot(1,3,3); hold on;
    for c = 1:3, plot(100*sens.G_scale, 100*S.G.(cities{c})(:,1), '-o', 'Color', col.(cities{c}), 'LineWidth', 2, 'MarkerFaceColor', col.(cities{c})); end
    xlabel(['Irradiance, % of ' P0.cfg.source_label]); title('Irradiance data uncertainty'); ylim([0 100]); grid on; set(gca, 'FontSize', fs-1, 'Box', 'off');
    save_fig(f, P0.cfg.outF, 'fig08_sensitivity');

    %% F9 - economics (reporting layer)
    f = newfig(1000, 380);
    subplot(1,2,1);
    V = zeros(3,3);
    for c = 1:3, e = R.(cities{c}).econ; V(c,:) = [e.LCOE_system R.(cities{c}).econ_pv.LCOE_system e.tariff]; end
    h = bar(1:3, V); set(h(1), 'FaceColor', [0.16 0.47 0.84], 'EdgeColor', 'w');
    set(h(2), 'FaceColor', [0.93 0.63 0.00], 'EdgeColor', 'w'); set(h(3), 'FaceColor', [0.62 0.62 0.60], 'EdgeColor', 'w');
    set(gca, 'XTickLabel', cities, 'FontSize', fs, 'Box', 'off'); ylabel('INR / kWh'); title('Solar LCOE vs EV-charging energy tariff');
    legend({'PV + battery','PV only','Grid tariff'}, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend boxoff;
    subplot(1,2,2);
    V = zeros(3,2);
    for c = 1:3, e = R.(cities{c}).econ; V(c,:) = [e.base.CO2_t e.stn.CO2_t]; end
    h = bar(1:3, V); set(h(1), 'FaceColor', [0.62 0.62 0.60], 'EdgeColor', 'w'); set(h(2), 'FaceColor', [0.11 0.69 0.48], 'EdgeColor', 'w');
    set(gca, 'XTickLabel', cities, 'FontSize', fs, 'Box', 'off'); ylabel('t CO_2 / yr'); title('Emissions from EV supply');
    legend({'Grid-only baseline','Solar station (grid import)'}, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend boxoff;
    save_fig(f, P0.cfg.outF, 'fig09_economics');

    %% F10 - hourly psi_PV vs diffuse share of the light (one point per daylight hour)
    f = newfig(620, 420); hold on;
    for c = 1:3
        pvo = SIM.(cities{c}).pv;  Wc = Wx.(cities{c});
        k = pvo.P_raw > 0.1*P0.pv.kWp;
        dfr = (Wc.Gd(k) + Wc.Gr(k)) ./ Wc.G(k);
        plot(100*dfr, 100*pvo.P_raw(k)./pvo.Ex_in(k), '.', 'Color', col.(cities{c}), 'MarkerSize', 4);
    end
    xlabel('Diffuse + ground share of the light [%]'); ylabel('Hourly \psi_{PV} [%]'); grid on; xlim([0 100]);
    title('Hourly exergy efficiency rises with the diffuse share'); set(gca, 'FontSize', fs, 'Box', 'off');
    legend(cities, 'Location', 'northwest'); legend boxoff;
    save_fig(f, P0.cfg.outF, 'fig10_psi_vs_diffuse');

    %% F11 - exergy content of sunlight, and psi_PV old vs new model
    f = newfig(1000, 380);
    subplot(1,2,1); hold on;
    for c = 1:3, plot(1:12, R.(cities{c}).m.psi_sun, '-o', 'Color', col.(cities{c}), 'LineWidth', 2, 'MarkerSize', 5, 'MarkerFaceColor', col.(cities{c})); end
    style(gca, fs, mn); ylabel('Ex_{in} / E_{in}  [-]'); title('Exergy content of the sunlight received');
    legend(cities, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend boxoff;
    subplot(1,2,2); hold on;
    for c = 1:3, plot(1:12, 100*R.(cities{c}).m.psi_PV, '-o', 'Color', col.(cities{c}), 'LineWidth', 2, 'MarkerSize', 5, 'MarkerFaceColor', col.(cities{c})); end
    for c = 1:3, plot(1:12, 100*S.model_m_old.(cities{c}), '--', 'Color', col.(cities{c}), 'LineWidth', 1.2); end
    style(gca, fs, mn); ylabel('\psi_{PV}  [%]'); title('\psi_{PV}: final model (solid) vs Checkpoint-2 model (dashed)');
    legend(cities, 'Location', 'southoutside', 'Orientation', 'horizontal'); legend boxoff;
    save_fig(f, P0.cfg.outF, 'fig11_sunlight_exergy');
    close all;
end

function f = newfig(w, h)
    f = figure('Visible', 'off', 'Color', 'w', 'Position', [50 50 w h], 'PaperPositionMode', 'auto');
end

function style(ax, fs, mn)
    set(ax, 'XTick', 1:12, 'XTickLabel', mn, 'FontSize', fs, 'Box', 'off');
    xlim([0.5 12.5]); grid on;
end

function save_fig(f, d, name)
    print(f, fullfile(d, [name '.png']), '-dpng', '-r150');
end
