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
import type { LLMStreamEvent } from '@runanywhere/proto-ts/llm_service';
import { LLMStreamAdapter } from '../../Adapters/LLMStreamAdapter';

const logger = new SDKLogger('RunAnywhere.TextGeneration');

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

  const optionsJson = JSON.stringify({
    max_tokens: options?.maxTokens ?? 1000,
    temperature: options?.temperature ?? 0.7,
    system_prompt: options?.systemPrompt ?? null,
  });

  const resultJson = await native.generate(prompt, optionsJson);

  try {
    const result = JSON.parse(resultJson);
    return {
      text: result.text ?? '',
      thinkingContent: result.thinkingContent,
      inputTokens: result.inputTokens ?? Math.ceil(prompt.length / 4),
      tokensGenerated: result.tokensGenerated ?? result.tokensUsed ?? 0,
      modelUsed: result.modelUsed ?? 'unknown',
      generationTimeMs: result.generationTimeMs ?? result.latencyMs ?? 0,
      ttftMs: result.ttftMs ?? result.performanceMetrics?.timeToFirstTokenMs,
      tokensPerSecond: result.tokensPerSecond ?? result.performanceMetrics?.tokensPerSecond ?? 0,
      framework: result.framework,
      finishReason: result.finishReason ?? 'stop',
      thinkingTokens: result.thinkingTokens ?? 0,
      responseTokens: result.responseTokens ?? result.tokensUsed ?? 0,
      jsonOutput: result.jsonOutput,
    };
  } catch {
    if (resultJson.includes('error')) {
      throw new Error(resultJson);
    }
    return {
      text: resultJson,
      inputTokens: 0,
      tokensGenerated: 0,
      modelUsed: 'unknown',
      generationTimeMs: 0,
      tokensPerSecond: 0,
      finishReason: 'stop',
      thinkingTokens: 0,
      responseTokens: 0,
    };
  }
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
): AsyncIterable<LLMStreamEvent> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const native = requireNativeModule();

  return {
    [Symbol.asyncIterator](): AsyncIterator<LLMStreamEvent> {
      let inner: AsyncIterator<LLMStreamEvent> | null = null;
      let kickoff: Promise<void> | null = null;
      let kickoffError: Error | null = null;

      const ensureStarted = async (): Promise<AsyncIterator<LLMStreamEvent>> => {
        if (inner) return inner;
        if (!kickoff) {
          kickoff = (async () => {
            try {
              const handle = await native.getLLMHandle();
              if (!handle || handle === 0) {
                throw new Error(
                  'LLM handle not available. Load an LLM model first via RunAnywhere.loadModel().',
                );
              }

              const adapter = new LLMStreamAdapter(handle);
              const iterable = adapter.stream({
                prompt,
                maxTokens: options?.maxTokens ?? 0,
                temperature: options?.temperature ?? 0,
                topP: options?.topP ?? 0,
                topK: options?.topK ?? 0,
                systemPrompt: options?.systemPrompt ?? '',
                emitThoughts: false,
              });
              inner = iterable[Symbol.asyncIterator]();

              // Kick the C++ generator after the callback is wired.
              const optionsJson = JSON.stringify({
                max_tokens: options?.maxTokens ?? 1000,
                temperature: options?.temperature ?? 0.7,
                top_p: options?.topP ?? undefined,
                top_k: options?.topK ?? undefined,
                system_prompt: options?.systemPrompt ?? null,
              });
              // Fire-and-forget — events flow through the proto callback.
              // Errors from the native promise propagate as stream errors via
              // the adapter's onError path (Nitro raises via the native side
              // when generation fails).
              native
                .generateStream(prompt, optionsJson, () => { /* legacy callback ignored */ })
                .catch((err: Error) => {
                  logger.warning(
                    `generateStream native promise rejected: ${err.message}`,
                  );
                });
            } catch (e) {
              kickoffError = e instanceof Error ? e : new Error(String(e));
              throw kickoffError;
            }
          })();
        }
        await kickoff;
        if (kickoffError) throw kickoffError;
        return inner!;
      };

      return {
        async next(): Promise<IteratorResult<LLMStreamEvent>> {
          const it = await ensureStarted();
          return it.next();
        },
        async return(): Promise<IteratorResult<LLMStreamEvent>> {
          // Best-effort cancellation through both the inner iterator and the
          // native generator (covers consumers who break out of for-await
          // before any token has arrived).
          try { native.cancelGeneration(); } catch { /* noop */ }
          if (inner && inner.return) {
            return inner.return(undefined as unknown as LLMStreamEvent);
          }
          return { value: undefined as unknown as LLMStreamEvent, done: true };
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
  native.cancelGeneration();
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
// Thinking Token Utilities (§3 — pure TS, no native bridge needed)
// ============================================================================

/** Result of extracting thinking tokens from text. */
export interface ThinkingExtractionResult {
  /** All thinking blocks extracted from the text, in order. */
  thinkingBlocks: string[];
  /** The text with all thinking blocks removed. */
  responseText: string;
}

/** Regex that matches a single `<think>…</think>` block (non-greedy, dotAll). */
const THINK_BLOCK_RE = /<think>([\s\S]*?)<\/think>/g;

/**
 * Extract all `<think>…</think>` blocks from `text`.
 *
 * Returns a `ThinkingExtractionResult` containing the raw thinking content
 * of each block and the text with all thinking blocks removed.
 *
 * Matches Swift SDK: `RunAnywhere.extractThinkingTokens(_:)`.
 */
export function extractThinkingTokens(text: string): ThinkingExtractionResult {
  const thinkingBlocks: string[] = [];
  let responseText = text.replace(THINK_BLOCK_RE, (_match, content: string) => {
    thinkingBlocks.push(content.trim());
    return '';
  });
  responseText = responseText.trim();
  return { thinkingBlocks, responseText };
}

/**
 * Remove all `<think>…</think>` blocks from `text`.
 *
 * Matches Swift SDK: `RunAnywhere.stripThinkingTokens(_:)`.
 */
export function stripThinkingTokens(text: string): string {
  return text.replace(THINK_BLOCK_RE, '').trim();
}

/**
 * Split `text` at the first `<think>` tag into a `(thinking, response)` pair.
 *
 * - If the text contains no `<think>` tag the whole text is returned as
 *   `response` and `thinking` is the empty string.
 * - If the text contains multiple thinking blocks, only the content up to (and
 *   including) the first `</think>` is treated as `thinking`; the remainder
 *   (including any further `<think>` blocks) is returned as `response`.
 *
 * Matches Swift SDK: `RunAnywhere.splitThinkingAndResponse(_:)`.
 */
export function splitThinkingAndResponse(text: string): { thinking: string; response: string } {
  const firstOpen = text.indexOf('<think>');
  if (firstOpen === -1) {
    return { thinking: '', response: text.trim() };
  }
  const closeTag = '</think>';
  const firstClose = text.indexOf(closeTag, firstOpen);
  if (firstClose === -1) {
    // Unclosed <think> block — treat everything after <think> as thinking.
    return {
      thinking: text.slice(firstOpen + '<think>'.length).trim(),
      response: text.slice(0, firstOpen).trim(),
    };
  }
  const thinkingContent = text.slice(firstOpen + '<think>'.length, firstClose).trim();
  const response = (text.slice(0, firstOpen) + text.slice(firstClose + closeTag.length)).trim();
  return { thinking: thinkingContent, response };
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
