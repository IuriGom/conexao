# pipeline/

The serverless "backend": scripts run by GitHub Actions on a weekly schedule.

Planned contents (Phase 1):

- `compile_gtfs.py` — GTFS zip → SQLite (normalized schema + FTS5 search
  index); merges multiple feeds per city; materializes `frequencies.txt`
  into explicit trips
- `build_tiles.sh` — Geofabrik OSM extract → per-city PMTiles (Planetiler)
- `sign.py` — ed25519 (minisign) signatures for packs + `catalog.json`
- `catalog.py` — release manifest: versions, sizes, coverage badges
- `diff_report.py` — per-release pack diff (stops/routes added/removed)
  for human review before publish

Quality gates (blocking in CI): Canonical GTFS Validator, network-audit
check, size caps. All feed data is treated as untrusted input.
