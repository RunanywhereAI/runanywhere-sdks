// bundle-native.ts — stage native artifacts for the Electron package split.
//
// Dual path (Track B7 + packaging Option A):
//   THIN / shared  — core gets runanywhere_native.node + librac_commons.*; each
//                    backend package gets librunanywhere_<id>.* plus
//                    librac_backend_<id>.* and librac_commons.* (carrier
//                    @rpath / $ORIGIN sidecars) under its own
//                    prebuilds/<platform>-<arch>/.
//   FAT (fallback) — when shared commons / plugin carriers are absent, stage
//                    only the fat .node (+ Windows/Linux onnx/sherpa sidecars)
//                    into core. Never fail CI/local just because Track A has
//                    not produced shared dylibs yet. Default until thin ships.
//
//   npm run bundle:native
//   npm run bundle:native -- --package=core|llamacpp|onnx|sherpa|all
// Override the addon dir with RA_NATIVE_DIR=<...>/sdk/runanywhere-electron/native
import * as fs from 'fs';
import * as path from 'path';

/** Which npm package receives staged files. */
const BundlePackageId = {
  Core: 'core',
  LlamaCPP: 'llamacpp',
  ONNX: 'onnx',
  Sherpa: 'sherpa',
  QHexRT: 'qhexrt',
} as const;
type BundlePackageId = (typeof BundlePackageId)[keyof typeof BundlePackageId];

const ALL_PACKAGES: readonly BundlePackageId[] = [
  BundlePackageId.Core,
  BundlePackageId.LlamaCPP,
  BundlePackageId.ONNX,
  BundlePackageId.Sherpa,
  BundlePackageId.QHexRT,
];

const BACKEND_PACKAGES: readonly BundlePackageId[] = [
  BundlePackageId.LlamaCPP,
  BundlePackageId.ONNX,
  BundlePackageId.Sherpa,
  BundlePackageId.QHexRT,
];

/** Detected packaging posture for this build tree. */
const StagingMode = {
  /** Shared commons + at least one plugin carrier found. */
  Thin: 'thin',
  /** Only the (fat or thin) .node — current default until Track A lands. */
  Fat: 'fat',
} as const;
type StagingMode = (typeof StagingMode)[keyof typeof StagingMode];

/** One file to stage into a package's prebuilds/<plat>-<arch>/. */
interface StagedFile {
  readonly name: string;
  readonly dir: string;
  readonly packageId: BundlePackageId;
  /** "copy if built, do not fail the bundle" — never set on the addon itself. */
  readonly optional?: boolean;
}

const pkgRoot = path.join(__dirname, '..');
const repoRoot = path.join(pkgRoot, '..', '..');
const win = process.platform === 'win32';
const mac = process.platform === 'darwin';
const winArm64 = win && process.arch === 'arm64';
const platformArch = `${process.platform}-${process.arch}` as const;

