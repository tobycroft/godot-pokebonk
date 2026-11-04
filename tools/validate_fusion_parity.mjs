#!/usr/bin/env node
// Diff the ported fusion catalogue against the web build.
//
//   node tools/validate_fusion_parity.mjs --web /path/to/pokebonk-web
//   node tools/validate_fusion_parity.mjs --web /path/to/pokebonk-web --fix
//
// --fix rewrites only power/cd/repeats/preload from the web truth; the default
// run is read-only.  `--web` defaults to ../pokebonk-web next to this repo.
//
// The web bundle keeps six fusion groups (YC/ZC/ew/cw/mw signatures + Cw extras)
// and applies three runtime tweaks before use: Mw power overrides, Pw repeat
// flags and Nw cooldown scaling.  This script replays those tweaks on the raw
// literals and compares the result with data/pb/fusion_catalog.json and
// data/pb/fusion_extras.json.
//
// Exit code 0 = every field matches, 1 = differences found.

import fs from 'node:fs';
import path from 'node:path';

const argv = process.argv.slice(2);
const arg = (name, fallback) => {
  const i = argv.indexOf(name);
  return i >= 0 && i + 1 < argv.length ? argv[i + 1] : fallback;
};

const repo = path.resolve(path.dirname(new URL(import.meta.url).pathname), '..');
const web = path.resolve(arg('--web', path.join(repo, '..', 'pokebonk-web')));
const assets = path.join(web, 'assets');
const mainJs = fs
  .readdirSync(assets)
  .filter((f) => f.startsWith('main-') && f.endsWith('.js'))
  .map((f) => path.join(assets, f))
  .sort((a, b) => fs.statSync(b).size - fs.statSync(a).size)[0];
if (!mainJs) throw new Error(`no main-*.js under ${assets}`);
const src = fs.readFileSync(mainJs, 'utf8');

// ---------------------------------------------------------------- span helpers
const OPENERS = { '[': ']', '{': '}', '(': ')' };

/** Index of the matching closer for the opener at `start`. */
function matchBracket(start) {
  const open = src[start];
  const close = OPENERS[open];
  let depth = 0;
  let quote = null;
  for (let i = start; i < src.length; i++) {
    const ch = src[i];
    if (quote) {
      if (ch === '\\') {
        i++;
      } else if (ch === quote) {
        quote = null;
      }
      continue;
    }
    if (ch === "'" || ch === '"' || ch === '`') {
      quote = ch;
    } else if (ch === open) {
      depth++;
    } else if (ch === close) {
      depth--;
      if (depth === 0) return i;
    }
  }
  throw new Error(`unbalanced ${open} at ${start}`);
}

/** `NAME=[...]` (or `,NAME=[...]`) literal text including the brackets. */
function arrayOf(marker) {
  const at = src.indexOf(marker);
  if (at < 0) throw new Error(`missing marker ${marker}`);
  const start = src.indexOf('[', at);
  return src.slice(start, matchBracket(start) + 1);
}

function exprBetween(marker, endMarker) {
  const at = src.indexOf(marker);
  if (at < 0) throw new Error(`missing marker ${marker}`);
  const start = at + marker.length;
  const end = src.indexOf(endMarker, start);
  if (end < 0) throw new Error(`missing end marker ${endMarker}`);
  return src.slice(start, end);
}

const evalExpr = (body, prelude = '') =>
  new Function('c', `${prelude}\nreturn (${body});`)((s) => s);

const signatureGroups = ['YC', 'ZC', 'ew', 'cw', 'mw'].map((name) => {
  const marker = name === 'ew' ? ',ew=[' : name === 'YC' || name === 'ZC' ? `var ${name}=[` : `var ${name}=[`;
  return evalExpr(arrayOf(marker));
});

const gw = evalExpr(exprBetween('var gw=', ';function _w'));
const yw = evalExpr(exprBetween(',yw=', ',bw=['));
const typeFusions = evalExpr(arrayOf('var vw=['), `const gw=${gw.toString()};`);
const reactions = evalExpr(arrayOf(',bw=['), `const yw=${yw.toString()};`);
const glitch = evalExpr(exprBetween('var Sw=', ',Cw=['));
const extras = [...typeFusions, ...reactions, glitch];

const raw = [...signatureGroups.flat(), ...extras];

