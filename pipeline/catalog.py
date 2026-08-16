#!/usr/bin/env python3
"""catalog.py — build the signed-release catalog (docs/ARCHITECTURE.md).

Scans a dist directory for <city>.sqlite / <city>.pmtiles files and emits
catalog.json: per-city file list with sizes and sha256. The catalog is then
ed25519-signed (sign.py) and published as a GitHub Release asset; the app
verifies the signature before trusting any entry.

Coverage badges come from cities/<id>.yaml (status.badge) — the app must
never invent coverage claims.

Usage: python3 catalog.py <dist_dir> <repo_release_base_url>
  e.g. python3 catalog.py dist \
         https://github.com/IuriGom/conexao/releases/download/packs
"""

import hashlib
import json
import re
import sys
from datetime import date
from pathlib import Path


def badge_for(city_id):
    """status.badge from cities/<id>.yaml, without a yaml dependency."""
    yml = Path(__file__).parent.parent / "cities" / f"{city_id}.yaml"
    if not yml.exists():
        return None
    m = re.search(r"^\s*badge:\s*(\w+)", yml.read_text(), re.M)
    return m.group(1) if m else None


def main():
    dist = Path(sys.argv[1])
    base = sys.argv[2].rstrip("/")

    cities = {}
    for f in sorted(dist.iterdir()):
        m = re.fullmatch(r"([\w-]+)\.(sqlite|pmtiles)(\.gz)?", f.name)
        if not m:
            continue
        city, kind, gz = m.groups()
        entry = cities.setdefault(city, {"files": {}})
        entry["files"][kind] = {
            "url": f"{base}/{f.name}",
            "size": f.stat().st_size,
            "sha256": hashlib.sha256(f.read_bytes()).hexdigest(),
        }
        if gz:
            entry["files"][kind]["compressed"] = "gzip"

    for city, entry in cities.items():
        badge = badge_for(city)
        if badge:
            entry["badge"] = badge

    catalog = {
        "version": 1,
        "generated": date.today().isoformat(),
        "cities": cities,
    }
    out = dist / "catalog.json"
    out.write_text(json.dumps(catalog, indent=2, ensure_ascii=False) + "\n")
    print(f"wrote {out}: {len(cities)} cities")
    for city, entry in cities.items():
        kinds = ", ".join(entry["files"])
        print(f"  {city}: {kinds} badge={entry.get('badge')}")


if __name__ == "__main__":
    main()
