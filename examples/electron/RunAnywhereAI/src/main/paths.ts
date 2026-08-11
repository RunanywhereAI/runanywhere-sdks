/**
 * Where things live, and which native addon to load.
 *
 * Dev: prefer `node_modules/@runanywhere/electron` (the `file:` link), else the
 * monorepo SDK path. Packaged: the same package is inside the asar; native
 * files are rewritten to `app.asar.unpacked` (see electron-builder.yml asarUnpack).
 */
import fs from 'node:fs';
import path from 'node:path';

/** `out/main` in a built tree, so the app root is two levels up. */
const appRoot = path.resolve(__dirname, '..', '..');
const repoRoot = path.resolve(appRoot, '..', '..', '..');

function resolveSdkRoot(): string {
  const fromNodeModules = path.join(appRoot, 'node_modules', '@runanywhere', 'electron');
  if (fs.existsSync(path.join(fromNodeModules, 'package.json'))) return fromNodeModules;
  return path.join(repoRoot, 'sdk', 'runanywhere-electron');
}

/** electron-builder mirrors unpacked globs under `app.asar.unpacked/`. */
function asarUnpacked(filePath: string): string {
  const needle = `${path.sep}app.asar${path.sep}`;
  const index = filePath.indexOf(needle);
  if (index === -1) return filePath;
  return (
    filePath.slice(0, index) +
    `${path.sep}app.asar.unpacked${path.sep}` +
    filePath.slice(index + needle.length)
  );
}

export const APP_ROOT = appRoot;
export const SDK_ROOT = resolveSdkRoot();
export const PREBUILDS = path.join(SDK_ROOT, 'prebuilds');
export const HOST_PATH = path.join(SDK_ROOT, 'dist', 'process', 'host.js');

/**
 * The catalog as a CommonJS module on disk.
 *
 * The utility host resolves the catalog by `require()`ing a path, so the
 * TypeScript table is re-exported through `src/shared/model-catalog.cjs.ts` and
 * emitted beside the main bundle. `__dirname` is `out/main` at runtime, and the
 * shared modules land in `out/shared`.
 */
export const CATALOG_PATH = path.join(__dirname, '..', 'shared', 'model-catalog.cjs.cjs');

export const IS_SELFTEST = process.env.RA_SELFTEST === '1';
/** Playwright / visual-parity runs — isolate userData, never touch the real store. */
export const IS_E2E = process.env.RA_E2E === '1';
export const IS_DEV = process.env.RA_DEV === '1';

/**
 * Pick the native addon.
 *
 * CPU is the default. The CUDA prebuild is used **only** when explicitly asked
 * for (`RA_GPU=1` / `--gpu`) AND present — loading it without an NVIDIA driver
 * stack fails hard, so it must never be the silent default.
 */
export function resolveNativePath(): string {
  const override = process.env.RUNANYWHERE_NATIVE_PATH;
  if (override !== undefined && override !== '') return override;

  const wantGpu = process.env.RA_GPU === '1' || process.argv.includes('--gpu');
  const base = `${process.platform}-${process.arch}`;
  const candidates = wantGpu ? [`${base}-cuda`, base] : [base];

  for (const variant of candidates) {
    const candidate = asarUnpacked(path.join(PREBUILDS, variant, 'runanywhere_native.node'));
    if (fs.existsSync(candidate)) return candidate;
  }

  // Say so HERE rather than letting an empty path travel into the utility host
  // and fail there with a message that points at the wrong layer.
  const available = fs.existsSync(PREBUILDS) ? fs.readdirSync(PREBUILDS).join(', ') : '';
  throw new Error(
    `no native addon for ${base}. This build ships prebuilds for: ${available || '(none)'}. ` +
      'Set RUNANYWHERE_NATIVE_PATH to a runanywhere_native.node built for this platform.',
  );
}

/** True when the resolved addon is a GPU/CUDA build. */
export function isGpuBuild(nativePath: string): boolean {
  return /cuda|gpu/i.test(nativePath);
}
