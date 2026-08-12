/**
 * ONNX - Public facade for `@runanywhere/web-onnx`.
 *
 * Loads `racommons-onnx-sherpa.{js,wasm}` (or the WebGPU twin when requested
 * and present) and registers the ONNX runtime + Sherpa speech vtables with
 * the C++ plugin registry. After `ONNX.register()` resolves, STT/TTS/VAD
 * operations flow through the proto-byte adapters in `@runanywhere/web`
 * into that WASM module.
 *
 * Usage:
 *   ```ts
 *   import { RunAnywhere } from '@runanywhere/web';
 *   import { ONNX } from '@runanywhere/web-onnx';
 *
 *   await RunAnywhere.initialize();
 *   await ONNX.register({ acceleration: 'auto', requireBackendWorker: true });
 *   const vad = await RunAnywhere.detectVoiceActivity(silence);
 *   ```
 */

import {
  BackendWorkerHost,
  SDKLogger,
  clearOnnxBackendWorkerDead,
  getBackendWorkerFactory,
  setBackendWorkerFactory,
  setOnnxBackendWorkerRequired,
  setRuntimeDegradedReason,
  setSpeechAccelerationMode,
  type BackendRegistrationState,
  type BackendWorkerFactory,
} from '@runanywhere/web/backend';
import { SherpaONNXBridge } from './Foundation/SherpaONNXBridge.js';
import { onnxStatus, type ONNXBackendStatus } from './ONNXStatus.js';
import { workerDefaults } from '@runanywhere/proto-ts/defaults/pool';

const MODULE_ID = 'onnx';
const logger = new SDKLogger('ONNX');
let _registrationState: BackendRegistrationState = 'unregistered';
let _installedBackendWorkerFactory = false;
let _backendWorkerFactory: BackendWorkerFactory | null = null;
let _backendWorkerHost: BackendWorkerHost | null = null;
let _accelerationMode: 'cpu' | 'webgpu' = 'cpu';
let _threads = 1;
let _lastFallbackReason: string | null = null;
let _lastWorkerDiagnostics: string[] = [];

export type ONNXAccelerationMode = 'auto' | 'cpu' | 'webgpu';

export interface ONNXRegisterOptions {
  /** Override URL to the CPU `racommons-onnx-sherpa.js` glue file. */
  wasmUrl?: string;
  /** Override URL to the WebGPU `racommons-onnx-sherpa-webgpu.js` glue file. */
  webgpuWasmUrl?: string;

  /**
   * Speech acceleration preference. LLM `RunAnywhere.runtime.setAcceleration`
   * does not affect speech — use this option (and `ONNX.accelerationMode`).
   *
   * - `'auto'` (default): try WebGPU when browser + artifact + ORT WebGPU EP
   *   probe all succeed; otherwise fall back to CPU and report `cpu`.
   * - `'webgpu'`: require real WebGPU EP (throws if probe fails).
   * - `'cpu'`: CPU artifact only.
   */
  acceleration?: ONNXAccelerationMode;

  /**
   * Sherpa/ORT intra-op thread count for WASM (clamped 1–8). Default 2 on
   * Emscripten; ignored when the linked artifact does not expose the setter.
   */
  threads?: number;

  /** Optional worker factory. Defaults to this package's worker entrypoint. */
  backendWorkerFactory?: BackendWorkerFactory;
  /** Prefer worker-owned ONNX/Sherpa model lifecycle and inference. */
  preferBackendWorker?: boolean;
  /**
   * Require a worker when the Worker API is available. Defaults to true in
   * browser environments (fail-closed, matching LlamaCPP).
   */
  requireBackendWorker?: boolean;
}

