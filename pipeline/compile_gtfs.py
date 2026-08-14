#!/usr/bin/env python3
"""compile_gtfs.py — GTFS zip -> SQLite city-pack database.

Part of the Conexão serverless data pipeline (see docs/ARCHITECTURE.md).
Stdlib only (zipfile, csv, sqlite3) — no pip installs, CI-friendly.

What it does:
  1. Parses the GTFS text files from the zip.
  2. Loads a normalized schema (stops, routes, trips, stop_times, calendar,
     calendar_dates, shapes). Times are stored as integer seconds past
     noon-minus-12h, per GTFS convention (values >= 24:00:00 are legal).
  3. MATERIALIZES frequencies.txt into explicit trips: CSA scans connections,
     not headways (plan §3.2). Each frequency window becomes concrete trips
     spaced `headway_secs` apart; the template trip is removed. Generated
     trips carry freq_exact = frequencies.exact_times so the app can label
     "a cada ~X min" honestly instead of fake precision.
  4. Builds an FTS5 search index (stops + routes) for on-device search.
  5. Runs a blocking quality gate: required files/columns, referential
     sanity, row counts. Fails non-zero on errors — CI relies on this.

All feed data is UNTRUSTED INPUT (plan §11A): parameterized SQL only,
row/byte caps, zip-bomb guards.

Usage:
  python3 compile_gtfs.py feed.zip -o transit.sqlite [--city CITY_ID]
"""

import argparse
import csv
import sqlite3
import sys
import zipfile
from pathlib import Path

# --- untrusted-input guards (plan §11A.2) -----------------------------------
MAX_ZIP_UNCOMPRESSED = 512 * 1024 * 1024   # 512 MiB decompressed cap
MAX_ROWS_PER_FILE = 10_000_000             # stop_times of huge feeds fit here
MAX_FIELD_LEN = 4096

REQUIRED_FILES = ("stops.txt", "routes.txt", "trips.txt", "stop_times.txt")

SCHEMA = """
CREATE TABLE agency (
  agency_id TEXT PRIMARY KEY, name TEXT, url TEXT, timezone TEXT, lang TEXT);
CREATE TABLE stops (
  stop_id TEXT PRIMARY KEY, code TEXT, name TEXT, lat REAL, lon REAL,
  parent_station TEXT, location_type INTEGER DEFAULT 0);
CREATE TABLE routes (
  route_id TEXT PRIMARY KEY, agency_id TEXT, short_name TEXT, long_name TEXT,
  route_type INTEGER, color TEXT, text_color TEXT);
CREATE TABLE trips (
  trip_id TEXT PRIMARY KEY, route_id TEXT, service_id TEXT, headsign TEXT,
  direction_id INTEGER, shape_id TEXT, freq_exact INTEGER);
CREATE TABLE stop_times (
  trip_id TEXT, stop_sequence INTEGER, stop_id TEXT,
  arrival_secs INTEGER, departure_secs INTEGER,
  PRIMARY KEY (trip_id, stop_sequence));
CREATE TABLE calendar (
  service_id TEXT PRIMARY KEY, monday INTEGER, tuesday INTEGER,
  wednesday INTEGER, thursday INTEGER, friday INTEGER, saturday INTEGER,
  sunday INTEGER, start_date TEXT, end_date TEXT);
CREATE TABLE calendar_dates (
  service_id TEXT, date TEXT, exception_type INTEGER);
CREATE TABLE shapes (
  shape_id TEXT, pt_lat REAL, pt_lon REAL, pt_sequence INTEGER,
  PRIMARY KEY (shape_id, pt_sequence));
CREATE INDEX idx_stop_times_stop ON stop_times(stop_id);
CREATE INDEX idx_stop_times_dep ON stop_times(departure_secs);
CREATE INDEX idx_trips_route ON trips(route_id);
CREATE INDEX idx_stops_parent ON stops(parent_station);
CREATE INDEX idx_stops_geo ON stops(lat, lon);
"""


def die(msg, code=1):
    print(f"ERROR: {msg}", file=sys.stderr)
    sys.exit(code)


def parse_time(value):
    """'25:30:00' -> seconds (GTFS allows >= 24h). None if blank/invalid."""
    if not value:
        return None
    try:
        h, m, s = value.strip().split(":")
        return int(h) * 3600 + int(m) * 60 + int(s)
    except (ValueError, AttributeError):
        return None


def clean(row):
    return {k: (v[:MAX_FIELD_LEN] if isinstance(v, str) else v)
            for k, v in row.items()}


