/**
 * RunAnywhere Web SDK - Sherpa-ONNX Helper Loader
 *
 * Loads sherpa-onnx CJS wrapper files (sherpa-onnx-asr.js, -tts.js, -vad.js)
 * at runtime via Blob URLs so they work in ESM strict mode without build-time
 * patching.
 *
 * The upstream files have two ESM incompatibilities:
 *   1. No `export` statements (CJS only)
 *   2. Implicit globals (`offset = 0` without `var`/`let`)
 *
 * This loader fixes both in-memory before importing:
 *   - Prepends `var offset;` to pre-declare the implicit global
 *   - Appends `export { ... };` if not already present
 *   - Creates a Blob URL and `import()`s it as an ES module
 *
 * Results are cached per file so subsequent calls return instantly.
 *
 * This mirrors the same runtime-loading pattern used by SherpaONNXBridge
 * for sherpa-onnx-glue.js (see SherpaONNXBridge._doLoad).
 */

import { SDKError, SDKErrorCode, SDKLogger } from '@runanywhere/web';
import { SherpaONNXBridge } from './SherpaONNXBridge';
import type { SherpaONNXModule } from './SherpaONNXBridge';

const logger = new SDKLogger('SherpaHelperLoader');

// ---------------------------------------------------------------------------
// Public Types
// ---------------------------------------------------------------------------

/** Opaque config struct handle returned by sherpa-onnx init*Config() helpers. */
export interface SherpaConfigHandle {
  ptr: number;
  [key: string]: unknown;
}

/** ASR (Speech-to-Text) helpers from sherpa-onnx-asr.js */
export interface SherpaASRHelpers {
  freeConfig: (config: SherpaConfigHandle, module: SherpaONNXModule) => void;
  initSherpaOnnxOfflineRecognizerConfig: (config: object, module: SherpaONNXModule) => SherpaConfigHandle;
  initSherpaOnnxOnlineRecognizerConfig: (config: object, module: SherpaONNXModule) => SherpaConfigHandle;
}

/** TTS (Text-to-Speech) helpers from sherpa-onnx-tts.js */
export interface SherpaTTSHelpers {
  freeConfig: (config: SherpaConfigHandle, module: SherpaONNXModule) => void;
  initSherpaOnnxOfflineTtsConfig: (config: object, module: SherpaONNXModule) => SherpaConfigHandle;
}

/** VAD (Voice Activity Detection) helpers from sherpa-onnx-vad.js */
export interface SherpaVADHelpers {
  freeConfig: (config: SherpaConfigHandle, module: SherpaONNXModule) => void;
  initSherpaOnnxVadModelConfig: (config: object, module: SherpaONNXModule) => SherpaConfigHandle;
}

// ---------------------------------------------------------------------------
// Internal: Cache & Constants
// ---------------------------------------------------------------------------

const moduleCache = new Map<string, Promise<unknown>>();

// Pre-declare implicit globals used by sherpa-onnx wrapper files.
// `offset` is used without `var`/`let` in several init functions, which
// causes ReferenceError in strict mode. Declaring it at module scope is
// safe even if the file was already patched (function-scoped `let` shadows it).
const IMPLICIT_GLOBAL_DECLARATIONS = 'var offset;\n';

// ---------------------------------------------------------------------------
// Generic Loader
// ---------------------------------------------------------------------------

async function loadSherpaModule<T>(
  filename: string,
  exportNames: readonly string[],
): Promise<T> {
  const cached = moduleCache.get(filename);
  if (cached) return cached as Promise<T>;

  const promise = doLoad<T>(filename, exportNames);
  moduleCache.set(filename, promise);

  try {
    return await promise;
  } catch (error) {
    moduleCache.delete(filename);
    throw error;
  }
}

async function doLoad<T>(
  filename: string,
  exportNames: readonly string[],
): Promise<T> {
  // Prefer the bridge's resolved base URL (auto-derived during WASM load)
  // over import.meta.url which breaks when bundlers rewrite module paths.
  const raw = SherpaONNXBridge.shared.helperBaseUrl;
  const bridgeBase = raw ? (raw.endsWith('/') ? raw : `${raw}/`) : null;
  const url = bridgeBase
    ? `${bridgeBase}${filename}`
    : new URL(`../../wasm/sherpa/${filename}`, import.meta.url).href;
  logger.info(`Loading sherpa helper: ${filename}`);

  const response = await fetch(url);
  if (!response.ok) {
    throw new SDKError(
      SDKErrorCode.WASMLoadFailed,
      `Failed to fetch ${filename}: ${response.status} ${response.statusText}`,
    );
  }

  let code = await response.text();

  code = IMPLICIT_GLOBAL_DECLARATIONS + code;

  if (!code.includes('export {')) {
    code += `\nexport { ${exportNames.join(', ')} };\n`;
  }

  const blob = new Blob([code], { type: 'text/javascript' });
  const blobUrl = URL.createObjectURL(blob);

  try {
    const mod = await import(/* @vite-ignore */ blobUrl) as T;
    logger.info(`Loaded sherpa helper: ${filename}`);
    return mod;
  } catch (error) {
    const msg = error instanceof Error ? error.message : String(error);
    throw new SDKError(
      SDKErrorCode.WASMLoadFailed,
      `Failed to load sherpa helper ${filename}: ${msg}`,
    );
  } finally {
    URL.revokeObjectURL(blobUrl);
  }
}

// ---------------------------------------------------------------------------
// Convenience Loaders (one per sherpa-onnx wrapper file)
// ---------------------------------------------------------------------------

const ASR_EXPORTS = [
  'freeConfig',
  'initSherpaOnnxOfflineRecognizerConfig',
  'initSherpaOnnxOnlineRecognizerConfig',
] as const;

const TTS_EXPORTS = [
  'freeConfig',
  'initSherpaOnnxOfflineTtsConfig',
] as const;

const VAD_EXPORTS = [
  'freeConfig',
  'initSherpaOnnxVadModelConfig',
] as const;

/** Load ASR struct-packing helpers (sherpa-onnx-asr.js). */
export function loadASRHelpers(): Promise<SherpaASRHelpers> {
  return loadSherpaModule<SherpaASRHelpers>('sherpa-onnx-asr.js', ASR_EXPORTS);
}

/** Load TTS struct-packing helpers (sherpa-onnx-tts.js). */
export function loadTTSHelpers(): Promise<SherpaTTSHelpers> {
  return loadSherpaModule<SherpaTTSHelpers>('sherpa-onnx-tts.js', TTS_EXPORTS);
}

/** Load VAD struct-packing helpers (sherpa-onnx-vad.js). */
export function loadVADHelpers(): Promise<SherpaVADHelpers> {
  return loadSherpaModule<SherpaVADHelpers>('sherpa-onnx-vad.js', VAD_EXPORTS);
}
