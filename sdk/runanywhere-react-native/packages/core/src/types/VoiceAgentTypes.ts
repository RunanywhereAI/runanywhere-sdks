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
// '@runanywhere/proto-ts/voice_events' when they need it.

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
// VoiceAgentStreamAdapter.stream() directly.

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

// v3.1: VoiceSessionConfig / VoiceSessionEventKind / VoiceSessionErrorType
// DELETED. Use VoiceAgentConfig + VoiceEvent (ts-proto) directly via
// VoiceAgentStreamAdapter.
