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
  SDKLogger,
  type BackendRegistrationState,
} from '@runanywhere/web/backend';
import { SherpaONNXBridge } from './Foundation/SherpaONNXBridge.js';
import { onnxStatus, type ONNXBackendStatus } from './ONNXStatus.js';

const MODULE_ID = 'onnx';
const logger = new SDKLogger('ONNX');
let _registrationState: BackendRegistrationState = 'unregistered';

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
  async register(options?: ONNXRegisterOptions): Promise<void> {
    const bridge = SherpaONNXBridge.shared;
    if (options?.wasmUrl) bridge.wasmUrl = options.wasmUrl;
    _registrationState = 'registering';
    try {
      await bridge.ensureLoaded(options);
      if (options?.acceptNvidiaSegformerNoncommercialLicense === true) {
        bridge.acceptNvidiaSegformerNoncommercialLicense();
      }
      _registrationState = 'registered';
      logger.info('ONNX/Sherpa backends registered (STT/TTS/VAD vtables installed)');
    } catch (error) {
      _registrationState = 'failed';
      throw error;
    }
  },

  /** Unregister the proto-byte plugins and release the WASM module. */
  unregister(): void {
    SherpaONNXBridge.shared.unregister();
    _registrationState = 'unregistered';
  },
};

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
