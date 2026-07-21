/**
 * ONNX - Public facade for `@runanywhere/web-onnx`.
 *
 * Loads `racommons-onnx-sherpa.{js,wasm}` (the dedicated ONNX/Sherpa
 * Emscripten module) and registers the ONNX runtime + Sherpa speech
 * vtables with the C++ plugin registry. After `ONNX.register()` resolves,
 * STT/TTS/VAD operations flow entirely through the proto-byte adapters
 * in `@runanywhere/web` core into that WASM module.
 *
 * Usage:
 *   ```ts
 *   import { RunAnywhere } from '@runanywhere/web';
 *   import { ONNX } from '@runanywhere/web-onnx';
 *
 *   await RunAnywhere.initialize();
 *   await ONNX.register();
 *   const vad = await RunAnywhere.detectVoiceActivity(silence);
 *   ```
 */

import {
  BackendWorkerHost,
  SDKLogger,
  getBackendWorkerFactory,
  setBackendWorkerFactory,
  type BackendRegistrationState,
  type BackendWorkerFactory,
} from '@runanywhere/web/backend';
import { SherpaONNXBridge } from './Foundation/SherpaONNXBridge.js';
import { onnxStatus, type ONNXBackendStatus } from './ONNXStatus.js';

const MODULE_ID = 'onnx';
const logger = new SDKLogger('ONNX');
let _registrationState: BackendRegistrationState = 'unregistered';
let _installedBackendWorkerFactory = false;
let _backendWorkerFactory: BackendWorkerFactory | null = null;
let _backendWorkerHost: BackendWorkerHost | null = null;

export interface ONNXRegisterOptions {
  /** Override URL to the `racommons-onnx-sherpa.js` glue file. */
  wasmUrl?: string;

  /**
   * Explicitly acknowledge the NVIDIA SegFormer noncommercial
   * research/evaluation license for this browser-WASM session.
   *
   * This does not download or catalog the restricted model. Set it only
   * after the application owner has reviewed and accepted the pinned
   * upstream terms:
   * https://github.com/NVlabs/SegFormer/blob/65fa8cfa9b52b6ee7e8897a98705abf8570f9e32/LICENSE
   * Model bytes must still be supplied separately.
   */
  acceptNvidiaSegformerNoncommercialLicense?: boolean;
  /**
   * Explicitly acknowledge the NVIDIA streaming Sortformer diarization
   * license for this browser-WASM session. Does not download or catalog the
   * model. Set it only after the application owner has reviewed and accepted
   * the pinned upstream terms; model bytes must still be supplied separately.
   */
  acceptNvidiaSortformerLicense?: boolean;
  /** Optional worker factory. Defaults to this package's worker entrypoint. */
  backendWorkerFactory?: BackendWorkerFactory;
  /** Prefer worker-owned ONNX/Sherpa model lifecycle and inference. */
  preferBackendWorker?: boolean;
  /** Require a worker when the Worker API is available. */
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

  /** Current STT/TTS/VAD export availability for this backend package. */
  status(): ONNXBackendStatus {
    return onnxStatus();
  },

  /**
   * Register the ONNX Runtime + Sherpa speech backends.
   *
   * Loads the dedicated `racommons-onnx-sherpa.{js,wasm}` artifact, calls
   * `rac_init()`, registers the ONNX runtime and Sherpa speech vtables,
   * then installs the module on every core proto-byte adapter so
   * STT/TTS/VAD calls in `@runanywhere/web` core route through it.
   */
  async register(options: ONNXRegisterOptions = {}): Promise<void> {
    const bridge = SherpaONNXBridge.shared;
    if (options.wasmUrl) bridge.wasmUrl = options.wasmUrl;
    _registrationState = 'registering';
    try {
      await bridge.ensureLoaded(options);
      if (options?.acceptNvidiaSegformerNoncommercialLicense === true) {
        bridge.acceptNvidiaSegformerNoncommercialLicense();
      }
      if (options?.acceptNvidiaSortformerLicense === true) {
        bridge.acceptNvidiaSortformerLicense();
      }
      await installONNXBackendWorker(options);
      _registrationState = 'registered';
      logger.info(
        `ONNX/Sherpa backends registered (STT/TTS/VAD vtables installed${
          _backendWorkerHost ? ', executionContext=worker' : ''
        })`,
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
    _registrationState = 'unregistered';
  },
};

async function installONNXBackendWorker(options: ONNXRegisterOptions): Promise<void> {
  const workerAvailable = typeof Worker !== 'undefined' && typeof URL !== 'undefined';
  const prefer = options.preferBackendWorker !== false && workerAvailable;
  if (!prefer) {
    if (options.requireBackendWorker) {
      throw new Error('Web Worker API unavailable or ONNX BackendWorker disabled.');
    }
    return;
  }
  const factory = options.backendWorkerFactory
    ?? (() => new Worker(new URL('./backendWorker.ts', import.meta.url), {
      type: 'module',
      name: 'runanywhere-onnx-backend',
    }));
  setBackendWorkerFactory(factory);
  _installedBackendWorkerFactory = true;
  _backendWorkerFactory = factory;
  // Soft-default: registration can complete on the main thread when the
  // handshake fails. Callers that need a hard worker requirement pass
  // `requireBackendWorker: true` explicitly (browser apps that load speech
  // models into the worker should do so).
  const requireWorker = options.requireBackendWorker ?? false;
  const host = new BackendWorkerHost(factory, {
    backendId: 'onnx',
    initTimeoutMs: 120_000,
  });
  _backendWorkerHost = host;
  try {
    await host.init();
  } catch (error) {
    host.dispose();
    _backendWorkerHost = null;
    clearONNXBackendWorker();
    if (requireWorker) throw error;
    logger.warning(
      `ONNX BackendWorker handshake failed; keeping main-thread inference: ${
        error instanceof Error ? error.message : String(error)
      }`,
    );
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
