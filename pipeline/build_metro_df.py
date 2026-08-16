#!/usr/bin/env python3
"""Builds the community GTFS feed for Metrô-DF (cities/brasilia.yaml: metro-df).

Why this exists: the official DF GTFS is legally mandated (Lei 7.836/2025)
but not yet published. Metrô-DF publishes timetables as HTML/PDF only. This
script encodes the two metro lines as a small GTFS feed so Brasília (the
lead/dogfood city) has real routing.

Data provenance — be honest about it:
  * Station names + coordinates: OpenStreetMap (ODbL), via Overpass.
  * Line topology: Metrô-DF published map (Verde: Central – Ceilândia;
    Laranja: Central – Samambaia; shared trunk Central ↔ Águas Claras).
  * Stop-to-stop times: INTERPOLATED from haversine distance at 36 km/h
    average + 25 s dwell — NOT measured run times.
  * Headways: plausible published-pattern approximations (peak ~8 min,
    off-peak ~12 min), encoded with exact_times=0 so the app labels
    departures as approximate.

Output: pipeline/tmp/metro_df_gtfs.zip (input for compile_gtfs.py).

Usage: python3 pipeline/build_metro_df.py
"""

import io
import math
import zipfile
from pathlib import Path

OUT = Path(__file__).parent / "tmp" / "metro_df_gtfs.zip"

# Station: (id, name, lat, lon) — OpenStreetMap, 2026-08-15.
TRUNK = [  # Central -> Águas Claras (shared by both lines)
    ("central", "Central", -15.793249, -47.884640),
    ("galeria", "Galeria", -15.799484, -47.886071),
    ("sul_102", "102 Sul", -15.805736, -47.889444),
    ("sul_106", "106 Sul", -15.814986, -47.898651),
    ("sul_108", "108 Sul", -15.818961, -47.903967),
    ("sul_110", "110 Sul", -15.822839, -47.909348),
    ("sul_112", "112 Sul", -15.826735, -47.914721),
    ("sul_114", "114 Sul", -15.830636, -47.920119),
    ("asa_sul", "Asa Sul", -15.837054, -47.932523),
    ("shopping", "Shopping", -15.832429, -47.950670),
    ("feira", "Feira", -15.823047, -47.975015),
    ("guara", "Guará", -15.826680, -47.983382),
    ("arniqueiras", "Arniqueiras", -15.836727, -48.017057),
    ("aguas_claras", "Águas Claras", -15.840001, -48.028256),
]
VERDE_BRANCH = [  # Águas Claras -> Ceilândia
    ("concessionarias", "Concessionárias", -15.835151, -48.038634),
    ("estrada_parque", "Estrada Parque", -15.832387, -48.045278),
    ("praca_relogio", "Praça do Relógio", -15.833277, -48.056332),
    ("centro_metropolitano", "Centro Metropolitano", -15.835449, -48.086154),
    ("ceilandia_sul", "Ceilândia Sul", -15.837780, -48.103294),
    ("guariroba", "Guariroba", -15.830618, -48.107302),
    ("ceilandia_centro", "Ceilândia Centro", -15.822278, -48.111910),
    ("ceilandia_norte", "Ceilândia Norte", -15.814885, -48.116135),
    ("ceilandia", "Ceilândia", -15.805572, -48.121314),
]
LARANJA_BRANCH = [  # Águas Claras -> Samambaia
    ("taguatinga_sul", "Taguatinga Sul", -15.851847, -48.041885),
    ("furnas", "Furnas", -15.864949, -48.059804),
    ("samambaia_sul", "Samambaia Sul", -15.869041, -48.071582),
    ("samambaia", "Samambaia", -15.873682, -48.084911),
]

LINES = {
    "verde": TRUNK + VERDE_BRANCH,
    "laranja": TRUNK + LARANJA_BRANCH,
}

AVG_KMH = 36.0   # metro average incl. accel/decel, interpolated
DWELL_S = 25     # per intermediate station


def haversine_m(a, b):
    lat1, lon1, lat2, lon2 = map(math.radians, (a[2], a[3], b[2], b[3]))
    h = (math.sin((lat2 - lat1) / 2) ** 2
         + math.cos(lat1) * math.cos(lat2) * math.sin((lon2 - lon1) / 2) ** 2)
    return 2 * 6371000 * math.asin(math.sqrt(h))


def leg_seconds(a, b):
    return round(haversine_m(a, b) / (AVG_KMH * 1000 / 3600)) + DWELL_S