// ------------------------------------------------------- web runtime tweaks
const powerOverrides = evalExpr(
  (() => {
    const at = src.indexOf('Mw={"fu-1"');
    return src.slice(src.indexOf('{', at), src.indexOf(',Nw=', at));
  })(),
);
const repeats = new Set(evalExpr(arrayOf('Pw=new Set([')));
const cdScale = Number(/},Nw=(\.?[0-9.]+),Pw=/.exec(src)[1]);

const webEntries = new Map();
for (const entry of raw) {
  let power = powerOverrides[entry.key] ?? entry.power;
  let cd = entry.cd * cdScale;
  const repeat = repeats.has(entry.key) || !!entry.repeats;
  if (power > 4) {
    const t = Math.max(2 / cd, Math.sqrt(4 / power));
    if (t < 1) {
      cd *= t;
      power *= t;
    }
  }
  webEntries.set(entry.key, { ...entry, power, cd, repeats: repeat });
}

// ---------------------------------------------------------- godot tables
const tables = {};
const godotEntries = new Map();
for (const file of ['fusion_catalog.json', 'fusion_extras.json']) {
  const table = JSON.parse(fs.readFileSync(path.join(repo, 'data', 'pb', file), 'utf8'));
  tables[file] = table;
  for (const entry of table.entries) godotEntries.set(entry.key, entry);
}

// Functions carry code, not data; `group`/`has_behaviour_code` are port-only bookkeeping.
const IGNORED = new Set(['cast', 'sfx', 'info', 'group', 'has_behaviour_code']);
// Fields the web leaves undefined and the port fills with a harmless default.
const PORT_DEFAULTS = { moves: [], range: 0 };
const FIXABLE = new Set(['power', 'cd', 'repeats', 'preload']);
const near = (a, b) => Math.abs(Number(a) - Number(b)) < 0.006;
const close = (v) => Number(Number(v).toFixed(6));
const rows = [];
const keyDiff = [];
const fixes = [];

for (const key of new Set([...webEntries.keys(), ...godotEntries.keys()])) {
  const w = webEntries.get(key);
  const g = godotEntries.get(key);
  if (!w || !g) {
    keyDiff.push({ key, web: !!w, godot: !!g });
    continue;
  }
  for (const field of new Set([...Object.keys(w), ...Object.keys(g)])) {
    if (IGNORED.has(field)) continue;
    const wv = w[field];
    const gv = g[field];
    const wvJson = JSON.stringify(wv ?? null);
    const gvJson = JSON.stringify(gv ?? null);
    if (wv === undefined && gvJson === JSON.stringify(PORT_DEFAULTS[field])) continue;
    if (typeof wv === 'number' && typeof gv === 'number') {
      if (!near(wv, gv)) rows.push({ key, field, web: wv, godot: gv });
    } else if (wvJson !== gvJson) {
      rows.push({ key, field, web: wvJson, godot: gvJson });
    }
  }
  const wHasBehaviour = !!(w.cast || w.sfx);
  const gHasBehaviour = !!g.has_behaviour_code || !!(g.cast || g.sfx);
  if (wHasBehaviour !== gHasBehaviour) {
    rows.push({ key, field: 'has_behaviour_code', web: wHasBehaviour, godot: gHasBehaviour });
  }
  if (argv.includes('--fix')) {
    for (const field of ['power', 'cd', 'repeats', 'preload']) {
      if (!FIXABLE.has(field) || w[field] === undefined) continue;
      if (!rows.some((r) => r.key === key && r.field === field)) continue;
      g[field] = typeof w[field] === 'number' ? close(w[field]) : w[field];
      fixes.push({ key, field });
    }
  }
}

if (argv.includes('--fix') && fixes.length) {
  for (const [file, table] of Object.entries(tables)) {
    fs.writeFileSync(
      path.join(repo, 'data', 'pb', file),
      JSON.stringify(table) + '\n',
    );
  }
  console.log(`fixed ${fixes.length} fields (power/cd/repeats/preload) in data/pb/*.json`);
}

console.log(`web bundle: ${path.relative(web, mainJs)}`);
console.log(`web entries: ${webEntries.size} | godot entries: ${godotEntries.size}`);
console.log(`mismatches: ${rows.length} | key gaps: ${keyDiff.length}`);
if (keyDiff.length) console.table(keyDiff);
if (rows.length) console.table(rows);
process.exit(rows.length || keyDiff.length ? 1 : 0);
