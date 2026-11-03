#!/usr/bin/env node
/**
 * Run the shipped terrain generator outside the browser.
 *
 * The minified bundle carries the whole world generator as one class (`cd` in build
 * mvlr7rzv) next to its helpers: a mulberry32 RNG (`Ol`), a 2D simplex (`iu`), the prop
 * catalogues (`au`) and the numeric constants. Nothing in `generate()`, `planLandmarks()`
 * or `placeEnv()` touches WebGL, so the class can be sliced out of the bundle and driven
 * directly — that makes it the reference the Godot port has to match cell for cell.
 *
 * Rendering-only dependencies (three.js geometry/material classes) are resolved through a
 * `with` scope that hands out permissive stubs, so methods like `buildPads()` still run
 * their data part; `Vector3` gets a real stub because landmark points carry coordinates.
 *
 * Usage:
 *   node tools/terrain_reference.mjs <bundle.js> <biome> <seed> [--props N]
 *   node tools/terrain_reference.mjs <bundle.js> --all            # every biome, 3 seeds
 *   node tools/terrain_reference.mjs <bundle.js> --list
 */
import fs from 'node:fs';
import path from 'node:path';

const OPENERS = { '{': '}', '[': ']', '(': ')' };
const CLOSERS = { '}': '{', ']': '[', ')': '[' };

/**
 * String-aware balanced literal starting at `start`.
 *
 * A mode stack (code / string / template) is what makes this work on the terrain class:
 * its GLSL lives in template literals that contain unbalanced `{`/`}` and `${}` holes, so a
 * naive brace counter truncates the slice at the first shader brace.
 */
function findLiteral(src, start) {
  if (!OPENERS[src[start]]) throw new Error(`anchor is not a bracket: ${src.slice(start, start + 40)}`);
  const stack = [{ type: 'code', braces: 0 }];
  let i = start;
  while (i < src.length) {
    const top = stack[stack.length - 1];
    const ch = src[i];
    if (top.type === 'str') {
      if (ch === '\\') { i += 2; continue; }
      if (ch === top.q) stack.pop();
      i += 1;
      continue;
    }
    if (top.type === 'tpl') {
      if (ch === '\\') { i += 2; continue; }
      if (ch === '`') { stack.pop(); i += 1; continue; }
      if (ch === '$' && src[i + 1] === '{') { stack.push({ type: 'code', braces: 0 }); i += 2; continue; }
      i += 1;
      continue;
    }
    if (ch === '"' || ch === "'") { stack.push({ type: 'str', q: ch }); i += 1; continue; }
    if (ch === '`') { stack.push({ type: 'tpl' }); i += 1; continue; }
    if (ch === '/' && src[i + 1] === '/') { const nl = src.indexOf('\n', i); i = nl < 0 ? src.length : nl; continue; }
    if (ch === '/' && src[i + 1] === '*') { const end = src.indexOf('*/', i); i = end < 0 ? src.length : end + 2; continue; }
    if (OPENERS[ch]) top.braces += 1;
    else if (CLOSERS[ch]) {
      top.braces -= 1;
      if (top.braces === 0 && stack.length === 1) return src.slice(start, i + 1);
      if (top.braces < 0) stack.pop();
    }
    i += 1;
  }
  throw new Error('unbalanced literal');
}

function at(src, anchor, label) {
  const i = src.indexOf(anchor);
  if (i < 0) throw new Error(`${label}: anchor ${JSON.stringify(anchor)} not found`);
  return i;
}

/** Slice a `name=class{...}` declaration, returning the whole `name=class{...}` text. */
function sliceClass(src, anchor, label) {
  const start = at(src, anchor, label);
  const brace = src.indexOf('{', start + anchor.length - 1);
  return src.slice(start, start + anchor.length - 'class'.length + findLiteral(src, brace).length + 'class'.length - 1)
    .replace(/$/, '');
}

function sliceDecls(src, startAnchor, endAnchor, label) {
  const start = at(src, startAnchor, label);
  const end = at(src, endAnchor, label);
  if (end <= start) throw new Error(`${label}: ${endAnchor} is before ${startAnchor}`);
  return src.slice(start, end).replace(/[,;]\s*$/, '');
}

