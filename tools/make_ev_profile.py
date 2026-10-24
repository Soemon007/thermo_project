"""
make_ev_profile.py
Builds the station's daily EV load profile from MEASURED charging sessions.

Source: "A dataset for multi-faceted analysis of electric vehicle charging transactions",
        Scientific Data 11, 2024 (doi:10.1038/s41597-024-02942-9). Data on figshare,
        doi:10.6084/m9.figshare.22495141, file ChargingRecords.csv, CC BY 4.0.
        72,856 sessions, 2,119 chargers, South Korea, 2022.

Method
  1. Keep sessions with 0 < duration <= 48 h and energy > 0.
  2. Spread each session's energy evenly over its duration (minute resolution) and add it
     to the local clock hour it falls in (hours 0..23). This is the hourly energy shape.
  3. Normalise the 24 hourly totals to shares that sum to 1, then scale to the project's
     fixed demand of 222 kWh/day, so only the TIMING comes from the data.

Groups (charger location categories in the dataset)
  public      = public area, public institution, public parking lot   -> main case
  workplace   = company                                               -> sensitivity
  residential = apartment                                             -> sensitivity

  python3 make_ev_profile.py ChargingRecords.csv      (original figshare file)
  python3 make_ev_profile.py ChargingRecords_compact.csv
Writes ev_profiles.csv next to the input file.
"""
import csv, sys, os, datetime as dt
import numpy as np

GROUPS = {'public': {'public area', 'public institution', 'public parking lot'},
          'workplace': {'company'},
          'residential': {'apartment'}}
DAILY_KWH = 222.0


def parse_time(s):
    s = s.strip()
    d, t = s.split(' ')
    h, m = t.split(':')[:2]
    return dt.datetime.strptime(d, '%Y-%m-%d') + dt.timedelta(hours=int(h), minutes=int(m))


def build(path):
    E = {g: np.zeros(24) for g in GROUPS}
    n = {g: 0 for g in GROUPS}
    kept = dropped = 0
    with open(path, newline='') as fh:
        rd = csv.DictReader(fh)
        for r in rd:
            loc = r['Location']
            g = next((k for k, v in GROUPS.items() if loc in v), None)
            if g is None:
                continue
            start = parse_time(r.get('StartDatetime') or r.get('StartDatetime '))
            dur = float(r.get('Duration') or r.get('Duration_min'))
            kwh = float(r.get('Demand') or r.get('Demand_kWh'))
            if not (0 < dur <= 48*60 and kwh > 0):
                dropped += 1
                continue
            kept += 1
            n[g] += 1
            m0 = start.hour*60 + start.minute
            mins = (m0 + np.arange(int(round(dur)))) % 1440      # minute-of-day of each charging minute
            np.add.at(E[g], mins // 60, kwh / len(mins))
    return E, n, kept, dropped


if __name__ == '__main__':
    path = sys.argv[1] if len(sys.argv) > 1 else 'ChargingRecords.csv'
    E, n, kept, dropped = build(path)
    out = os.path.join(os.path.dirname(os.path.abspath(path)), 'ev_profiles.csv')
    with open(out, 'w', newline='') as fh:
        w = csv.writer(fh)
        w.writerow(['hour'] + [f'{g}_share' for g in GROUPS] + [f'{g}_kW' for g in GROUPS])
        shares = {g: E[g] / E[g].sum() for g in GROUPS}
        for h in range(24):
            w.writerow([h] + [f'{shares[g][h]:.6f}' for g in GROUPS] +
                       [f'{DAILY_KWH*shares[g][h]:.4f}' for g in GROUPS])
    print(f'sessions kept {kept}, dropped {dropped}; per group {n}')
    for g in GROUPS:
        s = E[g] / E[g].sum()
        print(f'{g:12s} daytime 06-18 share {s[6:18].sum():.3f} | peak hour {int(np.argmax(s))} '
              f'| energy {E[g].sum():.0f} kWh')
    print('wrote', out)