export const ONNX = {
  get moduleId(): string {
    return MODULE_ID;
  },

  /** `true` when the ONNX/Sherpa plugin registration succeeded. */
  get isRegistered(): boolean {
    return SherpaONNXBridge.shared.isBackendRegistered;
  },

  /** Typed registration lifecycle for UI and diagnostics. */
  get registrationState(): BackendRegistrationState {
    return _registrationState;
  },

  /**
   * Active speech acceleration after register. `'webgpu'` only when the ORT
   * WebGPU EP probe succeeded; otherwise `'cpu'` (including auto-fallback).
   */
  get accelerationMode(): 'cpu' | 'webgpu' {
    return _accelerationMode;
  },

  /** Effective Sherpa/ORT thread count reported after register. */
  get threads(): number {
    return _threads;
  },

  /**
   * Why `accelerationMode` is CPU after `'auto'` (missing artifact, browser
   * WebGPU, or ORT EP probe). `null` when WebGPU is active or CPU was requested.
   */
  get lastFallbackReason(): string | null {
    return _lastFallbackReason;
  },

  /** Recent worker WASM stdout/stderr lines (probe / EP diagnostics). */
  get lastWorkerDiagnostics(): readonly string[] {
    return _lastWorkerDiagnostics;
  },

  /** Current STT/TTS/VAD export availability for this backend package. */
  status(): ONNXBackendStatus {
    return onnxStatus();
  },

  /**
   * Register the ONNX Runtime + Sherpa speech backends.
   *
   * Loads the dedicated ONNX/Sherpa WASM artifact, calls `rac_init()`,
   * registers the ONNX runtime and Sherpa speech vtables, then installs
   * the BackendWorker so STT/TTS/VAD calls route off the UI thread.
   */
  async register(options: ONNXRegisterOptions = {}): Promise<void> {
    const bridge = SherpaONNXBridge.shared;
    if (options.wasmUrl) bridge.wasmUrl = options.wasmUrl;
    _registrationState = 'registering';
    try {
      // Main bridge stays on CPU when a worker is preferred (mirrors llama:
      // avoid dual-heap GPU contention; worker owns accelerated inference).
      await bridge.ensureLoaded(options);
      await installONNXBackendWorker(options);
      publishSpeechDiagnostics();
      _registrationState = 'registered';
      logger.info(
        `ONNX/Sherpa backends registered (accel=${_accelerationMode}, threads=${_threads}`
          + `${_backendWorkerHost ? ', executionContext=worker' : ', executionContext=main'})`,
      );
    } catch (error) {
      if (_installedBackendWorkerFactory && getBackendWorkerFactory() === _backendWorkerFactory) {
        setBackendWorkerFactory(null);
      }
      _installedBackendWorkerFactory = false;
      _backendWorkerFactory = null;
      _registrationState = 'failed';
      throw error;
    }
  },

  /** Unregister the proto-byte plugins and release the WASM module. */
  unregister(): void {
    clearONNXBackendWorker();
    SherpaONNXBridge.shared.unregister();
    setOnnxBackendWorkerRequired(false);
    _lastFallbackReason = null;
    setSpeechAccelerationMode({
      acceleration: null,
      threads: 1,
      executionContext: 'main',
    });
    _accelerationMode = 'cpu';
    _threads = 1;
    _registrationState = 'unregistered';
  },
};

function publishSpeechDiagnostics(): void {
  setSpeechAccelerationMode({
    acceleration: _accelerationMode,
    threads: _threads,
    executionContext: _backendWorkerHost ? 'worker' : 'main',
  });
}

function clampThreads(value: number | undefined): number {
  if (value == null || !Number.isFinite(value)) return 2;
  return Math.max(1, Math.min(8, Math.floor(value)));
}