/** A permissive object: every method returns itself, every read yields another stub. */
const chainable = () => new Proxy(function () {}, {
  get: (_t, key) => (key === 'then' ? undefined : chainable()),
  apply: () => chainable(),
  construct: () => chainable(),
});

const ANY_METHODS = ['add', 'remove', 'set', 'clone', 'copy', 'lerp', 'normalize', 'multiplyScalar',
  'offsetHSL', 'getHex', 'setHex', 'setRGB', 'setScalar', 'setMatrixAt', 'compose', 'makeTranslation',
  'setFromAxisAngle', 'rotateX', 'translate', 'setAttribute', 'computeVertexNormals', 'dispose',
  'fill', 'needsUpdate', 'addColorStop'];

function makeEnv() {
  const known = new Map();
  const anyClass = (name) => {
    const cls = class {
      constructor(...args) {
        this.__args = args;
        if (args.length) Object.assign(this, { x: args[0], y: args[1], z: args[2] });
      }
    };
    for (const m of ANY_METHODS) cls.prototype[m] = function () { return this; };
    known.set(name, cls);
  };
  // Vector3-ish values are read back (landmark points, spawn), so they need real fields.
  known.set('ti', class Vec3 {
    constructor(x = 0, y = 0, z = 0) { this.x = x; this.y = y; this.z = z; }
    set(x, y, z) { this.x = x; this.y = y; this.z = z; return this; }
    setScalar(v) { this.x = v; this.y = v; this.z = v; return this; }
    setComponent(i, v) { this[['x', 'y', 'z'][i]] = v; return this; }
    clone() { return new Vec3(this.x, this.y, this.z); }
    copy(v) { return this.set(v.x, v.y, v.z); }
    add(v) { return this.set(this.x + v.x, this.y + v.y, this.z + v.z); }
    sub(v) { return this.set(this.x - v.x, this.y - v.y, this.z - v.z); }
    multiplyScalar(v) { return this.set(this.x * v, this.y * v, this.z * v); }
    lerp(v, a) { return this.set(this.x + (v.x - this.x) * a, this.y + (v.y - this.y) * a, this.z + (v.z - this.z) * a); }
    dot(v) { return this.x * v.x + this.y * v.y + this.z * v.z; }
    length() { return Math.hypot(this.x, this.y, this.z); }
    lengthSq() { return this.x ** 2 + this.y ** 2 + this.z ** 2; }
    normalize() { const l = this.length() || 1; return this.multiplyScalar(1 / l); }
  });
  for (const name of ['Ei', 'Cr', 'Tr', 'Yr', 'Nr', 'Sr', 'Pr', 'wr', 'vr', 'Kr', 'xr', 'di',
    'Oi', 'Zr', 'gr', 'Ti', 'Uint8ClampedArrayShim']) anyClass(name);

  const stub = chainable();
  const env = new Proxy(known, {
    has: () => true,
    get: (_t, key) => {
      if (key === Symbol.unscopables || typeof key === 'symbol') return undefined;
      if (key === 'undefined') return undefined;
      if (key in globalThis) return globalThis[key];
      if (known.has(key)) return known.get(key);
      return stub;
    },
    set: (_t, key, value) => { known.set(key, value); return true; },
  });
  return env;
}

function loadSandbox(bundleSrc) {
  const rng = sliceClass(bundleSrc, 'Ol=class{', 'rng');
  const noiseAnchor = at(bundleSrc, 'var tu=.5*(Math.sqrt(3)-1),nu=', 'noise');
  const tuStart = noiseAnchor + 'var '.length;
  const iuStart = bundleSrc.indexOf('iu=class{', noiseAnchor);
  if (iuStart < 0) throw new Error('noise: iu=class not found');
  const noiseDecl = bundleSrc.slice(tuStart, iuStart + 'iu=class'.length)
    + findLiteral(bundleSrc, bundleSrc.indexOf('{', iuStart + 'iu=class'.length - 1));

  const consts = sliceDecls(bundleSrc, 'Qu=1.12,$u=', 'cd=class{', 'terrain constants');
  const terrain = 'cd=class' + findLiteral(bundleSrc, at(bundleSrc, 'cd=class{', 'terrain class') + 'cd=class{'.length - 1);
  const props = sliceDecls(bundleSrc, 'au={forest:', 'var cu=', 'prop table');
  const helpers = sliceDecls(bundleSrc, 'Gs=(e,t,n)=>', 'Js=(e,t,n,r)=>', 'math helpers');

  const code = `
  const ${rng};
  const ${helpers};
  const ${noiseDecl};
  const ${consts};
  let ${props};
  const ${terrain};
  return { Ol, iu, au, cd, qs, Gs, C: { Qu, step: $u, ed, td, nd, rd, id, ad, od } };
  `;
  return new Function('__env', `with (__env) {\n${code}\n}`)(makeEnv());
}

