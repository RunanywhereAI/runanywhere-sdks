/**
 * RunAnywhere+VAD.ts
 *
 * Voice activity detection namespace — mirrors Swift's `RunAnywhere+VAD.swift`.
 * Provides `RunAnywhere.vad.*` capability surface for owning VAD component
 * handles plus a `RunAnywhere.vad.detectVoiceAuto(audio, options)` shortcut.
 *
 * The proto-byte adapters (`VADProtoAdapter`) take a numeric `handle` argument
 * — it comes from `_rac_vad_component_create()` followed by
 * `_rac_vad_component_initialize()` (and optionally
 * `_rac_vad_component_load_model()` when using a Silero model). This facade
 * owns those calls so consumers never have to touch raw exports.
 */

import {
  ModelCategory,
} from '@runanywhere/proto-ts/model_types';
import {
  type VADConfiguration,
  type VADOptions,
  type VADResult,
  type VADStatistics,
  type SpeechActivityEvent,
} from '@runanywhere/proto-ts/vad_options';
import { SDKErrorCode, SDKException } from '../../Foundation/SDKException';
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
import { VADProtoAdapter, type ProtoEventHandler } from '../../Adapters/ModalityProtoAdapter';
import { ModelLifecycle } from './RunAnywhere+ModelLifecycle';
import {
  getSpeechProvider,
  hasSpeechProviderVAD,
} from './SpeechProvider';

export type { VADConfiguration, VADOptions, VADResult, VADStatistics, SpeechActivityEvent };

const logger = new SDKLogger('VAD');

interface VADComponentModule extends EmscriptenRunanywhereModule {
  _rac_vad_component_create?(outHandlePtr: number): number;
  _rac_vad_component_initialize?(handle: number): number;
  _rac_vad_component_destroy?(handle: number): void;
  _rac_vad_component_is_initialized?(handle: number): number;
  _rac_vad_component_load_model?(
    handle: number,
    modelPathPtr: number,
    modelIdPtr: number,
    modelNamePtr: number,
  ): number;
  _rac_vad_component_unload?(handle: number): number;
  _rac_vad_component_reset?(handle: number): number;
  _rac_vad_component_start?(handle: number): number;
  _rac_vad_component_stop?(handle: number): number;
}

