/**
 * ORTRuntimeBridge — thin wrapper over Microsoft's `onnxruntime-web` npm package.
 *
 * This bridge exists alongside `SherpaONNXBridge` but serves different code paths:
 *
 *   - `SherpaONNXBridge`  → loads `sherpa-onnx.wasm` (STT/TTS/VAD decoders + phonemizer)
 *   - `ORTRuntimeBridge`  → loads `onnxruntime-web` (generic Ort.InferenceSession for
 *                           arbitrary ONNX models: openWakeWord, BERT embeddings, etc.)
 *
 * Design parity with native:
 *
 *   On iOS / Android / macOS / Linux / Windows, `rac::onnx::shared_ort_env()`
 *   gives every consumer one `Ort::Env`. On the web we can't share an `Ort::Env`
 *   between sherpa and onnxruntime-web (different WASM modules) — but within the
 *   web SDK's own code, every non-sherpa ONNX consumer routes through this
 *   bridge so there's still ONE `ort.env` shared by wake-word, embeddings, and
 *   any future direct-ORT feature.
 *
 * The `onnxruntime-web` WASM (~2 MB) is lazy-loaded on first use — `sherpa-onnx.wasm`
 * (12 MB) is NOT pulled in for apps that only use wake-word or embeddings, and
 * vice versa.
 */

import type * as ort from 'onnxruntime-web';

/** Options passed to `ORTRuntimeBridge.initialize()`. */
export interface ORTRuntimeInitOptions {
  /**
   * Logging severity level: 0=verbose, 1=info, 2=warning, 3=error, 4=fatal.
   * Defaults to 2 (warning) to match the native `shared_cxx_env` behavior.
   */
  logSeverityLevel?: 0 | 1 | 2 | 3 | 4;

  /**
   * Override the default `ort.env.wasm.wasmPaths`. Useful when the app serves
   * `onnxruntime-web` assets from a non-default path (CDN, subdirectory).
   */
  wasmPaths?: string | Record<string, string>;

  /**
   * Number of threads for the WASM executor. Only effective when
   * Cross-Origin-Isolation headers are set so SharedArrayBuffer is available.
   * Defaults to navigator.hardwareConcurrency (clamped to 4).
   */
  numThreads?: number;
}

/**
 * ORTRuntimeBridge
 *
 * Singleton that lazy-loads `onnxruntime-web` and exposes its namespace for
 * `InferenceSession` / tensor construction by higher-level services.
 */
export class ORTRuntimeBridge {
  private static _ort: typeof ort | null = null;
  private static _loadPromise: Promise<typeof ort> | null = null;
  private static _initialized = false;

  /**
   * Ensure the onnxruntime-web module is loaded and its global env is
   * configured. Idempotent — subsequent calls resolve with the same module.
   */
  static async initialize(options: ORTRuntimeInitOptions = {}): Promise<typeof ort> {
    if (this._ort) return this._ort;
    if (this._loadPromise) return this._loadPromise;

    this._loadPromise = (async () => {
      const mod = await import('onnxruntime-web');

      // Configure the shared ort.env before the first session is created.
      if (options.wasmPaths !== undefined) {
        mod.env.wasm.wasmPaths = options.wasmPaths as
          | string
          | Record<string, string>;
      }

      const threads = options.numThreads ?? Math.min(
        typeof navigator !== 'undefined' ? navigator.hardwareConcurrency ?? 1 : 1,
        4,
      );
      mod.env.wasm.numThreads = threads;

      if (options.logSeverityLevel !== undefined) {
        mod.env.logLevel = (
          ['verbose', 'info', 'warning', 'error', 'fatal'] as const
        )[options.logSeverityLevel];
      }

      this._ort = mod;
      this._initialized = true;
      return mod;
    })();

    return this._loadPromise;
  }

  /** Returns the loaded onnxruntime-web module. Throws if not yet initialized. */
  static get ort(): typeof ort {
    if (!this._ort) {
      throw new Error(
        'ORTRuntimeBridge not initialized. Call ORTRuntimeBridge.initialize() first.',
      );
    }
    return this._ort;
  }

  /** True once `onnxruntime-web` has loaded and `ort.env` is configured. */
  static get isInitialized(): boolean {
    return this._initialized;
  }

  /**
   * Convenience: create an InferenceSession from model bytes or URL.
   * Uses the shared ort.env configured at initialize() time.
   */
  static async createSession(
    modelSource: ArrayBuffer | Uint8Array | string,
    sessionOptions?: ort.InferenceSession.SessionOptions,
  ): Promise<ort.InferenceSession> {
    const ortMod = await this.initialize();
    return ortMod.InferenceSession.create(modelSource, sessionOptions);
  }

  /** Reset the singleton. Intended for tests; do not call in production. */
  static _resetForTests(): void {
    this._ort = null;
    this._loadPromise = null;
    this._initialized = false;
  }
}
