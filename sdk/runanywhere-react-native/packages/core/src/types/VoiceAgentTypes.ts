/**
 * VoiceAgentTypes.ts
 *
 * Type definitions for Voice Agent functionality.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VoiceAgent/
 */

// v3.1: proto imports removed — legacy mapper helpers that used them
// (voiceSessionEventFromProto / voiceSessionEventKindFromProto) were
// deleted. Consumers import VoiceEvent directly from
// '../generated/voice_events' when they need it.

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

// v3.1: VoiceSessionEvent / VoiceSessionEventType interface +
// voiceSessionEventFromProto + voiceSessionEventKindFromProto mappers +
// VoiceSessionCallback DELETED. Use VoiceEvent (ts-proto) via
// VoiceAgentStreamAdapter.stream() directly. See
// docs/migrations/VoiceSessionEvent.md for the canonical migration.

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

// v3.1: VoiceSessionEventKind DELETED. Use VoiceEvent (ts-proto)
// payload.$case switch directly.

/**
 * Voice session error types
 */
export enum VoiceSessionErrorType {
  MicrophonePermissionDenied = 'microphonePermissionDenied',
  NotReady = 'notReady',
  AlreadyRunning = 'alreadyRunning',
}
