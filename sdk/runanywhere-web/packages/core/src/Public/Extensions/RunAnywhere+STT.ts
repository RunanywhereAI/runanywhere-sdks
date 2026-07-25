/**
 * RunAnywhere+STT.ts
 *
 * Speech-to-text namespace — mirrors Swift's `RunAnywhere+STT.swift`.
 * Provides `RunAnywhere.stt.*` capability surface for owning STT component
 * handles plus lifecycle-owned `transcribeAuto` / `transcribeStreamAuto`
 * shortcuts.
 *
 * The proto-byte adapters (`STTProtoAdapter`) take a numeric `handle` argument
 * — it comes from `_rac_stt_component_create()` followed by
 * `_rac_stt_component_load_model()`. This facade owns those calls so the
 * example app and external consumers never have to touch raw exports. The
 * auto shortcuts deliberately do not create component handles: they dispatch
 * through commons' lifecycle-owned STT ABI so the currently loaded model is
 * never replaced as a side effect of inference.
 */

import {
  STTPartialResult,
  STTStreamEventKind,
  type STTOptions,
  type STTOutput,
} from '@runanywhere/proto-ts/stt_options';
import { sTTOptionsDefaults } from '@runanywhere/proto-ts/convenience/stt_options_convenience';
import { SDKException } from '../../Foundation/SDKException.js';
import { SDKLogger } from '../../Foundation/SDKLogger.js';
import { ProtoWasmBridge } from '../../runtime/ProtoWasm.js';
import {
  getModuleForCapability,
  type EmscriptenRunanywhereModule,
} from '../../runtime/EmscriptenModule.js';
import {
  missingSpeechBackendExports,
  speechBackendRequirementMessage,
} from '../../runtime/SpeechBackendExports.js';
import { STTProtoAdapter } from '../../Adapters/ModalityProtoAdapter.js';

export type { STTOptions, STTOutput, STTPartialResult };

const logger = new SDKLogger('STT');

/**
 * Extra Emscripten exports the STT facade reaches into directly. The proto
 * `transcribe`/`transcribeStream` calls go through `STTProtoAdapter`; what
 * this facade adds is the component lifecycle (create / load_model / destroy).
 */
interface STTComponentModule extends EmscriptenRunanywhereModule {
  _rac_stt_component_create?(outHandlePtr: number): number;
  _rac_stt_component_load_model?(
    handle: number,
    modelPathPtr: number,
    modelIdPtr: number,
    modelNamePtr: number,
  ): number;
  _rac_stt_component_unload?(handle: number): number;
  _rac_stt_component_destroy?(handle: number): void;
  _rac_stt_component_is_loaded?(handle: number): number;
}

function requireSTTModule(feature: string): STTComponentModule {
  const module = getModuleForCapability('stt') as STTComponentModule | null;
  if (!module) {
    throw SDKException.backendNotAvailable(
      feature,
      'No STT backend is registered. Call ONNX.register() (or another STT-providing backend) first.',
    );
  }
  const missing = missingSpeechBackendExports(module);
  if (missing.length > 0) {
    throw SDKException.backendNotAvailable(
      feature,
      speechBackendRequirementMessage(missing),
    );
  }
  return module;
}

// Proto-rac_default-derived defaults — byte-identical to Swift's RASTTOptions.defaults().
function defaultSTTOptions(overrides?: Partial<STTOptions>): STTOptions {
  return {
    ...sTTOptionsDefaults(),
    ...(overrides ?? {}),
  };
}

/**
 * Encode a Float32Array of audio samples to little-endian Int16 PCM bytes,
 * which is the canonical input format for `_rac_stt_component_transcribe_proto`.
 */
function encodeAudioToPcm16(samples: Float32Array): Uint8Array {
  const out = new Uint8Array(samples.length * 2);
  const view = new DataView(out.buffer);
  for (let i = 0; i < samples.length; i += 1) {
    let s = samples[i] ?? 0;
    if (s > 1) s = 1;
    if (s < -1) s = -1;
    view.setInt16(i * 2, Math.round(s * 0x7fff), true);
  }
  return out;
}

function coerceAudio(audio: Uint8Array | Float32Array): Uint8Array {
  if (audio instanceof Float32Array) return encodeAudioToPcm16(audio);
  return audio;
}

/**
 * Allocate the `out_handle` slot, run the create call, read the handle back.
 * Returns the numeric component handle on success.
 */
