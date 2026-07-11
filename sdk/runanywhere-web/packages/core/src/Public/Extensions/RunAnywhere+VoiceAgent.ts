/**
 * RunAnywhere+VoiceAgent.ts
 *
 * Public voice-agent facade. Web owns browser audio capture/playback in
 * adapters; voice-agent request/result/event orchestration is provider- or
 * native-handle-backed and flows through generated proto models.
 */

import {
  ProtoErrorCategory,
  ProtoErrorCode,
  ProtoErrorSeverity,
  SDKException,
} from '../../Foundation/SDKException.js';
import { SDKLogger } from '../../Foundation/SDKLogger.js';
import {
  AudioFormat,
  ModelCategory,
} from '@runanywhere/proto-ts/model_types';
import {
  ComponentLifecycleState,
  EventCategory,
} from '@runanywhere/proto-ts/component_types';
import { ErrorSeverity } from '@runanywhere/proto-ts/errors';
import { WebModelLifecycle } from './RunAnywhere+ModelLifecycle.js';
import { STT, transcribe } from './RunAnywhere+STT.js';
import { TTS, synthesize } from './RunAnywhere+TTS.js';
import { TextGeneration } from './RunAnywhere+TextGeneration.js';
import { VAD } from './RunAnywhere+VAD.js';
import {
  VoiceAgentProtoAdapter,
  type ModalityProtoModule,
} from '../../Adapters/ModalityProtoAdapter.js';
import { VoiceAgentStreamAdapter } from '../../Adapters/VoiceAgentStreamAdapter.js';
import type { VoiceAgentStreamTransport } from '@runanywhere/proto-ts/streams/voice_agent_service_stream';
import type {
  VoiceAgentComposeConfig,
  VoiceAgentRequest,
  VoiceAgentResult,
} from '@runanywhere/proto-ts/voice_agent_service';
import {
  AudioEncoding,
  PipelineState,
  TokenKind,
  VoicePipelineComponent,
  type VoiceAgentComponentStates,
  type VoiceEvent,
} from '@runanywhere/proto-ts/voice_events';
import { VADStreamEventKind } from '@runanywhere/proto-ts/vad_options';
import {
  ChatMessageStatus,
  MessageRole,
  type ChatMessage,
} from '@runanywhere/proto-ts/chat';
import type { EmscriptenRunanywhereModule } from '../../runtime/EmscriptenModule.js';

const logger = new SDKLogger('VoiceAgent');
const VOICE_SYSTEM_PROMPT =
  'You are a helpful voice assistant. Respond in one or two short, natural, spoken sentences. ' +
  'Be direct, warm, and conversational. Do not use markdown, bullet points, code blocks, or emoji. ' +
  'If you are unsure or lack the information, say so briefly instead of guessing.';
const VOICE_MAX_TOKENS = 200;
const VOICE_MAX_HISTORY_ENTRIES = 20;

export type VoiceAgentAvailabilitySource =
  | 'provider'
  | 'cross-wasm'
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
  readonly providerKind?: 'custom' | 'cross-wasm' | 'wasm-handle';
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
  if (!_provider && supportsCrossWasmVoiceAgent()) {
    _provider = new CrossWasmVoiceAgentProvider();
  }
  return _provider;
}

