/**
 * VoiceAgentTypes.ts
 *
 * Type definitions for Voice Agent functionality.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VoiceAgent/
 */

// Proto types from the canonical ts-proto output. The mappers below
// (voiceSessionEventFromProto, voiceSessionEventKindFromProto) are
// derived views — they take a VoiceEvent and project it into the
// legacy UX-shaped enums.
import {
  PipelineState,
  VADEventType,
  VoiceEvent,
} from '../generated/voice_events';

/**
 * Component load state
 */
export type ComponentLoadState = 'notLoaded' | 'loading' | 'loaded' | 'failed';

/**
 * Individual component state
 */
export interface ComponentState {
  state: ComponentLoadState;
  modelId?: string;
  voiceId?: string;
}

/**
 * Voice agent component states
 */
export interface VoiceAgentComponentStates {
  stt: ComponentState;
  llm: ComponentState;
  tts: ComponentState;
  isFullyReady: boolean;
}

/**
 * Voice agent configuration
 */
export interface VoiceAgentConfig {
  /** STT model ID */
  sttModelId?: string;

  /** LLM model ID */
  llmModelId?: string;

  /** TTS voice ID */
  ttsVoiceId?: string;

  /** VAD sample rate (default: 16000) */
  vadSampleRate?: number;

  /** VAD frame length (default: 512) */
  vadFrameLength?: number;

  /** VAD energy threshold (default: 0.1) */
  vadEnergyThreshold?: number;

  /** Language code (e.g., 'en') */
  language?: string;

  /** System prompt for LLM */
  systemPrompt?: string;
}

/**
 * Voice turn result
 */
export interface VoiceTurnResult {
  /** Whether speech was detected */
  speechDetected: boolean;

  /** Transcribed text from audio */
  transcription: string;

  /** Generated response text */
  response: string;

  /** Base64-encoded synthesized audio */
  synthesizedAudio?: string;

  /** Audio sample rate */
  sampleRate: number;
}

/**
 * Voice session event types
 */
export type VoiceSessionEventType =
  | 'started'
  | 'speechDetected'
  | 'transcriptionComplete'
  | 'responseGenerated'
  | 'speechSynthesized'
  | 'turnComplete'
  | 'error'
  | 'ended';

/**
 * Voice session event.
 *
 * **v2.1-1 deprecation (GAP 09 #6)**: This interface is now a *derived
 * view* over the canonical `VoiceEvent` proto (ts-proto codegen from
 * `idl/voice_events.proto`). The codegen'd type is the single source
 * of truth; this UX-shaped interface is kept as a backward-compat
 * shim.
 *
 * New code should subscribe to `VoiceAgentStreamAdapter.stream()` and
 * switch on `event.payload.oneofKind` directly.
 *
 * See `docs/migrations/VoiceSessionEvent.md` for the 10-case →
 * 8-payload mapping table, dropout list, and migration guide.
 *
 * @deprecated v2.1-1: Use the codegen'd `VoiceEvent` proto via
 *   `VoiceAgentStreamAdapter.stream()`. This UX-shaped interface is
 *   a derived view — see docs/migrations/VoiceSessionEvent.md.
 */
export interface VoiceSessionEvent {
  type: VoiceSessionEventType;
  timestamp: number;
  data?: {
    transcription?: string;
    response?: string;
    audio?: string;
    error?: string;
  };
}

