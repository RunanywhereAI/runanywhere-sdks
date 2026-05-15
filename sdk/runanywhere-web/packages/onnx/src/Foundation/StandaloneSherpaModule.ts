/**
 * StandaloneSherpaModule — loads the upstream-built `sherpa-onnx.wasm`
 * Emscripten module (produced by `wasm/scripts/build-sherpa-onnx.sh` and
 * post-processed by `wasm/scripts/patch-sherpa-glue.js`).
 *
 * The standalone Sherpa module is a self-contained Emscripten link of
 * ONNX Runtime + Sherpa-ONNX with consistent exception/threading flags,
 * so it does not hit the cross-TU `function signature mismatch` we see
 * when ORT/Sherpa static archives are linked into the unified
 * `racommons-llamacpp.wasm`. This module is the speech runtime backing
 * the V2 Swift-shaped facade verbs (`RunAnywhere.transcribe`,
 * `synthesize`, `detectVoiceActivity`) until the unified-WASM exception
 * model is fixed.
 */

import { SDKLogger } from '@runanywhere/web/internal';

const logger = new SDKLogger('StandaloneSherpa');

// ---------------------------------------------------------------------------
// Sherpa-ONNX module shape
// ---------------------------------------------------------------------------

export type SherpaCType =
  | 'i1' | 'i8' | 'i16' | 'i32' | 'i64'
  | 'float' | 'double'
  | '*' | 'i8*';

export interface SherpaFSCreateDataFile {
  (
    parent: string,
    name: string,
    data: Uint8Array,
    canRead: boolean,
    canWrite: boolean,
    canOwn: boolean,
  ): void;
}

export interface SherpaFSCreatePath {
  (parent: string, name: string, canRead: boolean, canWrite: boolean): void;
}

export interface SherpaFSUnlink {
  (path: string): void;
}

/**
 * The (subset of) Emscripten module surface we touch on the standalone
 * Sherpa module. We do not include the full type from main's bridge —
 * we add helpers as we wire each modality.
 */
export interface StandaloneSherpaModule extends Record<string, unknown> {
  HEAPU8: Uint8Array;
  HEAP32: Int32Array;
  HEAPU32: Uint32Array;
  HEAPF32: Float32Array;
  _malloc(n: number): number;
  _free(p: number): void;
  setValue(ptr: number, value: number, type: SherpaCType): void;
  getValue(ptr: number, type: SherpaCType): number;
  stringToUTF8(str: string, ptr: number, max: number): void;
  UTF8ToString(ptr: number): string;
  lengthBytesUTF8(str: string): number;
  FS_createDataFile: SherpaFSCreateDataFile;
  FS_createPath: SherpaFSCreatePath;
  FS_unlink: SherpaFSUnlink;
  // C API entrypoints we use across STT / TTS / VAD. Optional so missing
  // exports are handled gracefully with a typed error.
  _SherpaOnnxCreateOfflineRecognizer?(configPtr: number): number;
  _SherpaOnnxDestroyOfflineRecognizer?(handle: number): void;
  _SherpaOnnxCreateOfflineStream?(handle: number): number;
  _SherpaOnnxDestroyOfflineStream?(stream: number): void;
  _SherpaOnnxAcceptWaveformOffline?(
    stream: number,
    sampleRate: number,
    samplesPtr: number,
    numSamples: number,
  ): void;
  _SherpaOnnxDecodeOfflineStream?(handle: number, stream: number): void;
  _SherpaOnnxGetOfflineStreamResultAsJson?(stream: number): number;
  _SherpaOnnxDestroyOfflineStreamResultJson?(ptr: number): void;
  _SherpaOnnxCreateOfflineTts?(configPtr: number): number;
  _SherpaOnnxDestroyOfflineTts?(handle: number): void;
  _SherpaOnnxOfflineTtsGenerate?(
    handle: number,
    textPtr: number,
    sid: number,
    speed: number,
  ): number;
  _SherpaOnnxDestroyOfflineTtsGeneratedAudio?(audio: number): void;
  _SherpaOnnxOfflineTtsSampleRate?(handle: number): number;
  _SherpaOnnxCreateVoiceActivityDetector?(
    configPtr: number,
    bufferSizeInSeconds: number,
  ): number;
  _SherpaOnnxDestroyVoiceActivityDetector?(handle: number): void;
  _SherpaOnnxVoiceActivityDetectorAcceptWaveform?(
    handle: number,
    samplesPtr: number,
    numSamples: number,
  ): void;
  _SherpaOnnxVoiceActivityDetectorEmpty?(handle: number): number;
  _SherpaOnnxVoiceActivityDetectorDetected?(handle: number): number;
  _SherpaOnnxVoiceActivityDetectorPop?(handle: number): void;
  _SherpaOnnxVoiceActivityDetectorReset?(handle: number): void;
}

// ---------------------------------------------------------------------------
// Module loader
// ---------------------------------------------------------------------------

type SherpaModuleFactory = (overrides?: Record<string, unknown>) => Promise<StandaloneSherpaModule>;

