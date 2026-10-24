# Solar EV charging station: thermodynamic feasibility (CL207)

Hourly First and Second Law simulation of one fixed station design (49.6 kWp PV, 93.2 kWh LFP, 222 kWh/day EV load) in Jodhpur, Bengaluru and Guwahati.

## Run

Open MATLAB (R2016b+) or GNU Octave (6+) in this folder and run `main`.

- `main`: main case, NASA POWER 2021–2023 run back to back, results are 3-year means. Includes year-by-year runs, one-at-a-time sensitivity and a 200-draw Monte Carlo. About 25 min.
- `source = 'ERA5'; main`: cross-check on PVGIS-ERA5 2023, no Monte Carlo. About 3 min.

Outputs go to `results/<source>/` (CSV tables, `results.mat`, `console_output.txt`) and `figures/<source>/` (PNG).
Every hourly First Law and exergy balance is asserted to close; the run stops if one does not.

## Folder layout

```
main.m                    entry point
src/                      model functions (main.m adds this to the path)
data/weather/             NASAPOWER_<City>_<year>.csv (2021-2023, main), ERA5_<City>_2023.csv (cross-check)
data/raw_power/           NASA POWER API responses (horizontal GHI/DNI/DHI, T2M, WS10M) the weather files are built from
data/ev/                  measured charging sessions and the derived 24-h EV profiles
data/datasheets/          Trina NE19R module and REPT battery documents
tools/                    Python scripts that build the weather files and EV profiles
results/, figures/        outputs, one subfolder per weather source
legacy/                   superseded code, first-run outputs, original downloads, design screenshots
```

## Model files (`src/`)

| File | Role |
|---|---|
| `params.m` | Every fixed input: PV module, battery, converters, EV load, weather source and years, model switches |
| `ev_profile.m` | 24-h EV load in kW from `data/ev/ev_profiles.csv`, scaled to 222 kWh/day |
| `load_weather.m` | Reads PVGIS-layout CSVs, joins years, shifts UTC to IST, sanity-checks |
| `scale_weather.m` | Irradiance multiplier (sensitivity and Monte Carlo) |
| `solar_geometry.m` | Angle of incidence on the 20°, south-facing plane |
| `pv_model.m` | Cell temperature (convection + radiation balance), Huld low-light efficiency, power, solar exergy per component and its split |
| `radiation_exergy_factor.m` | Exergy factor of diluted (diffuse) radiation, tabulated by numerical integration |
| `calibrate_hfree.m` | Free-convection coefficient that reproduces the datasheet NOCT |
| `ems_dispatch.m`, `battery_limits.m` | Priority rule: PV to EV, surplus to battery then export, deficit from battery then grid |
| `battery_model.m` | I²R loss, lumped thermal model, entropy generation, Arrhenius capacity fade |
| `simulate_station.m` | The hourly loop and the hourly energy and exergy closures |
| `postprocess.m` | Annual (per average year), monthly, seasonal and daily-profile metrics |
| `economics.m` | Reporting layer: LCOE, NPV, payback, grid-only baseline, CO₂ |
| `update_params.m` | Recomputes derived values after a parameter change |
| `export_tables.m`, `make_plots.m` | CSV tables and figures |
| `prctile_.m` | Percentiles without a toolbox |

Model switches in `params.m`: `cfg.exergy_model` (`'split'` default, `'petela'` = Checkpoint 2), `cfg.lowlight` (Huld factor), `cfg.tc_model` (`'balance'` or `'noct'`), `ev.profile` (`'public'` default, `'workplace'`, `'residential'`, `'synthetic'`).

## Data

| Data | Source | Built by |
|---|---|---|
| Weather, main case | NASA POWER hourly API 2021–2023 (CERES SYN1deg irradiance, MERRA-2 temperature and wind), no key needed | `tools/make_power_csv.py` (Hay-Davies transposition to 20°, albedo 0.2). `--cached` rebuilds from `data/raw_power/` |
| Weather, cross-check | PVGIS-ERA5 hourly 2023, downloaded from PVGIS | original files, renamed |
| EV load timing | 72,856 charging sessions, South Korea 2022. "A dataset for multi-faceted analysis of electric vehicle charging transactions", *Scientific Data* 2024, figshare doi:10.6084/m9.figshare.22495141, CC BY 4.0 | `tools/make_ev_profile.py` (energy spread over each session's duration, hourly shares by charger location, scaled to 222 kWh/day) |
| Module, battery | Trina DT-M-0093-B datasheet; REPT ESS brochure | `data/datasheets/` |

## Monte Carlo inputs (only those with a defensible range)

| Input | Range | Basis |
|---|---|---|
| Irradiance scale | 0.93–1.07 | POWER GHI ≈ 0 % network bias vs BSRN; ±7 % kept for the 1° grid cell and transposition |
| Module efficiency | ±3 % | Datasheet Pmax measuring tolerance |
| NOCT | 41–45 °C | Datasheet 43 ± 2 °C |
| Inverter, PCS efficiency | 0.96–0.98 each | Project brief |
| Cell resistance | 0.30–0.90 mΩ | 0.30 mΩ AC value; DC resistance 2–3× AC |
| Battery price | INR 16k–25k/kWh | 2026 C&I LFP quotes (economics only) |
| Weather year | 2021, 2022 or 2023 | Equal probability |

Draws are uniform and paired across cities. Design, tariffs and the emission factor are fixed.

## Built-in checks

- Hourly First Law and exergy balances close to machine precision (asserted).
- PV internal exergy destruction is never negative (asserted).
- The baseline point of every sensitivity sweep reproduces the baseline run (asserted).
- Sun elevation matches PVGIS `H_sun` (mean error −0.2°); NASA POWER hour stamps checked against solar noon.
- The cell-temperature model reproduces the datasheet NOCT at NOCT test conditions by construction.
