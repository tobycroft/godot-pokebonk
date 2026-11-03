#!/usr/bin/env python3
"""Extract the world/terrain tables from the pokebonk-re offline mirror into data/pb/*.json.

The reference source is `pokebonk-re` (a byte-identical mirror of the shipped client that
also runs offline), not `pokebonk-web`: the mirror carries every `assets/env/<pack>` atlas
(`atlas.json` for 12 packs + `common/hazards.png`) and the complete locale chunks, so biome
names resolve in Chinese too.

Tables recovered (offsets are character positions in the minified game bundle):

  world_biomes.json      biome registry: size/relief/water/sky/fog/lights/tex/zones/sanctuary
                         (the table lives in the lazily-loaded `news` chunk)
  world_props.json       per-pack prop catalogue (`au`) + the atlas rects of the same pack
  world_palettes.json    cliff/ground toon palettes (`Wu`) + ground-detail mapping (`_d`)
  world_fx.json          weather look table (`cb`), hostile terrain (`bw`, `xw`)
  world_constants.json   terrain generator constants (`Qu/$u/Iu/td/nd/rd/id/ad/od/ed/sd`)

Rather than re-parsing JS literals by hand, each table is sliced out of the bundle and
**evaluated in Node** with stubs for the localiser: the bundle builds these tables with helper
functions (`ou`/`su`/`qS`) and arrow-valued strings, so evaluation is the only way to get the
values the game actually uses.

Usage:
    python3 tools/extract_world.py [--re-assets <dir>] [--out <dir>]
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import re
import subprocess
import sys

OPENERS = {"{": "}", "[": "]", "(": ")"}
CLOSERS = {v: k for k, v in OPENERS.items()}

RUNTIME = r"""
// Materialise one sliced table from the bundle. Functions are called when they take no
// argument (the localiser wrappers), otherwise recorded as {"__fn": true} so the port can
// see what carries code instead of data.
const fs = require('fs');
const [, , inFile, outFile] = process.argv;
const src = fs.readFileSync(inFile, 'utf8');
const norm = (v) => {
  if (Array.isArray(v)) return v.map(norm);
  if (typeof v === 'function') {
    if (v.length === 0) {
      try {
        return norm(v());
      } catch {
        return { __fn: true };
      }
    }
    return { __fn: true };
  }
  if (v && typeof v === 'object') {
    const o = {};
    for (const k of Object.keys(v)) o[k] = norm(v[k]);
    return o;
  }
  if (typeof v === 'number' && !Number.isFinite(v)) return null;
  return v;
};
// The localiser is stubbed; `new Function` only sees globals, so these must live there.
globalThis.c = (s) => s;
globalThis.t = (s) => s;
const result = new Function(`"use strict";\n${src}`)();
fs.writeFileSync(outFile, JSON.stringify(norm(result)));
"""


def balance(src: str, start: int) -> int:
    """Index just past the balanced literal that opens at ``start``."""
    if src[start] not in OPENERS:
        raise ValueError(f"anchor is not a bracket: {src[start:start + 60]!r}")
    depth = 0
    i = start
    quote = None
    n = len(src)
    while i < n:
        ch = src[i]
        if quote:
            if ch == "\\":
                i += 2
                continue
            if ch == quote:
                quote = None
            elif quote == "`" and src.startswith("${", i):
                quote = None  # template interpolation: treat as code again
            i += 1
            continue
        if ch in "\"'`":
            quote = ch
            i += 1
            continue
        if ch == "/" and i + 1 < n and src[i + 1] == "/":
            while i < n and src[i] != "\n":
                i += 1
            continue
        if ch in OPENERS:
            depth += 1
        elif ch in CLOSERS:
            depth -= 1
            if depth == 0:
                return i + 1
        i += 1
    raise ValueError("unbalanced literal")


def slice_literal(src: str, anchor_re: str, label: str) -> str:
    """Return the balanced literal that ``anchor_re``'s first capture group points at."""
    m = re.search(anchor_re, src)
    if not m:
        raise KeyError(f"{label}: anchor {anchor_re!r} not found")
    start = m.start(m.lastindex or 1)
    end = balance(src, start)
    return src[start:end], m.start()


def eval_js(workdir: str, name: str, body: str):
    """Run a sliced table through Node and return the parsed JSON."""
    js = os.path.join(workdir, f"{name}.in.js")
    out = os.path.join(workdir, f"{name}.out.json")
    runner = os.path.join(workdir, "_runtime.cjs")
    with open(runner, "w", encoding="utf8") as fh:
        fh.write(RUNTIME)
    # The slice is an *assignment sequence* (au={...}; function ou(){}; au.x=...), so lift the
    # declaration into a `let` and return the table.
    with open(js, "w", encoding="utf8") as fh:
        fh.write(body)
    subprocess.run(["node", runner, js, out], check=True)
    with open(out, encoding="utf8") as fh:
        return json.load(fh)


