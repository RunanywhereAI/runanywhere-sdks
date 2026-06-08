#!/usr/bin/env node
// Durable fix for a PRE-EXISTING toolchain incompatibility (unrelated to the
// RunAnywhere SDK): react-native-screens 4.24.0 emits native event props typed
// as a plain `UnionTypeAnnotation` (e.g. string-literal unions like
// 'push' | 'pop'), but React Native 0.83.1's codegen only handles
// `StringLiteralUnionTypeAnnotation`, so its event-emitter generators throw
//   "Received invalid event property type UnionTypeAnnotation"
// during `generateCodegenArtifactsFromSchema`, before any RunAnywhere code is
// reached. patch-package cannot cleanly patch RN's huge, nested
// @react-native/codegen, so we add the missing `case` (string-valued, mirroring
// the existing StringLiteralUnionTypeAnnotation handling) to every codegen
// generator copy found under node_modules. Idempotent.
//
// Remove this once react-native-screens is pinned to an RN-0.83-compatible
// release or @react-native/codegen learns to handle UnionTypeAnnotation.

const fs = require('node:fs');
const path = require('node:path');

const ROOT = path.join(process.cwd(), 'node_modules');
const NEEDLE = "case 'StringLiteralUnionTypeAnnotation':";
const ADD = "case 'UnionTypeAnnotation':";
const CODEGEN = `@react-native${path.sep}codegen`;

let patched = 0;

function walk(dir) {
  let entries;
  try {
    entries = fs.readdirSync(dir, { withFileTypes: true });
  } catch {
    return;
  }
  for (const e of entries) {
    if (e.isSymbolicLink()) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) {
      walk(p);
    } else if (e.name.endsWith('.js') && p.includes(CODEGEN)) {
      let src;
      try {
        src = fs.readFileSync(p, 'utf8');
      } catch {
        continue;
      }
      if (src.includes(NEEDLE) && !src.includes(ADD)) {
        const escaped = NEEDLE.replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
        const re = new RegExp(`(\\n[ \\t]*)${escaped}`, 'g');
        fs.writeFileSync(
          p,
          src.replace(re, (_m, ws) => `${ws}${ADD}${ws}${NEEDLE}`)
        );
        patched += 1;
      }
    }
  }
}

walk(ROOT);
process.stdout.write(
  `[patch-rn-codegen] UnionTypeAnnotation: patched ${patched} codegen generator file(s)\n`
);
