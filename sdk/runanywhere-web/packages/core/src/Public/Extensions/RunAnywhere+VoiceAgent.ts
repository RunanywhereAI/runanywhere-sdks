/**
 * RunAnywhere+VoiceAgent.ts
 *
 * Public voice-agent facade. Web owns browser audio capture/playback in
 * adapters; voice-agent request/result/event orchestration is provider- or
 * native-handle-backed and flows through generated proto models.
 */

import { SDKErrorCode, SDKException } from '../../Foundation/SDKException';
import { SDKLogger } from '../../Foundation/SDKLogger';
import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import { WebModelLifecycle } from './RunAnywhere+ModelLifecycle';
import {
  VoiceAgentProtoAdapter,
  type ModalityProtoModule,
} from '../../Adapters/ModalityProtoAdapter';
import { VoiceAgentStreamAdapter } from '../../Adapters/VoiceAgentStreamAdapter';
import type { VoiceAgentStreamTransport } from '@runanywhere/proto-ts/streams/voice_agent_service_stream';
import type {
  VoiceAgentComposeConfig,
  VoiceAgentRequest,
  VoiceAgentResult,
} from '@runanywhere/proto-ts/voice_agent_service';
import {
  AudioEncoding,
  VoicePipelineComponent,
  type VoiceAgentComponentStates,
  type VoiceEvent,
} from '@runanywhere/proto-ts/voice_events';
// IDL-03/04/07: VoiceEventCategory/VoiceEventSeverity/ComponentLoadState were
// consolidated into EventCategory/ErrorSeverity/ComponentLifecycleState.
import { EventCategory, ComponentLifecycleState } from '@runanywhere/proto-ts/component_types';
import { ErrorSeverity } from '@runanywhere/proto-ts/errors';
import type { EmscriptenRunanywhereModule } from '../../runtime/EmscriptenModule';

const logger = new SDKLogger('VoiceAgent');

export type VoiceAgentAvailabilitySource =
  | 'provider'
  | 'wasm-handle'
  | 'wasm-exports'
  | 'unavailable';

export interface VoiceAgentAvailability {
  available: boolean;
  source: VoiceAgentAvailabilitySource;
  reason: string;
  missingExports: string[];
  hasHandle: boolean;
}

export type VoiceAgentStreamSource = {
  handle: number;
  module: EmscriptenRunanywhereModule;
} | {
  transport: VoiceAgentStreamTransport;
};

/**
 * Backend-supplied voice-agent provider. Backends may register a native WASM
 * handle through `setVoiceAgentHandle(...)` or install a full custom provider
 * through `setVoiceAgentProvider(...)`.
 */
export interface VoiceAgentProvider {
  readonly providerKind?: 'custom' | 'wasm-handle';
  initializeVoiceAgent(config: VoiceAgentComposeConfig): Promise<void>;
  initializeVoiceAgentWithLoadedModels(ttsVoiceID?: string): Promise<void>;
  isVoiceAgentReady(): Promise<boolean> | boolean;
  getVoiceAgentComponentStates(): Promise<VoiceAgentComponentStates> | VoiceAgentComponentStates;
  processVoiceTurn(audio: Float32Array | Uint8Array): Promise<VoiceAgentResult>;
  voiceAgentTranscribe(audio: Float32Array | Uint8Array): Promise<string>;
  voiceAgentGenerateResponse(prompt: string): Promise<string>;
  voiceAgentSynthesizeSpeech(text: string): Promise<Float32Array>;
  cleanupVoiceAgent(): Promise<void> | void;
  getVoiceAgentStream?(): VoiceAgentStreamSource | null;
}

let _provider: VoiceAgentProvider | null = null;

export function setVoiceAgentProvider(provider: VoiceAgentProvider | null): void {
  _provider = provider;
}

export function createVoiceAgentHandleProvider(
  source: Extract<VoiceAgentStreamSource, { handle: number }>,
): VoiceAgentProvider {
  assertNativeHandle(source.handle, 'VoiceAgent.createHandleProvider');
  return new NativeVoiceAgentHandleProvider(source.handle, source.module);
}