function requireVADModule(feature: string): VADComponentModule {
  const module = getModuleForCapability('vad') as VADComponentModule | null;
  if (!module) {
    throw SDKException.backendNotAvailable(
      feature,
      'No VAD backend is registered. Call ONNX.register() (or another VAD-providing backend) first.',
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

function defaultVADConfig(overrides?: Partial<VADConfiguration>): VADConfiguration {
  return {
    modelId: '',
    sampleRate: 16000,
    frameLengthMs: 100,
    threshold: 0.015,
    enableAutoCalibration: false,
    calibrationMultiplier: 1.5,
    preferredFramework: undefined,
    ...(overrides ?? {}),
  } as VADConfiguration;
}

function defaultVADOptions(overrides?: Partial<VADOptions>): VADOptions {
  return {
    threshold: 0,
    minSpeechDurationMs: 100,
    minSilenceDurationMs: 300,
    maxSpeechDurationMs: 0,
    ...(overrides ?? {}),
  } as VADOptions;
}

function callCreate(module: VADComponentModule): number {
  if (typeof module._rac_vad_component_create !== 'function') {
    throw SDKException.backendNotAvailable(
      'VAD.create',
      'Loaded WASM module does not export _rac_vad_component_create.',
    );
  }
  const bridge = new ProtoWasmBridge(module, logger);
  const outPtr = bridge.allocOutPtr();
  if (!outPtr) {
    throw SDKException.fromCode(SDKErrorCode.StorageError, 'VAD.create: failed to allocate output handle slot');
  }
  try {
    const rc = module._rac_vad_component_create(outPtr);
    if (rc !== 0) {
      throw SDKException.fromRACResult(
        rc,
        `rac_vad_component_create failed with code ${rc}`,
      );
    }
    const handle = bridge.readU32(outPtr);
    if (!handle) {
      throw SDKException.componentNotReady(
        'vad',
        'rac_vad_component_create returned null handle',
      );
    }
    return handle;
  } finally {
    bridge.free(outPtr);
  }
}

function callLoadModel(
  module: VADComponentModule,
  handle: number,
  modelPath: string,
  modelId?: string,
  modelName?: string,
): void {
  if (typeof module._rac_vad_component_load_model !== 'function') {
    throw SDKException.backendNotAvailable(
      'VAD.loadModel',
      'Loaded WASM module does not export _rac_vad_component_load_model. ' +
        'Swift-aligned Web VAD requires the model-backed lifecycle path, not an energy-only fallback.',
    );
  }
  const bridge = new ProtoWasmBridge(module, logger);
  const pathPtr = bridge.allocUtf8(modelPath);
  if (!pathPtr) {
    throw SDKException.fromCode(SDKErrorCode.StorageError, 'VAD.loadModel: failed to allocate model path');
  }
  const idPtr = modelId ? bridge.allocUtf8(modelId) : 0;
  const namePtr = modelName ? bridge.allocUtf8(modelName) : 0;
  try {
    const rc = module._rac_vad_component_load_model(handle, pathPtr, idPtr, namePtr);
    if (rc !== 0) {
      throw SDKException.fromRACResult(
        rc,
        `rac_vad_component_load_model failed with code ${rc}`,
      );
    }
  } finally {
    bridge.free(pathPtr);
    if (idPtr) bridge.free(idPtr);
    if (namePtr) bridge.free(namePtr);
  }
}

/** Top-level detectVoice options for the ergonomic shortcut. */
export interface DetectVoiceOptions extends Partial<VADOptions> {
  /** Optional explicit model id. */
  modelId?: string;
  /** Optional explicit model file path (only needed for non-energy VAD). */
  modelPath?: string;
  /** Optional configuration override. */
  config?: Partial<VADConfiguration>;
}

export const VAD = {
  detectVoiceAuto: detectVoice,

  /**
   * Returns true when the WASM module is loaded with both the proto-byte VAD
   * exports AND the component lifecycle exports (create / destroy).
   */
  supportsProtoVAD(): boolean {
    const module = getModuleForCapability('vad') as VADComponentModule | null;
    if (!module) return false;
    if (missingSpeechBackendExports(module).length > 0) return false;
    if (typeof module._rac_vad_component_create !== 'function') return false;
    if (typeof module._rac_vad_component_destroy !== 'function') return false;
    return VADProtoAdapter.tryDefault()?.supportsProtoVAD() ?? false;
  },

  /**
   * Create a fresh VAD component handle. Caller owns lifecycle and MUST call
   * `VAD.destroy(handle)` when finished.
   */
  create(): number {
    const module = requireVADModule('VAD.create');
    return callCreate(module);
  },

  /**
   * Configure the VAD component (sample rate, threshold, etc). Wraps the
   * proto-byte configure call.
   */
  configure(handle: number, config?: Partial<VADConfiguration>): boolean {
    const adapter = VADProtoAdapter.tryDefault();
    if (!adapter || !adapter.supportsProtoVAD()) {
      throw SDKException.backendNotAvailable(
        'VAD.configure',
        'No Web WASM backend with rac_vad_*_proto exports is registered.',
      );
    }
    return adapter.configure(handle, defaultVADConfig(config));
  },

  /**
   * Initialize the VAD pipeline. Required after `configure`.
   */
  initialize(handle: number): boolean {
    const module = getModuleForCapability('vad') as VADComponentModule | null;
    if (!module || typeof module._rac_vad_component_initialize !== 'function') {
      throw SDKException.backendNotAvailable(
        'VAD.initialize',
        'Loaded WASM module does not export _rac_vad_component_initialize.',
      );
    }
    const rc = module._rac_vad_component_initialize(handle);
    return rc === 0;
  },

  /** Whether the VAD component has finished initialization. */
  isInitialized(handle: number): boolean {
    const module = getModuleForCapability('vad') as VADComponentModule | null;
    if (!module || typeof module._rac_vad_component_is_initialized !== 'function') return false;
    return Boolean(module._rac_vad_component_is_initialized(handle));
  },

  /** Load a Silero (or other ONNX) VAD model into the component. */
  loadModel(handle: number, modelPath: string, modelId?: string, modelName?: string): void {
    const module = requireVADModule('VAD.loadModel');
    callLoadModel(module, handle, modelPath, modelId, modelName);
  },

  /**
   * Process a chunk of audio samples. Returns `VADResult` with the speech
   * decision; subscribe to activity events via `setActivityHandler`.
   */
  process(
    handle: number,
    samples: Float32Array,
    options?: Partial<VADOptions>,
  ): VADResult {
    const adapter = VADProtoAdapter.tryDefault();
    if (!adapter || !adapter.supportsProtoVAD()) {
      throw SDKException.backendNotAvailable(
        'VAD.process',
        'No Web WASM backend with rac_vad_*_proto exports is registered.',
      );
    }
    const result = adapter.process(handle, samples, defaultVADOptions(options));
    if (!result) {
      throw SDKException.backendNotAvailable(
        'VAD.process',
        'rac_vad_component_process_proto returned no VADResult bytes.',
      );
    }
    return result;
  },

  /** Latest aggregate VAD statistics (frames processed, segments, etc). */
  statistics(handle: number): VADStatistics {
    const adapter = VADProtoAdapter.tryDefault();
    if (!adapter || !adapter.supportsProtoVAD()) {
      throw SDKException.backendNotAvailable(
        'VAD.statistics',
        'No Web WASM backend with rac_vad_*_proto exports is registered.',
      );
    }
    const stats = adapter.statistics(handle);
    if (!stats) {
      throw SDKException.backendNotAvailable(
        'VAD.statistics',
        'rac_vad_component_get_statistics_proto returned no VADStatistics bytes.',
      );
    }
    return stats;
  },

  /**
   * Subscribe to speech-activity events (started / ended). Pass `null` to
   * unsubscribe.
   */
  setActivityHandler(
    handle: number,
    handler: ProtoEventHandler<SpeechActivityEvent> | null,
  ): boolean {
    const adapter = VADProtoAdapter.tryDefault();
    if (!adapter || !adapter.supportsProtoVAD()) {
      throw SDKException.backendNotAvailable(
        'VAD.setActivityHandler',
        'No Web WASM backend with rac_vad_*_proto exports is registered.',
      );
    }
    return adapter.setActivityHandler(handle, handler);
  },

  /** Start the VAD pipeline. */
  start(handle: number): boolean {
    const module = getModuleForCapability('vad') as VADComponentModule | null;
    if (!module || typeof module._rac_vad_component_start !== 'function') return false;
    return module._rac_vad_component_start(handle) === 0;
  },

  /** Stop the VAD pipeline. */
  stop(handle: number): boolean {
    const module = getModuleForCapability('vad') as VADComponentModule | null;
    if (!module || typeof module._rac_vad_component_stop !== 'function') return false;
    return module._rac_vad_component_stop(handle) === 0;
  },

  /** Reset the VAD state (clears any speech-segment buffers). */
  reset(handle: number): boolean {
    const module = getModuleForCapability('vad') as VADComponentModule | null;
    if (!module || typeof module._rac_vad_component_reset !== 'function') return false;
    return module._rac_vad_component_reset(handle) === 0;
  },

  /** Destroy the component handle. Idempotent. */
  destroy(handle: number): void {
    const module = getModuleForCapability('vad') as VADComponentModule | null;
    if (!module || typeof module._rac_vad_component_destroy !== 'function') return;
    module._rac_vad_component_destroy(handle);
  },
};

/**
 * Top-level ergonomic shortcut: auto-creates a handle, applies default config,
 * runs `process`, and destroys the handle.
 *
 * If a `SpeechProvider` is registered (e.g. by `@runanywhere/web-onnx`'s
 * standalone Sherpa bridge) and supports VAD, dispatch through it instead
 * of the proto-byte path. This is the production path while the unified
 * `racommons-llamacpp.wasm` Sherpa link remains blocked by the Emscripten
 * exception-trampoline mismatch.
 */
export async function detectVoice(
  audio: Float32Array,
  options?: DetectVoiceOptions,
): Promise<VADResult> {
  let modelPath = options?.modelPath;
  let modelId = options?.modelId;
  let modelName: string | undefined;

  if (!modelPath && ModelLifecycle.supportsNativeLifecycle()) {
    const current = ModelLifecycle.currentModel({
      category: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
      includeModelMetadata: true,
    });
    if (current?.modelId) {
      modelPath = current.resolvedPath || current.modelId;
      modelId = current.modelId;
    }
  }

  if (hasSpeechProviderVAD()) {
    const provider = getSpeechProvider()!;
    if (modelPath && (typeof provider.isVADLoaded !== 'function' || !provider.isVADLoaded())) {
      if (typeof provider.loadVAD !== 'function') {
        throw SDKException.backendNotAvailable(
          'RunAnywhere.vad.detectVoiceAuto',
          `SpeechProvider "${provider.id}" does not implement loadVAD.`,
        );
      }
      await provider.loadVAD({ id: modelId ?? modelPath, path: modelPath, name: modelName });
    }
    if (typeof provider.detectVoiceActivity !== 'function') {
      throw SDKException.backendNotAvailable(
        'RunAnywhere.vad.detectVoiceAuto',
        `SpeechProvider "${provider.id}" does not implement detectVoiceActivity.`,
      );
    }
    return provider.detectVoiceActivity({
      audio,
      sampleRate: options?.config?.sampleRate ?? 16000,
      config: options?.config,
      options,
    });
  }

  const module = requireVADModule('RunAnywhere.vad.detectVoiceAuto');
  if (!modelPath) {
    throw SDKException.componentNotReady(
      'vad',
      'No VAD model is loaded. Call RunAnywhere.loadModel(...) with a VAD model before RunAnywhere.detectVoiceActivity().',
    );
  }

  const handle = callCreate(module);
  try {
    callLoadModel(module, handle, modelPath, modelId, modelName);
    VAD.configure(handle, options?.config);
    VAD.initialize(handle);
    return VAD.process(handle, audio, options);
  } finally {
    VAD.destroy(handle);
  }
}
