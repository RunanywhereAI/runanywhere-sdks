/**
 * RunAnywhere+STT.ts
 *
 * Speech-to-text namespace — mirrors Swift's `RunAnywhere+STT.swift`.
 * Provides `RunAnywhere.stt.*` capability surface for owning STT component
 * handles plus a `RunAnywhere.stt.transcribeAuto(audio, options)` ergonomic
 * shortcut.
 *
 * The proto-byte adapters (`STTProtoAdapter`) take a numeric `handle` argument
 * — it comes from `_rac_stt_component_create()` followed by
 * `_rac_stt_component_load_model()`. This facade owns those calls so the
 * example app and external consumers never have to touch raw exports.
 */

import { AudioFormat, ModelCategory } from '@runanywhere/proto-ts/model_types';
import {
  STTLanguage,
  type STTOptions,
  type STTOutput,
  type STTPartialResult,
} from '@runanywhere/proto-ts/stt_options';
import { SDKException } from '../../Foundation/SDKException';
import { SDKLogger } from '../../Foundation/SDKLogger';
import { ProtoWasmBridge } from '../../runtime/ProtoWasm';
import {
  getModuleForCapability,
  type EmscriptenRunanywhereModule,
} from '../../runtime/EmscriptenModule';
import {
  missingSpeechBackendExports,
  speechBackendRequirementMessage,
} from '../../runtime/SpeechBackendExports';
import { STTProtoAdapter } from '../../Adapters/ModalityProtoAdapter';
import { WebModelLifecycle } from './RunAnywhere+ModelLifecycle';
import {
  getSpeechProvider,
  hasSpeechProviderSTT,
} from './SpeechProvider';

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

function defaultSTTOptions(overrides?: Partial<STTOptions>): STTOptions {
  return {
    language: STTLanguage.STT_LANGUAGE_AUTO,
    enablePunctuation: true,
    enableDiarization: false,
    maxSpeakers: 0,
    vocabularyList: [],
    enableWordTimestamps: false,
    beamSize: 0,
    languageCode: undefined,
    detectLanguage: true,
    audioFormat: AudioFormat.AUDIO_FORMAT_PCM,
    sampleRate: 16000,
    maxAlternatives: 0,
    chunkDurationMs: 0,
    endpointSilenceMs: 0,
    ...(overrides ?? {}),
  } as STTOptions;
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
 * Decode a Uint8Array of little-endian PCM16 audio into normalized Float32
 * samples in the range [-1, 1]. Used by the SpeechProvider path which expects
 * Float32 samples — never reinterpret the underlying buffer as Float32 because
 * the byte offset/length need not be 4-aligned and the bytes are not IEEE754.
 */
function decodePcm16ToFloat32(audio: Uint8Array): Float32Array {
  const usableBytes = audio.byteLength - (audio.byteLength % 2);
  const sampleCount = usableBytes / 2;
  const out = new Float32Array(sampleCount);
  const view = new DataView(audio.buffer, audio.byteOffset, usableBytes);
  for (let i = 0; i < sampleCount; i += 1) {
    out[i] = view.getInt16(i * 2, true) / 0x8000;
  }
  return out;
}

/**
 * Convert a public-API audio buffer into the Float32 sample format expected by
 * SpeechProvider implementations. Float32Array passes through unchanged; the
 * Uint8Array branch interprets bytes according to options.audioFormat (PCM16
 * is the documented default for STT).
 */
function audioToFloat32Samples(
  audio: Uint8Array | Float32Array,
  options: TranscribeOptions | undefined,
): Float32Array {
  if (audio instanceof Float32Array) return audio;
  const format = options?.audioFormat ?? AudioFormat.AUDIO_FORMAT_PCM;
  if (format !== AudioFormat.AUDIO_FORMAT_PCM) {
    throw SDKException.backendNotAvailable(
      'RunAnywhere.stt.transcribeAuto',
      `SpeechProvider path only supports PCM16 Uint8Array input; got audioFormat=${format}. ` +
        `Pass a Float32Array of normalized samples or use the proto-byte adapter path.`,
    );
  }
  return decodePcm16ToFloat32(audio);
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
      throw SDKException.componentNotReady(
        'stt',
        'rac_stt_component_create returned null handle',
      );
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

/** Top-level transcribe options for the ergonomic shortcut. */
export interface TranscribeOptions extends Partial<STTOptions> {
  /** Optional explicit model id. When omitted, uses the loaded STT model from lifecycle. */
  modelId?: string;
  /** Optional explicit model file path. Required when no STT model has been loaded yet. */
  modelPath?: string;
}

export const STT = {
  transcribeAuto: transcribe,

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
 * Top-level ergonomic shortcut: auto-creates a handle, loads the current STT
 * model from lifecycle (if any), runs transcription, and destroys the handle.
 * Use the namespaced `RunAnywhere.stt.*` verbs when you want to reuse a handle
 * across calls.
 */
export async function transcribe(
  audio: Uint8Array | Float32Array,
  options?: TranscribeOptions,
): Promise<STTOutput> {
  let modelPath = options?.modelPath;
  let modelId = options?.modelId;
  let modelName: string | undefined;

  if (!modelPath && WebModelLifecycle.supportsNativeLifecycle()) {
    const current = WebModelLifecycle.currentModel({
      category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
      includeModelMetadata: true,
    });
    if (current?.modelId) {
      modelPath = current.resolvedPath || current.modelId;
      modelId = current.modelId;
    }
  }

  // Provider-first dispatch: when a SpeechProvider is registered (e.g.
  // standalone Sherpa via @runanywhere/web-onnx) and supports STT, route
  // through it. Falls back to the proto-byte adapter otherwise.
  if (hasSpeechProviderSTT()) {
    const provider = getSpeechProvider()!;
    if (modelPath && (typeof provider.isSTTLoaded !== 'function' || !provider.isSTTLoaded())) {
      if (typeof provider.loadSTT !== 'function') {
        throw SDKException.backendNotAvailable(
          'RunAnywhere.stt.transcribeAuto',
          `SpeechProvider "${provider.id}" does not implement loadSTT.`,
        );
      }
      await provider.loadSTT({ id: modelId ?? modelPath, path: modelPath, name: modelName });
    }
    if (typeof provider.transcribe !== 'function') {
      throw SDKException.backendNotAvailable(
        'RunAnywhere.stt.transcribeAuto',
        `SpeechProvider "${provider.id}" does not implement transcribe.`,
      );
    }
    const samples = audioToFloat32Samples(audio, options);
    return provider.transcribe({
      audio: samples,
      sampleRate: options?.sampleRate ?? 16000,
      options,
    });
  }

  const module = requireSTTModule('RunAnywhere.stt.transcribeAuto');
  if (!modelPath) {
    throw SDKException.componentNotReady(
      'stt',
      'No STT model is loaded. Call RunAnywhere.modelLifecycle.loadModel(...) before RunAnywhere.stt.transcribeAuto().',
    );
  }

  const handle = callCreate(module);
  try {
    callLoadModel(module, handle, modelPath, modelId, modelName);
    return STT.transcribe(handle, audio, options);
  } finally {
    STT.destroy(handle);
  }
}
