/**
 * VoiceAgentCTypes.ts
 *
 * C-ABI parity types for `RunAnywhere.processVoiceTurn / voiceAgentTranscribe /
 * voiceAgentGenerateResponse / voiceAgentSynthesizeSpeech`.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/VoiceAgent/VoiceAgentTypes.swift
 *
 * Note: These types are intentionally distinct from `VoicePipeline*` (TS-side
 * STT->LLM->TTS composition) and `VoiceEvent` (proto-byte stream). The voice-agent
 * verbs mirror the Swift `RunAnywhere.processVoiceTurn(audioData) -> VoiceAgentResult`
 * symmetry — i.e. a one-shot call returning all outputs.
 */

/** Component load state per the Swift `ComponentLoadState` enum. */
export type VoiceAgentComponentLoadState = 'notLoaded' | 'loading' | 'loaded' | 'failed';

/** Single component (STT/LLM/TTS) state. */
export interface VoiceAgentComponentState {
  state: VoiceAgentComponentLoadState;
  modelId?: string;
  voiceId?: string;
}

/** Aggregate voice-agent component states. Mirrors Swift `VoiceAgentComponentStates`. */
export interface VoiceAgentComponentStates {
  stt: VoiceAgentComponentState;
  llm: VoiceAgentComponentState;
  tts: VoiceAgentComponentState;
  isFullyReady: boolean;
}

/**
 * Voice agent configuration. Mirrors Swift `VoiceAgentConfiguration`.
 * On Web there is no native `rac_voice_agent_*` C-ABI yet — the runtime
 * delegates to the existing TS-side `VoicePipeline` composition over
 * STT/LLM/TTS. This config is forwarded to those component loaders.
 */
export interface VoiceAgentConfig {
  /** STT model ID (uses currently loaded model if undefined) */
  sttModelId?: string;
  /** LLM model ID (uses currently loaded model if undefined) */
  llmModelId?: string;
  /** TTS voice ID (uses currently loaded voice if undefined) */
  ttsVoice?: string;
  /** VAD sample rate (default: 16000) */
  vadSampleRate?: number;
  /** VAD frame length seconds (default: 0.1) */
  vadFrameLength?: number;
  /** VAD energy threshold (default: 0.005) */
  vadEnergyThreshold?: number;
  /** Optional language hint (e.g., 'en') */
  language?: string;
  /** Optional system prompt forwarded to the LLM step */
  systemPrompt?: string;
}

/**
 * Result of a single voice turn (audio in -> transcription -> response -> audio).
 * Mirrors Swift `VoiceAgentResult`.
 */
export interface VoiceAgentResult {
  /** Whether speech was detected in the input audio */
  speechDetected: boolean;
  /** Transcribed text from STT (undefined if no speech) */
  transcription?: string;
  /** Generated response text from LLM */
  response?: string;
  /** Thinking content (when supported) */
  thinkingContent?: string;
  /** Synthesized audio as Float32 PCM samples (TTS sample rate) */
  synthesizedAudio?: Float32Array;
  /** Sample rate of the synthesized audio */
  sampleRate?: number;
}
