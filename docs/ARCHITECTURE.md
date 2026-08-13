# Architecture

> This file is the map of the repo — keep it current (plan §9A.3).

## The one-sentence version

There is no server. The phone computes everything; CI builds and signs data
packs; the cities serve their own live data.

```
┌──────────────────────── THE PHONE ────────────────────────┐
│  Flutter app (GPL-3.0, fork of Trufi Core)                │
│                                                           │
│  Map (MapLibre + offline PMTiles)                         │
│  Stops/routes/schedules (SQLite city pack, drift)         │
│  Trip planner (on-device CSA over GTFS timetable)         │
│  Search (on-device FTS5: stops + streets + POIs)          │
│  Live layer (per-city adapters, GTFS-RT parser)           │
│  Favorites/settings — on-device only                      │
└───────┬──────────────────────┬────────────────────────────┘
        │ pack download        │ live data (optional)
┌───────▼───────────┐  ┌───────▼──────────┐  ┌──────────────┐
│ GitHub Releases   │  │ City public APIs │  │ Free community│
│ (signed packs +   │  │ (BH, Rio, SP…)   │  │ services      │
│ signed catalog)   │  │                  │  │ (OpenFreeMap, │
│ built weekly by   │  │                  │  │ Transitous)   │
│ GitHub Actions    │  │                  │  │               │
└───────────────────┘  └──────────────────┘  └──────────────┘
        Nothing here is operated or paid for by the project.
```

## Components

| Piece | Where | Tech | State |
|---|---|---|---|
| City configs | `cities/*.yaml` | YAML | ✅ first two written |
| Pack pipeline | `pipeline/` | Python (GTFS→SQLite+FTS5), Planetiler (PMTiles) | ⬜ Phase 1 |
| CI workflows | `.github/workflows/` | GitHub Actions, SHA-pinned | ⬜ Phase 1 |
| Pack signing | `pipeline/` | ed25519 (minisign); public key baked into app | ⬜ Phase 1 |
| App | `app/` | Flutter, fork of Trufi Core v5 | ⬜ Phase 0/2 |
| On-device routing | `app/lib/routing/` | Trufi offline planner, else Dart CSA (ref: Mobroute) | ⬜ Phase 2 |
| Live adapters | `app/lib/adapters/` | Dart, per city | ⬜ Phase 3 |

## City pack contents (the contract)

1. `transit.sqlite` — stops, routes, trips, stop_times, shapes, calendar;
   `frequencies.txt` materialized into explicit trips (CSA scans connections,
   not headways); multi-feed merged per city; FTS5 search index included.
2. `map.pmtiles` — vector tiles for the city bbox (OSM/Geofabrik, ODbL).
3. `ATTRIBUTION.md` — every source + license.
4. `pack.json` — version, sizes, checksums, ed25519 signature.
5. `catalog.json` (release-level, signed) — control plane: versions, sizes,
   coverage badges, SPTrans token rotation, per-city kill-switches,
   minimum-app-version.

## Routing strategy (layered)

- Layer 1 (always): on-device CSA over pack SQLite + simple walk estimate.
- Layer 2 (online): Transitous door-to-door boost (optional, toggleable).
- Layer 3 (live): city APIs adjust Layer-1 results.
- UI rule: every itinerary shows which layer produced it.

## Security essentials (plan v2.4)

- Every pack and the catalog are ed25519-signed; public key baked into app.
- CI: Actions pinned by commit SHA, least-privilege token, no secret-bearing
  PR triggers, environment protection on release job.
- All feed data is untrusted input: validator gate, parameterized SQL,
  size caps, fuzzing.
- Android `networkSecurityConfig`: cleartext denied by default, explicit
  allow-list; HTTP-sourced data labeled lower-trust.
- `android:allowBackup="false"`; user secrets in `flutter_secure_storage`.

## Privacy

No accounts, no analytics, no ads, no trackers. Network calls only to:
GitHub (packs), city APIs (live), and optionally OpenFreeMap/Transitous
(user-toggleable). A CI network-audit check enforces this list.
