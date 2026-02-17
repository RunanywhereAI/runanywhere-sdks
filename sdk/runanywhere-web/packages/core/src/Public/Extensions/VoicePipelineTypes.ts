/**
 * RunAnywhere Web SDK - VoicePipeline Types
 *
 * Types for the high-level streaming voice pipeline that orchestrates
 * STT -> LLM (streaming) -> TTS using the existing SDK extensions.
 */

import { PipelineState } from './VoiceAgentTypes';
import type { STTTranscriptionResult } from './STTTypes';
import type { LLMGenerationResult } from '../../types/LLMTypes';
import type { TTSSynthesisResult } from './TTSTypes';

export { PipelineState };

// ---------------------------------------------------------------------------
// Callbacks
// ---------------------------------------------------------------------------

/**
 * Streaming callbacks for each stage of the voice pipeline.
 *
 * All callbacks are optional — subscribe only to the stages you need
 * to update the UI.
 */
export interface VoicePipelineCallbacks {
  /** Fires when the pipeline transitions between stages. */
  onStateChange?: (state: PipelineState) => void;

  /** Fires when STT completes with the transcribed user text. */
  onTranscription?: (text: string, result: STTTranscriptionResult) => void;

  /**
   * Fires for each LLM token during streaming generation.
   * @param token - The individual new token
   * @param accumulated - The full response so far
   */
  onResponseToken?: (token: string, accumulated: string) => void;

  /** Fires when LLM generation is complete. */
  onResponseComplete?: (text: string, result: LLMGenerationResult) => void;

  /** Fires when TTS synthesis is complete with playable audio. */
  onSynthesisComplete?: (audio: Float32Array, sampleRate: number, result: TTSSynthesisResult) => void;

  /** Fires on any error during the pipeline. */
  onError?: (error: Error, stage: PipelineState) => void;
}

// ---------------------------------------------------------------------------
// Options
// ---------------------------------------------------------------------------

/** Options for a single voice pipeline turn. */
export interface VoicePipelineOptions {
  /** Max tokens for LLM generation (default: 150). */
  maxTokens?: number;

  /** LLM temperature (default: 0.7). */
  temperature?: number;

  /** System prompt for the LLM (default: conversational assistant). */
  systemPrompt?: string;

  /** TTS speech speed factor (default: 1.0). */
  ttsSpeed?: number;

  /** STT audio sample rate (default: 16000). */
  sampleRate?: number;
}

// ---------------------------------------------------------------------------
// Result
// ---------------------------------------------------------------------------

/** Result of a complete voice pipeline turn. */
export interface VoicePipelineTurnResult {
  /** Transcribed user speech. Empty string if no speech detected. */
  transcription: string;

  /** LLM response text. */
  response: string;

  /** Synthesized audio (PCM Float32 samples). */
  synthesizedAudio?: Float32Array;

  /** Audio sample rate of synthesized audio. */
  sampleRate?: number;

  /** Time in ms for each stage. */
  timing: {
    sttMs: number;
    llmMs: number;
    ttsMs: number;
    totalMs: number;
  };

  /** LLM metrics (tokens, tok/s, etc.). */
  llmResult?: LLMGenerationResult;
}