class Feed:
    """Streams rows from a GTFS zip with guards."""

    def __init__(self, zip_path):
        self.zf = zipfile.ZipFile(zip_path)
        total = sum(i.file_size for i in self.zf.infolist())
        if total > MAX_ZIP_UNCOMPRESSED:
            die(f"feed decompresses to {total / 1e6:.0f} MB "
                f"(cap {MAX_ZIP_UNCOMPRESSED // 2**20} MiB) — possible zip bomb")
        self.names = {Path(n).name for n in self.zf.namelist()
                      if not n.endswith("/")}

    def has(self, name):
        return name in self.names

    def rows(self, name):
        """Yield dict rows for name, or nothing if the file is absent."""
        if not self.has(name):
            return
        with self.zf.open(name) as f:
            text = (line.decode("utf-8-sig", errors="replace")
                    for line in f)
            reader = csv.DictReader(text)
            n = 0
            for row in reader:
                n += 1
                if n > MAX_ROWS_PER_FILE:
                    die(f"{name} exceeds {MAX_ROWS_PER_FILE} rows")
                yield clean(row)


def load_feed(cur, feed):
    counts = {}

    for r in feed.rows("agency.txt") or []:
        cur.execute("INSERT OR REPLACE INTO agency VALUES (?,?,?,?,?)",
                    (r.get("agency_id") or "", r.get("agency_name"),
                     r.get("agency_url"), r.get("agency_timezone"),
                     r.get("agency_lang")))

    n = 0
    for r in feed.rows("stops.txt"):
        cur.execute(
            "INSERT OR REPLACE INTO stops VALUES (?,?,?,?,?,?,?)",
            (r["stop_id"], r.get("stop_code"), r.get("stop_name"),
             float(r["stop_lat"]) if r.get("stop_lat") else None,
             float(r["stop_lon"]) if r.get("stop_lon") else None,
             r.get("parent_station") or None,
             int(r["location_type"] or 0)))
        n += 1
    counts["stops"] = n

    n = 0
    for r in feed.rows("routes.txt"):
        cur.execute(
            "INSERT OR REPLACE INTO routes VALUES (?,?,?,?,?,?,?)",
            (r["route_id"], r.get("agency_id"), r.get("route_short_name"),
             r.get("route_long_name"), int(r["route_type"]),
             r.get("route_color"), r.get("route_text_color")))
        n += 1
    counts["routes"] = n

    n = 0
    for r in feed.rows("trips.txt"):
        cur.execute(
            "INSERT OR REPLACE INTO trips VALUES (?,?,?,?,?,?,NULL)",
            (r["trip_id"], r["route_id"], r["service_id"],
             r.get("trip_headsign"),
             int(r["direction_id"]) if r.get("direction_id") else None,
             r.get("shape_id")))
        n += 1
    counts["trips"] = n

    n = skipped = 0
    for r in feed.rows("stop_times.txt"):
        arr = parse_time(r.get("arrival_time"))
        dep = parse_time(r.get("departure_time"))
        if arr is None and dep is None:
            skipped += 1
            continue
        cur.execute(
            "INSERT INTO stop_times VALUES (?,?,?,?,?)",
            (r["trip_id"], int(r["stop_sequence"]), r["stop_id"],
             arr, dep))
        n += 1
    counts["stop_times"] = n
    if skipped:
        print(f"  note: {skipped} stop_times rows without times skipped")

    n = 0
    for r in feed.rows("calendar.txt") or []:
        cur.execute(
            "INSERT OR REPLACE INTO calendar VALUES (?,?,?,?,?,?,?,?,?,?)",
            (r["service_id"], *[int(r.get(d) or 0) for d in
              ("monday", "tuesday", "wednesday", "thursday", "friday",
               "saturday", "sunday")],
             r.get("start_date"), r.get("end_date")))
        n += 1
    counts["calendar"] = n

    n = 0
    for r in feed.rows("calendar_dates.txt") or []:
        cur.execute("INSERT INTO calendar_dates VALUES (?,?,?)",
                    (r["service_id"], r["date"],
                     int(r["exception_type"] or 1)))
        n += 1
    counts["calendar_dates"] = n

    n = 0
    for r in feed.rows("shapes.txt") or []:
        cur.execute("INSERT INTO shapes VALUES (?,?,?,?)",
                    (r["shape_id"], float(r["shape_pt_lat"]),
                     float(r["shape_pt_lon"]),
                     int(float(r["shape_pt_sequence"]))))
        n += 1
    counts["shapes"] = n

    return counts


