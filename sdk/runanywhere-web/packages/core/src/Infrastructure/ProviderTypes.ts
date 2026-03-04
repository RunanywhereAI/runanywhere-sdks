/**
 * Typed provider interfaces for cross-package communication.
 *
 * Backend packages (@runanywhere/web-llamacpp, @runanywhere/web-onnx) implement
 * these interfaces and register instances via `ExtensionPoint.registerProvider()`.
 * Core code (e.g. VoicePipeline) retrieves them at runtime via
 * `ExtensionPoint.getProvider()` with full compile-time type safety.
 *
 * Replaces the previous implicit `globalThis.__runanywhere_*` contract.
 * See: https://github.com/RunanywhereAI/runanywhere-sdks/issues/371
 */

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
 *
 * Only the subset of the TextGeneration API that cross-package consumers
 * (e.g. VoicePipeline) depend on. Backend packages may expose additional
 * methods beyond this interface.
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
    result: Promise<{
      text: string;
      tokensUsed: number;
      tokensPerSecond: number;
      [key: string]: unknown;
    }>;
    cancel: () => void;
  }>;
}

/**
 * STT (speech-to-text) provider — implemented by @runanywhere/web-onnx.
 *
 * Only the subset of the STT API that cross-package consumers depend on.
 */
export interface STTProvider {
  transcribe(
    audio: Float32Array,
    options?: { sampleRate?: number },
  ): Promise<{
    text: string;
    [key: string]: unknown;
  }>;
}

/**
 * TTS (text-to-speech) provider — implemented by @runanywhere/web-onnx.
 *
 * Only the subset of the TTS API that cross-package consumers depend on.
 */
export interface TTSProvider {
  synthesize(
    text: string,
    options?: { speed?: number },
  ): Promise<{
    audioData: Float32Array;
    sampleRate: number;
    durationMs: number;
    processingTimeMs: number;
    [key: string]: unknown;
  }>;
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
