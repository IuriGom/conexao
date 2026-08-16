# Roadmap

Timeline honesty (plan v2.2/9A): phase estimates are full-time-equivalents;
part-time with AI assistance, plan on **6–12 months to v1.0 Android**.

## Phase 0 — Project setup ✅ in progress
- [x] Repo scaffold, GPL-3.0, README
- [x] `cities/brasilia.yaml` (lead city), `cities/belo_horizonte.yaml` (reference)
- [x] Brasília data hunt: official GTFS **not yet published** → LAI path
- [x] GitHub repo (**public** since 2026-08-16 — pack downloads need it)
- [x] MapLibre plugin picked: `maplibre_gl` (offline PMTiles verified)
- [ ] Fork Trufi Core into `app/`; build locally; strip server deps
      (decided against for now: own shell is lean; Trufi models reusable later)
- [ ] website stub on GitHub Pages
- [ ] File LAI request for DF GTFS (docs/LAI_BRASILIA.md)
- [ ] SPTrans developer token; Mobility Database API account
- [ ] Draft privacy policy (PT-BR)

## Phase 1 — Data pack pipeline (3–4 wks FTE)
- [x] `compile_gtfs.py` v1: GTFS → SQLite + FTS5; frequencies.txt
      materialized into explicit trips; blocking quality gate; untrusted-input
      guards — tested offline against a synthetic feed (18 checks green)
- [x] App shell v0: PT-BR city picker + honest badges (on emulator)
- [x] Planner UI: map-first (tap origin/dest pins); verified on emulator
      with the real BH pack and the Brasília Metrô-DF pack, fully offline.
      RouterWorker isolate keeps the day timetable resident; ANR-safe
- [x] PMTiles per city bbox (built locally with Planetiler; CI rebuild TODO)
- [x] ed25519 pack + catalog signing (`pipeline/sign.py`; key in CI secret)
- [x] Weekly GitHub Actions → rolling `packs` release + signed `catalog.json`
- [x] In-app pack manager: download, verify signature + sha256, atomic apply
      (rollback = reinstall previous pack; delta updates still TODO)
- [x] Compile against the real Belo Horizonte feed (in CI, green)
- [x] Brasília Metrô-DF community feed encoded (`build_metro_df.py`)
- **Deliverable:** app downloads Belo Horizonte pack, browses fully offline ✅

## Phase 2 — On-device routing (2–6 wks FTE) — decision gate
- [x] Evaluate Trufi Core v5 offline GTFS planner on a real feed
      (BH, 113k trips): queries 25–55 ms ✅, but **max 1 transfer and no
      time-aware itineraries** — parse-from-zip 27 s also unsuitable for
      app startup
- [x] Decision: reuse Trufi's GTFS models/parser + spatial/route indexes;
      **own time-aware core written**: `app/lib/routing/` — CSA with unlimited
      transfers, footpath transfers, service-day filtering, honest
      approximate labeling. Deterministic (dep, tripI) tie-break kills
      transfer-thrash on parallel corridors
- [x] Tabs filled in: Paradas (next departures), Linhas (stop diagrams)
- [x] My-location dot without Play Services (LocationManager)
- [ ] Golden-route tests: 10 known A→B pairs per city
- **Deliverable:** offline multimodal A→B planning, <2 s on mid-range phone ✅

## Phase 3 — Live layer (4–5 wks FTE) — NEXT
- Adapters: BH (easy; GTFS-RT endpoints resolved, see cities/belo_horizonte.yaml)
  → Rio → SP (cookie auth, BYO-token from day one)
- Live↔static trip matching per city (~1 wk each for Rio/SP)
- LIVE/SCHEDULED badges everywhere
- **Deliverable:** live buses in 3 cities with match-confidence labels

## Phase 4 — Search + polish + Android release (3–4 wks FTE)
- FTS search UI, favorites, onboarding, PT-BR
- F-Droid submission (start early), Obtainium releases, network-audit CI
- **Deliverable: v1.0 Android, €0 spent**

## Phase 5 — Online boost + more cities (ongoing)
- Transitous integration; upstream BR feeds to its atlas
- "Add your city" contributor pipeline; Brasília watch (Lei 7.836)

## Phase 6 — iOS (when $99 available)
- Same codebase; local notifications only; "Data Not Collected" label
