#!/usr/bin/env node
/**
 * Fail closed if the resolved @runanywhere/proto-ts version does not satisfy
 * our peerDependencies range. Lives in a real .mjs so Windows npm/cmd cannot
 * corrupt the caret-range regex the way an inline `node -e` string does.
 */
import { createRequire } from "node:module";
import { readFileSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";

const root = join(dirname(fileURLToPath(import.meta.url)), "..");
const pkg = JSON.parse(readFileSync(join(root, "package.json"), "utf8"));
const peer = pkg.peerDependencies?.["@runanywhere/proto-ts"];
if (typeof peer !== "string") {
  console.error("Missing peerDependencies[@runanywhere/proto-ts]");
  process.exit(1);
}

const match = /^\^(\d+)\.(\d+)\.(\d+)$/.exec(peer);
if (!match) {
  console.error("Invalid peerDependencies[@runanywhere/proto-ts]:", peer);
  process.exit(1);
}
const wantMaj = Number(match[1]);
const wantMin = Number(match[2]);
const wantPat = Number(match[3]);

const require = createRequire(join(root, "package.json"));
const resolved = require("@runanywhere/proto-ts/package.json");
const parts = String(resolved.version)
  .split(".")
  .map(Number);
if (parts.length < 3 || parts.some((n) => Number.isNaN(n))) {
  console.error("@runanywhere/proto-ts version drift: unreadable version", resolved.version);
  process.exit(1);
}
const [maj, min, pat] = parts;
const ok =
  wantMaj === 0
    ? maj === 0 && min === wantMin && pat >= wantPat
    : maj === wantMaj && (min > wantMin || (min === wantMin && pat >= wantPat));
if (!ok) {
  console.error(
    "@runanywhere/proto-ts version drift: resolved",
    resolved.version,
    "does not satisfy peer",
    peer,
  );
  process.exit(1);
}
console.log("@runanywhere/proto-ts", resolved.version, "satisfies", peer);