def hms(seconds):
    h, rem = divmod(seconds, 3600)
    m, s = divmod(rem, 60)
    return f"{h:02d}:{m:02d}:{s:02d}"


def csv(name, header, rows):
    buf = io.StringIO()
    buf.write(",".join(header) + "\n")
    for r in rows:
        buf.write(",".join(str(x) for x in r) + "\n")
    return name, buf.getvalue()


def main():
    files = []

    files.append(csv("agency.txt",
                     ["agency_id", "agency_name", "agency_url",
                      "agency_timezone", "agency_lang"],
                     [("metrodf", "Metrô-DF (feed comunitário)",
                       "https://www.metro.df.gov.br/",
                       "America/Sao_Paulo", "pt")]))

    seen = {}
    for line in LINES.values():
        for sid, name, lat, lon in line:
            seen[sid] = (name, lat, lon)
    files.append(csv("stops.txt",
                     ["stop_id", "stop_name", "stop_lat", "stop_lon",
                      "location_type"],
                     [(sid, n, la, lo, 0)
                      for sid, (n, la, lo) in seen.items()]))

    files.append(csv("routes.txt",
                     ["route_id", "agency_id", "route_short_name",
                      "route_long_name", "route_type"],
                     [("verde", "metrodf", "Verde",
                       "Linha Verde: Central – Ceilândia", 1),
                      ("laranja", "metrodf", "Laranja",
                       "Linha Laranja: Central – Samambaia", 1)]))

    # One weekday + one weekend service; frequencies carry the schedule.
    files.append(csv("calendar.txt",
                     ["service_id", "monday", "tuesday", "wednesday",
                      "thursday", "friday", "saturday", "sunday",
                      "start_date", "end_date"],
                     [("weekday", 1, 1, 1, 1, 1, 0, 0, "20260101", "20361231"),
                      ("saturday", 0, 0, 0, 0, 0, 1, 0, "20260101", "20361231"),
                      ("sunday", 0, 0, 0, 0, 0, 0, 1, "20260101", "20361231")]))

    trips, stop_times, freqs = [], [], []
    for route_id, stations in LINES.items():
        for direction, seq in ((0, stations), (1, stations[::-1])):
            terminus = seq[-1][1]
            for svc in ("weekday", "saturday", "sunday"):
                trip_id = f"{route_id}_{direction}_{svc}"
                trips.append((trip_id, route_id, svc,
                              f"Sentido {terminus}", direction))
                t = 0
                for i, st in enumerate(seq):
                    if i:
                        t += leg_seconds(seq[i - 1], st)
                    stop_times.append((trip_id, hms(t), hms(t),
                                       st[0], i + 1))
                # Headway windows (seconds). exact_times=0: the app must
                # label these departures as approximate — they are.
                if svc == "weekday":
                    windows = [(5 * 3600, 6 * 3600, 720),
                               (6 * 3600, 9 * 3600, 480),
                               (9 * 3600, 16 * 3600, 720),
                               (16 * 3600, 20 * 3600, 480),
                               (20 * 3600, 24 * 3600, 720)]
                elif svc == "saturday":
                    windows = [(6 * 3600, 23 * 3600, 720)]
                else:
                    windows = [(7 * 3600, 23 * 3600, 900)]
                for start, end, headway in windows:
                    freqs.append((trip_id, hms(start), hms(end), headway, 0))

    files.append(csv("trips.txt",
                     ["trip_id", "route_id", "service_id",
                      "trip_headsign", "direction_id"],
                     trips))
    files.append(csv("stop_times.txt",
                     ["trip_id", "arrival_time", "departure_time",
                      "stop_id", "stop_sequence"],
                     stop_times))
    files.append(csv("frequencies.txt",
                     ["trip_id", "start_time", "end_time",
                      "headway_secs", "exact_times"],
                     freqs))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUT, "w", zipfile.ZIP_DEFLATED) as z:
        for name, content in files:
            z.writestr(name, content)

    print(f"wrote {OUT} ({OUT.stat().st_size} bytes)")
    print(f"  stops={len(seen)} routes=2 trips={len(trips)} "
          f"stop_times={len(stop_times)} freq_windows={len(freqs)}")
    for route_id, stations in LINES.items():
        total = sum(leg_seconds(a, b) for a, b in zip(stations, stations[1:]))
        print(f"  {route_id}: {len(stations)} stations, "
              f"end-to-end ≈ {total // 60} min (interpolated)")


if __name__ == "__main__":
    main()
