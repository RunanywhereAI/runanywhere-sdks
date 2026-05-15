/**
 * ONNX - Public facade for `@runanywhere/web-onnx`.
 *
 * The package now ships TWO speech runtimes side by side:
 *
 *   1. **Standalone Sherpa-ONNX module** (`packages/onnx/wasm/sherpa/`)
 *      built by `wasm/scripts/build-sherpa-onnx.sh`. This is the proven
 *      production path from `main`: a self-contained Emscripten link of
 *      ONNX Runtime + Sherpa-ONNX with consistent exception/threading
 *      flags, loaded as a separate WASM file. Driven through the V2
 *      `SpeechProvider` interface so `RunAnywhere.transcribe`,
 *      `RunAnywhere.synthesize`, and `RunAnywhere.detectVoiceActivity`
 *      work end-to-end.
 *
 *   2. **Proto-byte plugin registration** against the unified RACommons
 *      WASM module (`SherpaONNXBridge`). This is the V2 architecture's
 *      preferred path but currently hits a cross-TU exception trampoline
 *      mismatch when ORT/Sherpa static archives are linked into the
 *      same module. Kept around so other RACommons-side proto exports
 *      (RAG, embeddings) still light up.
 *
 * `ONNX.register()` installs the standalone speech provider AND attempts
 * the proto-byte registration. The standalone provider takes precedence
 * for STT/TTS/VAD; the proto-byte adapters cover the rest.
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

import { SDKLogger } from '@runanywhere/web/internal';
import { SherpaONNXBridge } from './Foundation/SherpaONNXBridge';
import {
  installStandaloneSherpaSpeechProvider,
  uninstallStandaloneSherpaSpeechProvider,
} from './Foundation/StandaloneSherpaSpeechProvider';
import {
  setStandaloneSherpaWasmLocation,
  type StandaloneSherpaLoadOptions,
} from './Foundation/StandaloneSherpaModule';

const MODULE_ID = 'onnx';
const logger = new SDKLogger('ONNX');

export interface ONNXRegisterOptions {
  /** Override URL to the RACommons `racommons-llamacpp.js` glue file. */
  wasmUrl?: string;
  /** Override URLs for the standalone Sherpa-ONNX module. */
  standaloneSherpa?: StandaloneSherpaLoadOptions;
  /**
   * If `true`, skip installing the standalone Sherpa speech provider.
   * Useful when the unified RACommons proto-byte path is healthy and
   * the consumer wants every modality to go through it.
   */
  skipStandaloneSpeech?: boolean;
  /**
   * If `true`, skip the proto-byte plugin registration against the
   * unified RACommons module. Useful for tests / harnesses that only
   * exercise the standalone speech path.
   */
  skipProtoBytePlugins?: boolean;
}

export const ONNX = {
  get moduleId(): string {
    return MODULE_ID;
  },

  /**
   * `true` when the proto-byte ONNX/Sherpa plugin registration succeeded.
   * Independent of the standalone speech provider — speech can be
   * available via the standalone path even when this is `false`.
   */
  get isRegistered(): boolean {
    return SherpaONNXBridge.shared.isBackendRegistered;
  },

  /**
   * Register the ONNX Runtime + Sherpa speech backends.
   *
   * Side effects, in order:
   *   1. Install the standalone Sherpa speech provider on the V2
   *      `SpeechProvider` registry (lazy — the WASM module loads on
   *      first speech call).
   *   2. Acquire / load the RACommons WASM module and call
   *      `rac_backend_onnx_register()` + `rac_backend_sherpa_register()`
   *      so RAG / embeddings / generic ONNX services light up. If this
   *      fails (e.g. the unified Sherpa link aborts), it is logged but
   *      the call still resolves successfully — speech remains
   *      available via the standalone provider.
   */
  async register(options?: ONNXRegisterOptions): Promise<void> {
    if (options?.standaloneSherpa) {
      setStandaloneSherpaWasmLocation(options.standaloneSherpa);
    }

    if (!options?.skipStandaloneSpeech) {
      installStandaloneSherpaSpeechProvider();
      logger.info('Standalone Sherpa speech provider installed (lazy WASM load)');
    }

    if (!options?.skipProtoBytePlugins) {
      const bridge = SherpaONNXBridge.shared;
      if (options?.wasmUrl) bridge.wasmUrl = options.wasmUrl;
      try {
        await bridge.ensureLoaded(options);
      } catch (err) {
        logger.warning(
          `Proto-byte ONNX/Sherpa plugin registration failed (non-fatal — standalone speech path still active): ${
            err instanceof Error ? err.message : String(err)
          }`,
        );
      }
    }
  },

  /** Unregister both the standalone speech provider and the proto-byte plugins. */
  unregister(): void {
    uninstallStandaloneSherpaSpeechProvider();
    SherpaONNXBridge.shared.unregister();
  },
};

/** Best-effort registration helper for apps that import the package eagerly. */
export function autoRegister(options?: ONNXRegisterOptions): Promise<void> {
  return ONNX.register(options).catch(() => {
    // Suppress — callers should use `ONNX.register()` directly to inspect failures.
  });
}
