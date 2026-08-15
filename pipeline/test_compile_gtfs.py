#!/usr/bin/env python3
"""test_compile_gtfs.py — offline test for compile_gtfs.py.

Builds a tiny synthetic GTFS feed in memory (bus + metro, including a
headway-based rail trip via frequencies.txt), compiles it, and asserts the
output SQLite is correct. Zero network, zero fixtures on disk.

Run: python3 pipeline/test_compile_gtfs.py
"""

import sqlite3
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path

FEED = {
    "agency.txt": (
        "agency_id,agency_name,agency_url,agency_timezone,agency_lang\n"
        "DF,Operadora Teste,https://example.com,America/Sao_Paulo,pt\n"
    ),
    "stops.txt": (
        "stop_id,stop_code,stop_name,stop_lat,stop_lon,parent_station,location_type\n"
        "S1,001,Rodoviária do Plano Piloto,-15.794,-47.882,,0\n"
        "S2,002,Esplanada dos Ministérios,-15.799,-47.864,,0\n"
        "M1,,Metrô Central,-15.794,-47.883,,1\n"
        "M1P,,Metrô Central Plataforma 1,-15.794,-47.883,M1,0\n"
        "M2,,Metrô Sul,-15.820,-47.900,,0\n"
    ),
    "routes.txt": (
        "route_id,agency_id,route_short_name,route_long_name,route_type,route_color,route_text_color\n"
        "R_BUS,DF,0.102,Rodoviária - Esplanada,3,00695C,FFFFFF\n"
        "R_METRO,DF,L1,Linha 1 - Laranja,1,FF8800,000000\n"
    ),
    "trips.txt": (
        "route_id,service_id,trip_id,trip_headsign,direction_id,shape_id\n"
        "R_BUS,WKD,T_BUS_1,Esplanada,0,SH1\n"
        "R_METRO,WKD,T_METRO_FREQ,Metrô Sul,0,\n"
    ),
    "stop_times.txt": (
        "trip_id,arrival_time,departure_time,stop_id,stop_sequence\n"
        "T_BUS_1,08:00:00,08:00:00,S1,1\n"
        "T_BUS_1,08:12:00,08:12:00,S2,2\n"
        "T_BUS_1,25:05:00,25:07:00,S2,3\n"
        "T_METRO_FREQ,06:00:00,06:00:00,M1P,1\n"
        "T_METRO_FREQ,06:20:00,06:21:00,M2,2\n"
    ),
    "calendar.txt": (
        "service_id,monday,tuesday,wednesday,thursday,friday,saturday,sunday,start_date,end_date\n"
        "WKD,1,1,1,1,1,0,0,20260101,20261231\n"
    ),
    "shapes.txt": (
        "shape_id,shape_pt_lat,shape_pt_lon,shape_pt_sequence\n"
        "SH1,-15.794,-47.882,1\n"
        "SH1,-15.799,-47.864,2\n"
    ),
    "frequencies.txt": (
        "trip_id,start_time,end_time,headway_secs,exact_times\n"
        "T_METRO_FREQ,06:00:00,07:00:00,600,0\n"
        "T_METRO_FREQ,08:00:00,08:30:00,900,0\n"
    ),
}


def build_feed(path):
    with zipfile.ZipFile(path, "w") as z:
        for name, content in FEED.items():
            z.writestr(name, content)


def main():
    tmp = Path(tempfile.mkdtemp(prefix="conexao-test-"))
    feed = tmp / "feed.zip"
    out = tmp / "transit.sqlite"
    build_feed(feed)

    compiler = Path(__file__).parent / "compile_gtfs.py"
    proc = subprocess.run(
        [sys.executable, str(compiler), str(feed), "-o", str(out),
         "--city", "testlandia"],
        capture_output=True, text=True)
    print(proc.stdout)
    if proc.returncode != 0:
        print(proc.stderr, file=sys.stderr)
        sys.exit("FAIL: compiler exited non-zero")

    db = sqlite3.connect(out)
    q = lambda sql: db.execute(sql).fetchone()[0]

    failures = []

    def check(label, actual, expected):
        ok = actual == expected
        print(f"  {'ok ' if ok else 'FAIL'} {label}: {actual}"
              + ("" if ok else f" (expected {expected})"))
        if not ok:
            failures.append(label)

    check("stops", q("SELECT COUNT(*) FROM stops"), 5)
    check("routes", q("SELECT COUNT(*) FROM routes"), 2)
    check("bus trips", q("SELECT COUNT(*) FROM trips WHERE trip_id='T_BUS_1'"), 1)
    check("freq trips materialized (6 in 06:00-07:00 @600s + 2 in 08:00-08:30 @900s)",
          q("SELECT COUNT(*) FROM trips WHERE trip_id LIKE 'T_METRO_FREQ#%'"), 8)
    check("second window expanded (regression: template deleted too early)",
          q("SELECT COUNT(*) FROM trips WHERE trip_id LIKE 'T_METRO_FREQ#%' "
            "AND CAST(substr(trip_id, instr(trip_id, '#') + 1) AS INT) >= 28800"), 2)
    check("template trip removed",
          q("SELECT COUNT(*) FROM trips WHERE trip_id='T_METRO_FREQ'"), 0)
    check("freq_exact=0 kept for honest labeling",
          q("SELECT freq_exact FROM trips WHERE trip_id LIKE 'T_METRO_FREQ#%' LIMIT 1"), 0)
    check("parent_station mapped to int",
          q("SELECT parent_i FROM stops WHERE stop_id='M1P'"),
          q("SELECT stop_i FROM stops WHERE stop_id='M1'"))
    check("stop_times for one freq trip",
          q("SELECT COUNT(*) FROM stop_times st JOIN trips t USING (trip_i) "
            "WHERE t.trip_id='T_METRO_FREQ#21600'"), 2)
    check("freq stop_times shifted (arrival 06:20 = 22800)",
          q("SELECT st.arrival_secs FROM stop_times st "
            "JOIN trips t USING (trip_i) "
            "WHERE t.trip_id='T_METRO_FREQ#21600' AND st.stop_sequence=2"),
          22800)
    check("arr == dep stored as NULL (read with COALESCE)",
          q("SELECT COALESCE(st.arrival_secs, st.departure_secs) "
            "FROM stop_times st JOIN trips t USING (trip_i) "
            "WHERE t.trip_id='T_BUS_1' AND st.stop_sequence=1"), 28800)
    check("25h time stored as 90300 secs",
          q("SELECT st.arrival_secs FROM stop_times st "
            "JOIN trips t USING (trip_i) "
            "WHERE t.trip_id='T_BUS_1' AND st.stop_sequence=3"), 90300)
    check("calendar", q("SELECT COUNT(*) FROM calendar"), 1)
    check("shape_pts", q("SELECT COUNT(*) FROM shape_pts"), 2)
    check("search: 'Rodoviária' matches stop + route",
          q("SELECT COUNT(*) FROM search WHERE search MATCH 'Rodoviária'"), 2)
    check("search: route by number",
          q("SELECT COUNT(*) FROM search WHERE search MATCH '\"0.102\"'"), 1)
    check("meta city_id",
          q("SELECT value FROM meta WHERE key='city_id'"), "testlandia")

    db.close()
    if failures:
        sys.exit(f"FAIL: {len(failures)} checks failed: {failures}")
    print("PASS: all checks green")


if __name__ == "__main__":
    main()