def materialize_frequencies(cur, feed):
    """Expand frequencies.txt windows into explicit trips. Returns count."""
    if not feed.has("frequencies.txt"):
        return 0

    made = 0
    for r in feed.rows("frequencies.txt"):
        tpl = r["trip_id"]
        start, end = parse_time(r["start_time"]), parse_time(r["end_time"])
        headway = int(r["headway_secs"])
        exact = 1 if r.get("exact_times") == "1" else 0
        if start is None or end is None or headway <= 0:
            continue

        tpl_st = cur.execute(
            "SELECT stop_sequence, stop_id, arrival_secs, departure_secs "
            "FROM stop_times WHERE trip_id=? ORDER BY stop_sequence",
            (tpl,)).fetchall()
        if not tpl_st:
            continue
        base_dep = tpl_st[0][3] if tpl_st[0][3] is not None else tpl_st[0][2]
        if base_dep is None:
            continue
        tpl_info = cur.execute(
            "SELECT route_id, service_id, headsign, direction_id, shape_id "
            "FROM trips WHERE trip_id=?", (tpl,)).fetchone()

        for t in range(start, end, headway):
            off = t - base_dep
            new_id = f"{tpl}#{t}"
            cur.execute(
                "INSERT INTO trips VALUES (?,?,?,?,?,?,?)",
                (new_id, *tpl_info, exact))
            cur.executemany(
                "INSERT INTO stop_times VALUES (?,?,?,?,?)",
                [(new_id, seq, sid,
                  a + off if a is not None else None,
                  d + off if d is not None else None)
                 for seq, sid, a, d in tpl_st])
            made += 1

        # Remove the headway template so CSA never sees a phantom trip.
        cur.execute("DELETE FROM stop_times WHERE trip_id=?", (tpl,))
        cur.execute("DELETE FROM trips WHERE trip_id=?", (tpl,))
    return made


def build_search_index(cur):
    try:
        cur.execute(
            "CREATE VIRTUAL TABLE search USING fts5(name, kind, ref_id, "
            "tokenize='trigram')")
    except sqlite3.OperationalError:
        cur.execute(
            "CREATE VIRTUAL TABLE search USING fts5(name, kind, ref_id)")
    cur.execute(
        "INSERT INTO search SELECT name, 'stop', stop_id FROM stops "
        "WHERE name IS NOT NULL AND (location_type IS NULL OR location_type = 0)")
    cur.execute(
        "INSERT INTO search SELECT "
        "COALESCE(short_name,'') || ' ' || COALESCE(long_name,''), "
        "'route', route_id FROM routes")


def quality_gate(cur, counts):
    """Blocking checks — CI treats any failure as a broken pack."""
    problems = []
    if counts.get("stops", 0) == 0:
        problems.append("no stops parsed")
    if counts.get("routes", 0) == 0:
        problems.append("no routes parsed")
    if counts.get("trips", 0) == 0:
        problems.append("no trips parsed")
    if counts.get("stop_times", 0) == 0:
        problems.append("no stop_times parsed")
    if counts.get("calendar", 0) == 0 and counts.get("calendar_dates", 0) == 0:
        problems.append("neither calendar.txt nor calendar_dates.txt present")

    orphans = cur.execute(
        "SELECT COUNT(*) FROM stop_times st "
        "LEFT JOIN stops s ON s.stop_id = st.stop_id "
        "WHERE s.stop_id IS NULL").fetchone()[0]
    if orphans:
        problems.append(f"{orphans} stop_times reference unknown stops")
    dead = cur.execute(
        "SELECT COUNT(*) FROM trips t "
        "LEFT JOIN routes r ON r.route_id = t.route_id "
        "WHERE r.route_id IS NULL").fetchone()[0]
    if dead:
        problems.append(f"{dead} trips reference unknown routes")

    if problems:
        for p in problems:
            print(f"  QUALITY GATE FAIL: {p}", file=sys.stderr)
        die("quality gate failed — pack not written")


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("feed", help="GTFS zip file")
    ap.add_argument("-o", "--out", required=True, help="output SQLite path")
    ap.add_argument("--city", help="city id (metadata only)")
    args = ap.parse_args()

    feed = Feed(args.feed)
    for f in REQUIRED_FILES:
        if not feed.has(f):
            die(f"required GTFS file missing: {f}")

    out = Path(args.out)
    out.unlink(missing_ok=True)
    db = sqlite3.connect(out)
    cur = db.cursor()
    cur.executescript(SCHEMA)

    print(f"Compiling {args.feed} -> {out}")
    with db:
        counts = load_feed(cur, feed)
        freq_made = materialize_frequencies(cur, feed)
        if freq_made:
            print(f"  frequencies.txt materialized into {freq_made} "
                  f"explicit trips")
        build_search_index(cur)
        if args.city:
            cur.execute("CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)")
            cur.execute("INSERT INTO meta VALUES ('city_id', ?)", (args.city,))
        quality_gate(cur, counts)
        cur.execute("ANALYZE")
    cur.execute("VACUUM")

    size = out.stat().st_size / 1e6
    print("OK: "
          + ", ".join(f"{k}={v}" for k, v in sorted(counts.items()))
          + (f", freq_trips={freq_made}" if freq_made else "")
          + f" | {size:.1f} MB")
    db.close()


if __name__ == "__main__":
    main()