def sequence_body(src: str, start: int, end_anchor: str, label: str, returns: str) -> str:
    """Slice ``start`` up to ``end_anchor`` and wrap it as a function returning ``returns``."""
    stop = src.find(end_anchor, start)
    if stop < 0:
        raise KeyError(f"{label}: end anchor {end_anchor!r} not found")
    body = src[start:stop].rstrip().rstrip(",;")
    return f"let {body};\nreturn {returns};"


def locale_maps(assets_dir: str, build: str, workdir: str, langs=("en", "zh", "zht")) -> dict:
    """Spanish-source → translated maps, read from the mirror's locale chunks."""
    maps: dict[str, dict] = {}
    for lang in langs:
        cand = sorted(glob.glob(os.path.join(assets_dir, f"{lang}-*-{build}.js")))
        if not cand:
            cand = sorted(glob.glob(os.path.join(assets_dir, f"{lang}-*.js")))
        if not cand:
            continue
        src = open(cand[-1], encoding="utf8", errors="replace").read()
        try:
            literal, _ = slice_literal(src, r'[\w$]+=(\{")', f"{lang} locale")
            maps[lang] = eval_js(workdir, f"locale_{lang}", f"return {literal};")
        except Exception as exc:  # a locale chunk we cannot read is not fatal
            print(f"    ! locale {lang}: {exc}", file=sys.stderr)
    return maps