export function setVoiceAgentHandle(
  handle: number,
  module: EmscriptenRunanywhereModule,
): void {
  assertNativeHandle(handle, 'VoiceAgent.setHandle');
  _provider = createVoiceAgentHandleProvider({ handle, module });
}

function activeProvider(): VoiceAgentProvider | null {
  return _provider;
}

export function getVoiceAgentAvailability(): VoiceAgentAvailability {
  if (_provider) {
    return {
      available: true,
      source: _provider.providerKind === 'wasm-handle' ? 'wasm-handle' : 'provider',
      reason: _provider.providerKind === 'wasm-handle'
        ? 'Native voice-agent handle registered.'
        : 'Voice-agent provider registered.',
      missingExports: [],
      hasHandle: _provider.providerKind === 'wasm-handle',
    };
  }

  const adapter = VoiceAgentProtoAdapter.tryDefault();
  if (!adapter) {
    return {
      available: false,
      source: 'unavailable',
      reason: 'No voice-agent provider or native handle is registered.',
      missingExports: [],
      hasHandle: false,
    };
  }

  const missingExports = adapter.missingVoiceAgentExports();
  if (missingExports.length > 0) {
    return {
      available: false,
      source: 'unavailable',
      reason: 'Voice agent is unavailable in this Web WASM build because native voice-agent exports are missing.',
      missingExports,
      hasHandle: false,
    };
  }

  return {
    available: false,
    source: 'wasm-exports',
    reason: 'Native voice-agent exports are present, but no voice-agent handle/provider is registered.',
    missingExports: [],
    hasHandle: false,
  };
}

export function isVoiceAgentAvailable(): boolean {
  return getVoiceAgentAvailability().available;
}

function requireProvider(feature: string): VoiceAgentProvider {
  const provider = activeProvider();
  if (provider) return provider;
  const availability = getVoiceAgentAvailability();
  throw SDKException.backendNotAvailable(
    feature,
    `${availability.reason}${availability.missingExports.length > 0
      ? ` Missing exports: ${availability.missingExports.join(', ')}.`
      : ''}`,
  );
}

/** Default Silero VAD model id seeded by every example app's catalog. */
export const defaultVADModelID = 'silero-vad';

/**
 * Ensure a VAD model is loaded in the canonical lifecycle before a voice-agent
 * session starts. When no VAD model is currently registered for
 * `MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION`, attempts to load the catalogued
 * default (`defaultVADModelID`, Silero) so the voice agent's speech-start /
 * speech-end events fire. The energy-based fallback does not produce the
 * lifecycle events the voice-agent orchestrator listens for, so without a VAD
 * lifecycle load the session stays silent after init.
 *
 * Idempotent: returns `true` immediately when a VAD model is already loaded.
 * Logs (but does not throw) when the optional auto-load fails; callers may
 * inspect the return value to decide whether to surface a warning.
 *
 * @param modelID VAD model id to auto-load when none is current. Defaults to
 *   `defaultVADModelID`.
 * @returns `true` when a VAD model is loaded after the call; `false` when no
 *   VAD model is loaded (auto-load failed or skipped).
 */
export async function ensureDefaultVAD(modelID?: string): Promise<boolean> {
  const current = WebModelLifecycle.currentModel({
    category: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
    includeModelMetadata: false,
  });
  if (current?.modelId) return true;

  const targetID = modelID ?? defaultVADModelID;
  if (!targetID) return false;

  logger.info(`Auto-loading default VAD '${targetID}' for voice-agent session`);

  try {
    const result = await WebModelLifecycle.loadModelAsync({
      modelId: targetID,
      category: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
      forceReload: false,
      validateAvailability: false,
    });
    if (!result?.success) {
      logger.warning(
        `Default VAD '${targetID}' auto-load failed: ${result?.errorMessage ?? 'unknown error'} — voice agent will use energy fallback`,
      );
      return false;
    }
    return true;
  } catch (err) {
    logger.warning(
      `Default VAD '${targetID}' auto-load threw: ${err instanceof Error ? err.message : String(err)} — voice agent will use energy fallback`,
    );
    return false;
  }
}

