# app/

The Flutter app will live here as a fork of **Trufi Core v5** (GPL-3.0),
adapted per the architecture in `docs/ARCHITECTURE.md`:

- `lib/routing/` — on-device routing (Trufi offline planner or Dart CSA)
- `lib/adapters/` — per-city live API adapters (`bh/`, `rio/`, `sp/`)
- `lib/packs/` — pack download, ed25519 verification, versioning, rollback

Not forked yet — pending local Flutter toolchain check (Phase 0).
