#!/usr/bin/env python3
"""compile_gtfs.py — GTFS zip -> SQLite city-pack database.

Part of the Conexão serverless data pipeline (see docs/ARCHITECTURE.md).
Stdlib only (zipfile, csv, sqlite3) — no pip installs, CI-friendly.

Design notes:
  * GTFS text ids are mapped to small integers; the hot tables
    (stop_times, shape_pts) reference ints only. This takes a real
    6.7M-row feed (Belo Horizonte) from ~750 MB to well under 200 MB,
    and the pack is zip-compressed on top of that.
  * arrival_secs is NULL when it equals departure_secs (GTFS feeds almost
    always duplicate them) — read with COALESCE(arrival_secs, departure_secs).
  * frequencies.txt is MATERIALIZED into explicit trips: CSA scans
    connections, not headways (plan §3.2). Generated trips carry
    freq_exact = frequencies.exact_times so the app labels
    "a cada ~X min" honestly instead of fake precision.
  * Blocking quality gate: required files, row counts, referential sanity.
    Fails non-zero on errors — CI relies on this.
  * All feed data is UNTRUSTED INPUT (plan §11A): parameterized SQL only,
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
MAX_ZIP_UNCOMPRESSED = 2 * 1024**3         # 2 GiB decompressed cap
MAX_ROWS_PER_FILE = 50_000_000
MAX_FIELD_LEN = 4096

REQUIRED_FILES = ("stops.txt", "routes.txt", "trips.txt", "stop_times.txt")

SCHEMA = """
CREATE TABLE agency (
  agency_id TEXT PRIMARY KEY, name TEXT, url TEXT, timezone TEXT, lang TEXT);
CREATE TABLE stops (
  stop_i INTEGER PRIMARY KEY, stop_id TEXT UNIQUE, code TEXT, name TEXT,
  lat REAL, lon REAL, parent_i INTEGER, location_type INTEGER DEFAULT 0);
CREATE TABLE routes (
  route_i INTEGER PRIMARY KEY, route_id TEXT UNIQUE, agency_id TEXT,
  short_name TEXT, long_name TEXT, route_type INTEGER,
  color TEXT, text_color TEXT);
CREATE TABLE services (service_i INTEGER PRIMARY KEY, service_id TEXT UNIQUE);
CREATE TABLE trips (
  trip_i INTEGER PRIMARY KEY, trip_id TEXT UNIQUE, route_i INTEGER,
  service_i INTEGER, headsign TEXT, direction_id INTEGER, shape_i INTEGER,
  freq_exact INTEGER);
CREATE TABLE stop_times (
  trip_i INTEGER, stop_sequence INTEGER, stop_i INTEGER,
  arrival_secs INTEGER, departure_secs INTEGER,
  PRIMARY KEY (trip_i, stop_sequence)) WITHOUT ROWID;
CREATE INDEX idx_stop_times_stop ON stop_times(stop_i);
CREATE TABLE calendar (
  service_i INTEGER PRIMARY KEY, monday INTEGER, tuesday INTEGER,
  wednesday INTEGER, thursday INTEGER, friday INTEGER, saturday INTEGER,
  sunday INTEGER, start_date TEXT, end_date TEXT);
CREATE TABLE calendar_dates (
  service_i INTEGER, date TEXT, exception_type INTEGER);
CREATE TABLE shapes (shape_i INTEGER PRIMARY KEY, shape_id TEXT UNIQUE);
CREATE TABLE shape_pts (
  shape_i INTEGER, pt_sequence INTEGER, pt_lat REAL, pt_lon REAL,
  PRIMARY KEY (shape_i, pt_sequence)) WITHOUT ROWID;