class NativeVoiceAgentHandleProvider implements VoiceAgentProvider {
  readonly providerKind = 'wasm-handle' as const;
  private readonly adapter: VoiceAgentProtoAdapter;

  constructor(
    private readonly handle: number,
    private readonly module: EmscriptenRunanywhereModule,
  ) {
    assertNativeHandle(handle, 'VoiceAgent.nativeProvider');
    this.adapter = new VoiceAgentProtoAdapter(module as unknown as ModalityProtoModule);
  }

  async initializeVoiceAgent(config: VoiceAgentComposeConfig): Promise<void> {
    const state = this.adapter.initialize(this.handle, config);
    if (!state) {
      throw SDKException.backendNotAvailable(
        'initializeVoiceAgent',
        'Native voice-agent initialize returned no component state.',
      );
    }
  }

  async initializeVoiceAgentWithLoadedModels(ttsVoiceID?: string): Promise<void> {
    await this.initializeVoiceAgent(defaultVoiceAgentComposeConfig(ttsVoiceID));
  }

  isVoiceAgentReady(): boolean {
    return this.getVoiceAgentComponentStates().ready;
  }

  getVoiceAgentComponentStates(): VoiceAgentComponentStates {
    return this.adapter.componentStates(this.handle)
      ?? unavailableComponentStates('Native voice-agent component state is unavailable.');
  }

  async processVoiceTurn(audio: Float32Array | Uint8Array): Promise<VoiceAgentResult> {
    const result = this.adapter.processVoiceTurn(this.handle, toUint8Audio(audio));
    return result ?? unavailableVoiceAgentResult(
      'Native voice-agent processVoiceTurn returned no result.',
    );
  }

  async voiceAgentTranscribe(): Promise<string> {
    throw SDKException.backendNotAvailable(
      'voiceAgentTranscribe',
      'The native Web voice-agent handle exposes whole-turn processing, not standalone STT.',
    );
  }

  async voiceAgentGenerateResponse(): Promise<string> {
    throw SDKException.backendNotAvailable(
      'voiceAgentGenerateResponse',
      'The native Web voice-agent handle exposes whole-turn processing, not standalone LLM generation.',
    );
  }

  async voiceAgentSynthesizeSpeech(): Promise<Float32Array> {
    throw SDKException.backendNotAvailable(
      'voiceAgentSynthesizeSpeech',
      'The native Web voice-agent handle exposes whole-turn processing, not standalone TTS.',
    );
  }

  cleanupVoiceAgent(): void {
    this.adapter.destroy(this.handle);
  }

  getVoiceAgentStream(): VoiceAgentStreamSource {
    return { handle: this.handle, module: this.module };
  }
}

function defaultVoiceAgentComposeConfig(ttsVoiceID?: string): VoiceAgentComposeConfig {
  return {
    vadSampleRate: 16000,
    vadFrameLength: 0.1,
    vadEnergyThreshold: 0.005,
    wakewordEnabled: false,
    wakewordThreshold: 0.5,
    sessionId: 'web-voice-agent',
    ...(ttsVoiceID ? { ttsVoiceId: ttsVoiceID } : {}),
  };
}

function assertNativeHandle(handle: number, feature: string): number {
  if (!Number.isFinite(handle) || handle <= 0) {
    throw SDKException.backendNotAvailable(
      feature,
      'A non-zero native voice-agent handle is required.',
    );
  }
  return handle;
}

function unavailableComponentStates(reason: string): VoiceAgentComponentStates {
  return {
    sttState: ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_ERROR,
    llmState: ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_ERROR,
    ttsState: ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_ERROR,
    vadState: ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_ERROR,
    ready: false,
    anyLoading: false,
    wakewordState: ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_NOT_LOADED,
    errorMessage: reason,
  };
}

export function unavailableVoiceAgentResult(reason?: string): VoiceAgentResult {
  const message = reason ?? getVoiceAgentAvailability().reason;
  return {
    speechDetected: false,
    transcription: undefined,
    assistantResponse: undefined,
    thinkingContent: undefined,
    synthesizedAudio: undefined,
    finalState: unavailableComponentStates(message),
    synthesizedAudioSampleRateHz: 0,
    synthesizedAudioChannels: 0,
    synthesizedAudioEncoding: AudioEncoding.AUDIO_ENCODING_UNSPECIFIED,
    sessionId: '',
    turnId: createId('voice-turn-unavailable'),
    sttTimeMs: 0,
    llmTimeMs: 0,
    ttsTimeMs: 0,
    totalTimeMs: 0,
    errorMessage: message,
    errorCode: SDKErrorCode.BackendNotAvailable,
  };
}