function callCreate(module: STTComponentModule): number {
  if (typeof module._rac_stt_component_create !== 'function') {
    throw SDKException.backendNotAvailable(
      'STT.create',
      'Loaded WASM module does not export _rac_stt_component_create.',
    );
  }
  const bridge = new ProtoWasmBridge(module, logger);
  const outPtr = bridge.allocOutPtr();
  if (!outPtr) {
    throw SDKException.fromCode(
      -180,
      'STT.create: failed to allocate output handle slot',
    );
  }
  try {
    const rc = module._rac_stt_component_create(outPtr);
    if (rc !== 0) {
      throw SDKException.fromRACResult(
        rc,
        `rac_stt_component_create failed with code ${rc}`,
        { module, logger },
      );
    }
    const handle = bridge.readU32(outPtr);
    if (!handle) {
      throw SDKException.processingFailed('rac_stt_component_create returned null handle');
    }
    return handle;
  } finally {
    bridge.free(outPtr);
  }
}

function callLoadModel(
  module: STTComponentModule,
  handle: number,
  modelPath: string,
  modelId?: string,
  modelName?: string,
): void {
  if (typeof module._rac_stt_component_load_model !== 'function') {
    throw SDKException.backendNotAvailable(
      'STT.loadModel',
      'Loaded WASM module does not export _rac_stt_component_load_model.',
    );
  }
  const bridge = new ProtoWasmBridge(module, logger);
  const pathPtr = bridge.allocUtf8(modelPath);
  if (!pathPtr) {
    throw SDKException.fromCode(-180, 'STT.loadModel: failed to allocate model path');
  }
  const idPtr = modelId ? bridge.allocUtf8(modelId) : 0;
  const namePtr = modelName ? bridge.allocUtf8(modelName) : 0;
  try {
    const rc = module._rac_stt_component_load_model(handle, pathPtr, idPtr, namePtr);
    if (rc !== 0) {
      throw SDKException.fromRACResult(
        rc,
        `rac_stt_component_load_model failed with code ${rc}`,
        { module, logger },
      );
    }
  } finally {
    bridge.free(pathPtr);
    if (idPtr) bridge.free(idPtr);
    if (namePtr) bridge.free(namePtr);
  }
}

/** Top-level transcription options; model selection is lifecycle-owned. */
export type TranscribeOptions = Partial<STTOptions>;

export const STT = {
  transcribeAuto: transcribe,
  transcribeStreamAuto: transcribeStream,

  /**
   * Returns true when the WASM module is loaded with both the proto-byte
   * STT exports AND the component lifecycle exports (create / load_model /
   * destroy). The proto-byte half is what `STTProtoAdapter.supportsProtoSTT()`
   * already checks; this adds the lifecycle slot detection.
   */
  supportsProtoSTT(): boolean {
    const module = getModuleForCapability('stt') as STTComponentModule | null;
    if (!module) return false;
    if (missingSpeechBackendExports(module).length > 0) return false;
    if (typeof module._rac_stt_component_create !== 'function') return false;
    if (typeof module._rac_stt_component_load_model !== 'function') return false;
    if (typeof module._rac_stt_component_destroy !== 'function') return false;
    return STTProtoAdapter.tryDefault()?.supportsProtoSTT() ?? false;
  },

  /** Whether the registered STT backend exposes the lifecycle-owned ABI. */
  supportsLifecycleProtoSTT(): boolean {
    const module = getModuleForCapability('stt') as STTComponentModule | null;
    if (!module || missingSpeechBackendExports(module).length > 0) return false;
    return STTProtoAdapter.tryDefault()?.supportsLifecycleProtoSTT() ?? false;
  },

  /**
   * Create a fresh STT component handle. Caller owns lifecycle and MUST call
   * `STT.destroy(handle)` when finished.
   */
  create(): number {
    const module = requireSTTModule('STT.create');
    return callCreate(module);
  },

  /**
   * Load a model into the component handle. `modelPath` is the on-device file
   * path resolved by the C++ model lifecycle (or any path the platform adapter
   * can serve). `modelId` and `modelName` are optional telemetry hints.
   */
  loadModel(handle: number, modelPath: string, modelId?: string, modelName?: string): void {
    const module = requireSTTModule('STT.loadModel');
    callLoadModel(module, handle, modelPath, modelId, modelName);
  },

  /** Whether the component handle has a model loaded. */
  isLoaded(handle: number): boolean {
    const module = getModuleForCapability('stt') as STTComponentModule | null;
    if (!module || typeof module._rac_stt_component_is_loaded !== 'function') return false;
    return Boolean(module._rac_stt_component_is_loaded(handle));
  },

  /** Transcribe a single audio buffer through the proto-byte adapter. */
  transcribe(
    handle: number,
    audio: Uint8Array | Float32Array,
    options?: Partial<STTOptions>,
  ): STTOutput {
    const adapter = STTProtoAdapter.tryDefault();
    if (!adapter || !adapter.supportsProtoSTT()) {
      throw SDKException.backendNotAvailable(
        'STT.transcribe',
        'No Web WASM backend with rac_stt_*_proto exports is registered.',
      );
    }
    const result = adapter.transcribe(handle, coerceAudio(audio), defaultSTTOptions(options));
    if (!result) {
      throw SDKException.backendNotAvailable(
        'STT.transcribe',
        'rac_stt_component_transcribe_proto returned no STTOutput bytes.',
      );
    }
    return result;
  },

  /** Streaming transcription — yields partial events ending with isFinal=true. */
  transcribeStream(
    handle: number,
    audio: Uint8Array | Float32Array,
    options?: Partial<STTOptions>,
  ): AsyncIterable<STTPartialResult> {
    const adapter = STTProtoAdapter.tryDefault();
    if (!adapter || !adapter.supportsProtoSTT()) {
      throw SDKException.backendNotAvailable(
        'STT.transcribeStream',
        'No Web WASM backend with rac_stt_*_proto exports is registered.',
      );
    }
    return adapter.transcribeStream(handle, coerceAudio(audio), defaultSTTOptions(options));
  },

  /** Unload the model but keep the component handle alive. */
  unload(handle: number): boolean {
    const module = getModuleForCapability('stt') as STTComponentModule | null;
    if (!module || typeof module._rac_stt_component_unload !== 'function') return false;
    const rc = module._rac_stt_component_unload(handle);
    return rc === 0;
  },

  /** Destroy the component handle. Idempotent — safe to call multiple times. */
  destroy(handle: number): void {
    const module = getModuleForCapability('stt') as STTComponentModule | null;
    if (!module || typeof module._rac_stt_component_destroy !== 'function') return;
    module._rac_stt_component_destroy(handle);
  },
};