CREATE INDEX idx_stops_geo ON stops(lat, lon);
CREATE INDEX idx_trips_route ON trips(route_i);
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
            die(f"feed decompresses to {total / 2**20:.0f} MiB "
                f"(cap {MAX_ZIP_UNCOMPRESSED // 2**30} GiB) — possible zip bomb")
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

    stop_i = {}
    n = 0
    for r in feed.rows("stops.txt"):
        n += 1
        stop_i[r["stop_id"]] = n
        cur.execute(
            "INSERT INTO stops (stop_i, stop_id, code, name, lat, lon,"
            " location_type) VALUES (?,?,?,?,?,?,?)",
            (n, r["stop_id"], r.get("stop_code"), r.get("stop_name"),
             float(r["stop_lat"]) if r.get("stop_lat") else None,
             float(r["stop_lon"]) if r.get("stop_lon") else None,
             int(r["location_type"] or 0)))
    counts["stops"] = n
    # parent_station text refs -> ints, now that all stops exist
    for r in feed.rows("stops.txt"):
        p = r.get("parent_station")
        if p and p in stop_i:
            cur.execute("UPDATE stops SET parent_i=? WHERE stop_i=?",
                        (stop_i[p], stop_i[r["stop_id"]]))

    route_i = {}
    n = 0
    for r in feed.rows("routes.txt"):
        n += 1
        route_i[r["route_id"]] = n
        cur.execute(
            "INSERT INTO routes VALUES (?,?,?,?,?,?,?,?)",
            (n, r["route_id"], r.get("agency_id"), r.get("route_short_name"),
             r.get("route_long_name"), int(r["route_type"]),
             r.get("route_color"), r.get("route_text_color")))
    counts["routes"] = n

    service_i = {}
    shape_i = {}
    trip_i = {}
    n = 0
    for r in feed.rows("trips.txt"):
        n += 1
        trip_i[r["trip_id"]] = n
        sid, shp = r["service_id"], r.get("shape_id") or ""
        if sid not in service_i:
            service_i[sid] = len(service_i) + 1
            cur.execute("INSERT INTO services VALUES (?,?)",
                        (service_i[sid], sid))
        if shp and shp not in shape_i:
            shape_i[shp] = len(shape_i) + 1
            cur.execute("INSERT INTO shapes VALUES (?,?)",
                        (shape_i[shp], shp))
        cur.execute(
            "INSERT INTO trips VALUES (?,?,?,?,?,?,?,NULL)",
            (n, r["trip_id"], route_i.get(r["route_id"]), service_i[sid],
             r.get("trip_headsign"),
             int(r["direction_id"]) if r.get("direction_id") else None,
             shape_i.get(shp)))
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
            (trip_i.get(r["trip_id"]), int(r["stop_sequence"]),
             stop_i.get(r["stop_id"]),
             arr if arr != dep else None, dep))
        n += 1
    counts["stop_times"] = n
    if skipped:
        print(f"  note: {skipped} stop_times rows without times skipped")

    n = 0
    for r in feed.rows("calendar.txt") or []:
        si = service_i.get(r["service_id"])
        if si is None:
            continue
        cur.execute(
            "INSERT OR REPLACE INTO calendar VALUES (?,?,?,?,?,?,?,?,?,?)",
            (si, *[int(r.get(d) or 0) for d in
              ("monday", "tuesday", "wednesday", "thursday", "friday",
               "saturday", "sunday")],
             r.get("start_date"), r.get("end_date")))
        n += 1
    counts["calendar"] = n

    n = 0
    for r in feed.rows("calendar_dates.txt") or []:
        si = service_i.get(r["service_id"])
        if si is None:
            continue
        cur.execute("INSERT INTO calendar_dates VALUES (?,?,?)",
                    (si, r["date"], int(r["exception_type"] or 1)))
        n += 1
    counts["calendar_dates"] = n

    n = 0
    for r in feed.rows("shapes.txt") or []:
        shp = shape_i.get(r["shape_id"])
        if shp is None:
            shp = len(shape_i) + 1
            shape_i[r["shape_id"]] = shp
            cur.execute("INSERT INTO shapes VALUES (?,?)",
                        (shp, r["shape_id"]))
        cur.execute("INSERT INTO shape_pts VALUES (?,?,?,?)",
                    (shp, int(float(r["shape_pt_sequence"])),
                     float(r["shape_pt_lat"]), float(r["shape_pt_lon"])))
        n += 1
    counts["shape_pts"] = n

    return counts, trip_i


