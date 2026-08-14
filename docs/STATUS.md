# STATUS — where we left off (2026-08-14)

> Read this first when resuming. Working dir: `/Users/iuri/conexao`.
> Repo: github.com/IuriGom/conexao (private, branch main).

## The project

Conexão — fully offline, open-source (GPL-3.0), Google-free transit app for
Brazil, per `/Users/iuri/Downloads/Brazil_Bus_App_Plan_v2.4_Revised.md`.
Lead city: **Brasília** (user lives there); reference city: **Belo Horizonte**.

## Done and verified

- **Pipeline**: `pipeline/compile_gtfs.py` — GTFS→SQLite, integer-normalized,
  frequencies materialized, FTS5 index, quality gate, input guards.
  Real BH feed (52 MB zip) → 224 MB DB → 65 MB zipped. Tests: 16 checks.
  `pipeline/test_compile_gtfs.py` runs offline.
- **Routing engine**: `app/lib/routing/` — CSA (unlimited transfers, footpath
  transfers, service-day filter, approximate labels). 7 tests. 200k conns
  scanned in ~90 ms debug.
- **Pack loader + worker**: `pack_loader.dart` (calendar exceptions, FTS
  search, lazy depAt), `router_worker.dart` (persistent isolate — UI never
  blocks; fixed an ANR). 4 loader tests.
- **Real routing proven**: BH pack on emulator, Av. Vilarinho → Estação
  Pampulha, line 617, fully offline.
- **Offline map (just built)**: `map/offline_style.dart` (Positron fork →
  local pmtiles + local glyphs), `map/map_screen.dart` (MapLibre, pins),
  Planner is now map-first: tap = origin pin, tap = dest pin.
  Tiles built locally: `pipeline/tmp/brasilia.pmtiles` (24 MB, whole DF),
  `pipeline/tmp/belo_horizonte.pmtiles` (10 MB, city bbox).
- **Toolchain**: Flutter 3.47, JDK 17 (app builds) + JDK 21 (Planetiler),
  Android SDK at `/opt/homebrew/share/android-commandlinetools`
  (ANDROID_HOME), NDK 28.2 already installed. Emulator AVD `conexao`
  (Android 36 AOSP, no Google).

## Data budget

User on hotspot. Cap: ~4.5 GB total (approved). Spent ≈ 3.6 GB incl. NDK
(was already installed — no new 0.95 GB needed). Recurring work runs in CI
(GitHub bandwidth), not the user's connection.

## Resume checklist (next session)

1. If APK build (`flutter build apk --debug` in app/) finished: install +
   push BH pmtiles to emulator and demo the map + pin planner:
   - `adb push pipeline/tmp/belo_horizonte.pmtiles /data/local/tmp/`
   - `adb shell run-as dev.conexao.conexao cp /data/local/tmp/belo_horizonte.pmtiles /data/data/dev.conexao.conexao/files/packs/`
   - Packs live in `<app files>/packs/<city>.sqlite|.pmtiles`
2. Fix cosmetic: keyboard overflow banner in planner (debug-only).
3. Brasília: no official GTFS yet (Lei 7.836/2025 unpublished). Hand-encode
   Metrô-DF community GTFS (2 lines, ~27 stations) — `cities/brasilia.yaml`.
   LAI template ready: `docs/LAI_BRASILIA.md` (not yet filed — user action).
4. Pack download flow: GitHub Releases + ed25519 signing + catalog.json
   (plan v2.4: signed catalog is the control plane). See `docs/ARCHITECTURE.md`.
5. CI workflow: weekly pack build (validator gate blocking, SHA-pinned
   actions). `.github/workflows/` is still empty.
6. Live layer adapters: BH GTFS-RT endpoints resolved (see
   `cities/belo_horizonte.yaml`; http cleartext → lower-trust label).
7. Phase 2 note: Trufi Core v5 offline planner evaluated and found shallow
   (max 1 transfer, no time-awareness) — we wrote our own CSA. Trufi's
   models/parser/indexes may still be reused later.

## Useful commands

```bash
# emulator
/opt/homebrew/share/android-commandlinetools/emulator/emulator -avd conexao -gpu host -no-metrics
# env for builds
export JAVA_HOME=/opt/homebrew/opt/openjdk@17
export ANDROID_HOME=/opt/homebrew/share/android-commandlinetools
# tests
cd app && flutter test
cd .. && python3 pipeline/test_compile_gtfs.py
# real-pack route eval (no emulator)
cd app && dart run tool/eval_pack.dart ../pipeline/tmp/bh.sqlite
```
