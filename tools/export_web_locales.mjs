// Export the web build's UI dictionaries into the port's data/i18n/ui/<lang>.json.
//
// The web's i18n chunk (assets/i18n-*.js) stores the UI strings keyed by their
// Spanish source text: `c("Daño")` looks up `dict["Daño"]`. Locale dictionaries
// live in one chunk per language (assets/zh-*.js, ...), and `es` is the identity
// (no chunk). This script imports those chunks and writes a flat key -> text
// JSON per language, exactly as shipped, so the Godot port can reproduce the
// same lookup and the same fallback (missing key -> the Spanish key itself).
//
// Usage:
//   node tools/export_web_locales.mjs /path/to/pokebonk-web
//
// The build hash is resolved from index.html so a rebuilt web bundle only
// needs a re-run of this script.

import fs from "node:fs";
import path from "node:path";
import url from "node:url";

const webRoot = path.resolve(process.argv[2] || path.join(path.dirname(url.fileURLToPath(import.meta.url)), "..", "..", "pokebonk-web"));
const assets = path.join(webRoot, "assets");
const indexHtml = fs.readFileSync(path.join(webRoot, "index.html"), "utf8");
const build = /name="pokebonk-build" content="([^"]+)"/.exec(indexHtml)?.[1];
if (!build) throw new Error("pokebonk-build not found in index.html");

// `es` has no chunk: its dictionary is the identity of the keys.
const LANGS = ["en", "pt", "fr", "ja", "zh", "zht", "ko", "ru"];
const outDir = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), "..", "data", "i18n", "ui");
fs.mkdirSync(outDir, { recursive: true });

for (const lang of LANGS) {
  const chunk = fs.readdirSync(assets).find((f) => f.startsWith(`${lang}-`) && f.includes(build) && f.endsWith(".js"));
  if (!chunk) throw new Error(`no ${lang} chunk for build ${build}`);
  const mod = await import(url.pathToFileURL(path.join(assets, chunk)).href);
  const dict = mod.default;
  const keys = Object.keys(dict).sort();
  const sorted = {};
  for (const key of keys) sorted[key] = dict[key];
  const out = path.join(outDir, `${lang}.json`);
  fs.writeFileSync(out, JSON.stringify(sorted));
  console.log(`${lang}: ${keys.length} keys -> ${path.relative(webRoot, out)}`);
}