/**
 * Top-level ergonomic shortcut. Commons resolves and retains the STT model
 * already loaded by ModelLifecycle; this call never creates, loads, unloads,
 * or destroys a component handle.
 */
export async function transcribe(
  audio: Uint8Array | Float32Array,
  options?: TranscribeOptions,
): Promise<STTOutput> {
  requireSTTModule('RunAnywhere.stt.transcribeAuto');
  const adapter = STTProtoAdapter.tryDefault();
  if (!adapter?.supportsLifecycleProtoSTT()) {
    throw SDKException.backendNotAvailable(
      'RunAnywhere.stt.transcribeAuto',
      'Loaded WASM module does not export rac_stt_transcribe_lifecycle_proto.',
    );
  }
  const result = await adapter.transcribeLifecycle(
    coerceAudio(audio),
    defaultSTTOptions(options),
  );
  if (!result) {
    throw SDKException.notInitialized(
      'STT lifecycle transcription failed. Load an STT model through RunAnywhere.loadModel(...) before transcribing.',
    );
  }
  return result;
}

/**
 * Stream through the lifecycle-owned STT model and expose the established
 * partial-result surface. Native STARTED envelopes are intentionally omitted;
 * PARTIAL/ENDPOINT/FINAL/ERROR envelopes are folded into STTPartialResult.
 */
export function transcribeStream(
  audio: Uint8Array | Float32Array,
  options?: TranscribeOptions,
): AsyncIterable<STTPartialResult> {
  requireSTTModule('RunAnywhere.stt.transcribeStreamAuto');
  const adapter = STTProtoAdapter.tryDefault();
  if (!adapter?.supportsLifecycleProtoSTT()) {
    throw SDKException.backendNotAvailable(
      'RunAnywhere.stt.transcribeStreamAuto',
      'Loaded WASM module does not export rac_stt_transcribe_stream_lifecycle_proto.',
    );
  }
  const events = adapter.transcribeLifecycleStream(
    coerceAudio(audio),
    defaultSTTOptions(options),
  );
  return (async function* (): AsyncIterable<STTPartialResult> {
    for await (const event of events) {
      if (event.kind === STTStreamEventKind.STT_STREAM_EVENT_KIND_ERROR) {
        const detail = event.errorMessage || String(event.errorCode);
        yield STTPartialResult.fromPartial({
          text: detail.startsWith('STT stream failed')
            ? detail
            : `STT stream failed: ${detail}`,
          isFinal: true,
          requestId: event.requestId,
        });
        return;
      }
      if (event.kind === STTStreamEventKind.STT_STREAM_EVENT_KIND_FINAL) {
        yield STTPartialResult.fromPartial({
          ...(event.partial ?? {}),
          text: event.partial?.text || event.finalOutput?.text || '',
          isFinal: true,
          finalOutput: event.finalOutput ?? event.partial?.finalOutput,
          requestId: event.requestId || event.partial?.requestId,
        });
        return;
      }
      if (
        (event.kind === STTStreamEventKind.STT_STREAM_EVENT_KIND_PARTIAL
          || event.kind === STTStreamEventKind.STT_STREAM_EVENT_KIND_ENDPOINT)
        && event.partial
      ) {
        yield event.partial;
      }
    }
  })();
}
