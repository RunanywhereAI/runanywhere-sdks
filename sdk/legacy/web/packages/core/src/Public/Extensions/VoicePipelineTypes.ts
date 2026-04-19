/**
 * RunAnywhere Web SDK - VoicePipeline Types
 *
 * Types for the high-level streaming voice pipeline that orchestrates
 * STT -> LLM (streaming) -> TTS using backend extensions.
 *
 * These types use generic result shapes so the core VoicePipeline doesn't
 * need to import types from backend packages.
 */

import { PipelineState } from './VoiceAgentTypes';

export { PipelineState };

// ---------------------------------------------------------------------------
// Generic result types (match backend shapes without importing them)
// ---------------------------------------------------------------------------

/** Generic STT result shape (matches STTTranscriptionResult). */
export interface VoicePipelineSTTResult {
  text: string;
  [key: string]: unknown;
}

/** Generic LLM result shape (matches LLMGenerationResult). */
export interface VoicePipelineLLMResult {
  text: string;
  tokensUsed: number;
  tokensPerSecond: number;
  [key: string]: unknown;
}

/** Generic TTS result shape (matches TTSSynthesisResult). */
export interface VoicePipelineTTSResult {
  audioData: Float32Array;
  sampleRate: number;
  durationMs: number;
  processingTimeMs: number;
  [key: string]: unknown;
}

// ---------------------------------------------------------------------------
// Callbacks
// ---------------------------------------------------------------------------

export interface VoicePipelineCallbacks {
  onStateChange?: (state: PipelineState) => void;
  onTranscription?: (text: string, result: VoicePipelineSTTResult) => void;
  onResponseToken?: (token: string, accumulated: string) => void;
  onResponseComplete?: (text: string, result: VoicePipelineLLMResult) => void;
  onSynthesisComplete?: (audio: Float32Array, sampleRate: number, result: VoicePipelineTTSResult) => void;
  onError?: (error: Error, stage: PipelineState) => void;
}

// ---------------------------------------------------------------------------
// Options
// ---------------------------------------------------------------------------

export interface VoicePipelineOptions {
  maxTokens?: number;
  temperature?: number;
  systemPrompt?: string;
  ttsSpeed?: number;
  sampleRate?: number;
}

// ---------------------------------------------------------------------------
// Result
// ---------------------------------------------------------------------------

export interface VoicePipelineTurnResult {
  transcription: string;
  response: string;
  synthesizedAudio?: Float32Array;
  sampleRate?: number;
  timing: {
    sttMs: number;
    llmMs: number;
    ttsMs: number;
    totalMs: number;
  };
  llmResult?: VoicePipelineLLMResult;
}