export function getVoiceAgentAvailability(): VoiceAgentAvailability {
  const provider = activeProvider();
  if (provider) {
    const source = provider.providerKind === 'wasm-handle'
      ? 'wasm-handle'
      : provider.providerKind === 'cross-wasm'
        ? 'cross-wasm'
        : 'provider';
    return {
      available: true,
      source,
      reason: source === 'wasm-handle'
        ? 'Native voice-agent handle registered.'
        : source === 'cross-wasm'
          ? 'Web cross-WASM STT, LLM, and TTS provider registered.'
          : 'Voice-agent provider registered.',
      missingExports: [],
      hasHandle: source === 'wasm-handle',
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
    // Swift parity (RunAnywhere+VoiceAgent.swift:114-165): the C++ lifecycle
    // service is the canonical source of truth for "is this modality loaded".
    // Query it per category, throw modelNotLoaded listing the missing
    // components, and pin the loaded model ids on the compose config.
    const sttModelID = loadedModelID(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION);
    const llmModelID = loadedModelID(ModelCategory.MODEL_CATEGORY_LANGUAGE);
    const ttsModelID = loadedModelID(ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS);

    const missing: string[] = [];
    if (!sttModelID) missing.push('STT');
    if (!llmModelID) missing.push('LLM');
    if (!ttsModelID) missing.push('TTS');
    if (missing.length > 0) {
      throw modelNotLoadedException(
        `Cannot initialize voice agent: Models not loaded: ${missing.join(', ')}`,
      );
    }

    // ttsVoiceID is the voice id *within* the loaded TTS model, NOT the model
    // id — defaultVoiceAgentComposeConfig only sets it when supplied, matching
    // Swift's `if let voiceID = ttsVoiceID, !voiceID.isEmpty`.
    await this.initializeVoiceAgent({
      ...defaultVoiceAgentComposeConfig(ttsVoiceID),
      sttModelId: sttModelID,
      llmModelId: llmModelID,
    });
  }

  isVoiceAgentReady(): boolean {
    return this.getVoiceAgentComponentStates().ready;
  }

  getVoiceAgentComponentStates(): VoiceAgentComponentStates {
    const states = this.adapter.componentStates(this.handle);
    if (!states) {
      // Swift parity: CppBridge.VoiceAgent.componentStatesProto throws —
      // no synthetic error-shaped result.
      throw SDKException.backendNotAvailable(
        'getVoiceAgentComponentStates',
        'Native voice-agent component state is unavailable.',
      );
    }
    return states;
  }

  async processVoiceTurn(audio: Float32Array | Uint8Array): Promise<VoiceAgentResult> {
    const result = this.adapter.processVoiceTurn(this.handle, toUint8Audio(audio));
    if (!result) {
      // Swift parity: processVoiceTurnProto throws — no synthetic result.
      throw SDKException.backendNotAvailable(
        'processVoiceTurn',
        'Native voice-agent processVoiceTurn returned no result.',
      );
    }
    return result;
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

/**
 * Browser provider for the split-WASM architecture.
 *
 * Llama.cpp and ONNX/Sherpa intentionally live in separate Emscripten
 * modules, so neither module's private C++ registry can compose a native
 * voice-agent handle that sees all three primitives. This provider keeps the
 * public one-call VoiceAgent contract while routing STT and TTS to the speech
 * module and LLM generation to the llama module. The orchestration belongs in
 * the Web SDK (the lowest layer that can see both WASM instances), not in the
 * example app.
 */
class CrossWasmVoiceAgentProvider implements VoiceAgentProvider {
  readonly providerKind = 'cross-wasm' as const;

  private initialized = false;
  private config: VoiceAgentComposeConfig = defaultVoiceAgentComposeConfig();
  private transport = new LocalVoiceAgentTransport();
  private seq = 0;
  private pipelineState = PipelineState.PIPELINE_STATE_IDLE;
  private lifecycleVersion = 0;
  private conversationHistory: Array<{ user: string; assistant: string }> = [];

  async initializeVoiceAgent(config: VoiceAgentComposeConfig): Promise<void> {
    if (!supportsCrossWasmVoiceAgent()) {
      throw SDKException.backendNotAvailable(
        'initializeVoiceAgent',
        'The Web voice agent requires registered STT, LLM, and TTS WASM backends.',
      );
    }
    this.lifecycleVersion += 1;
    this.transport.complete();
    this.transport = new LocalVoiceAgentTransport();
    this.config = { ...defaultVoiceAgentComposeConfig(), ...config };
    this.conversationHistory = [];
    this.initialized = true;
    this.pipelineState = PipelineState.PIPELINE_STATE_IDLE;
    this.emitState(PipelineState.PIPELINE_STATE_LISTENING);
    logger.info('Cross-WASM Web voice agent initialized');
  }

  async initializeVoiceAgentWithLoadedModels(ttsVoiceID?: string): Promise<void> {
    const sttModelID = loadedModelID(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION);
    const llmModelID = loadedModelID(ModelCategory.MODEL_CATEGORY_LANGUAGE);
    const ttsModelID = loadedModelID(ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS);

    const missing: string[] = [];
    if (!sttModelID) missing.push('STT');
    if (!llmModelID) missing.push('LLM');
    if (!ttsModelID) missing.push('TTS');
    if (missing.length > 0) {
      throw modelNotLoadedException(
        `Cannot initialize voice agent: Models not loaded: ${missing.join(', ')}`,
      );
    }

    await this.initializeVoiceAgent({
      ...defaultVoiceAgentComposeConfig(ttsVoiceID),
      sttModelId: sttModelID,
      llmModelId: llmModelID,
      ttsVoiceId: ttsVoiceID || undefined,
    });
  }

  isVoiceAgentReady(): boolean {
    return this.getVoiceAgentComponentStates().ready;
  }

  getVoiceAgentComponentStates(): VoiceAgentComponentStates {
    const ready = ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_READY;
    const notLoaded = ComponentLifecycleState.COMPONENT_LIFECYCLE_STATE_NOT_LOADED;
    const sttReady = Boolean(loadedModelID(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION));
    const llmReady = Boolean(loadedModelID(ModelCategory.MODEL_CATEGORY_LANGUAGE));
    const ttsReady = Boolean(loadedModelID(ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS));
    // A model-backed VAD is preferred; energy detection remains a deliberate
    // fallback when the optional Silero model could not be initialized.
    const vadReady = this.initialized;
    return {
      sttState: sttReady ? ready : notLoaded,
      llmState: llmReady ? ready : notLoaded,
      ttsState: ttsReady ? ready : notLoaded,
      vadState: vadReady ? ready : notLoaded,
      ready: this.initialized && sttReady && llmReady && ttsReady,
      anyLoading: false,
      wakewordState: notLoaded,
      errorMessage: undefined,
    };
  }

  async processVoiceTurn(audio: Float32Array | Uint8Array): Promise<VoiceAgentResult> {
    if (!this.initialized) {
      throw SDKException.notInitialized('Voice agent not ready');
    }

    const lifecycleVersion = this.lifecycleVersion;
    const transport = this.transport;
    const config = this.config;
    const startedAt = performance.now();
    const sessionId = config.sessionId || 'web-voice-agent';
    const turnId = createTurnID();
    let sttTimeMs = 0;
    let llmTimeMs = 0;
    let ttsTimeMs = 0;

    try {
      const vad = await this.detectTurnSpeech(audio);
      if (vad.isSpeech) {
        transport.emit(this.event({
          sessionId,
          turnId,
          component: VoicePipelineComponent.VOICE_PIPELINE_COMPONENT_VAD,
          vad: {
            type: VADStreamEventKind.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY,
            frameOffsetUs: 0,
            confidence: vad.confidence,
            isSpeech: true,
            speechDurationMs: vad.durationMs,
            silenceDurationMs: 0,
            noiseFloorDb: vad.noiseFloorDb,
          },
        }));
      }

      this.emitState(
        PipelineState.PIPELINE_STATE_PROCESSING_SPEECH,
        sessionId,
        turnId,
        transport,
        lifecycleVersion,
      );
      const sttStarted = performance.now();
      const stt = await transcribe(audio, {
        languageCode: config.sessionConfig?.languageCode ?? config.defaultLanguageCode,
      });
      this.assertCurrent(lifecycleVersion);
      sttTimeMs = performance.now() - sttStarted;
      const transcription = stt.text.trim();

      if (!transcription) {
        this.emitState(
          PipelineState.PIPELINE_STATE_LISTENING,
          sessionId,
          turnId,
          transport,
          lifecycleVersion,
        );
        return voiceTurnResult({
          speechDetected: vad.isSpeech,
          sessionId,
          turnId,
          sttTimeMs,
          totalTimeMs: performance.now() - startedAt,
          finalState: this.getVoiceAgentComponentStates(),
        });
      }

      if (vad.isSpeech) {
        transport.emit(this.event({
          sessionId,
          turnId,
          component: VoicePipelineComponent.VOICE_PIPELINE_COMPONENT_VAD,
          vad: {
            type: VADStreamEventKind.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY,
            frameOffsetUs: Math.max(0, Math.round(stt.durationMs * 1000)),
            confidence: vad.confidence,
            isSpeech: false,
            speechDurationMs: vad.durationMs,
            silenceDurationMs: 0,
            noiseFloorDb: vad.noiseFloorDb,
          },
        }));
      }

      transport.emit(this.event({
        sessionId,
        turnId,
        component: VoicePipelineComponent.VOICE_PIPELINE_COMPONENT_STT,
        userSaid: {
          text: transcription,
          isFinal: true,
          confidence: stt.confidence,
          audioStartUs: 0,
          audioEndUs: Math.max(0, Math.round(stt.durationMs * 1000)),
          languageCode: stt.languageCode ?? '',
          segmentIndex: stt.segmentIndex,
        },
      }));

      this.emitState(
        PipelineState.PIPELINE_STATE_GENERATING_RESPONSE,
        sessionId,
        turnId,
        transport,
        lifecycleVersion,
      );
      const llmStarted = performance.now();
      const configuredMaxTokens = config.sessionConfig?.maxTokens ?? 0;
      const llm = await TextGeneration.generate({
        prompt: transcription,
        maxTokens: configuredMaxTokens > 0 ? configuredMaxTokens : VOICE_MAX_TOKENS,
        temperature: 0.7,
        systemPrompt: VOICE_SYSTEM_PROMPT,
        history: voiceHistoryMessages(this.conversationHistory),
        conversationId: sessionId,
        disableThinking: !(config.sessionConfig?.thinkingModeEnabled ?? false),
      });
      this.assertCurrent(lifecycleVersion);
      llmTimeMs = performance.now() - llmStarted;
      const assistantResponse = llm.text.trim();
      this.conversationHistory.push({ user: transcription, assistant: assistantResponse });
      while (this.conversationHistory.length * 2 > VOICE_MAX_HISTORY_ENTRIES) {
        this.conversationHistory.shift();
      }

      transport.emit(this.event({
        sessionId,
        turnId,
        component: VoicePipelineComponent.VOICE_PIPELINE_COMPONENT_LLM,
        assistantToken: {
          text: assistantResponse,
          isFinal: true,
          kind: TokenKind.TOKEN_KIND_ANSWER,
          tokenId: 0,
          logprob: 0,
          finishReason: llm.finishReason || 'stop',
        },
      }));

      this.emitState(
        PipelineState.PIPELINE_STATE_PLAYING_TTS,
        sessionId,
        turnId,
        transport,
        lifecycleVersion,
      );
      const ttsStarted = performance.now();
      const tts = await synthesize(assistantResponse, {
        voiceId: config.sessionConfig?.voiceId ?? config.ttsVoiceId,
        voicePath: config.ttsVoicePath,
        languageCode: config.sessionConfig?.languageCode ?? config.defaultLanguageCode ?? '',
      });
      this.assertCurrent(lifecycleVersion);
      ttsTimeMs = performance.now() - ttsStarted;
      const audioBytes = copyBytes(tts.audioData);
      const encoding = voiceAudioEncoding(tts.audioFormat);

      if (audioBytes.byteLength > 0) {
        transport.emit(this.event({
          sessionId,
          turnId,
          category: EventCategory.EVENT_CATEGORY_AUDIO,
          component: VoicePipelineComponent.VOICE_PIPELINE_COMPONENT_TTS,
          audio: {
            pcm: audioBytes,
            sampleRateHz: tts.sampleRate,
            channels: 1,
            encoding,
            isFinal: true,
            chunkIndex: tts.chunkIndex,
            durationMs: tts.durationMs,
          },
        }));
      }

      const continueListening = config.sessionConfig?.continuousMode ?? true;
      this.emitState(
        continueListening
          ? PipelineState.PIPELINE_STATE_LISTENING
          : PipelineState.PIPELINE_STATE_STOPPED,
        sessionId,
        turnId,
        transport,
        lifecycleVersion,
      );
      return voiceTurnResult({
        speechDetected: vad.isSpeech,
        transcription,
        assistantResponse,
        thinkingContent: llm.thinkingContent,
        synthesizedAudio: audioBytes,
        synthesizedAudioSampleRateHz: tts.sampleRate,
        synthesizedAudioChannels: 1,
        synthesizedAudioEncoding: encoding,
        sessionId,
        turnId,
        sttTimeMs,
        llmTimeMs,
        ttsTimeMs,
        totalTimeMs: performance.now() - startedAt,
        finalState: this.getVoiceAgentComponentStates(),
      });
    } catch (error) {
      if (error instanceof VoiceTurnCancelledError) throw error;
      const message = error instanceof Error ? error.message : String(error);
      transport.emit(this.event({
        sessionId,
        turnId,
        severity: ErrorSeverity.ERROR_SEVERITY_ERROR,
        error: {
          code: -1,
          message,
          component: 'voice-agent',
          isRecoverable: true,
          operation: 'processVoiceTurn',
          detailsJson: '',
        },
      }));
      this.emitState(
        PipelineState.PIPELINE_STATE_ERROR,
        sessionId,
        turnId,
        transport,
        lifecycleVersion,
      );
      throw error;
    }
  }

  async voiceAgentTranscribe(audio: Float32Array | Uint8Array): Promise<string> {
    return (await transcribe(audio)).text;
  }

  async voiceAgentGenerateResponse(prompt: string): Promise<string> {
    const configuredMaxTokens = this.config.sessionConfig?.maxTokens ?? 0;
    return (await TextGeneration.generate({
      prompt,
      maxTokens: configuredMaxTokens > 0 ? configuredMaxTokens : VOICE_MAX_TOKENS,
      temperature: 0.7,
      systemPrompt: VOICE_SYSTEM_PROMPT,
      history: voiceHistoryMessages(this.conversationHistory),
      conversationId: this.config.sessionId ?? 'web-voice-agent',
      disableThinking: !(this.config.sessionConfig?.thinkingModeEnabled ?? false),
    })).text;
  }

  async voiceAgentSynthesizeSpeech(text: string): Promise<Float32Array> {
    const output = await synthesize(text, {
      voiceId: this.config.ttsVoiceId,
      voicePath: this.config.ttsVoicePath,
    });
    return ttsAudioToFloat32(output.audioData, output.audioFormat);
  }

  cleanupVoiceAgent(): void {
    if (this.initialized) {
      this.emitState(PipelineState.PIPELINE_STATE_STOPPED);
    }
    this.lifecycleVersion += 1;
    this.initialized = false;
    TextGeneration.cancelGeneration();
    this.conversationHistory = [];
    this.transport.complete();
    this.pipelineState = PipelineState.PIPELINE_STATE_IDLE;
  }

  getVoiceAgentStream(): VoiceAgentStreamSource | null {
    return this.initialized ? { transport: this.transport } : null;
  }

  private async detectTurnSpeech(
    audio: Float32Array | Uint8Array,
  ): Promise<TurnVADVerdict> {
    const samples = toFloat32Audio(audio);
    const durationMs = (samples.length / (this.config.vadSampleRate || 16_000)) * 1000;
    const currentVAD = WebModelLifecycle.currentModel({
      category: ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
      includeModelMetadata: false,
    });
    if (currentVAD?.modelId && VAD.supportsLifecycleProtoVAD()) {
      try {
        const result = await VAD.detectVoiceAuto(samples, {
          modelId: currentVAD.modelId,
          threshold: this.config.vadEnergyThreshold || 0,
          minSpeechDurationMs: 100,
          minSilenceDurationMs: this.config.sessionConfig?.silenceDurationMs || 800,
          maxSpeechDurationMs: this.config.sessionConfig?.maxRecordingDurationMs || 0,
          config: {
            sampleRate: this.config.vadSampleRate || 16_000,
            frameLengthMs: Math.round((this.config.vadFrameLength || 0.1) * 1000),
            threshold: this.config.vadEnergyThreshold || 0.015,
          },
        });
        return {
          isSpeech: result.isSpeech,
          confidence: result.confidence,
          durationMs: result.durationMs || durationMs,
          noiseFloorDb: amplitudeToDb(result.energy),
        };
      } catch (error) {
        logger.warning(
          `Model-backed VAD turn check failed; using energy fallback: ${error instanceof Error ? error.message : String(error)}`,
        );
      }
    }

    const energy = rmsAudio(samples);
    const threshold = this.config.vadEnergyThreshold || 0.015;
    return {
      isSpeech: energy >= threshold,
      confidence: Math.min(1, energy / threshold),
      durationMs,
      noiseFloorDb: amplitudeToDb(energy),
    };
  }

  private assertCurrent(lifecycleVersion: number): void {
    if (!this.initialized || lifecycleVersion !== this.lifecycleVersion) {
      throw new VoiceTurnCancelledError();
    }
  }

  private emitState(
    next: PipelineState,
    sessionId = this.config.sessionId || 'web-voice-agent',
    turnId = '',
    transport = this.transport,
    lifecycleVersion = this.lifecycleVersion,
  ): void {
    if (!this.initialized || lifecycleVersion !== this.lifecycleVersion) return;
    const previous = this.pipelineState;
    this.pipelineState = next;
    transport.emit(this.event({
      sessionId,
      turnId,
      state: { previous, current: next },
    }));
  }

  private event(overrides: Partial<VoiceEvent>): VoiceEvent {
    return {
      seq: ++this.seq,
      timestampUs: Date.now() * 1000,
      category: EventCategory.EVENT_CATEGORY_VOICE_AGENT,
      severity: ErrorSeverity.ERROR_SEVERITY_INFO,
      component: VoicePipelineComponent.VOICE_PIPELINE_COMPONENT_AGENT,
      sessionId: this.config.sessionId || 'web-voice-agent',
      turnId: '',
      requestId: '',
      metadata: {},
      ...overrides,
    };
  }
}

class LocalVoiceAgentTransport implements VoiceAgentStreamTransport {
  private nextID = 0;
  private readonly subscribers = new Map<number, {
    request: VoiceAgentRequest;
    onMessage: (event: VoiceEvent) => void;
    onDone: () => void;
  }>();

  subscribe(
    request: VoiceAgentRequest,
    onMessage: (event: VoiceEvent) => void,
    _onError: (error: Error) => void,
    onDone: () => void,
  ): () => void {
    const id = ++this.nextID;
    this.subscribers.set(id, { request, onMessage, onDone });
    return () => this.subscribers.delete(id);
  }

  emit(event: VoiceEvent): void {
    for (const subscriber of this.subscribers.values()) {
      if (event.audio && !subscriber.request.includeAudio) continue;
      subscriber.onMessage(event);
    }
  }

  complete(): void {
    const current = [...this.subscribers.values()];
    this.subscribers.clear();
    for (const subscriber of current) subscriber.onDone();
  }
}

interface TurnVADVerdict {
  isSpeech: boolean;
  confidence: number;
  durationMs: number;
  noiseFloorDb: number;
}

class VoiceTurnCancelledError extends Error {
  constructor() {
    super('Voice turn cancelled because the session stopped or restarted');
    this.name = 'VoiceTurnCancelledError';
  }
}

function toFloat32Audio(audio: Float32Array | Uint8Array): Float32Array {
  if (audio instanceof Float32Array) return audio;
  const count = Math.floor(audio.byteLength / 2);
  const view = new DataView(audio.buffer, audio.byteOffset, count * 2);
  const samples = new Float32Array(count);
  for (let index = 0; index < count; index += 1) {
    samples[index] = view.getInt16(index * 2, true) / 0x8000;
  }
  return samples;
}

function rmsAudio(samples: Float32Array): number {
  if (samples.length === 0) return 0;
  let sum = 0;
  for (let index = 0; index < samples.length; index += 1) {
    const sample = samples[index] ?? 0;
    sum += sample * sample;
  }
  return Math.sqrt(sum / samples.length);
}

function amplitudeToDb(amplitude: number): number {
  return 20 * Math.log10(Math.max(amplitude, 1e-8));
}

function voiceHistoryMessages(
  turns: ReadonlyArray<{ user: string; assistant: string }>,
): ChatMessage[] {
  return turns.flatMap((turn) => [
    voiceHistoryMessage(MessageRole.MESSAGE_ROLE_USER, turn.user),
    voiceHistoryMessage(MessageRole.MESSAGE_ROLE_ASSISTANT, turn.assistant),
  ]);
}

function voiceHistoryMessage(role: MessageRole, content: string): ChatMessage {
  return {
    id: '',
    role,
    content,
    timestampUs: 0,
    toolCalls: [],
    status: ChatMessageStatus.CHAT_MESSAGE_STATUS_COMPLETE,
    metadata: {},
    attachments: [],
  };
}

function supportsCrossWasmVoiceAgent(): boolean {
  return STT.supportsLifecycleProtoSTT()
    && TTS.supportsLifecycleProtoTTS()
    && TextGeneration.supportsProtoLLM();
}

function copyBytes(bytes: Uint8Array): Uint8Array {
  const copy = new Uint8Array(bytes.byteLength);
  copy.set(bytes);
  return copy;
}

function createTurnID(): string {
  return globalThis.crypto?.randomUUID?.()
    ?? `web-turn-${Date.now()}-${Math.random().toString(16).slice(2)}`;
}

function voiceAudioEncoding(format: AudioFormat): AudioEncoding {
  if (format === AudioFormat.AUDIO_FORMAT_PCM_S16LE) {
    return AudioEncoding.AUDIO_ENCODING_PCM_S16_LE;
  }
  if (format === AudioFormat.AUDIO_FORMAT_PCM) {
    return AudioEncoding.AUDIO_ENCODING_PCM_F32_LE;
  }
  return AudioEncoding.AUDIO_ENCODING_UNSPECIFIED;
}

function ttsAudioToFloat32(bytes: Uint8Array, format: AudioFormat): Float32Array {
  if (format === AudioFormat.AUDIO_FORMAT_PCM) {
    const count = Math.floor(bytes.byteLength / 4);
    const view = new DataView(bytes.buffer, bytes.byteOffset, count * 4);
    const samples = new Float32Array(count);
    for (let i = 0; i < count; i += 1) samples[i] = view.getFloat32(i * 4, true);
    return samples;
  }
  if (format === AudioFormat.AUDIO_FORMAT_PCM_S16LE) {
    const count = Math.floor(bytes.byteLength / 2);
    const view = new DataView(bytes.buffer, bytes.byteOffset, count * 2);
    const samples = new Float32Array(count);
    for (let i = 0; i < count; i += 1) samples[i] = view.getInt16(i * 2, true) / 0x8000;
    return samples;
  }
  throw SDKException.backendNotAvailable(
    'voiceAgentSynthesizeSpeech',
    `Unsupported Web voice-agent audio format: ${format}.`,
  );
}

function voiceTurnResult(
  values: Partial<VoiceAgentResult> & Pick<VoiceAgentResult, 'speechDetected' | 'sessionId' | 'turnId'>,
): VoiceAgentResult {
  return {
    speechDetected: values.speechDetected,
    transcription: values.transcription,
    assistantResponse: values.assistantResponse,
    thinkingContent: values.thinkingContent,
    synthesizedAudio: values.synthesizedAudio,
    finalState: values.finalState,
    synthesizedAudioSampleRateHz: values.synthesizedAudioSampleRateHz ?? 0,
    synthesizedAudioChannels: values.synthesizedAudioChannels ?? 0,
    synthesizedAudioEncoding: values.synthesizedAudioEncoding
      ?? AudioEncoding.AUDIO_ENCODING_UNSPECIFIED,
    sessionId: values.sessionId,
    turnId: values.turnId,
    sttTimeMs: values.sttTimeMs ?? 0,
    llmTimeMs: values.llmTimeMs ?? 0,
    ttsTimeMs: values.ttsTimeMs ?? 0,
    totalTimeMs: values.totalTimeMs ?? 0,
    errorMessage: values.errorMessage,
    errorCode: values.errorCode ?? 0,
  };
}

/**
 * Model id currently loaded in the canonical C++ lifecycle for `category`, or
 * '' when nothing is loaded. Web's equivalent of Swift's
 * `loadedModelSnapshot(category:)` (RunAnywhere+ModelLifecycle.swift:55).
 */
function loadedModelID(category: ModelCategory): string {
  const snapshot = WebModelLifecycle.currentModel({
    category,
    includeModelMetadata: false,
  });
  return snapshot?.found ? snapshot.modelId : '';
}

/**
 * Swift parity: `SDKException(code: .modelNotLoaded, message: ..., category:
 * .component)` (RunAnywhere+VoiceAgent.swift:142-147). The category is pinned
 * to COMPONENT explicitly because the code-range table would derive MODEL.
 */
function modelNotLoadedException(message: string): SDKException {
  return new SDKException({
    category: ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
    code: ProtoErrorCode.ERROR_CODE_MODEL_NOT_LOADED,
    cAbiCode: -ProtoErrorCode.ERROR_CODE_MODEL_NOT_LOADED,
    message,
    nestedMessage: undefined,
    context: undefined,
    timestampMs: Date.now(),
    severity: ProtoErrorSeverity.ERROR_SEVERITY_ERROR,
    component: 'voice-agent',
    retryable: false,
    remediationHint: '',
    correlationId: '',
  });
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

/**
 * Swift parity: `streamVoiceAgent()` finishes the stream silently when the
 * agent is not ready (RunAnywhere+VoiceAgent.swift:213-225). The reason is
 * logged for debuggability but never synthesized into the event stream.
 */
// eslint-disable-next-line require-yield -- intentionally yields nothing: the stream must finish empty (Swift parity)
async function* emptyVoiceEventStream(reason: string): AsyncIterable<VoiceEvent> {
  logger.warning(`streamVoiceAgent finished empty: ${reason}`);
}

function toUint8Audio(audio: Float32Array | Uint8Array): Uint8Array {
  if (audio instanceof Uint8Array) return audio;
  return new Uint8Array(
    audio.buffer.slice(audio.byteOffset, audio.byteOffset + audio.byteLength),
  );
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
  // Swift parity (RunAnywhere+VoiceAgent.swift:118-122): guard isInitialized
  // first. The Web SDK exposes this via lifecycle-adapter presence — the same
  // requireInitialized pattern Embeddings uses.
  if (!WebModelLifecycle.supportsNativeLifecycle()) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_NOT_INITIALIZED,
      'SDK not initialized or no backend registered',
      'initializeVoiceAgentWithLoadedModels',
    );
  }
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
  // Swift parity (RunAnywhere+VoiceAgent.swift:177-185): throws when the SDK /
  // voice agent is not initialized instead of returning an error-shaped state.
  return requireProvider('getVoiceAgentComponentStates').getVoiceAgentComponentStates();
}

export async function areAllVoiceComponentsReady(): Promise<boolean> {
  return (await getVoiceAgentComponentStates()).ready;
}

export async function processVoiceTurn(
  audio: Float32Array | Uint8Array,
): Promise<VoiceAgentResult> {
  // Swift parity (RunAnywhere+VoiceAgent.swift:188-196): throws
  // `.notInitialized` ("Voice agent not ready") — no synthetic result.
  const provider = activeProvider();
  if (!provider) {
    throw SDKException.notInitialized('Voice agent not ready');
  }
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
  // Swift parity (RunAnywhere+VoiceAgent.swift:208-238): when the SDK or the
  // voice agent is not ready, the stream simply finishes empty — no synthetic
  // error events on the iterator.
  const provider = activeProvider();
  if (!provider) return emptyVoiceEventStream('no voice-agent provider is registered');
  if (typeof provider.getVoiceAgentStream !== 'function') {
    return emptyVoiceEventStream(
      'voice-agent provider does not expose a generated proto event stream',
    );
  }
  const src = provider.getVoiceAgentStream();
  if (src == null) {
    return emptyVoiceEventStream(
      'voice-agent provider has not constructed a stream source yet',
    );
  }
  if ('handle' in src && (!Number.isFinite(src.handle) || src.handle <= 0)) {
    return emptyVoiceEventStream(
      'voice-agent provider returned a missing native handle',
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

/** Internal constructors used by focused provider contract tests. */
export const __testing__ = {
  createCrossWasmVoiceAgentProvider: (): VoiceAgentProvider => (
    new CrossWasmVoiceAgentProvider()
  ),
};

/**
 * Public `RunAnywhere.voiceAgent.*` namespace — Web-only extensions ONLY.
 *
 * The Swift source of truth (`RunAnywhere+VoiceAgent.swift`) has no
 * `voiceAgent` namespace; its flat verbs (`initializeVoiceAgent`,
 * `initializeVoiceAgentWithLoadedModels`, `ensureDefaultVAD`,
 * `getVoiceAgentComponentStates`, `processVoiceTurn`, `streamVoiceAgent`,
 * `cleanupVoiceAgent`, `defaultVADModelID`) live directly on the
 * `RunAnywhere` facade (see RunAnywhere+FlatFacade.ts) and are the canonical
 * cross-SDK surface. Every member below is a Web-platform extension that
 * does not appear in Swift — they exist because Web voice agents are
 * provider-backed (backend packages install providers at register() time,
 * where Swift links CppBridge statically) and because providers may expose
 * standalone sub-operations the native whole-turn handle does not.
 */
export const VoiceAgent = {
  /** @webOnly Inspect provider/availability without throwing. */
  availability: getVoiceAgentAvailability,
  /** @webOnly Convenience boolean for availability checks. */
  isAvailable: isVoiceAgentAvailable,
  /** @webOnly Provider readiness probe (Swift reads CppBridge.VoiceAgent.isReady internally). */
  isReady: isVoiceAgentReady,
  /** @webOnly Aggregate readiness over the component-state snapshot. */
  areAllComponentsReady: areAllVoiceComponentsReady,
  /** @webOnly Standalone STT sub-operation on custom providers. */
  transcribe: voiceAgentTranscribe,
  /** @webOnly Standalone LLM sub-operation on custom providers. */
  generateResponse: voiceAgentGenerateResponse,
  /** @webOnly Standalone TTS sub-operation on custom providers. */
  synthesizeSpeech: voiceAgentSynthesizeSpeech,
};