function unavailableVoiceEvent(reason?: string): VoiceEvent {
  const message = reason ?? getVoiceAgentAvailability().reason;
  return {
    seq: 0,
    timestampUs: nowUs(),
    category: EventCategory.EVENT_CATEGORY_ERROR,
    severity: ErrorSeverity.ERROR_SEVERITY_ERROR,
    component: VoicePipelineComponent.VOICE_PIPELINE_COMPONENT_AGENT,
    error: {
      code: SDKErrorCode.BackendNotAvailable,
      message,
      component: 'voice-agent',
      isRecoverable: false,
      operation: 'streamVoiceAgent',
      detailsJson: '',
    },
    sessionId: '',
    turnId: '',
    requestId: '',
    metadata: {},
  };
}

async function* unavailableVoiceEventStream(reason?: string): AsyncIterable<VoiceEvent> {
  yield unavailableVoiceEvent(reason);
}

function toUint8Audio(audio: Float32Array | Uint8Array): Uint8Array {
  if (audio instanceof Uint8Array) return audio;
  return new Uint8Array(
    audio.buffer.slice(audio.byteOffset, audio.byteOffset + audio.byteLength),
  );
}

function nowUs(): number {
  return Math.floor(Date.now() * 1000);
}

function createId(prefix: string): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return `${prefix}-${crypto.randomUUID()}`;
  }
  return `${prefix}-${Math.random().toString(36).slice(2)}`;
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

export async function initializeVoiceAgent(config: VoiceAgentComposeConfig): Promise<void> {
  await requireProvider('initializeVoiceAgent').initializeVoiceAgent(config);
  logger.info('VoiceAgent initialized');
}

/**
 * Initialize the voice agent from currently-loaded STT / LLM / TTS models.
 *
 * When `ensureVAD` is `true` (default), the SDK guarantees that a VAD model is
 * loaded into the canonical lifecycle before initialization runs via
 * `ensureDefaultVAD(...)`. Without this the session would silently fall back to
 * the energy-based detector and the C++ voice agent's speech-start / speech-end
 * lifecycle events would not fire. Set to `false` only if the caller has
 * already loaded an explicit VAD model (or knows the energy fallback is
 * acceptable for the deployment).
 *
 * @param ttsVoiceID Optional voice id within the loaded TTS model. For
 *   multi-voice TTS engines (e.g., Sherpa-ONNX-TTS with Piper multi-speaker
 *   models), this selects which voice to use and is semantically distinct from
 *   the TTS model id. When `undefined` (the default), the engine's default
 *   voice is used — appropriate for single-voice models. Never reuse the TTS
 *   model id here — model id ≠ voice id.
 * @param ensureVAD Whether to auto-load the catalogued default VAD when no
 *   `MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION` model is loaded. Defaults to
 *   `true`.
 */
export async function initializeVoiceAgentWithLoadedModels(
  ttsVoiceID?: string,
  ensureVAD = true,
): Promise<void> {
  if (ensureVAD) {
    await ensureDefaultVAD();
  }
  await requireProvider('initializeVoiceAgentWithLoadedModels').initializeVoiceAgentWithLoadedModels(ttsVoiceID);
}

export async function isVoiceAgentReady(): Promise<boolean> {
  const provider = activeProvider();
  return provider ? Promise.resolve(provider.isVoiceAgentReady()) : false;
}

export async function getVoiceAgentComponentStates(): Promise<VoiceAgentComponentStates> {
  const provider = activeProvider();
  return provider
    ? Promise.resolve(provider.getVoiceAgentComponentStates())
    : unavailableComponentStates(getVoiceAgentAvailability().reason);
}

export async function areAllVoiceComponentsReady(): Promise<boolean> {
  return (await getVoiceAgentComponentStates()).ready;
}

