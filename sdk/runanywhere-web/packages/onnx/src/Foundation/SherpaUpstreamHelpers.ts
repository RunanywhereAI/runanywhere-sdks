/**
 * SherpaUpstreamHelpers — load the upstream sherpa-onnx-{asr,tts,vad}.js
 * struct-packing helpers as ES modules at runtime.
 *
 * The upstream files (shipped from `wasm/scripts/build-sherpa-onnx.sh`
 * into `packages/onnx/wasm/sherpa/`) are CJS-flavoured and have two
 * incompatibilities that prevent direct ESM `import`:
 *
 *   1. They use `export`-less top-level `function` declarations.
 *   2. Several helpers reference an implicit `offset` global without a
 *      `var` declaration, which throws `ReferenceError` in strict mode.
 *
 * This loader fetches the file as text, prepends `var offset;`, appends
 * the necessary `export { ... }` statement, then `import()`s the result
 * via a Blob URL. The OfflineRecognizer (Whisper/etc.) struct is
 * complex enough that re-implementing its byte layout in TypeScript is
 * a maintenance burden; using the upstream helper keeps us aligned with
 * sherpa-onnx upstream changes for free.
 *
 * UPSTREAM PIN: Targets sherpa-onnx 1.12.x CJS-flavoured helpers. When
 * `wasm/scripts/build-sherpa-onnx.sh` is bumped to a newer upstream, the
 * `loadHelper()` post-import validation will surface a clear error listing
 * which expected names are missing on the resolved namespace, so the
 * failure mode is "loud and pointing at the upstream bump" rather than a
 * confusing SyntaxError / ReferenceError at first speech call. Bump the
 * pin in this docstring AND in `wasm/scripts/build-sherpa-onnx.sh` together.
 */

import { SDKLogger } from '@runanywhere/web/internal';
import type { StandaloneSherpaModule } from './StandaloneSherpaModule';

const logger = new SDKLogger('SherpaUpstreamHelpers');

const PRELUDE = 'var offset;\n';

const cache = new Map<string, Promise<unknown>>();

let _baseUrlOverride: string | null = null;

export function setSherpaUpstreamHelperBase(baseUrl: string): void {
  _baseUrlOverride = baseUrl.endsWith('/') ? baseUrl : `${baseUrl}/`;
}

function defaultBaseUrl(): string {
  return new URL('../../wasm/sherpa/', import.meta.url).href;
}

/**
 * Detect whether the fetched upstream text already has a top-level
 * `export { ... }` declaration. Uses a line-anchored regex rather than a
 * raw substring check so the presence of `export {` inside a comment,
 * string literal, or unrelated construct does not cause us to skip the
 * append. The pattern is anchored to a line start (possibly preceded by
 * whitespace) and requires the literal `export` keyword to be followed
 * by `{`, which is the form `wasm/scripts/build-sherpa-onnx.sh` would
 * produce in any future ESM-ified release.
 */