// One CMake preset per Windows architecture — the ARM64 build tree is separate
// because the generator platform (and therefore node.lib) differs. macOS builds
// through the macos-release preset; the plan's verified local tree is
// build/electron-macos (fat) and build/electron-shared-macos (thin spike).
const winPreset = winArm64 ? 'windows-arm64-release' : 'windows-release';
const nativeSubPath = path.join('sdk', 'runanywhere-electron', 'native');
const macBuildDirs = [
  // Prefer the known-good fat tree for local apps; shared/thin is opt-in via
  // RA_NATIVE_DIR or when only electron-shared-macos exists.
  path.join(repoRoot, 'build', 'electron-macos', nativeSubPath),
  path.join(repoRoot, 'build', 'electron-shared-macos', nativeSubPath),
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

function parsePackageArg(argv: readonly string[]): BundlePackageId | 'all' {
  for (const arg of argv) {
    if (!arg.startsWith('--package=')) continue;
    const value = arg.slice('--package='.length).trim().toLowerCase();
    if (value === 'all') return 'all';
    if ((ALL_PACKAGES as readonly string[]).includes(value)) {
      return value as BundlePackageId;
    }
    console.error(
      `unknown --package=${value}; expected all|${ALL_PACKAGES.join('|')}`
    );
    process.exit(1);
  }
  return 'all';
}

function packageOutDir(packageId: BundlePackageId): string {
  if (packageId === BundlePackageId.Core) {
    return path.join(pkgRoot, 'prebuilds', platformArch);
  }
  return path.join(pkgRoot, 'packages', packageId, 'prebuilds', platformArch);
}

/** Wipe a package's platform prebuild dir so mode switches do not leave stale sidecars. */
function resetPackageOutDir(packageId: BundlePackageId): void {
  const outDir = packageOutDir(packageId);
  fs.rmSync(outDir, { recursive: true, force: true });
  fs.mkdirSync(outDir, { recursive: true });
}

/** Filename commons' plugin loader expects for a backend id (thin carrier). */
function pluginLibraryFileName(id: BundlePackageId): string {
  if (id === BundlePackageId.Core) {
    throw new Error('core is not a plugin package');
  }
  const stem = `runanywhere_${id}`;
  if (win) return `${stem}.dll`;
  if (mac) return `lib${stem}.dylib`;
  return `lib${stem}.so`;
}

/**
 * Engine implementation dylib/DLL that thin carriers link via `@rpath` /
 * `$ORIGIN` (`librac_backend_<id>.*`). Must sit beside the carrier.
 */
function backendLibraryFileName(id: BundlePackageId): string {
  if (id === BundlePackageId.Core) {
    throw new Error('core is not a backend package');
  }
  const stem = `rac_backend_${id}`;
  if (win) return `${stem}.dll`;
  if (mac) return `lib${stem}.dylib`;
  return `lib${stem}.so`;
}

function commonsLibraryFileName(): string {
  if (win) return 'rac_commons.dll';
  if (mac) return 'librac_commons.dylib';
  return 'librac_commons.so';
}

/** First existing path among candidates, or null. */
function findExisting(candidates: readonly string[]): string | null {
  for (const candidate of candidates) {
    if (fs.existsSync(candidate)) return candidate;
  }
  return null;
}

function commonsCandidates(): readonly string[] {
  const name = commonsLibraryFileName();
  return [
    path.join(buildDir, name),
    path.join(buildRoot, 'sdk', 'runanywhere-commons', name),
    // Multi-config generators (VS) may place the DLL under Release/.
    path.join(buildRoot, 'sdk', 'runanywhere-commons', 'Release', name),
    path.join(buildRoot, 'lib', name),
    path.join(buildRoot, 'bin', name),
  ];
}

function pluginCandidates(id: BundlePackageId): readonly string[] {
  const name = pluginLibraryFileName(id);
  return [
    path.join(buildDir, name),
    path.join(buildRoot, 'engines', id, name),
    path.join(buildRoot, 'engines', id, 'Release', name),
    path.join(buildRoot, 'lib', name),
    path.join(buildRoot, 'bin', name),
  ];
}

function backendCandidates(id: BundlePackageId): readonly string[] {
  const name = backendLibraryFileName(id);
  return [
    path.join(buildDir, name),
    path.join(buildRoot, 'engines', id, name),
    path.join(buildRoot, 'engines', id, 'Release', name),
    path.join(buildRoot, 'lib', name),
    path.join(buildRoot, 'bin', name),
  ];
}

/** Stage an optional sidecar into `packageId` when the file exists. */
function pushOptionalSidecar(
  files: StagedFile[],
  packageId: BundlePackageId,
  found: string | null
): void {
  if (!found) return;
  files.push({
    name: path.basename(found),
    dir: path.dirname(found),
    packageId,
    optional: true,
  });
}

function detectStagingMode(): StagingMode {
  const commons = findExisting(commonsCandidates());
  if (!commons) return StagingMode.Fat;
  for (const id of BACKEND_PACKAGES) {
    if (findExisting(pluginCandidates(id))) return StagingMode.Thin;
  }
  // Shared commons alone still counts as thin core staging (plugins optional).
  return StagingMode.Thin;
}

function selectPackages(want: BundlePackageId | 'all'): readonly BundlePackageId[] {
  return want === 'all' ? ALL_PACKAGES : [want];
}

/**
 * Build the staging plan for the detected mode.
 *
 * Fat macOS ships NO onnx/sherpa sidecars (statically linked into the .node).
 * Fat Windows/Linux still stage onnxruntime + sherpa next to the .node.
 * Thin mode stages commons into core and, for each backend package, the plugin
 * carrier plus `librac_backend_<id>.*` and `librac_commons.*` beside it
 * (`@loader_path` / `$ORIGIN`). Fat dual-path skips backends when carriers are
 * absent and does not fail.
 */
function buildStagingPlan(
  mode: StagingMode,
  packages: readonly BundlePackageId[]
): readonly StagedFile[] {
  const want = new Set(packages);
  const files: StagedFile[] = [];
  const commonsPath = findExisting(commonsCandidates());

  if (want.has(BundlePackageId.Core)) {
    files.push({
      name: 'runanywhere_native.node',
      dir: buildDir,
      packageId: BundlePackageId.Core,
    });

    if (mode === StagingMode.Thin) {
      pushOptionalSidecar(files, BundlePackageId.Core, commonsPath);
    }

    // Fat (and optional thin) runtime sidecars — never required on macOS.
    if (win) {
      files.push(
        {
          name: 'onnxruntime.dll',
          dir: buildDir,
          packageId: BundlePackageId.Core,
          optional: true,
        },
        {
          name: 'onnxruntime_providers_shared.dll',
          dir: buildDir,
          packageId: BundlePackageId.Core,
          optional: true,
        },
        {
          name: 'sherpa-onnx-c-api.dll',
          dir: buildDir,
          packageId: BundlePackageId.Core,
          optional: true,
        }
      );
    } else if (!mac) {
      files.push(
        {
          name: 'libonnxruntime.so.1',
          dir: path.join(buildRoot, '_deps', 'onnxruntime-src', 'lib'),
          packageId: BundlePackageId.Core,
          optional: true,
        },
        {
          name: 'libonnxruntime.so',
          dir: path.join(
            repoRoot,
            'sdk',
            'runanywhere-commons',
            'third_party',
            'sherpa-onnx-linux',
            'lib'
          ),
          packageId: BundlePackageId.Core,
          optional: true,
        },
        {
          name: 'libsherpa-onnx-c-api.so',
          dir: path.join(
            repoRoot,
            'sdk',
            'runanywhere-commons',
            'third_party',
            'sherpa-onnx-linux',
            'lib'
          ),
          packageId: BundlePackageId.Core,
          optional: true,
        }
      );
    }
  }

  for (const id of BACKEND_PACKAGES) {
    if (!want.has(id)) continue;
    const carrier = findExisting(pluginCandidates(id));
    if (!carrier) {
      // Dual-path: missing plugins are fine — fat core still works.
      continue;
    }
    pushOptionalSidecar(files, id, carrier);

    if (mode === StagingMode.Thin) {
      // Carrier links `librac_backend_<id>` + commons via @rpath / $ORIGIN —
      // stage both beside the plugin so dlopen does not need a manual cp step.
      pushOptionalSidecar(files, id, findExisting(backendCandidates(id)));
      pushOptionalSidecar(files, id, commonsPath);
    }
  }

  return files;
}

function stageFiles(files: readonly StagedFile[]): {
  copied: number;
  required: number;
  bytes: number;
  byPackage: Map<BundlePackageId, number>;
} {
  const required = files.filter((f) => !f.optional).length;
  let copied = 0;
  let bytes = 0;
  const byPackage = new Map<BundlePackageId, number>();
  const reset = new Set<BundlePackageId>();

  for (const f of files) {
    const src = path.join(f.dir, f.name);
    if (!fs.existsSync(src)) {
      console.error(f.optional ? '  skipped (not built):' : '  MISSING:', src);
      continue;
    }
    if (!reset.has(f.packageId)) {
      resetPackageOutDir(f.packageId);
      reset.add(f.packageId);
    }
    const outDir = packageOutDir(f.packageId);
    const size = fs.statSync(src).size;
    fs.copyFileSync(src, path.join(outDir, f.name));
    bytes += size;
    copied++;
    byPackage.set(f.packageId, (byPackage.get(f.packageId) ?? 0) + 1);
    console.log(`  + [${f.packageId}] ${f.name} ${(size / 1e6).toFixed(1)} MB -> ${outDir}`);
  }

  return { copied, required, bytes, byPackage };
}

/**
 * QAIRT/QNN runtime for Hexagon — the flat directory QHexRT requires, staged
 * into the **qhexrt package** (it is that engine's dependency, and nothing else
 * in the SDK opens these libraries).
 *
 * Flat is not a convenience: on Windows there is no `ADSP_LIBRARY_PATH`, so the
 * loader resolves the HTP stub's dependencies through the DLL's own directory
 * and every file — the four DLLs, the `libQnnHtpV<arch>Skel.so`, AND its
 * `.cat` — must sit in ONE directory. The `.cat` is mandatory; without it the
 * skel fails signature verification with no error naming the catalog.
 *
 * `.exe` entries are skipped: a staging dir built for the `qhx_*` tools carries
 * them, and they are not part of the runtime.
 *
 * Opt-in via RA_QNN_RUNTIME_DIR (licensed vendor SDK, absent on CI).
 */
function stageQnnRuntime(): { files: number; bytes: number } {
  const qnnDir = process.env.RA_QNN_RUNTIME_DIR;
  if (!qnnDir) return { files: 0, bytes: 0 };
  if (!fs.existsSync(qnnDir)) {
    console.error('  MISSING: RA_QNN_RUNTIME_DIR does not exist:', qnnDir);
    process.exit(1);
  }
  const outDir = packageOutDir(BundlePackageId.QHexRT);
  if (!fs.existsSync(outDir)) fs.mkdirSync(outDir, { recursive: true });
  let qnnFiles = 0;
  let qnnBytes = 0;
  for (const entry of fs.readdirSync(qnnDir, { withFileTypes: true })) {
    if (!entry.isFile() || /\.exe$/i.test(entry.name)) continue;
    const src = path.join(qnnDir, entry.name);
    fs.copyFileSync(src, path.join(outDir, entry.name));
    qnnBytes += fs.statSync(src).size;
    qnnFiles++;
  }
  console.log(
    `  + [qhexrt] QNN runtime: ${qnnFiles} files, ${(qnnBytes / 1e6).toFixed(1)} MB (from ${qnnDir})`
  );
  return { files: qnnFiles, bytes: qnnBytes };
}

const wantPackage = parsePackageArg(process.argv.slice(2));
const packages = selectPackages(wantPackage);
const mode = detectStagingMode();
const plan = buildStagingPlan(mode, packages);

console.log(
  `bundle-native: mode=${mode} package=${wantPackage} platform=${platformArch}`
);
console.log(`  addon dir: ${buildDir}`);

// Clear backend package dirs that have nothing to stage (fat dual-path / missing
// carriers) so a prior thin run cannot leave stale dylibs behind.
const plannedPackages = new Set(plan.map((f) => f.packageId));
for (const id of packages) {
  if (id === BundlePackageId.Core) continue;
  if (!plannedPackages.has(id)) resetPackageOutDir(id);
}

const staged = stageFiles(plan);
if (staged.copied < staged.required) {
  console.error(
    `bundled ${staged.copied}/${staged.required} required files — build the addon first (see README).`
  );
  process.exit(1);
}

// Runs after stageFiles so the carrier's resetPackageOutDir() cannot wipe it.
const qnn = wantPackage === 'all' || wantPackage === BundlePackageId.QHexRT
  ? stageQnnRuntime()
  : { files: 0, bytes: 0 };

const totalBytes = staged.bytes + qnn.bytes;
const summary = [...staged.byPackage.entries()]
  .map(([id, n]) => `${id}:${n}`)
  .join(', ');
console.log(
  `native bundle (${(totalBytes / 1e6).toFixed(1)} MB) mode=${mode}` +
    (summary ? ` [${summary}]` : ' [nothing staged]')
);

// Thin core-alone (no plugins copied) is a valid outcome — apps get a typed
// SDKException.noBackendEngines() at ensure()/capability probe time (B8).
if (mode === StagingMode.Thin) {
  const pluginsStaged = BACKEND_PACKAGES.reduce(
    (n, id) => n + (staged.byPackage.get(id) ?? 0),
    0
  );
  if (pluginsStaged === 0 && packages.some((p) => p !== BundlePackageId.Core)) {
    console.log(
      '  note: thin mode with zero backend plugins staged — core-alone / zero-engines path'
    );
  }
}