export async function processVoiceTurn(
  audio: Float32Array | Uint8Array,
): Promise<VoiceAgentResult> {
  const provider = activeProvider();
  if (!provider) return unavailableVoiceAgentResult();
  return provider.processVoiceTurn(audio);
}

export async function voiceAgentTranscribe(
  audio: Float32Array | Uint8Array,
): Promise<string> {
  return requireProvider('voiceAgentTranscribe').voiceAgentTranscribe(audio);
}

export async function voiceAgentGenerateResponse(prompt: string): Promise<string> {
  return requireProvider('voiceAgentGenerateResponse').voiceAgentGenerateResponse(prompt);
}

export async function voiceAgentSynthesizeSpeech(text: string): Promise<Float32Array> {
  return requireProvider('voiceAgentSynthesizeSpeech').voiceAgentSynthesizeSpeech(text);
}

export async function cleanupVoiceAgent(): Promise<void> {
  if (!_provider) return;
  await Promise.resolve(_provider.cleanupVoiceAgent());
}

export function streamVoiceAgent(
  req: VoiceAgentRequest = {
    eventFilter: '',
    sessionId: '',
    categories: [],
    minSeverity: 0,
    replayFromSeq: 0,
    includeAudio: false,
  },
  signal?: AbortSignal,
): AsyncIterable<VoiceEvent> {
  const provider = activeProvider();
  if (!provider) return unavailableVoiceEventStream();
  if (typeof provider.getVoiceAgentStream !== 'function') {
    return unavailableVoiceEventStream(
      'Voice-agent provider does not expose a generated proto event stream.',
    );
  }
  const src = provider.getVoiceAgentStream();
  if (src == null) {
    return unavailableVoiceEventStream(
      'Voice-agent provider has not constructed a stream source yet.',
    );
  }
  if ('handle' in src && (!Number.isFinite(src.handle) || src.handle <= 0)) {
    return unavailableVoiceEventStream(
      'Voice-agent provider returned a missing native handle.',
    );
  }
  const adapter = 'transport' in src
    ? new VoiceAgentStreamAdapter(src.transport)
    : new VoiceAgentStreamAdapter(src.handle, src.module);
  const iterable = adapter.stream(req);
  if (!signal) return iterable;
  return wrapWithSignal(iterable, signal);
}

/**
 * Wraps an AsyncIterable so that when `signal` fires an abort event the
 * underlying iterator is torn down via `iterator.return?.()`. This mirrors
 * how Swift Task cancellation propagates through `AsyncStream` and how Kotlin
 * coroutine scope cancellation terminates a Flow — the iterator's `return()`
 * path triggers `HandleFanOut.detach()` which clears the C++ callback slot
 * when the last subscriber leaves.
 */
async function* wrapWithSignal(
  source: AsyncIterable<VoiceEvent>,
  signal: AbortSignal,
): AsyncIterable<VoiceEvent> {
  const iterator = source[Symbol.asyncIterator]();
  const onAbort = (): void => {
    void iterator.return?.();
  };
  signal.addEventListener('abort', onAbort);
  try {
    while (true) {
      if (signal.aborted) break;
      const { done, value } = await iterator.next();
      if (done) break;
      yield value;
    }
  } finally {
    signal.removeEventListener('abort', onAbort);
    void iterator.return?.();
  }
}

export const VoiceAgent = {
  defaultVADModelID,
  ensureDefaultVAD,
  availability: getVoiceAgentAvailability,
  isAvailable: isVoiceAgentAvailable,
  initialize: initializeVoiceAgent,
  initializeWithLoadedModels: initializeVoiceAgentWithLoadedModels,
  isReady: isVoiceAgentReady,
  getComponentStates: getVoiceAgentComponentStates,
  areAllComponentsReady: areAllVoiceComponentsReady,
  processTurn: processVoiceTurn,
  transcribe: voiceAgentTranscribe,
  generateResponse: voiceAgentGenerateResponse,
  synthesizeSpeech: voiceAgentSynthesizeSpeech,
  stream: streamVoiceAgent,
  cleanup: cleanupVoiceAgent,
};
