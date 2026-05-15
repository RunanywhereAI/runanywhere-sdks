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
    if (!code.includes('export {')) {
      code += `\nexport { ${exports.join(', ')} };\n`;
    }
    const blob = new Blob([code], { type: 'text/javascript' });
    const blobUrl = URL.createObjectURL(blob);
    try {
      return (await import(/* @vite-ignore */ blobUrl)) as T;
    } finally {
      URL.revokeObjectURL(blobUrl);
    }
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