/**
 * Derive a {@link VoiceSessionEvent} from the canonical `VoiceEvent`
 * (proto3 via ts-proto, generated from `idl/voice_events.proto`).
 *
 * Returns `null` for proto events that don't have a UX-visible
 * counterpart — see `docs/migrations/VoiceSessionEvent.md` for the
 * full dropout list (metrics, interrupted, low-level VAD BARGE_IN/
 * SILENCE, state=THINKING).
 *
 * v3-readiness Phase A7: ported 1:1 from the Swift template at
 * `sdk/runanywhere-swift/.../VoiceAgentTypes.swift`
 * `VoiceSessionEvent.from(_:)`.
 *
 * Note on RN-vs-Swift shape divergence: this SDK's `VoiceSessionEvent`
 * is a flat `{ type, timestamp, data }` interface (legacy RN style),
 * not the 10-case discriminated union Swift/Kotlin/Dart use. The
 * mapping therefore maps to the RN-specific `VoiceSessionEventType`
 * values:
 *   userSaid         → 'transcriptionComplete'
 *   assistantToken   → 'responseGenerated'
 *   audio            → 'speechSynthesized'
 *   vad VOICE_START  → 'speechDetected'
 *   state IDLE       → 'started'
 *   state STOPPED    → 'ended'
 *   error            → 'error'
 *   others           → null
 *
 * Use {@link voiceSessionEventKindFromProto} if you want the richer
 * `VoiceSessionEventKind` discriminated-union shape that matches Swift.
 *
 * @deprecated v2.1-1: Use the codegen'd `VoiceEvent` proto directly.
 */
export function voiceSessionEventFromProto(
  event: VoiceEvent,
): VoiceSessionEvent | null {
  const timestamp =
    typeof event.timestampUs === 'number' && event.timestampUs > 0
      ? Math.floor(event.timestampUs / 1000)
      : Date.now();

  if (event.userSaid !== undefined) {
    return {
      type: 'transcriptionComplete',
      timestamp,
      data: { transcription: event.userSaid.text },
    };
  }
  if (event.assistantToken !== undefined) {
    return {
      type: 'responseGenerated',
      timestamp,
      data: { response: event.assistantToken.text },
    };
  }
  if (event.audio !== undefined) {
    return { type: 'speechSynthesized', timestamp };
  }
  if (event.vad !== undefined) {
    if (event.vad.type === VADEventType.VAD_EVENT_VOICE_START) {
      return { type: 'speechDetected', timestamp };
    }
    // VOICE_END_OF_UTTERANCE, BARGE_IN, SILENCE, UNSPECIFIED have no
    // UX counterpart in this flat interface.
    return null;
  }
  if (event.state !== undefined) {
    if (event.state.current === PipelineState.PIPELINE_STATE_IDLE) {
      return { type: 'started', timestamp };
    }
    if (event.state.current === PipelineState.PIPELINE_STATE_STOPPED) {
      return { type: 'ended', timestamp };
    }
    // LISTENING, SPEAKING, THINKING have no counterpart in this flat
    // interface (use voiceSessionEventKindFromProto instead).
    return null;
  }
  if (event.error !== undefined) {
    return {
      type: 'error',
      timestamp,
      data: { error: event.error.message },
    };
  }
  // interrupted, metrics, or no-payload → null.
  return null;
}

/**
 * Derive the richer {@link VoiceSessionEventKind} discriminated-union
 * from the canonical `VoiceEvent` proto.
 *
 * Unlike {@link voiceSessionEventFromProto} (which maps to the flat
 * legacy interface), this variant matches the 10-case shape Swift +
 * Kotlin + Dart all use so cross-SDK consumers can share the same
 * exhaustive-switch pattern.
 *
 * @deprecated v2.1-1: Use the codegen'd `VoiceEvent` proto directly.
 */
export function voiceSessionEventKindFromProto(
  event: VoiceEvent,
): VoiceSessionEventKind | null {
  if (event.userSaid !== undefined) {
    return { type: 'transcribed', text: event.userSaid.text };
  }
  if (event.assistantToken !== undefined) {
    return { type: 'responded', text: event.assistantToken.text };
  }
  if (event.audio !== undefined) {
    return { type: 'speaking' };
  }
  if (event.vad !== undefined) {
    if (event.vad.type === VADEventType.VAD_EVENT_VOICE_START) {
      return { type: 'speechStarted' };
    }
    if (event.vad.type === VADEventType.VAD_EVENT_VOICE_END_OF_UTTERANCE) {
      return { type: 'processing' };
    }
    return null; // BARGE_IN, SILENCE, UNSPECIFIED
  }
  if (event.state !== undefined) {
    switch (event.state.current) {
      case PipelineState.PIPELINE_STATE_IDLE:
        return { type: 'started' };
      case PipelineState.PIPELINE_STATE_LISTENING:
        return { type: 'listening', audioLevel: 0 };
      case PipelineState.PIPELINE_STATE_SPEAKING:
        return { type: 'speaking' };
      case PipelineState.PIPELINE_STATE_STOPPED:
        return { type: 'stopped' };
      default:
        return null; // THINKING, UNSPECIFIED
    }
  }
  if (event.error !== undefined) {
    return { type: 'error', message: event.error.message };
  }
  // interrupted, metrics, or no-payload → null. The 'turnCompleted'
  // kind is intentionally unreachable here — it aggregates multiple
  // proto events across a turn and cannot be derived from a single
  // VoiceEvent.
  return null;
}

