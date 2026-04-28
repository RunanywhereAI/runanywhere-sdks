/**
 * Typed provider interfaces for cross-package communication.
 *
 * Backend packages (@runanywhere/web-llamacpp, @runanywhere/web-onnx) implement
 * these interfaces and register instances via `ExtensionPoint.registerProvider()`.
 * Core code (e.g. VoicePipeline) retrieves them at runtime via
 * `ExtensionPoint.getProvider()` with full compile-time type safety.
 *
 * All referenced types (LLMGenerationResult, STTTranscriptionResult, etc.)
 * are defined in core so providers return properly typed results.
 */

import type { LLMGenerationOptions, LLMGenerationResult } from '@runanywhere/proto-ts/llm_options';
import type {
  STTTranscriptionResult,
  STTTranscribeOptions,
  TTSSynthesisResult,
  TTSSynthesizeOptions,
  SpeechActivityCallback,
} from '../types/index';

// ---------------------------------------------------------------------------
// Provider Capability Keys
// ---------------------------------------------------------------------------

/**
 * Typed capability keys for the provider registry.
 * Each key maps to exactly one provider interface.
 */
export type ProviderCapability = 'llm' | 'stt' | 'tts' | 'vad';

// ---------------------------------------------------------------------------
// Provider Interfaces
// ---------------------------------------------------------------------------

/**
 * LLM (text generation) provider — implemented by @runanywhere/web-llamacpp.
 */
export interface LLMProvider {
  generate?(
    prompt: string,
    options?: Partial<LLMGenerationOptions>,
  ): Promise<LLMGenerationResult>;
  generateStream(
    prompt: string,
    options?: {
      maxTokens?: number;
      temperature?: number;
      systemPrompt?: string;
    },
  ): Promise<{
    stream: AsyncIterable<string>;
    result: Promise<LLMGenerationResult>;
    cancel: () => void;
  }>;
}

/**
 * STT (speech-to-text) provider — implemented by @runanywhere/web-onnx.
 */
export interface STTProvider {
  transcribe(
    audio: Float32Array,
    options?: STTTranscribeOptions,
  ): Promise<STTTranscriptionResult>;
}

/**
 * TTS (text-to-speech) provider — implemented by @runanywhere/web-onnx.
 */
export interface TTSProvider {
  synthesize(
    text: string,
    options?: TTSSynthesizeOptions,
  ): Promise<TTSSynthesisResult>;
}

/**
 * VAD (voice activity detection) provider — implemented by @runanywhere/web-onnx.
 * Top-level `RunAnywhere.detectSpeech(...)` / `setVADCallback(...)` /
 * `startVAD()` / `stopVAD()` / `cleanupVAD()` dispatch through this provider.
 */
export interface VADProvider {
  /** Whether the underlying VAD model has been loaded. */
  readonly isInitialized: boolean;
  processSamples(samples: Float32Array): boolean;
  onSpeechActivity(callback: SpeechActivityCallback): () => void;
  reset(): void;
  cleanup(): void;
}

// ---------------------------------------------------------------------------
// Provider Type Map (capability key → interface)
// ---------------------------------------------------------------------------

/**
 * Maps each `ProviderCapability` string to its corresponding interface.
 * Used by `registerProvider` / `getProvider` for compile-time type safety.
 */
export interface ProviderMap {
  llm: LLMProvider;
  stt: STTProvider;
  tts: TTSProvider;
  vad: VADProvider;
}
