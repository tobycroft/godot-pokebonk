// Export the web build's weather-event table (`uS` in the logic bundle) into
// data/pb/weather.json. The table holds the four random map events
// (fog / storm / eclipse / meowth) with their duration, species pool and
// look-atmosphere. `c()` is the web i18n lookup; with the identity fallback it
// yields the Spanish source strings, which is how the port stores its keys.
//
// Usage: node tools/export_web_weather.mjs /path/to/pokebonk-web

import fs from "node:fs";
import path from "node:path";
import url from "node:url";

const root = path.resolve(process.argv[2] || path.join(path.dirname(url.fileURLToPath(import.meta.url)), "..", "..", "pokebonk-web"));
const build = /name="pokebonk-build" content="([^"]+)"/.exec(fs.readFileSync(path.join(root, "index.html"), "utf8"))?.[1];
if (!build) throw new Error("pokebonk-build not found in index.html");

const bundlePath = path.join(root, "assets", `main-C5MieX6g-${build}.js`);
const src = fs.readFileSync(bundlePath, "utf8");
const match = /(?:,|;|var|const|let)uS=(\{fog:\{[\s\S]*?\}),dS=52,fS=class/.exec(src);
if (!match) throw new Error("weather-event table uS not found in " + bundlePath);

// The literal only calls c("...") for the display strings; keep them as-is.
const table = new Function("c", `return (${match[1]})`)((s) => s);
const outDir = path.resolve(path.dirname(url.fileURLToPath(import.meta.url)), "..", "data", "pb");
fs.writeFileSync(path.join(outDir, "weather.json"), JSON.stringify(table));
console.log(`weather: ${Object.keys(table).join(", ")} -> data/pb/weather.json`);