function hasTopLevelExportDeclaration(code: string): boolean {
  return /^\s*export\s*\{/m.test(code);
}

async function loadHelper<T>(filename: string, exports: readonly string[]): Promise<T> {
  const cached = cache.get(filename);
  if (cached) return cached as Promise<T>;

  const promise = (async () => {
    const url = (_baseUrlOverride ?? defaultBaseUrl()) + filename;
    logger.info(`Fetching upstream Sherpa helper: ${url}`);
    const response = await fetch(url);
    if (!response.ok) {
      throw new Error(`Failed to fetch ${filename}: ${response.status} ${response.statusText}`);
    }
    let code = await response.text();
    code = PRELUDE + code;
    if (!hasTopLevelExportDeclaration(code)) {
      code += `\nexport { ${exports.join(', ')} };\n`;
    }
    const blob = new Blob([code], { type: 'text/javascript' });
    const blobUrl = URL.createObjectURL(blob);
    let imported: Record<string, unknown>;
    try {
      imported = (await import(/* @vite-ignore */ blobUrl)) as Record<string, unknown>;
    } finally {
      URL.revokeObjectURL(blobUrl);
    }

    // Verify every expected name resolved as a callable on the namespace.
    // A missing/renamed export here means the upstream sherpa-onnx version
    // shipped by `wasm/scripts/build-sherpa-onnx.sh` no longer matches the
    // pin in this file's docstring. Surface a typed, actionable error rather
    // than letting the consumer chase a downstream ReferenceError at the
    // first speech call.
    const missing = exports.filter((name) => typeof imported[name] !== 'function');
    if (missing.length > 0) {
      throw new Error(
        `Upstream Sherpa helper ${filename} is missing expected exports: ${missing.join(
          ', ',
        )}. The sherpa-onnx upstream shape this loader targets has drifted; ` +
          `bump the pin in SherpaUpstreamHelpers.ts AND verify ` +
          `wasm/scripts/build-sherpa-onnx.sh fetches a compatible release.`,
      );
    }

    return imported as T;
  })();

  cache.set(filename, promise);
  try {
    return await promise;
  } catch (err) {
    cache.delete(filename);
    throw err;
  }
}

// ---------------------------------------------------------------------------
// ASR helpers (sherpa-onnx-asr.js)
// ---------------------------------------------------------------------------

export interface SherpaConfigHandle {
  ptr: number;
  buffer?: number;
  [key: string]: unknown;
}

export interface SherpaASRHelpers {
  freeConfig: (handle: SherpaConfigHandle, module: StandaloneSherpaModule) => void;
  initSherpaOnnxOfflineRecognizerConfig: (
    config: Record<string, unknown>,
    module: StandaloneSherpaModule,
  ) => SherpaConfigHandle;
}

const ASR_EXPORTS = [
  'freeConfig',
  'initSherpaOnnxOfflineRecognizerConfig',
] as const;

export function loadSherpaASRHelpers(): Promise<SherpaASRHelpers> {
  return loadHelper<SherpaASRHelpers>('sherpa-onnx-asr.js', ASR_EXPORTS);
}

// ---------------------------------------------------------------------------
// TTS helpers (sherpa-onnx-tts.js)
// ---------------------------------------------------------------------------

/**
 * Mirrors the upstream `OfflineTtsConfig` shape consumed by
 * `initSherpaOnnxOfflineTtsConfig`. The helper expects nested model-specific
 * configs under `offlineTtsModelConfig`. Optional sub-configs default to
 * empty/disabled inside the helper.
 */
export interface UpstreamTtsConfig {
  offlineTtsModelConfig: {
    offlineTtsVitsModelConfig: {
      model: string;
      lexicon?: string;
      tokens: string;
      dataDir?: string;
      noiseScale?: number;
      noiseScaleW?: number;
      lengthScale?: number;
    };
    numThreads?: number;
    debug?: number;
    provider?: string;
  };
  ruleFsts?: string;
  ruleFars?: string;
  maxNumSentences?: number;
  silenceScale?: number;
}

export interface SherpaTTSHelpers {
  freeConfig: (handle: SherpaConfigHandle, module: StandaloneSherpaModule) => void;
  initSherpaOnnxOfflineTtsConfig: (
    config: UpstreamTtsConfig,
    module: StandaloneSherpaModule,
  ) => SherpaConfigHandle;
}

const TTS_EXPORTS = [
  'freeConfig',
  'initSherpaOnnxOfflineTtsConfig',
  'initSherpaOnnxOfflineTtsModelConfig',
  'initSherpaOnnxOfflineTtsVitsModelConfig',
  'initSherpaOnnxOfflineTtsMatchaModelConfig',
  'initSherpaOnnxOfflineTtsKokoroModelConfig',
  'initSherpaOnnxOfflineTtsKittenModelConfig',
  'initSherpaOnnxOfflineTtsZipVoiceModelConfig',
] as const;

export function loadSherpaTTSHelpers(): Promise<SherpaTTSHelpers> {
  return loadHelper<SherpaTTSHelpers>('sherpa-onnx-tts.js', TTS_EXPORTS);
}

// ---------------------------------------------------------------------------
// VAD helpers (sherpa-onnx-vad.js)
// ---------------------------------------------------------------------------

/**
 * Mirrors the upstream `SherpaOnnxVadModelConfig` shape consumed by
 * `initSherpaOnnxVadModelConfig`. Either `sileroVad` or `tenVad` (or both)
 * may be populated; the helper fills the other with a zeroed default.
 */
export interface UpstreamVadConfig {
  sileroVad?: {
    model: string;
    threshold?: number;
    minSilenceDuration?: number;
    minSpeechDuration?: number;
    windowSize?: number;
    maxSpeechDuration?: number;
  };
  tenVad?: {
    model: string;
    threshold?: number;
    minSilenceDuration?: number;
    minSpeechDuration?: number;
    windowSize?: number;
    maxSpeechDuration?: number;
  };
  sampleRate?: number;
  numThreads?: number;
  provider?: string;
  debug?: number;
}

export interface SherpaVADHelpers {
  freeConfig: (handle: SherpaConfigHandle, module: StandaloneSherpaModule) => void;
  initSherpaOnnxVadModelConfig: (
    config: UpstreamVadConfig,
    module: StandaloneSherpaModule,
  ) => SherpaConfigHandle;
}

const VAD_EXPORTS = [
  'freeConfig',
  'initSherpaOnnxVadModelConfig',
  'initSherpaOnnxSileroVadModelConfig',
  'initSherpaOnnxTenVadModelConfig',
] as const;

export function loadSherpaVADHelpers(): Promise<SherpaVADHelpers> {
  return loadHelper<SherpaVADHelpers>('sherpa-onnx-vad.js', VAD_EXPORTS);
}
