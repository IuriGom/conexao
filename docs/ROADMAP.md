# Roadmap

Timeline honesty (plan v2.2/9A): phase estimates are full-time-equivalents;
part-time with AI assistance, plan on **6–12 months to v1.0 Android**.

## Phase 0 — Project setup ✅ in progress
- [x] Repo scaffold, GPL-3.0, README
- [x] `cities/brasilia.yaml` (lead city), `cities/belo_horizonte.yaml` (reference)
- [x] Brasília data hunt: official GTFS **not yet published** → LAI path
- [ ] Fork Trufi Core into `app/`; build locally; strip server deps
- [ ] Pick + pin MapLibre plugin (`flutter_maplibre` vs `maplibre_gl`)
- [ ] GitHub repo (public), website stub on GitHub Pages
- [ ] File LAI request for DF GTFS (docs/LAI_BRASILIA.md)
- [ ] SPTrans developer token; Mobility Database API account
- [ ] Draft privacy policy (PT-BR)

## Phase 1 — Data pack pipeline (3–4 wks FTE)
- [x] `compile_gtfs.py` v1: GTFS → SQLite + FTS5; frequencies.txt
      materialized into explicit trips; blocking quality gate; untrusted-input
      guards — tested offline against a synthetic feed (14 checks green)
- [ ] App shell v0: PT-BR city picker + honest badges (done, on emulator)
- [ ] PMTiles per city bbox (Geofabrik → Planetiler in CI)
- [ ] ed25519 pack + catalog signing
- [ ] Weekly GitHub Actions → Release `data-YYYY.WW` + `catalog.json`
- [ ] In-app pack manager: download, verify signature, atomic apply + rollback
- [ ] Compile against the real Belo Horizonte feed (needs Wi-Fi: ~10 MB)
- **Deliverable:** app downloads Belo Horizonte pack, browses fully offline;
  Brasília Metrô-DF community feed encoded

## Phase 2 — On-device routing (2–6 wks FTE) — decision gate
- Evaluate Trufi Core v5 offline GTFS planner on a big pack
- Adopt-and-harden, or Dart CSA port (Mobroute as reference)
- Golden-route tests: 10 known A→B pairs per city
- **Deliverable:** offline multimodal A→B planning, <2 s on mid-range phone

## Phase 3 — Live layer (4–5 wks FTE)
- Adapters: BH (easy) → Rio → SP (cookie auth, BYO-token from day one)
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