async function installONNXBackendWorker(options: ONNXRegisterOptions): Promise<void> {
  const workerAvailable = typeof Worker !== 'undefined' && typeof URL !== 'undefined';
  const prefer = options.preferBackendWorker !== false && workerAvailable;
  if (!prefer) {
    const reason = !workerAvailable
      ? 'Web Worker API unavailable; speech inference stays on the main thread.'
      : 'BackendWorker disabled via ONNX.register({ preferBackendWorker: false }).';
    setRuntimeDegradedReason(reason);
    setOnnxBackendWorkerRequired(false);
    _accelerationMode = 'cpu';
    _threads = clampThreads(options.threads);
    if (options.requireBackendWorker) {
      throw new Error(reason);
    }
    return;
  }

  if (!globalThis.crossOriginIsolated) {
    logger.warning(
      'crossOriginIsolated is false; pthread-backed ONNX BackendWorker WASM may fail. '
      + 'Serve with COOP/COEP headers for production speech inference.',
    );
  }

  const factory = options.backendWorkerFactory
    ?? (() => new Worker(new URL('./backendWorker.js', import.meta.url), {
      type: 'module',
      name: 'runanywhere-onnx-backend',
    }));
  setBackendWorkerFactory(factory);
  _installedBackendWorkerFactory = true;
  _backendWorkerFactory = factory;

  const requireWorker = options.requireBackendWorker
    ?? (typeof Worker !== 'undefined' && typeof URL !== 'undefined');
  setOnnxBackendWorkerRequired(requireWorker);

  const requestedThreads = clampThreads(options.threads);
  const host = new BackendWorkerHost(factory, {
    backendId: 'onnx',
    initTimeoutMs: workerDefaults.backendInitTimeoutMs,
  });
  _backendWorkerHost = host;
  try {
    await host.init({
      acceleration: options.acceleration ?? 'auto',
      threads: requestedThreads,
      webgpuWasmUrl: options.webgpuWasmUrl,
      wasmUrl: options.wasmUrl,
    });
    clearOnnxBackendWorkerDead();
    setRuntimeDegradedReason(null);

    let publishedAccel: 'cpu' | 'webgpu' = 'cpu';
    let publishedThreads = requestedThreads;
    let fallbackReason: string | null = null;
    try {
      const health = await host.health();
      const details = (health.details ?? {}) as {
        acceleration?: 'cpu' | 'webgpu';
        threads?: number;
        fallbackReason?: string | null;
        diagnostics?: string[];
      };
      if (details.acceleration === 'webgpu' || details.acceleration === 'cpu') {
        publishedAccel = details.acceleration;
      }
      if (typeof details.threads === 'number' && details.threads > 0) {
        publishedThreads = clampThreads(details.threads);
      }
      if (details.fallbackReason) fallbackReason = details.fallbackReason;
      if (Array.isArray(details.diagnostics)) {
        _lastWorkerDiagnostics = details.diagnostics.slice(-40);
      }
    } catch {
      /* health is best-effort */
    }
    _accelerationMode = publishedAccel;
    _threads = publishedThreads;
    _lastFallbackReason = publishedAccel === 'webgpu' ? null : fallbackReason;
    logger.info(
      `BackendWorker ready (executionContext=worker; speech=${publishedAccel}; threads=${publishedThreads}`
        + `${fallbackReason ? `; fallback=${fallbackReason}` : ''})`,
    );
  } catch (error) {
    const message = error instanceof Error ? error.message : String(error);
    host.dispose();
    _backendWorkerHost = null;
    clearONNXBackendWorker();
    const reason = `ONNX BackendWorker handshake failed: ${message}`;
    setRuntimeDegradedReason(reason);
    if (requireWorker) {
      logger.error(`${reason}; main-thread speech inference is disabled`);
      throw error instanceof Error ? error : new Error(reason);
    }
    setOnnxBackendWorkerRequired(false);
    _accelerationMode = 'cpu';
    _threads = requestedThreads;
    logger.warning(`${reason}; continuing without BackendWorker (requireBackendWorker=false)`);
  }
}

function clearONNXBackendWorker(): void {
  try {
    _backendWorkerHost?.dispose();
  } catch {
    /* best effort */
  }
  _backendWorkerHost = null;
  if (_installedBackendWorkerFactory && getBackendWorkerFactory() === _backendWorkerFactory) {
    setBackendWorkerFactory(null);
  }
  _installedBackendWorkerFactory = false;
  _backendWorkerFactory = null;
}

/** Best-effort registration helper for apps that import the package eagerly. */
export function autoRegister(options?: ONNXRegisterOptions): Promise<void> {
  return ONNX.register(options).catch((error: unknown) => {
    logger.warning(
      `ONNX auto-registration failed: ${error instanceof Error ? error.message : String(error)}`,
    );
    // Preserve best-effort eager registration semantics. Callers that need a
    // rejecting promise use ONNX.register() directly.
  });
}