/**
 * Voice session callback
 */
export type VoiceSessionCallback = (event: VoiceSessionEvent) => void;

/**
 * Voice agent metrics
 */
export interface VoiceAgentMetrics {
  /** Time for STT processing (ms) */
  sttLatencyMs: number;

  /** Time for LLM generation (ms) */
  llmLatencyMs: number;

  /** Time for TTS synthesis (ms) */
  ttsLatencyMs: number;

  /** Total turn latency (ms) */
  totalLatencyMs: number;

  /** Number of tokens generated */
  tokensGenerated: number;

  /** Audio duration (seconds) */
  audioDurationSeconds: number;
}

/**
 * Voice session configuration (matches Swift VoiceSessionConfig)
 */
export interface VoiceSessionConfig {
  /** Silence duration (seconds) before processing speech (default: 1.5) */
  silenceDuration?: number;

  /** Minimum audio level to detect speech (0.0 - 1.0, default: 0.1) */
  speechThreshold?: number;

  /** Whether to auto-play TTS response (default: true) */
  autoPlayTTS?: boolean;

  /** Whether to auto-resume listening after TTS playback (default: true) */
  continuousMode?: boolean;

  /** Language code (default: 'en') */
  language?: string;

  /** System prompt for LLM */
  systemPrompt?: string;
}

/**
 * Voice session events (matches Swift VoiceSessionEvent).
 *
 * @deprecated v2.1-1: derived view over the canonical `VoiceEvent`
 *   proto. Use `VoiceAgentStreamAdapter.stream()` and switch on
 *   `event.payload.oneofKind` directly. See
 *   `docs/migrations/VoiceSessionEvent.md`.
 *
 * Per-kind proto mapping (closes GAP 09 #6):
 *   'started'       ← VoiceEvent.state { current: IDLE }
 *   'listening'     ← VoiceEvent.state { current: LISTENING } (audioLevel 0)
 *   'speechStarted' ← VoiceEvent.vad { type: VOICE_START }
 *   'processing'    ← VoiceEvent.vad { type: VOICE_END_OF_UTTERANCE }
 *   'transcribed'   ← VoiceEvent.userSaid { text }
 *   'responded'     ← VoiceEvent.assistantToken { text }
 *   'speaking'      ← VoiceEvent.audio { pcm, ... }
 *   'turnCompleted' ← CANNOT be derived (aggregates multiple events)
 *   'stopped'       ← VoiceEvent.state { current: STOPPED }
 *   'error'         ← VoiceEvent.error { message }
 */
export type VoiceSessionEventKind =
  | { type: 'started' }
  | { type: 'listening'; audioLevel: number }
  | { type: 'speechStarted' }
  | { type: 'processing' }
  | { type: 'transcribed'; text: string }
  | { type: 'responded'; text: string }
  | { type: 'speaking' }
  | { type: 'turnCompleted'; transcript: string; response: string; audio?: string }
  | { type: 'stopped' }
  | { type: 'error'; message: string };

/**
 * Voice session error types
 */
export enum VoiceSessionErrorType {
  MicrophonePermissionDenied = 'microphonePermissionDenied',
  NotReady = 'notReady',
  AlreadyRunning = 'alreadyRunning',
}
