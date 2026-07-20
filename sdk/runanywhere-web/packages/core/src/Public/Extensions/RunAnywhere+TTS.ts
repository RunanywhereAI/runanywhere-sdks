/**
 * RunAnywhere+TTS.ts
 *
 * Text-to-speech namespace — mirrors Swift's `RunAnywhere+TTS.swift`.
 * Provides `RunAnywhere.tts.*` capability surface for owning TTS component
 * handles plus a `RunAnywhere.tts.synthesizeAuto(text, options)` shortcut.
 *
 * Low-level proto-byte adapter methods take a numeric component handle. The
 * auto shortcut uses commons' lifecycle-owned TTS ABI so synthesis cannot
 * evict the canonical model.
 */

import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import {
  type TTSOptions,
  type TTSOutput,
  type TTSVoiceInfo,
} from '@runanywhere/proto-ts/tts_options';
import { tTSOptionsDefaults } from '@runanywhere/proto-ts/convenience/tts_options_convenience';
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
import { TTSProtoAdapter } from '../../Adapters/ModalityProtoAdapter.js';
import { WebModelLifecycle } from './RunAnywhere+ModelLifecycle.js';
import { AudioPlayback } from '../../Infrastructure/AudioPlayback.js';

export type { TTSOptions, TTSOutput, TTSVoiceInfo };

const logger = new SDKLogger('TTS');

/**
 * Extra Emscripten exports the TTS facade reaches into directly. The proto
 * `synthesize`/`synthesizeStream`/`listVoices` calls go through
 * `TTSProtoAdapter`; what this facade adds is the component lifecycle.
 */
interface TTSComponentModule extends EmscriptenRunanywhereModule {
  _rac_tts_component_create?(outHandlePtr: number): number;
  _rac_tts_component_load_voice?(
    handle: number,
    voicePathPtr: number,
    voiceIdPtr: number,
    voiceNamePtr: number,
  ): number;
  _rac_tts_component_unload?(handle: number): number;
  _rac_tts_component_destroy?(handle: number): void;
  _rac_tts_component_is_loaded?(handle: number): number;
  _rac_tts_component_stop?(handle: number): number;
}

