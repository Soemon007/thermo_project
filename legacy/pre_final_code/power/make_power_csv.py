"""
make_power_csv.py
Builds Timeseries_<City>_NASAPOWER.csv (PVGIS column layout) from NASA POWER hourly data.

  python3 make_power_csv.py            # downloads 2023 data from the NASA POWER API (no key needed)

What it does
  1. Gets hourly GHI, DNI, DHI (CERES SYN1deg), T2M and WS10M (MERRA-2) for 2023, UTC.
     Each POWER value is the mean over HH:00-HH:59 UTC (checked: the centre of the daily
     irradiance curve sits ~0.5 h before solar noon), so it is stamped HH:30 like PVGIS.
  2. Converts horizontal irradiance to the 20 deg, south-facing plane:
       beam    Gb = DNI * cos(theta)
       diffuse Gd = DHI * [Ai*Rb + (1 - Ai)(1 + cos b)/2]      (Hay-Davies, Ai = DNI/I0)
       ground  Gr = GHI * rho * (1 - cos b)/2,  rho = 0.2
     with the sun position at mid-hour (Duffie & Beckman), sun below 5 deg -> isotropic only.
  3. Writes the file next to main.m in the PVGIS layout that load_weather.m reads.
"""
import json, urllib.request, datetime as dt
import numpy as np

CITIES = {'Jodhpur': (26.297, 73.035), 'Bengaluru': (12.977, 77.590), 'Guwahati': (26.181, 91.754)}
TILT, RHO, YEAR = 20, 0.2, 2023
PARAMS = 'ALLSKY_SFC_SW_DWN,ALLSKY_SFC_SW_DNI,ALLSKY_SFC_SW_DIFF,T2M,WS10M'


def fetch(lat, lon):
    url = ('https://power.larc.nasa.gov/api/temporal/hourly/point?parameters=' + PARAMS +
           f'&community=RE&longitude={lon}&latitude={lat}&start={YEAR}0101&end={YEAR}1231'
           '&format=JSON&time-standard=UTC')
    with urllib.request.urlopen(url, timeout=120) as r:
        p = json.load(r)['properties']['parameter']
    return {k: np.array(list(v.values()), dtype=float) for k, v in p.items()}


def to_plane(d, lat, lon):
    G, DNI, DHI = d['ALLSKY_SFC_SW_DWN'], d['ALLSKY_SFC_SW_DNI'], d['ALLSKY_SFC_SW_DIFF']
    hrs = np.arange(len(G)); n = hrs // 24 + 1; hu = (hrs % 24) + 0.5
    B = np.radians((n - 1) * 360 / 365)
    EoT = 229.2 * (0.000075 + 0.001868*np.cos(B) - 0.032077*np.sin(B)
                   - 0.014615*np.cos(2*B) - 0.04089*np.sin(2*B))
    dec = np.radians(23.45 * np.sin(np.radians(360 * (284 + n) / 365)))
    om = np.radians(15 * (hu + lon/15 + EoT/60 - 12))
    la, be = np.radians(lat), np.radians(TILT)
    cz = np.sin(la)*np.sin(dec) + np.cos(la)*np.cos(dec)*np.cos(om)
    ct = np.sin(dec)*np.sin(la - be) + np.cos(dec)*np.cos(la - be)*np.cos(om)
    I0 = 1367 * (1 + 0.033*np.cos(np.radians(360*n/365)))
    up = cz > 0.087
    Rb = np.where(up, np.maximum(ct, 0) / np.maximum(cz, 0.087), 0)
    Ai = np.where(up, np.clip(DNI / I0, 0, 1), 0)
    Gb = np.where(up, DNI * np.maximum(ct, 0), 0)
    Gd = DHI * (Ai*Rb + (1 - Ai)*(1 + np.cos(be))/2)
    Gr = G * RHO * (1 - np.cos(be)) / 2
    Hs = np.degrees(np.arcsin(np.clip(cz, -1, 1)))
    return Gb, Gd, Gr, Hs


def write(city, lat, lon, d, Gb, Gd, Gr, Hs, path):
    with open(path, 'w') as fh:
        fh.write(f'Latitude (decimal degrees):\t{lat:.3f}\nLongitude (decimal degrees):\t{lon:.3f}\n'
                 'Elevation (m):\tn/a\nRadiation database:\tNASA POWER hourly '
                 f'{YEAR} (CERES SYN1deg / MERRA-2); POA via Hay-Davies, albedo {RHO}\n\n\n'
                 f'Slope: {TILT} deg. \nAzimuth: 180 deg (south). \n'
                 'time,Gb(i),Gd(i),Gr(i),H_sun,T2m,WS10m,Int\n')
        t0 = dt.datetime(YEAR, 1, 1)
        for i in range(len(Gb)):
            s = (t0 + dt.timedelta(hours=i)).strftime('%Y%m%d:%H30')
            fh.write(f'{s},{Gb[i]:.2f},{Gd[i]:.2f},{Gr[i]:.2f},{Hs[i]:.2f},'
                     f'{d["T2M"][i]:.2f},{d["WS10M"][i]:.2f},0.0\n')
        fh.write('\nSource: NASA Langley Research Center (LaRC) POWER Project, https://power.larc.nasa.gov\n')


if __name__ == '__main__':
    for city, (lat, lon) in CITIES.items():
        d = fetch(lat, lon)
        assert all(len(v) == 8760 and (v > -900).all() for v in d.values()), f'{city}: missing data'
        Gb, Gd, Gr, Hs = to_plane(d, lat, lon)
        write(city, lat, lon, d, Gb, Gd, Gr, Hs, f'../Timeseries_{city}_NASAPOWER.csv')
        print(f'{city}: GHI {d["ALLSKY_SFC_SW_DWN"].sum()/1000:.0f}, POA {(Gb+Gd+Gr).sum()/1000:.0f} kWh/m2')
