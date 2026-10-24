#!/bin/bash
# tidy_folder.command - one-time move of the pre-final flat layout into legacy/.
# Moves only; nothing is deleted. Run once: double-click, or in Terminal:
#   bash ~/Desktop/thermo_project/tidy_folder.command
cd "$(dirname "$0")" || exit 1
mkdir -p legacy/checkpoint2_code legacy/pre_final_code legacy/pre_final_results/figures \
         legacy/original_downloads legacy/screenshots data/datasheets
mvq() { [ -e "$1" ] && mv -n "$1" "$2" && echo "moved $1 -> $2"; }
# superseded flat-layout code (current versions live in src/)
for f in battery_limits battery_model economics ems_dispatch export_tables load_weather make_plots \
         params postprocess pv_model radiation_exergy_factor simulate_station solar_geometry update_params; do
  mvq "$f.m" legacy/pre_final_code/
done
mvq power legacy/pre_final_code/
for f in archive/*.m; do mvq "$f" legacy/checkpoint2_code/; done
rmdir archive 2>/dev/null
# original weather downloads (renamed copies are in data/weather/)
for f in Timeseries_*.csv; do mvq "$f" legacy/original_downloads/; done
# datasheets and screenshots
for f in *.pdf; do mvq "$f" data/datasheets/; done
for f in PHOTO-*.jpg; do mvq "$f" legacy/screenshots/; done
# first-run outputs (flat results/, figures/) and the retired fig10 plot
for f in results/*.csv results/*.mat results/*.txt; do mvq "$f" legacy/pre_final_results/; done
for f in figures/*.png; do mvq "$f" legacy/pre_final_results/figures/; done
for d in ERA5 NASAPOWER; do mvq "figures/$d/fig10_psi_vs_Tc.png" "legacy/pre_final_results/figures/fig10_psi_vs_Tc_$d.png"; done
mvq "$0" legacy/
echo "Done. Run main.m from this folder."