function requireTTSModule(feature: string): TTSComponentModule {
  const module = getModuleForCapability('tts') as TTSComponentModule | null;
  if (!module) {
    throw SDKException.backendNotAvailable(
      feature,
      'No TTS backend is registered. Call ONNX.register() (or another TTS-providing backend) first.',
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

// Proto-rac_default-derived defaults — byte-identical to Swift's RATTSOptions.defaults().
function defaultTTSOptions(overrides?: Partial<TTSOptions>): TTSOptions {
  return {
    ...tTSOptionsDefaults(),
    ...(overrides ?? {}),
  };
}

function autoTTSOptions(options?: SynthesizeOptions): TTSOptions {
  if (!options) return defaultTTSOptions();
  const { voiceId, ...overrides } = options;
  return defaultTTSOptions({
    ...overrides,
    voice: overrides.voice || voiceId || '',
  });
}

function currentLifecycleVoiceId(): string | null {
  if (!WebModelLifecycle.supportsNativeLifecycle()) return null;
  const current = WebModelLifecycle.currentModel({
    category: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
    includeModelMetadata: true,
  });
  return current?.modelId || null;
}

function callCreate(module: TTSComponentModule): number {
  if (typeof module._rac_tts_component_create !== 'function') {
    throw SDKException.backendNotAvailable(
      'TTS.create',
      'Loaded WASM module does not export _rac_tts_component_create.',
    );
  }
  const bridge = new ProtoWasmBridge(module, logger);
  const outPtr = bridge.allocOutPtr();
  if (!outPtr) {
    throw SDKException.fromCode(-180, 'TTS.create: failed to allocate output handle slot');
  }
  try {
    const rc = module._rac_tts_component_create(outPtr);
    if (rc !== 0) {
      throw SDKException.fromRACResult(
        rc,
        `rac_tts_component_create failed with code ${rc}`,
        { module, logger },
      );
    }
    const handle = bridge.readU32(outPtr);
    if (!handle) {
      throw SDKException.processingFailed('rac_tts_component_create returned null handle');
    }
    return handle;
  } finally {
    bridge.free(outPtr);
  }
}

function callLoadVoice(
  module: TTSComponentModule,
  handle: number,
  voicePath: string,
  voiceId?: string,
  voiceName?: string,
): void {
  if (typeof module._rac_tts_component_load_voice !== 'function') {
    throw SDKException.backendNotAvailable(
      'TTS.loadVoice',
      'Loaded WASM module does not export _rac_tts_component_load_voice.',
    );
  }
  const bridge = new ProtoWasmBridge(module, logger);
  const pathPtr = bridge.allocUtf8(voicePath);
  if (!pathPtr) {
    throw SDKException.fromCode(-180, 'TTS.loadVoice: failed to allocate voice path');
  }
  const idPtr = voiceId ? bridge.allocUtf8(voiceId) : 0;
  const namePtr = voiceName ? bridge.allocUtf8(voiceName) : 0;
  try {
    const rc = module._rac_tts_component_load_voice(handle, pathPtr, idPtr, namePtr);
    if (rc !== 0) {
      throw SDKException.fromRACResult(
        rc,
        `rac_tts_component_load_voice failed with code ${rc}`,
        { module, logger },
      );
    }
  } finally {
    bridge.free(pathPtr);
    if (idPtr) bridge.free(idPtr);
    if (namePtr) bridge.free(namePtr);
  }
}

/**
 * Shared audio playback for `RunAnywhere.speak()` — Swift parity: the private
 * `ttsAudioPlayback = AudioPlaybackManager()` singleton in
 * RunAnywhere+TTS.swift. One instance for the SDK lifetime so
 * `stopSpeaking()` can stop whatever `speak()` started.
 */
let ttsAudioPlayback: AudioPlayback | null = null;

export function sharedTTSPlayback(): AudioPlayback {
  if (!ttsAudioPlayback) ttsAudioPlayback = new AudioPlayback();
  return ttsAudioPlayback;
}

/** Stop in-flight `speak()` browser playback (no-op when nothing plays). */
export function stopTTSPlayback(): void {
  ttsAudioPlayback?.stop();
}

/** Top-level synthesize options for the ergonomic shortcut. */
export interface SynthesizeOptions extends Partial<TTSOptions> {
  /** Optional explicit voice id. */
  voiceId?: string;
}

export const TTS = {
  synthesizeAuto: synthesize,

  /**
   * Returns true when the WASM module is loaded with both the proto-byte
   * TTS exports AND the component lifecycle exports (create / load_voice /
   * destroy).
   */
  supportsProtoTTS(): boolean {
    const module = getModuleForCapability('tts') as TTSComponentModule | null;
    if (!module) return false;
    if (missingSpeechBackendExports(module).length > 0) return false;
    if (typeof module._rac_tts_component_create !== 'function') return false;
    if (typeof module._rac_tts_component_load_voice !== 'function') return false;
    if (typeof module._rac_tts_component_destroy !== 'function') return false;
    return TTSProtoAdapter.tryDefault()?.supportsProtoTTS() ?? false;
  },

  /** Whether the registered backend exposes lifecycle-owned TTS synthesis. */
  supportsLifecycleProtoTTS(): boolean {
    const module = getModuleForCapability('tts') as TTSComponentModule | null;
    if (!module || missingSpeechBackendExports(module).length > 0) return false;
    return TTSProtoAdapter.tryDefault()?.supportsLifecycleProtoTTS() ?? false;
  },

  /**
   * Create a fresh TTS component handle. Caller owns lifecycle and MUST call
   * `TTS.destroy(handle)` when finished.
   */
  create(): number {
    const module = requireTTSModule('TTS.create');
    return callCreate(module);
  },

  /**
   * Load a voice into the component handle. `voicePath` is the on-device file
   * path resolved by the C++ model lifecycle. `voiceId` and `voiceName` are
   * optional telemetry hints.
   */
  loadVoice(handle: number, voicePath: string, voiceId?: string, voiceName?: string): void {
    const module = requireTTSModule('TTS.loadVoice');
    callLoadVoice(module, handle, voicePath, voiceId, voiceName);
  },

  /** Whether the component handle has a voice loaded. */
  isLoaded(handle: number): boolean {
    const module = getModuleForCapability('tts') as TTSComponentModule | null;
    if (!module || typeof module._rac_tts_component_is_loaded !== 'function') return false;
    return Boolean(module._rac_tts_component_is_loaded(handle));
  },

  /** Enumerate the voices the loaded TTS engine can render. */
  listVoices(handle: number): TTSVoiceInfo[] {
    const adapter = TTSProtoAdapter.tryDefault();
    if (!adapter || !adapter.supportsProtoTTS()) {
      throw SDKException.backendNotAvailable(
        'TTS.listVoices',
        'No Web WASM backend with rac_tts_*_proto exports is registered.',
      );
    }
    return adapter.listVoices(handle) ?? [];
  },

  /** Enumerate voices through the currently lifecycle-owned TTS service. */
  listLoadedVoices(): TTSVoiceInfo[] {
    const adapter = TTSProtoAdapter.tryDefault();
    if (!adapter) return [];
    return adapter.listLifecycleVoices() ?? [];
  },

  /** Synthesize a chunk of text — returns an audio buffer. */
  synthesize(
    handle: number,
    text: string,
    options?: Partial<TTSOptions>,
  ): TTSOutput {
    const adapter = TTSProtoAdapter.tryDefault();
    if (!adapter || !adapter.supportsProtoTTS()) {
      throw SDKException.backendNotAvailable(
        'TTS.synthesize',
        'No Web WASM backend with rac_tts_*_proto exports is registered.',
      );
    }
    const result = adapter.synthesize(handle, text, defaultTTSOptions(options));
    if (!result) {
      throw SDKException.backendNotAvailable(
        'TTS.synthesize',
        'rac_tts_component_synthesize_proto returned no TTSOutput bytes.',
      );
    }
    return result;
  },

  /** Streaming synthesis — yields TTSOutput chunks. */
  synthesizeStream(
    handle: number,
    text: string,
    options?: Partial<TTSOptions>,
  ): AsyncIterable<TTSOutput> {
    const adapter = TTSProtoAdapter.tryDefault();
    if (!adapter || !adapter.supportsProtoTTS()) {
      throw SDKException.backendNotAvailable(
        'TTS.synthesizeStream',
        'No Web WASM backend with rac_tts_*_proto exports is registered.',
      );
    }
    return adapter.synthesizeStream(handle, text, defaultTTSOptions(options));
  },

  /** Stop in-flight synthesis (best-effort). */
  stop(handle: number): boolean {
    const module = getModuleForCapability('tts') as TTSComponentModule | null;
    if (!module || typeof module._rac_tts_component_stop !== 'function') return false;
    const rc = module._rac_tts_component_stop(handle);
    return rc === 0;
  },

  /** Stop synthesis on the model-lifecycle-owned TTS service. */
  stopLoaded(): boolean {
    const adapter = TTSProtoAdapter.tryDefault();
    if (!adapter || !currentLifecycleVoiceId()) return false;
    const state = adapter.stopLifecycle();
    return state?.errorCode === 0;
  },

  /** Unload the voice but keep the component handle alive. */
  unload(handle: number): boolean {
    const module = getModuleForCapability('tts') as TTSComponentModule | null;
    if (!module || typeof module._rac_tts_component_unload !== 'function') return false;
    const rc = module._rac_tts_component_unload(handle);
    return rc === 0;
  },

  /** Destroy the component handle. Idempotent. */
  destroy(handle: number): void {
    const module = getModuleForCapability('tts') as TTSComponentModule | null;
    if (!module || typeof module._rac_tts_component_destroy !== 'function') return;
    module._rac_tts_component_destroy(handle);
  },
};

/**
 * Top-level ergonomic shortcut. A lifecycle-owned TTS voice is synthesized
 * directly through commons and remains loaded after this call.
 */
export async function synthesize(
  text: string,
  options?: SynthesizeOptions,
): Promise<TTSOutput> {
  requireTTSModule('RunAnywhere.tts.synthesizeAuto');
  const resolvedOptions = autoTTSOptions(options);
  if (currentLifecycleVoiceId()) {
    const adapter = TTSProtoAdapter.tryDefault();
    if (!adapter?.supportsLifecycleProtoTTS()) {
      throw SDKException.backendNotAvailable(
        'RunAnywhere.tts.synthesizeAuto',
        'Loaded WASM module does not export rac_tts_synthesize_lifecycle_proto.',
      );
    }
    const output = await adapter.synthesizeLifecycle(text, resolvedOptions);
    if (!output) {
      throw SDKException.notInitialized(
        'TTS lifecycle synthesis failed. Reload the TTS model through RunAnywhere.loadModel(...) and retry.',
      );
    }
    return output;
  }

  // Swift parity: RunAnywhere+TTS.swift throws `.notInitialized` when no
  // lifecycle voice is loaded. Explicit component handles remain available
  // through the low-level TTS namespace for callers that own that lifecycle.
  throw SDKException.notInitialized(
    'No TTS voice is loaded. Call RunAnywhere.loadModel(...) before RunAnywhere.synthesize().',
  );
}
