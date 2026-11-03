#!/usr/bin/env python3
"""Build data/pb/terrain_golden.json: reference values from the shipped terrain generator.

`tools/terrain_reference.mjs` runs the real class (`cd`) out of the pokebonk-re bundle in
Node. This script snapshots what it produces for every biome at a few seeds, and the Godot
port is then asserted against that snapshot (tools/probe_terrain.gd, SmokeTest).

It is the terrain twin of pokebonk-web/tools-re/golden_values.py: two independent
implementations (JS from the bundle, GDScript in the port) have to agree, so neither can be
silently wrong.

Usage:
    python3 tools/build_terrain_golden.py [--re-bundle <path>] [--props N]
"""
from __future__ import annotations

import glob
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
PROJECT = os.path.dirname(HERE)
SEEDS = [0, 2026, 1987654321]


def find_bundle(explicit: str | None) -> tuple[str, str]:
    if explicit:
        return explicit, os.path.dirname(explicit)
    assets = os.path.expanduser("~/Documents/GitHub/pokebonk-re/public/assets")
    index = os.path.join(assets, "..", "index.html")
    build = ""
    if os.path.exists(index):
        text = open(index, encoding="utf8").read()
        marker = 'pokebonk-build" content="'
        if marker in text:
            build = text.split(marker, 1)[1].split('"', 1)[0]
    cands = [f for f in glob.glob(os.path.join(assets, f"main-*{'-' + build if build else ''}.js"))
             if os.path.getsize(f) > 500_000]
    if not cands:
        raise SystemExit(f"game bundle not found under {assets} (pass --re-bundle)")
    return sorted(cands, key=os.path.getmtime)[-1], assets


def main() -> int:
    args = sys.argv[1:]

    def flag(name, default=None):
        return args[args.index(name) + 1] if name in args else default

    bundle, _assets = find_bundle(flag("--bundle"))
    props = flag("--props", "10")
    out_path = os.path.join(PROJECT, "data", "pb", "terrain_golden.json")

    result = subprocess.run(
        ["node", os.path.join(HERE, "terrain_reference.mjs"), bundle, "--all"],
        capture_output=True, text=True, check=True)
    worlds = json.loads(result.stdout)
    doc = {
        "_source": {
            "note": ("reference values for PbTerrain; produced by running the shipped terrain "
                     "class in Node (tools/terrain_reference.mjs), not by the Godot port"),
            "bundle": os.path.basename(bundle),
            "seeds": SEEDS,
            "heights": "17x17 samples across the playable square",
            "probes": "counters over 4000 deterministic points (flat/water/blocked/out of bounds)",
            "regenerate": "python3 tools/build_terrain_golden.py",
        },
        "worlds": worlds,
    }
    with open(out_path, "w", encoding="utf8") as fh:
        json.dump(doc, fh, ensure_ascii=False, separators=(",", ":"))
        fh.write("\n")
    print(f"    wrote {os.path.relpath(out_path, PROJECT)} "
          f"({os.path.getsize(out_path)} bytes, {len(worlds)} worlds, props sample={props})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
