// bundle-native.js — assemble a self-contained native bundle for packaging.
// Copies the compiled addon + its sidecar runtime libraries from the CMake build
// tree into prebuilds/<platform>-<arch>/ so a published package needs no build
// step. The sidecars must sit beside the .node (Windows resolves dependents from
// that dir; on Linux the addon carries an $ORIGIN RUNPATH).
//
//   node scripts/bundle-native.js
// Override the addon dir with RA_NATIVE_DIR=<...>/sdk/runanywhere-electron/native
// (the CMake build output dir containing runanywhere_native.node).
const fs = require('fs');
const path = require('path');

const pkgRoot = path.join(__dirname, '..');
const repoRoot = path.join(pkgRoot, '..', '..');
const win = process.platform === 'win32';

const defaultBuild = win
  ? path.join(repoRoot, 'build', 'windows-release', 'sdk', 'runanywhere-electron', 'native', 'Release')
  : path.join(repoRoot, 'build', 'linux-release', 'sdk', 'runanywhere-electron', 'native');
const buildDir = process.env.RA_NATIVE_DIR || defaultBuild;
// The CMake build root, e.g. build/windows-release — sidecar libs live under it.
const buildRoot = path.resolve(buildDir, win ? '../../../..' : '../../..');
const outDir = path.join(pkgRoot, 'prebuilds', `${process.platform}-${process.arch}`);

// The addon plus the runtime libraries it dynamically links (onnxruntime for the
// ONNX engine, sherpa for STT/TTS). onnxruntime_providers_shared is a 0-byte stub
// on CPU builds but onnxruntime.dll still imports it, so it must be present.
// On Linux two distinct onnxruntime sonames ship: libonnxruntime.so.1 (the ONNX
// engine's, from the FetchContent lib dir) and libonnxruntime.so (sherpa's).
const FILES = win
  ? [
      { name: 'runanywhere_native.node', dir: buildDir },
      { name: 'onnxruntime.dll', dir: buildDir },
      { name: 'onnxruntime_providers_shared.dll', dir: buildDir },
      { name: 'sherpa-onnx-c-api.dll', dir: buildDir },
    ]
  : [
      { name: 'runanywhere_native.node', dir: buildDir },
      { name: 'libonnxruntime.so.1', dir: path.join(buildRoot, '_deps', 'onnxruntime-src', 'lib') },
      { name: 'libonnxruntime.so', dir: path.join(repoRoot, 'sdk', 'runanywhere-commons', 'third_party', 'sherpa-onnx-linux', 'lib') },
      { name: 'libsherpa-onnx-c-api.so', dir: path.join(repoRoot, 'sdk', 'runanywhere-commons', 'third_party', 'sherpa-onnx-linux', 'lib') },
    ];

fs.mkdirSync(outDir, { recursive: true });
let copied = 0;
let bytes = 0;
for (const f of FILES) {
  const src = path.join(f.dir, f.name);
  if (!fs.existsSync(src)) {
    console.error('  MISSING:', src);
    continue;
  }
  const size = fs.statSync(src).size;
  fs.copyFileSync(src, path.join(outDir, f.name));
  bytes += size;
  copied++;
  console.log('  +', f.name, (size / 1e6).toFixed(1) + ' MB');
}

if (copied < FILES.length) {
  console.error(`bundled ${copied}/${FILES.length} files — build the addon first (see README).`);
  process.exit(1);
}
console.log(`native bundle (${(bytes / 1e6).toFixed(1)} MB) -> ${outDir}`);
