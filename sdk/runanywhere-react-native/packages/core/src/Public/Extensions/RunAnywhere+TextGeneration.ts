/**
 * RunAnywhere+TextGeneration.ts
 *
 * Text generation (LLM) extension for RunAnywhere SDK.
 * Uses backend-agnostic rac_llm_component_* C++ APIs via the core native module.
 * The actual backend (LlamaCPP, etc.) must be registered by installing
 * and importing the appropriate backend package (e.g., @runanywhere/llamacpp).
 *
 * Matches iOS: RunAnywhere+TextGeneration.swift
 */

import {
  requireNativeModule,
  isNativeModuleAvailable,
} from '../../native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import type {
  LLMGenerationOptions,
  LLMGenerationResult,
} from '@runanywhere/proto-ts/llm_options';
import {
  executionTargetToJSON,
} from '@runanywhere/proto-ts/llm_options';
import {
  LLMGenerationResult as LLMGenerationResultMessage,
} from '@runanywhere/proto-ts/llm_options';
import {
  LLMGenerateRequest,
  LLMStreamEvent,
  type LLMStreamEvent as LLMStreamEventType,
} from '@runanywhere/proto-ts/llm_service';
import { inferenceFrameworkToJSON } from '@runanywhere/proto-ts/model_types';
import { LlmThinking } from '../../Features/LLM/LlmThinking';
import {
  arrayBufferToBytes,
  bytesToArrayBuffer,
} from '../../services/ProtoBytes';

const logger = new SDKLogger('RunAnywhere.TextGeneration');

function buildLLMGenerateRequest(
  prompt: string,
  options?: LLMGenerationOptions,
  streamingEnabled: boolean = false
) {
  return LLMGenerateRequest.create({
    prompt,
    maxTokens: options?.maxTokens ?? 1000,
    temperature: options?.temperature ?? 0.7,
    topP: options?.topP ?? 1.0,
    topK: options?.topK ?? 0,
    systemPrompt: options?.systemPrompt ?? '',
    emitThoughts: !!options?.thinkingPattern,
    repetitionPenalty: options?.repetitionPenalty ?? 1.0,
    stopSequences: options?.stopSequences ?? [],
    streamingEnabled,
    preferredFramework:
      options?.preferredFramework !== undefined
        ? inferenceFrameworkToJSON(options.preferredFramework)
        : '',
    jsonSchema: options?.jsonSchema ?? options?.structuredOutput?.jsonSchema ?? '',
    executionTarget:
      options?.executionTarget !== undefined
        ? executionTargetToJSON(options.executionTarget)
        : '',
  });
}

function encodeLLMGenerateRequest(request: ReturnType<typeof buildLLMGenerateRequest>): ArrayBuffer {
  return bytesToArrayBuffer(LLMGenerateRequest.encode(request).finish());
}

function decodeLLMGenerationResult(buffer: ArrayBuffer): LLMGenerationResult {
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) {
    throw new Error('LLM proto generation returned an empty result');
  }
  return LLMGenerationResultMessage.decode(bytes);
}

// ============================================================================
// Text Generation (LLM) Extension - Backend Agnostic
// ============================================================================

/**
 * Load an LLM model by ID or path
 *
 * Matches iOS: `RunAnywhere.loadModel(_:)`
 * @throws Error if no LLM backend is registered
 */
export async function loadModel(
  modelPathOrId: string,
  config?: Record<string, unknown>
): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    logger.warning('Native module not available for loadModel');
    return false;
  }
  const native = requireNativeModule();
  return native.loadTextModel(
    modelPathOrId,
    config ? JSON.stringify(config) : undefined
  );
}

/**
 * Check if an LLM model is loaded
 * Matches iOS: `RunAnywhere.isModelLoaded`
 */
export async function isModelLoaded(): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }
  const native = requireNativeModule();
  return native.isTextModelLoaded();
}

/**
 * Unload the currently loaded LLM model
 * Matches iOS: `RunAnywhere.unloadModel()`
 */
export async function unloadModel(): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }
  const native = requireNativeModule();
  return native.unloadTextModel();
}

/**
 * Simple chat - returns just the text response
 * Matches Swift SDK: RunAnywhere.chat(_:)
 */
export async function chat(prompt: string): Promise<string> {
  const result = await generate(prompt);
  return result.text;
}

/**
 * Text generation with options and full metrics.
 * Matches Swift SDK: RunAnywhere.generate(_:options:)
 */
export async function generate(
  prompt: string,
  options?: LLMGenerationOptions
): Promise<LLMGenerationResult> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }
  const native = requireNativeModule();
  const requestBytes = encodeLLMGenerateRequest(
    buildLLMGenerateRequest(prompt, options, false)
  );
  const resultBytes = await native.llmGenerateProto(requestBytes);
  return decodeLLMGenerationResult(resultBytes);
}

/**
 * Streaming text generation — canonical cross-SDK signature.
 *
 * Returns an AsyncIterable<LLMStreamEvent> where each event carries
 * `seq`, `timestampUs`, `token`, `isFinal`, `kind`, `tokenId`, `logprob`,
 * `finishReason`, and `errorMessage` (proto `LLMStreamEvent` shape).
 *
 * Matches Swift SDK: RunAnywhere.generateStream(_:options:) and Web SDK's
 * RunAnywhere.generateStream — all 5 SDKs converge on
 * `AsyncIterable<LLMStreamEvent>` (or language-idiomatic equivalent).
 *
 * Wire-up: events are pushed by C++ via the proto-byte callback registered
 * by `LLMStreamAdapter` against the LLM handle returned by
 * `RunAnywhereCore.getLLMHandle()`.
 *
 * The native generation is kicked off lazily once the consumer starts
 * iterating; cancellation propagates back through `for-await break` →
 * `iterator.return()` → adapter unsubscribe → `cancelGeneration()`.
 */