export interface StandaloneSherpaLoadOptions {
  /** Override the default URL to `sherpa-onnx-glue.js`. */
  glueUrl?: string;
  /** Override the WASM binary URL (defaults to `sherpa-onnx.wasm` next to the glue). */
  wasmUrl?: string;
}

let _instance: StandaloneSherpaModule | null = null;
let _loading: Promise<StandaloneSherpaModule> | null = null;
let _glueUrlOverride: string | null = null;
let _wasmUrlOverride: string | null = null;

/**
 * Test-only / app-only override for the glue URL. Set BEFORE the first
 * `getStandaloneSherpaModule()` call. Vite consumers should resolve via
 * `new URL('@runanywhere/web-onnx/wasm/sherpa/sherpa-onnx-glue.js',
 * import.meta.url).href`.
 */
export function setStandaloneSherpaWasmLocation(options: StandaloneSherpaLoadOptions): void {
  if (options.glueUrl) _glueUrlOverride = options.glueUrl;
  if (options.wasmUrl) _wasmUrlOverride = options.wasmUrl;
}

function defaultGlueUrl(): string {
  return new URL('../../wasm/sherpa/sherpa-onnx-glue.js', import.meta.url).href;
}

export function isStandaloneSherpaLoaded(): boolean {
  return _instance !== null;
}

export function tryStandaloneSherpaModule(): StandaloneSherpaModule | null {
  return _instance;
}

export function clearStandaloneSherpaModule(): void {
  _instance = null;
  _loading = null;
}

export async function getStandaloneSherpaModule(
  options?: StandaloneSherpaLoadOptions,
): Promise<StandaloneSherpaModule> {
  if (_instance) return _instance;
  if (_loading) return _loading;
  _loading = (async () => {
    const glueUrl = options?.glueUrl ?? _glueUrlOverride ?? defaultGlueUrl();
    if (options?.wasmUrl) _wasmUrlOverride = options.wasmUrl;

    logger.info(`Loading standalone Sherpa-ONNX glue from ${glueUrl}`);
    let factory: SherpaModuleFactory;
    try {
      const imported = (await import(/* @vite-ignore */ glueUrl)) as {
        default: SherpaModuleFactory;
      };
      factory = imported.default ?? (imported as unknown as SherpaModuleFactory);
    } catch (err) {
      throw new Error(
        `Failed to import standalone sherpa-onnx-glue.js at ${glueUrl}: ${
          err instanceof Error ? err.message : String(err)
        }`,
      );
    }

    const wasmUrl = _wasmUrlOverride
      ?? new URL('sherpa-onnx.wasm', glueUrl).href;
    logger.info(`Fetching standalone Sherpa-ONNX WASM binary from ${wasmUrl}`);
    const wasmResponse = await fetch(wasmUrl);
    if (!wasmResponse.ok) {
      throw new Error(
        `Failed to fetch ${wasmUrl}: ${wasmResponse.status} ${wasmResponse.statusText}`,
      );
    }
    const wasmBinary = await wasmResponse.arrayBuffer();
    logger.info(
      `Standalone Sherpa-ONNX WASM fetched: ${(wasmBinary.byteLength / 1_000_000).toFixed(1)} MB`,
    );

    const baseUrl = wasmUrl.substring(0, wasmUrl.lastIndexOf('/') + 1);

    const module = await factory({
      noFSInit: true,
      print: (text: string) => {
        // Surface upstream Sherpa stdout via the SDK logger AND console
        // so spec traces capture useful diagnostics without raising the
        // SDK log level globally.
        logger.debug(text);
        console.log('[sherpa stdout]', text);
      },
      printErr: (text: string) => {
        logger.warning(text);
        console.warn('[sherpa stderr]', text);
      },
      wasmBinary,
      locateFile: (path: string) => {
        if (path.endsWith('.wasm')) return wasmUrl;
        return baseUrl + path;
      },
      // Use the addRunDependency-based async instantiate path. This matches
      // Patch 6 of `patch-sherpa-glue.js` which converts the inner Promise
      // wrapper into addRunDependency / removeRunDependency so the module's
      // `run()` defers until the WASM finishes streaming-compile.
      instantiateWasm: (
        imports: WebAssembly.Imports,
        receiveInstance: (instance: WebAssembly.Instance, mod: WebAssembly.Module) => void,
      ) => {
        WebAssembly.instantiate(wasmBinary, imports).then((result) => {
          try {
            receiveInstance(result.instance, result.module);
          } catch {
            /* receiveInstance is wrapped by addRunDependency in the patched
               glue, so an init-time throw is normal — the run dependency
               clears asynchronously. */
          }
        }).catch((err) => {
          logger.error(
            `Standalone Sherpa WASM instantiate failed: ${
              err instanceof Error ? err.message : String(err)
            }`,
          );
        });
        return {};
      },
    });

    _instance = module;
    _loading = null;
    logger.info('Standalone Sherpa-ONNX module loaded');
    return module;
  })();

  try {
    return await _loading;
  } catch (err) {
    _loading = null;
    throw err;
  }
}
