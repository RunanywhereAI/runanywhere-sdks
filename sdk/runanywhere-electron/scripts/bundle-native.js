// bundle-native.js — assemble a self-contained native bundle for packaging.
// Copies the compiled addon + its sidecar DLLs from the CMake build tree into
// prebuilds/<platform>-<arch>/ so a published package needs no build step. The
// DLLs must sit beside the .node (Windows resolves dependents from that dir).
//
//   node scripts/bundle-native.js
// Override the source dir with RA_NATIVE_DIR=<...>\native\Release.
const fs = require('fs');
const path = require('path');

const pkgRoot = path.join(__dirname, '..');
const defaultBuild = path.join(
  pkgRoot, '..', '..', 'build', 'windows-release', 'sdk',
  'runanywhere-electron', 'native', 'Release'
);
const buildDir = process.env.RA_NATIVE_DIR || defaultBuild;
const outDir = path.join(pkgRoot, 'prebuilds', `${process.platform}-${process.arch}`);

// The addon plus the runtime DLLs it dynamically links (onnxruntime for the ONNX
// engine, sherpa for STT/TTS). onnxruntime_providers_shared is a 0-byte stub on
// CPU builds but onnxruntime.dll still imports it, so it must be present.
const FILES = [
  'runanywhere_native.node',
  'onnxruntime.dll',
  'onnxruntime_providers_shared.dll',
  'sherpa-onnx-c-api.dll',
];

fs.mkdirSync(outDir, { recursive: true });
let copied = 0;
let bytes = 0;
for (const f of FILES) {
  const src = path.join(buildDir, f);
  if (!fs.existsSync(src)) {
    console.error('  MISSING:', src);
    continue;
  }
  const size = fs.statSync(src).size;
  fs.copyFileSync(src, path.join(outDir, f));
  bytes += size;
  copied++;
  console.log('  +', f, (size / 1e6).toFixed(1) + ' MB');
}

if (copied < FILES.length) {
  console.error(`bundled ${copied}/${FILES.length} files — build the addon first (see README).`);
  process.exit(1);
}
console.log(`native bundle (${(bytes / 1e6).toFixed(1)} MB) -> ${outDir}`);
