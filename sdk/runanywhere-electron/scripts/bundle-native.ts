// bundle-native.ts — assemble a self-contained native bundle for packaging.
// Copies the compiled addon + its sidecar runtime libraries from the CMake build
// tree into prebuilds/<platform>-<arch>/ so a published package needs no build
// step. The sidecars must sit beside the .node (Windows resolves dependents from
// that dir; on Linux the addon carries an $ORIGIN RUNPATH).
//
//   npm run bundle:native
// Override the addon dir with RA_NATIVE_DIR=<...>/sdk/runanywhere-electron/native
// (the CMake build output dir containing runanywhere_native.node).
import * as fs from 'fs';
import * as path from 'path';

/** One file to stage, and the directory it is built into. */
interface SidecarFile {
  name: string;
  dir: string;
  /** "copy if built, do not fail the bundle" — never set on the addon itself. */
  optional?: boolean;
}

const pkgRoot = path.join(__dirname, '..');
const repoRoot = path.join(pkgRoot, '..', '..');
const win = process.platform === 'win32';
const mac = process.platform === 'darwin';
const winArm64 = win && process.arch === 'arm64';

// One CMake preset per Windows architecture — the ARM64 build tree is separate
// because the generator platform (and therefore node.lib) differs. macOS builds
// through the macos-release preset; the plan's verified local tree is
// build/electron-macos, so both are tried in order.
const winPreset = winArm64 ? 'windows-arm64-release' : 'windows-release';
const nativeSubPath = path.join('sdk', 'runanywhere-electron', 'native');
const macBuildDirs = [
  path.join(repoRoot, 'build', 'electron-macos', nativeSubPath),
  path.join(repoRoot, 'build', 'macos-release', nativeSubPath),
];
const defaultBuild = win
  ? path.join(repoRoot, 'build', winPreset, nativeSubPath, 'Release')
  : mac
    ? (macBuildDirs.find((dir) => fs.existsSync(path.join(dir, 'runanywhere_native.node'))) ??
      macBuildDirs[0])
    : path.join(repoRoot, 'build', 'linux-release', nativeSubPath);
const buildDir = process.env.RA_NATIVE_DIR || defaultBuild;
// The CMake build root, e.g. build/windows-release — sidecar libs live under it.
const buildRoot = path.resolve(buildDir, win ? '../../../..' : '../../..');
// process.arch is 'arm64' on Windows on ARM, so this is prebuilds/win32-arm64/.
const outDir = path.join(pkgRoot, 'prebuilds', `${process.platform}-${process.arch}`);

// The addon plus the runtime libraries it dynamically links (onnxruntime for the
// ONNX engine, sherpa for STT/TTS). onnxruntime_providers_shared is a 0-byte stub
// on CPU builds but onnxruntime.dll still imports it, so it must be present.
// On Linux two distinct onnxruntime sonames ship: libonnxruntime.so.1 (the ONNX
// engine's, from the FetchContent lib dir) and libonnxruntime.so (sherpa's).
//
// macOS ships NO sidecars: the addon links onnx and sherpa statically, so
// `otool -L runanywhere_native.node` lists only system frameworks. Staging a
// .dylib there would be staging a file that does not exist.
//
// `optional: true` means "copy if built, do not fail the bundle". Windows on ARM64
// uses it for the ONNX/sherpa sidecars: FetchONNXRuntime.cmake has no win-arm64
// release URL, so an ARM64 build has no ONNX engine to ship a DLL for. The addon
// itself is never optional.
const FILES: readonly SidecarFile[] = win
  ? [
      { name: 'runanywhere_native.node', dir: buildDir },
      { name: 'onnxruntime.dll', dir: buildDir, optional: winArm64 },
      { name: 'onnxruntime_providers_shared.dll', dir: buildDir, optional: winArm64 },
      { name: 'sherpa-onnx-c-api.dll', dir: buildDir, optional: winArm64 },
    ]
  : mac
    ? [{ name: 'runanywhere_native.node', dir: buildDir }]
    : [
        { name: 'runanywhere_native.node', dir: buildDir },
        { name: 'libonnxruntime.so.1', dir: path.join(buildRoot, '_deps', 'onnxruntime-src', 'lib') },
        { name: 'libonnxruntime.so', dir: path.join(repoRoot, 'sdk', 'runanywhere-commons', 'third_party', 'sherpa-onnx-linux', 'lib') },
        { name: 'libsherpa-onnx-c-api.so', dir: path.join(repoRoot, 'sdk', 'runanywhere-commons', 'third_party', 'sherpa-onnx-linux', 'lib') },
      ];

fs.mkdirSync(outDir, { recursive: true });
const required = FILES.filter((f) => !f.optional).length;
let copied = 0;
let bytes = 0;
for (const f of FILES) {
  const src = path.join(f.dir, f.name);
  if (!fs.existsSync(src)) {
    console.error(f.optional ? '  skipped (not built):' : '  MISSING:', src);
    continue;
  }
  const size = fs.statSync(src).size;
  fs.copyFileSync(src, path.join(outDir, f.name));
  bytes += size;
  copied++;
  console.log('  +', f.name, (size / 1e6).toFixed(1) + ' MB');
}

if (copied < required) {
  console.error(`bundled ${copied}/${required} required files — build the addon first (see README).`);
  process.exit(1);
}

// The QAIRT/QNN runtime for the Hexagon NPU, when one has been staged. Opt-in via
// RA_QNN_RUNTIME_DIR because QAIRT is a licensed vendor SDK that is not in this
// repo and is absent on every CI host — a build without it simply ships no NPU
// runtime and the engine reports the device as unavailable.
//
// This copies a FLAT directory verbatim: on Windows the HTP stub finds the per-arch
// skel and its .cat through its own directory (there is no ADSP_LIBRARY_PATH), so
// splitting the set across directories breaks it with an opaque signature error.
// Anything else already staged there (a second arch's skel) comes along.
const qnnDir = process.env.RA_QNN_RUNTIME_DIR;
if (qnnDir) {
  if (!fs.existsSync(qnnDir)) {
    console.error('  MISSING: RA_QNN_RUNTIME_DIR does not exist:', qnnDir);
    process.exit(1);
  }
  let qnnFiles = 0;
  let qnnBytes = 0;
  for (const entry of fs.readdirSync(qnnDir, { withFileTypes: true })) {
    // Flat set only. The staging dir also holds QHexRT's own CLI tools, which the
    // app has no use for.
    if (!entry.isFile() || /\.exe$/i.test(entry.name)) continue;
    const src = path.join(qnnDir, entry.name);
    fs.copyFileSync(src, path.join(outDir, entry.name));
    qnnBytes += fs.statSync(src).size;
    qnnFiles++;
  }
  bytes += qnnBytes;
  console.log(`  + QNN runtime: ${qnnFiles} files, ${(qnnBytes / 1e6).toFixed(1)} MB (from ${qnnDir})`);
}

console.log(`native bundle (${(bytes / 1e6).toFixed(1)} MB) -> ${outDir}`);