def tr(maps: dict, spanish: str) -> dict:
    out = {"es": spanish}
    for lang, table in maps.items():
        if lang == "es":
            continue
        val = table.get(spanish)
        if isinstance(val, str) and val:
            out[lang] = val
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--re-assets", help="path to pokebonk-re/public/assets")
    ap.add_argument("--out", default=os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "data", "pb"))
    args = ap.parse_args()

    here = os.path.dirname(os.path.abspath(__file__))
    project = os.path.dirname(here)
    candidates = [args.re_assets] if args.re_assets else []
    candidates += [
        os.path.expanduser("~/Documents/GitHub/pokebonk-re/public/assets"),
        os.path.join(project, "..", "pokebonk-re", "public", "assets"),
    ]
    assets = next((c for c in candidates if c and os.path.isdir(c)), None)
    if not assets:
        print("pokebonk-re/public/assets not found; pass --re-assets", file=sys.stderr)
        return 2

    root = os.path.dirname(assets)
    build = ""
    index = os.path.join(root, "index.html")
    if os.path.exists(index):
        m = re.search(r'pokebonk-build" content="([0-9a-z]+)"', open(index, encoding="utf8").read())
        build = m.group(1) if m else ""
    game = [f for f in glob.glob(os.path.join(assets, f"main-*{'-' + build if build else ''}.js"))
            if os.path.getsize(f) > 500_000]
    news = [f for f in glob.glob(os.path.join(assets, f"news-*{'-' + build if build else ''}.js"))]
    if not game or not news:
        print(f"cannot find game/news bundle for build {build!r} in {assets}", file=sys.stderr)
        return 2
    game.sort(key=os.path.getmtime)
    news.sort(key=os.path.getmtime)
    bundle = open(game[-1], encoding="utf8", errors="replace").read()
    newssrc = open(news[-1], encoding="utf8", errors="replace").read()
    print(f"    bundle: {os.path.basename(game[-1])} ({len(bundle)} chars)")
    print(f"    news  : {os.path.basename(news[-1])} ({len(newssrc)} chars)")

    work = os.path.join(project, ".port")
    os.makedirs(work, exist_ok=True)
    meta = {
        "source": "pokebonk-re offline mirror",
        "site_build": build,
        "logic_bundle": f"assets/{os.path.basename(game[-1])}",
        "news_bundle": f"assets/{os.path.basename(news[-1])}",
        "note": "generated by tools/extract_world.py; offsets are character positions in logic_bundle",
    }

    # ---------------------------------------------------------------- biomes (news chunk)
    biomes_lit, bioff = slice_literal(newssrc, r"[\w$]+=(\[\{id:`forest`)", "biome table")
    biomes = eval_js(work, "biomes", f"return {biomes_lit};")
    maps = locale_maps(assets, build, work)
    for b in biomes:
        b["_offset_news"] = bioff
        for key in ("name", "desc", "unlock"):
            if isinstance(b.get(key), str):
                b[key] = tr(maps, b[key])
        for z in b.get("zones") or []:
            if isinstance(z.get("name"), str):
                z["name"] = tr(maps, z["name"])
        sanc = b.get("sanctuary")
        if isinstance(sanc, dict):
            for key in ("name", "heart"):
                if isinstance(sanc.get(key), str):
                    sanc[key] = tr(maps, sanc[key])

    # ---------------------------------------------------------------- props (`au`)
    m = re.search(r"(?<![\w$])au=\{forest:\{", bundle)
    if not m:
        print("prop table `au` not found", file=sys.stderr)
        return 1
    au_start = m.start()
    props = eval_js(work, "props",
                    sequence_body(bundle, au_start, "var cu=", "prop table", "au"))
    props_off = au_start
    # The rects the runtime reads for each pack, straight off the mirror.
    for pack in sorted(props):
        path = os.path.join(assets, "env", pack, "atlas.json")
        if os.path.exists(path):
            props[pack]["atlas"] = json.load(open(path, encoding="utf8"))
        else:
            props[pack]["atlas"] = None

    # ---------------------------------------------------------------- palettes (`Wu`)
    m = re.search(r"(?<![\w$])zu=\{a:\[", bundle)
    pal_start = m.start()
    palettes = eval_js(work, "palettes",
                       sequence_body(bundle, pal_start, "Gu=e=>", "palettes", "({base:zu,Wu})"))
    palettes["by_pack"] = palettes.pop("Wu")
    palettes["_offset"] = pal_start
    palettes["ground_detail"] = {  # `_d()`: which toon ground shader a palette uses
        "_default": "toonGrass",
        "grass": "toonGrass",
        "sand": "toonSand",
        "beach": "toonBeach",
        "snow": "toonSnow",
    }
    palettes["tile_size"] = 128  # env/<pack>/ground.png is 128 px = 128 / pixel_size world units

    # ---------------------------------------------------------------- constants
    m = re.search(r"(?<![\w$])Qu=1\.12,\$u=", bundle)
    c_start = m.start()
    consts = eval_js(work, "constants",
                     sequence_body(bundle, c_start, "cd=class", "terrain constants",
                                   "({grid_size:Qu,step:$u,landmark_radii:ed,shore_drop:td,"
                                   "shore_band:nd,coast_base:rd,coast_shore:id,coast_bias:ad,glacier_bias:od})"))
    consts["_offset"] = c_start
    consts["poly_dist"] = {
        "comment": "sd(x,z): distance to the edge of the 16-gon of the same radius, used for the tower arena wall",
        "sides": 16,
    }
    consts["pixel_size"] = None
    m = re.search(r"(?<![\w$])Iu=([\d.]+)", bundle)
    consts["pixel_size"] = float(m.group(1))
    consts["pixel_size_offset"] = m.start()
    consts["noise"] = {
        "rng": "Ol: s=(s+1831565813)>>>0; e=imul(s^s>>>15, s|1); e^= e+imul(e^e>>>7, e|61); ((e^e>>>14)>>>0)/2^32",
        "rng_offset": None,
        "simplex": "iu: 2D simplex, perm = Ol-shuffled 0..255, gradients [[1,1],[-1,1],[1,-1],[-1,-1],[1,0],[-1,0],[0,1],[0,-1]], F2=0.5*(sqrt(3)-1), G2=(3-sqrt(3))/6, scale 70",
        "fbm": "fbm(x,y,octaves=4,lacunarity=2,gain=0.5) normalised by the amplitude sum",
    }
    m = re.search(r"(?<![\w$])Ol=class\{s;constructor", bundle)
    consts["noise"]["rng_offset"] = m.start()

    # ---------------------------------------------------------------- weather + hazards
    m = re.search(r"(?<![\w$])cb=\{fog:\{name:", bundle)
    weather = eval_js(work, "weather",
                      sequence_body(bundle, m.start(), "lb=52,", "weather table", "cb"))
    weather["_offset"] = m.start()
    m = re.search(r"(?<![\w$])bw=\{mud:\{cell:0", bundle)
    hazards = eval_js(work, "hazards",
                      sequence_body(bundle, m.start(), "Sw=.5", "hazard table", "({defs:bw,byBiome:xw})"))
    hazards["_offset"] = m.start()
    for d in hazards["defs"].values():
        if isinstance(d.get("name"), str):
            d["name"] = tr(maps, d["name"])
        if isinstance(d.get("say"), str):
            d["say"] = tr(maps, d["say"])
    for d in weather.values():
        if isinstance(d, dict):
            for key in ("name", "sub"):
                if isinstance(d.get(key), str):
                    d[key] = tr(maps, d[key])

    out = args.out
    os.makedirs(out, exist_ok=True)

    def write(name: str, payload, key: str = "data") -> None:
        """Envelope used by every data/pb table: `_source` plus the payload under one key."""
        path = os.path.join(out, name)
        doc = {"_source": dict(meta)}
        doc["_generated_by"] = "tools/extract_world.py"
        if isinstance(payload, dict) and key == "data":
            doc.update(payload)
        else:
            doc[key] = payload
        with open(path, "w", encoding="utf8") as fh:
            json.dump(doc, fh, ensure_ascii=False, indent=1)
            fh.write("\n")
        print(f"    wrote {name} ({os.path.getsize(path)} bytes)")

    write("world_biomes.json", biomes, "biomes")
    write("world_props.json", props, "packs")
    write("world_palettes.json", palettes)
    write("world_fx.json", {"weather": weather, "hazards": hazards})
    write("world_constants.json", consts)
    return 0


if __name__ == "__main__":
    sys.exit(main())
