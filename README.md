# Conexão (working name)

A fully on-device, open-source, Google-free transit app for Brazil.

Buses, BRT, metro, trains, VLT and ferries — maps, timetables, search and
A→B trip planning work **offline**, from per-city data packs. Live bus
positions and line status are fetched **directly from the cities' own public
APIs**. There is no backend server, no account, no analytics, no tracking —
and no hosting bill. Ever.

- **License:** GPL-3.0 (see [LICENSE](LICENSE))
- **Status:** Phase 0 — project setup (see [docs/ROADMAP.md](docs/ROADMAP.md))
- **Lead city:** Brasília (DF) · **Pipeline reference city:** Belo Horizonte

## How it works (60-second version)

1. A weekly GitHub Actions job downloads each city's GTFS feed, validates it
   with the Canonical GTFS Validator, compiles it into a signed **city pack**
   (SQLite timetable + FTS5 search index + PMTiles offline map), and attaches
   it to a GitHub Release. CI *is* the backend; GitHub Releases is the CDN.
2. The app downloads a pack once per city and then works in airplane mode:
   map, stops, lines, timetables, multimodal trip planning (on-device CSA
   routing), search.
3. When online, optional layers fade in: live bus positions and alerts from
   city APIs (Rio, São Paulo, Belo Horizonte), and an optional routing boost
   via the free community Transitous API.

Full rationale and research: see `docs/ARCHITECTURE.md`. The project follows
the build plan in *Brazil Bus App Plan v2.4* (serverless / €0 edition).

## Repository layout

```
app/        Flutter app (to be forked from Trufi Core, GPL-3.0)
pipeline/   Python pack compiler + GitHub Actions workflows (the "backend")
cities/     Per-city configs: feed URLs, bbox, adapter, license, provenance
docs/       Architecture, roadmap, adding-a-city guide, privacy policy
website/    Project website source (GitHub Pages)
```

## Principles

- **Offline is the default**, not a degraded mode.
- **Honest labels**: LIVE vs SCHEDULED vs COMMUNITY data, always visible.
- **No server to breach, no data to leak.** Privacy is architectural.
- **€0 forever**: everything runs on free tiers of public infrastructure.

## Contributing

Not open for contributions yet (pre-Phase 1). The first contribution path
will be "add your city" — one YAML config and, optionally, one live-data
adapter. See `docs/` as it lands.
