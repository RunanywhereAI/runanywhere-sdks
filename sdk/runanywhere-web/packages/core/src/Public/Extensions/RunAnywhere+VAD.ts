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
import { vADConfigurationDefaults } from '@runanywhere/proto-ts/convenience/vad_options_convenience';
import { ProtoErrorCode, SDKException } from '../../Foundation/SDKException.js';
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
import { VADProtoAdapter, type ProtoEventHandler } from '../../Adapters/ModalityProtoAdapter.js';
import { WebModelLifecycle } from './RunAnywhere+ModelLifecycle.js';

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

// Proto-rac_default-derived defaults — byte-identical to Swift's RAVADConfiguration.defaults().
function defaultVADConfig(overrides?: Partial<VADConfiguration>): VADConfiguration {
  return {
    ...vADConfigurationDefaults(),
    ...(overrides ?? {}),
  };
}

function defaultVADOptions(overrides?: Partial<VADOptions>): VADOptions {
  return {
    threshold: 0,
    minSpeechDurationMs: 100,
    minSilenceDurationMs: 300,
    maxSpeechDurationMs: 0,
    includeStatistics: false,
    ...(overrides ?? {}),
  };
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
    throw SDKException.fromCode(-ProtoErrorCode.ERROR_CODE_STORAGE_ERROR, 'VAD.create: failed to allocate output handle slot');
  }
  try {
    const rc = module._rac_vad_component_create(outPtr);
    if (rc !== 0) {
      throw SDKException.fromRACResult(
        rc,
        `rac_vad_component_create failed with code ${rc}`,
        { module, logger },
      );
    }
    const handle = bridge.readU32(outPtr);
    if (!handle) {
      throw SDKException.processingFailed('rac_vad_component_create returned null handle');
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
    throw SDKException.fromCode(-ProtoErrorCode.ERROR_CODE_STORAGE_ERROR, 'VAD.loadModel: failed to allocate model path');
  }
  const idPtr = modelId ? bridge.allocUtf8(modelId) : 0;
  const namePtr = modelName ? bridge.allocUtf8(modelName) : 0;
  try {
    const rc = module._rac_vad_component_load_model(handle, pathPtr, idPtr, namePtr);
    if (rc !== 0) {
      throw SDKException.fromRACResult(
        rc,
        `rac_vad_component_load_model failed with code ${rc}`,
        { module, logger },
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
  /** Optional configuration override. */
  config?: Partial<VADConfiguration>;
}

interface ResolvedVADModel {
  id: string;
}

function currentLifecycleVADModel(): ResolvedVADModel | null {
  if (!WebModelLifecycle.supportsNativeLifecycle()) return null;
  const current = WebModelLifecycle.currentModel({
    category: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
    includeModelMetadata: true,
  });
  if (!current?.modelId) return null;
  return { id: current.modelId };
}

function lifecycleVADAdapter(feature: string): VADProtoAdapter {
  const adapter = VADProtoAdapter.tryDefault();
  if (!adapter || !adapter.supportsLifecycleVAD()) {
    throw SDKException.backendNotAvailable(
      feature,
      'The registered VAD backend does not expose the canonical lifecycle VAD ABI.',
    );
  }
  return adapter;
}

function callOptions(options?: DetectVoiceOptions, threshold = options?.threshold ?? 0): VADOptions {
  return defaultVADOptions({
    threshold,
    minSpeechDurationMs: options?.minSpeechDurationMs ?? 100,
    minSilenceDurationMs: options?.minSilenceDurationMs ?? 300,
    maxSpeechDurationMs: options?.maxSpeechDurationMs ?? 0,
    includeStatistics: options?.includeStatistics ?? false,
  });
}

function lifecycleConfiguration(options?: DetectVoiceOptions): VADConfiguration {
  const config = defaultVADConfig(options?.config);
  if (options?.config?.threshold === undefined && options?.threshold !== undefined) {
    return { ...config, threshold: options.threshold };
  }
  return config;
}

function assertRequestedModelMatches(
  current: ResolvedVADModel,
  options?: DetectVoiceOptions,
): void {
  if (options?.modelId && current.id && options.modelId !== current.id) {
    throw SDKException.invalidConfiguration(
      `VAD model "${options.modelId}" was requested, but lifecycle model "${current.id}" is loaded.`,
    );
  }
}

export const VAD = {
  detectVoiceAuto: detectVoice,
  streamVoiceAuto: streamVoiceActivity,

  /**
   * Reset the lifecycle-loaded VAD service (clears speech-segment buffers).
   * Handle-less form backing Swift's parameterless `RunAnywhere.resetVAD()`.
   * No-op returning false when no VAD model is loaded through lifecycle.
   */
  resetVoiceAuto(): boolean {
    if (!currentLifecycleVADModel()) return false;
    return (
      lifecycleVADAdapter('RunAnywhere.vad.resetVoiceAuto').resetLifecycle() !=
      null
    );
  },

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

  /** Whether the native persistent VAD stream-session ABI is available. */
  supportsProtoVADStream(): boolean {
    return VADProtoAdapter.tryDefault()?.supportsProtoVADStream() ?? false;
  },

  /** Whether the loaded ModelLifecycle VAD service can be used handle-free. */
  supportsLifecycleProtoVAD(): boolean {
    return VADProtoAdapter.tryDefault()?.supportsLifecycleVAD() ?? false;
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
 * Top-level ergonomic shortcut. When ModelLifecycle owns a VAD model this
 * routes directly through that canonical service, preserving the detector's
 * recurrent state and avoiding a second ONNX Runtime session.
 */
export async function detectVoice(
  audio: Float32Array,
  options?: DetectVoiceOptions,
): Promise<VADResult> {
  const current = currentLifecycleVADModel();
  if (!current) {
    throw SDKException.notInitialized(
      'No VAD model is loaded. Call RunAnywhere.loadModel(...) with a VAD model before voice activity detection.',
    );
  }
  assertRequestedModelMatches(current, options);
  const adapter = lifecycleVADAdapter('RunAnywhere.vad.detectVoiceAuto');
  const config = lifecycleConfiguration(options);
  if (!adapter.configureLifecycle(config)) {
    throw SDKException.processingFailed('Failed to configure the lifecycle VAD service');
  }
  // The threshold was applied by configureLifecycle. Keeping the per-frame
  // override at zero avoids rebuilding Sherpa's detector for this frame.
  const result = await adapter.processLifecycle(
    audio,
    callOptions(options, 0),
    config.sampleRate || 16_000,
  );
  if (!result) {
    throw SDKException.processingFailed(
      'rac_vad_process_lifecycle_proto returned no VADResult bytes.',
    );
  }
  return result;
}

/**
 * Stream microphone frames through one persistent native VAD session.
 *
 * A Silero model owns recurrent detector state and an ONNX Runtime session.
 * When ModelLifecycle owns that model, this wrapper configures and starts the
 * canonical service once, processes every frame against the same backend
 * implementation, then always pairs stop/reset during iterator teardown.
 */
export async function* streamVoiceActivity(
  audio: AsyncIterable<Float32Array>,
  options?: DetectVoiceOptions,
): AsyncIterable<VADResult> {
  const configuredRate = options?.config?.sampleRate ?? 16_000;
  if (configuredRate !== 16_000) {
    throw SDKException.invalidConfiguration(
      `Native VAD streaming currently requires 16000 Hz PCM (received ${configuredRate} Hz).`,
    );
  }

  const current = currentLifecycleVADModel();
  if (!current) {
    throw SDKException.notInitialized(
      'No VAD model is loaded. Call RunAnywhere.loadModel(...) with a VAD model before voice activity detection.',
    );
  }
  assertRequestedModelMatches(current, options);
  const adapter = lifecycleVADAdapter('VAD.streamVoiceAuto');
  const config = lifecycleConfiguration(options);
  if (!adapter.configureLifecycle(config)) {
    throw SDKException.processingFailed('Failed to configure the lifecycle VAD service');
  }

  let started = false;
  try {
    if (!adapter.startLifecycle()) {
      throw SDKException.processingFailed('Failed to start the lifecycle VAD service');
    }
    started = true;
    const frameOptions = callOptions(options, 0);
    for await (const chunk of audio) {
      if (chunk.length === 0) continue;
      const result = await adapter.processLifecycle(chunk, frameOptions, configuredRate);
      if (!result) {
        throw SDKException.processingFailed(
          'rac_vad_process_lifecycle_proto returned no VADResult bytes.',
        );
      }
      yield result;
    }
  } finally {
    if (started && !adapter.stopLifecycle()) {
      logger.warning('Failed to stop the lifecycle VAD service during stream cleanup');
    }
    if (!adapter.resetLifecycle()) {
      logger.warning('Failed to reset the lifecycle VAD service during stream cleanup');
    }
  }
}