def materialize_frequencies(cur, feed, trip_i):
    """Expand frequencies.txt windows into explicit trips. Returns count."""
    if not feed.has("frequencies.txt"):
        return 0

    made = 0
    next_i = max(trip_i.values(), default=0)
    templates_used = set()
    for r in feed.rows("frequencies.txt"):
        tpl = r["trip_id"]
        tpl_i = trip_i.get(tpl)
        if tpl_i is None:
            continue
        start, end = parse_time(r["start_time"]), parse_time(r["end_time"])
        headway = int(r["headway_secs"])
        exact = 1 if r.get("exact_times") == "1" else 0
        if start is None or end is None or headway <= 0:
            continue

        tpl_st = cur.execute(
            "SELECT stop_sequence, stop_i, arrival_secs, departure_secs "
            "FROM stop_times WHERE trip_i=? ORDER BY stop_sequence",
            (tpl_i,)).fetchall()
        if not tpl_st:
            continue
        base_dep = tpl_st[0][3] if tpl_st[0][3] is not None else tpl_st[0][2]
        if base_dep is None:
            continue
        tpl_info = cur.execute(
            "SELECT route_i, service_i, headsign, direction_id, shape_i "
            "FROM trips WHERE trip_i=?", (tpl_i,)).fetchone()

        for t in range(start, end, headway):
            off = t - base_dep
            next_i += 1
            cur.execute(
                "INSERT INTO trips VALUES (?,?,?,?,?,?,?,?)",
                (next_i, f"{tpl}#{t}", *tpl_info, exact))
            cur.executemany(
                "INSERT INTO stop_times VALUES (?,?,?,?,?)",
                [(next_i, seq, si,
                  a + off if a is not None else None,
                  d + off if d is not None else None)
                 for seq, si, a, d in tpl_st])
            made += 1
        templates_used.add(tpl)

    # Remove headway templates only after ALL windows are expanded — a trip
    # can have several frequencies.txt rows (e.g. peak/off-peak), and each
    # expansion reads the template's stop_times.
    for tpl in templates_used:
        tpl_i = trip_i[tpl]
        cur.execute("DELETE FROM stop_times WHERE trip_i=?", (tpl_i,))
        cur.execute("DELETE FROM trips WHERE trip_i=?", (tpl_i,))
    return made


def build_search_index(cur):
    try:
        cur.execute(
            "CREATE VIRTUAL TABLE search USING fts5(name, kind, ref_i "
            "UNINDEXED, tokenize='trigram')")
    except sqlite3.OperationalError:
        cur.execute(
            "CREATE VIRTUAL TABLE search USING fts5(name, kind, ref_i "
            "UNINDEXED)")
    cur.execute(
        "INSERT INTO search SELECT name, 'stop', stop_i FROM stops "
        "WHERE name IS NOT NULL AND location_type = 0")
    cur.execute(
        "INSERT INTO search SELECT "
        "COALESCE(short_name,'') || ' ' || COALESCE(long_name,''), "
        "'route', route_i FROM routes")


def quality_gate(cur, counts):
    """Blocking checks — CI treats any failure as a broken pack."""
    problems = []
    for key in ("stops", "routes", "trips", "stop_times"):
        if counts.get(key, 0) == 0:
            problems.append(f"no {key} parsed")
    if counts.get("calendar", 0) == 0 and counts.get("calendar_dates", 0) == 0:
        problems.append("neither calendar.txt nor calendar_dates.txt present")

    orphans = cur.execute(
        "SELECT COUNT(*) FROM stop_times st "
        "LEFT JOIN stops s ON s.stop_i = st.stop_i "
        "WHERE s.stop_i IS NULL").fetchone()[0]
    if orphans:
        problems.append(f"{orphans} stop_times reference unknown stops")
    dead = cur.execute(
        "SELECT COUNT(*) FROM trips t "
        "LEFT JOIN routes r ON r.route_i = t.route_i "
        "WHERE r.route_i IS NULL").fetchone()[0]
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
    db.execute("PRAGMA journal_mode=OFF")
    db.execute("PRAGMA synchronous=OFF")
    cur = db.cursor()
    cur.executescript(SCHEMA)

    print(f"Compiling {args.feed} -> {out}")
    with db:
        counts, trip_i = load_feed(cur, feed)
        freq_made = materialize_frequencies(cur, feed, trip_i)
        if freq_made:
            print(f"  frequencies.txt materialized into {freq_made} "
                  f"explicit trips")
        build_search_index(cur)
        if args.city:
            cur.execute(
                "CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT)")
            cur.execute("INSERT INTO meta VALUES ('city_id', ?)",
                        (args.city,))
        quality_gate(cur, counts)
    db.execute("PRAGMA analysis_limit=1000")
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
