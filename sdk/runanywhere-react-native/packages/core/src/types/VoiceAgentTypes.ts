/**
 * VoiceAgentTypes.ts
 *
 * Type definitions for Voice Agent functionality.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VoiceAgent/
 */

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
 * full dropout list (metrics, interrupted, low-level VAD, state=thinking).
 *
 * **v2.1-1 SCAFFOLD**: parameter type is `unknown` (not `VoiceEvent`)
 * because importing the generated proto type here would couple this
 * public-API file to the codegen output layout. The v2.1-1d per-SDK
 * cleanup PR tightens the parameter type when it implements the mapper
 * body. Today this returns null for every input; new code should use
 * the proto stream directly via `VoiceAgentStreamAdapter.stream()`.
 *
 * @deprecated v2.1-1: Use the codegen'd `VoiceEvent` proto directly.
 */
// eslint-disable-next-line @typescript-eslint/no-unused-vars
export function voiceSessionEventFromProto(event: unknown): VoiceSessionEvent | null {
  // TODO(v2.1-1d): implement per the Swift template at
  // sdk/runanywhere-swift/.../VoiceAgentTypes.swift
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
