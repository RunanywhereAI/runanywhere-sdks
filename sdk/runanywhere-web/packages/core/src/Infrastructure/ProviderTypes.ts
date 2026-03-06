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

import type { LLMGenerationResult } from '../types/LLMTypes';
import type { STTTranscriptionResult, STTTranscribeOptions } from '../types/STTTypes';
import type { TTSSynthesisResult, TTSSynthesizeOptions } from '../types/TTSTypes';

// ---------------------------------------------------------------------------
// Provider Capability Keys
// ---------------------------------------------------------------------------

/**
 * Typed capability keys for the provider registry.
 * Each key maps to exactly one provider interface.
 */
export type ProviderCapability = 'llm' | 'stt' | 'tts';

// ---------------------------------------------------------------------------
// Provider Interfaces
// ---------------------------------------------------------------------------

/**
 * LLM (text generation) provider — implemented by @runanywhere/web-llamacpp.
 */
export interface LLMProvider {
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
}