function loadBiomes(assetsDir) {
  const index = fs.readFileSync(path.join(assetsDir, '..', 'index.html'), 'utf8');
  const build = (index.match(/pokebonk-build" content="([0-9a-z]+)"/) ?? [])[1] ?? '';
  const news = fs.readdirSync(assetsDir)
    .filter((f) => f.startsWith('news-') && f.endsWith('.js') && (!build || f.includes(build)))
    .sort().pop();
  if (!news) throw new Error('news chunk not found');
  const src = fs.readFileSync(path.join(assetsDir, news), 'utf8');
  const start = at(src, '[{id:`forest`', 'biome registry');
  return new Function('t', `return ${findLiteral(src, start)};`)((s) => s);
}

const q = (v, digits = 6) => {
  const f = 10 ** digits;
  return Math.round(v * f) / f;
};

function buildTerrain(api, biomes, biomeId, seed) {
  const biome = biomes.find((b) => b.id === biomeId);
  if (!biome) throw new Error(`unknown biome ${biomeId}`);
  const T = Object.create(api.cd.prototype);
  Object.assign(T, {
    biome, seed: seed >>> 0, arena: null, shared: { uTime: { value: 0 } },
    world: biome.size ?? 280, arenaR: Infinity,
    res: Math.round((biome.size ?? 280) / api.C.Qu),
  });
  T.cell = T.world / T.res;
  T.play = T.world / 2 - 12;
  T.heights = new Float32Array((T.res + 1) * (T.res + 1));
  T.pathMask = new Float32Array((T.res + 1) * (T.res + 1));
  T.noise = new api.iu(T.seed);
  T.noise2 = new api.iu(T.seed ^ 1540483477);
  T.hasWater = biome.water !== null;
  T.isLava = biome.water === -1;
  T.frozen = biome.id === 'glacier';
  Object.assign(T, {
    waterLevel: -99, baseWater: -99, colliders: [], solidBoxes: [], clearZones: [],
    massifs: [], landmarks: [], ponds: [], waterMeshes: [], textures: [], mats: [],
    colGrid: new Map(), covers: [], group: { add() {} }, disposed: false, phase: 0,
    spawn: new (globalThis.Vector3Stub ?? Object)(),
  });
  T.spawn = { x: 0, y: 0, z: 0, set(x, y, z) { this.x = x; this.y = y; this.z = z; return this; } };

  // Record the ramp pairs connectPlateaus() picks, so a divergence can be attributed to the
  // plateau-linking step instead of the height field.
  const ramps = [];
  let latticePre = 0;
  const baseConnect = api.cd.prototype.connectPlateaus;
  T.connectPlateaus = function () {
    for (const h of this.heights) latticePre += Math.round(h * 1000);
    return baseConnect.call(this);
  };
  const baseCarve = api.cd.prototype.carveRamp;
  T.carveRamp = function (a, b, c, d) { ramps.push([a, b, c, d]); return baseCarve.call(this, a, b, c, d); };
  T.generate();
  T.planLandmarks();
  const props = T.placeEnv(api.au[biome.id]);
  let hash = 0;
  for (const h of T.heights) hash += Math.round(h * 1000);
  return { T, props, ramps, lattice: hash, latticePre };
}

function report(T, props, seed, propSample, ramps = [], lattice = 0, latticePre = 0) {
  const N = 17;
  const heights = [];
  for (let a = 0; a < N; a++) {
    const row = [];
    for (let b = 0; b < N; b++) {
      const x = -T.play + (2 * T.play * a) / (N - 1);
      const z = -T.play + (2 * T.play * b) / (N - 1);
      row.push(q(T.height(x, z)));
    }
    heights.push(row);
  }
  let flat = 0, water = 0, hits = 0, solid = 0;
  for (let i = 0; i < 4000; i++) {
    const x = (((i * 7919) % 1000) / 1000) * 2 * T.play - T.play;
    const z = (((i * 104729) % 1000) / 1000) * 2 * T.play - T.play;
    if (T.isFlatOpen(x, z)) flat++;
    if (T.inWater(x, z)) water++;
    if (T.hitProp(x, z, 0, 0.5)) hits++;
    if (!T.inBounds(x, z, 1)) solid++;
  }
  const perKind = {};
  let checksum = 0;
  for (const p of props) {
    perKind[p.kind.name] = (perKind[p.kind.name] ?? 0) + 1;
    checksum += q(p.x * 100) + q(p.z * 100) + q(p.s * 1000) + (p.flip ? 1 : 0);
  }
  const row = (p) => [p.kind.name, q(p.x), q(p.y), q(p.z), !!p.flip, q(p.s)];
  return {
    biome: T.biome.id, seed,
    world: T.world, res: T.res, cell: q(T.cell), play: T.play,
    minH: q(T.minH), maxH: q(T.maxH),
    waterLevel: q(T.waterLevel), baseWater: q(T.baseWater),
    hasWater: T.hasWater, isLava: T.isLava, frozen: T.frozen,
    spawn: [q(T.spawn.x), q(T.spawn.y), q(T.spawn.z)],
    massifs: T.massifs.map((m) => [q(m.x), q(m.z), q(m.r)]),
    ponds: T.ponds.map((p) => [q(p.x), q(p.z), q(p.r), q(p.h), q(p.level), q(p.seed)]),
    landmarks: T.landmarks.map((l) => [l.kind, q(l.x), q(l.z), q(l.r)]),
    colliders: { count: T.colliders.length, first: T.colliders.slice(0, 24).map((c) => [q(c.x), q(c.z), q(c.r), q(c.h)]) },
    heights,
    props: {
      count: props.length, perKind, checksum: q(checksum, 0),
      first: props.slice(0, propSample).map(row),
      last: props.slice(Math.max(0, props.length - propSample)).map(row),
    },
    probes: { flat, water, hits, outOfBounds: solid },
    ramps,
    lattice,
    latticePre,
  };
}

function main() {
  const [, , bundlePath, arg2, arg3, ...rest] = process.argv;
  if (!bundlePath) { console.error('usage: terrain_reference.mjs <bundle.js> <biome> <seed>'); return 2; }
  const api = loadSandbox(fs.readFileSync(bundlePath, 'utf8'));
  const biomes = loadBiomes(path.dirname(bundlePath));

  if (arg2 === '--list') { console.log(biomes.map((b) => b.id).join(' ')); return 0; }
  const propSample = Number((rest.find((a) => a.startsWith('--props')) ?? '--props 12').split(' ')[1] ?? 12);
  if (arg2 === '--all') {
    const seeds = [0, 2026, 1987654321];
    const out = [];
    for (const b of biomes) for (const s of seeds) {
      const { T, props, ramps, lattice, latticePre } = buildTerrain(api, biomes, b.id, s);
      out.push(report(T, props, s, propSample, ramps, lattice, latticePre));
    }
    console.log(JSON.stringify(out));
    return 0;
  }
  const { T, props, ramps, lattice, latticePre } = buildTerrain(api, biomes, arg2, Number(arg3 ?? 2026));
  console.log(JSON.stringify(report(T, props, Number(arg3 ?? 2026), propSample, ramps, lattice, latticePre), null, rest.includes('--pretty') ? 1 : 0));
  return 0;
}

// `process.exit()` right after a large console.log truncates stdout at the 64 KB pipe limit;
// setting exitCode lets the write drain.
process.exitCode = main();