export function generateStream(
  prompt: string,
  options?: LLMGenerationOptions,
): AsyncIterable<LLMStreamEventType> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const native = requireNativeModule();
  const requestBytes = encodeLLMGenerateRequest(
    buildLLMGenerateRequest(prompt, options, true)
  );

  return {
    [Symbol.asyncIterator](): AsyncIterator<LLMStreamEventType> {
      const queue: LLMStreamEventType[] = [];
      let resolver: ((value: IteratorResult<LLMStreamEventType>) => void) | null = null;
      let done = false;
      let started = false;
      let streamError: Error | null = null;

      const finish = (): void => {
        done = true;
        if (resolver) {
          resolver({ value: undefined as unknown as LLMStreamEventType, done: true });
          resolver = null;
        }
      };

      const start = (): void => {
        if (started) return;
        started = true;
        native
          .llmGenerateStreamProto(requestBytes, (eventBytes: ArrayBuffer) => {
            try {
              const event = LLMStreamEvent.decode(arrayBufferToBytes(eventBytes));
              if (event.errorMessage) {
                streamError = new Error(event.errorMessage);
              }
              if (resolver) {
                resolver({ value: event, done: false });
                resolver = null;
              } else {
                queue.push(event);
              }
              if (event.isFinal) finish();
            } catch (error) {
              streamError = error instanceof Error ? error : new Error(String(error));
              finish();
            }
          })
          .then(() => {
            if (!done) finish();
          })
          .catch((err: Error) => {
            streamError = err;
            logger.warning(`llmGenerateStreamProto rejected: ${err.message}`);
            finish();
          });
      };

      return {
        async next(): Promise<IteratorResult<LLMStreamEventType>> {
          start();
          if (queue.length > 0) {
            return { value: queue.shift()!, done: false };
          }
          if (streamError) throw streamError;
          if (done) {
            return { value: undefined as unknown as LLMStreamEventType, done: true };
          }
          return new Promise<IteratorResult<LLMStreamEventType>>((resolve) => {
            resolver = resolve;
          }).then((result) => {
            if (streamError) throw streamError;
            return result;
          });
        },
        async return(): Promise<IteratorResult<LLMStreamEventType>> {
          try { await native.llmCancelProto(); } catch { /* noop */ }
          finish();
          return { value: undefined as unknown as LLMStreamEventType, done: true };
        },
      };
    },
  };
}

/**
 * Cancel ongoing text generation
 */
export function cancelGeneration(): void {
  if (!isNativeModuleAvailable()) {
    return;
  }
  const native = requireNativeModule();
  void native.llmCancelProto();
}

// ============================================================================
// Introspection
// ============================================================================

/**
 * Native dispatch surface for LLM introspection. Each method is optional —
 * older bridges may not implement it.
 */
interface LLMIntrospectionNativeModule {
  getCurrentLLMModelId?: () => Promise<string>;
  currentLLMModel?: () => Promise<string>;
}

// ============================================================================
// Thinking Token Utilities (§3 — delegated to C++ rac_llm_thinking)
// ============================================================================

/** Result of extracting thinking tokens from text. */
export interface ThinkingExtractionResult {
  /** All thinking blocks extracted from the text, in order. */
  thinkingBlocks: string[];
  /** The text with all thinking blocks removed. */
  responseText: string;
}

/**
 * Extract thinking content from `text` using the shared C++ parser.
 *
 * Returns a `ThinkingExtractionResult` containing the raw thinking content
 * and the text with thinking content removed.
 *
 * Matches Swift SDK: `RunAnywhere.extractThinkingTokens(_:)`.
 */
export async function extractThinkingTokens(text: string): Promise<ThinkingExtractionResult> {
  const result = await LlmThinking.extract(text);
  return {
    thinkingBlocks: result.thinking ? [result.thinking] : [],
    responseText: result.response,
  };
}

/**
 * Remove all thinking blocks from `text` using the shared C++ parser.
 *
 * Matches Swift SDK: `RunAnywhere.stripThinkingTokens(_:)`.
 */
export async function stripThinkingTokens(text: string): Promise<string> {
  return LlmThinking.strip(text);
}

/**
 * Split `text` into a `(thinking, response)` pair using shared C++ behavior.
 *
 * Matches Swift SDK: `RunAnywhere.splitThinkingAndResponse(_:)`.
 */
export async function splitThinkingAndResponse(
  text: string
): Promise<{ thinking: string; response: string }> {
  const result = await LlmThinking.extract(text);
  return {
    thinking: result.thinking ?? '',
    response: result.response,
  };
}

// ============================================================================
// Introspection
// ============================================================================

/**
 * Get the currently loaded LLM model ID, or `null` if none is loaded.
 *
 * Matches Swift: `RunAnywhere.currentLLMModel`. RN/Web/Flutter: returns
 * `Promise<string | null>` (async getter idiom).
 */
export async function currentLLMModel(): Promise<string | null> {
  if (!isNativeModuleAvailable()) return null;
  const native = requireNativeModule() as unknown as LLMIntrospectionNativeModule;
  // Prefer the getter name used elsewhere in the bridge; fall back to the
  // alternate name for older native module shapes.
  const fn = native.currentLLMModel ?? native.getCurrentLLMModelId;
  if (!fn) return null;
  const id = await fn.call(native);
  return id && id.length > 0 ? id : null;
}
