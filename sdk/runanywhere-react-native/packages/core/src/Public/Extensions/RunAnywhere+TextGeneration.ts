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

import { EventBus } from '../Events';
import {
  requireNativeModule,
  isNativeModuleAvailable,
} from '../../native';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import type {
  LLMGenerationOptions,
  LLMGenerationResult,
  StreamToken,
} from '@runanywhere/proto-ts/llm_options';

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
 * Returns an AsyncIterable<StreamToken> where each token carries `.text`,
 * `.timestampMs`, and `.index` (proto StreamToken shape).
 *
 * Matches Swift SDK: RunAnywhere.generateStream(_:options:)
 *
 * Wire-up: tokens are pushed by C++ via the struct-callback
 * `(token: string, isComplete: boolean) => void` passed to
 * `native.generateStream(...)`.
 */
export async function* generateStream(
  prompt: string,
  options?: LLMGenerationOptions
): AsyncIterable<StreamToken> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const native = requireNativeModule();
  let cancelled = false;
  let index = 0;

  const optionsJson = JSON.stringify({
    max_tokens: options?.maxTokens ?? 1000,
    temperature: options?.temperature ?? 0.7,
    system_prompt: options?.systemPrompt ?? null,
  });

  const tokenQueue: StreamToken[] = [];
  let resolver: ((value: IteratorResult<StreamToken>) => void) | null = null;
  let done = false;
  let error: Error | null = null;

  native
    .generateStream(prompt, optionsJson, (token: string, isComplete: boolean) => {
      if (cancelled) return;

      if (token) {
        const st: StreamToken = { text: token, timestampMs: Date.now(), index: index++ };
        if (resolver) {
          resolver({ value: st, done: false });
          resolver = null;
        } else {
          tokenQueue.push(st);
        }
      }

      if (isComplete) {
        done = true;
        EventBus.publish('Generation', { type: 'completed' });
        if (resolver) {
          resolver({ value: undefined as unknown as StreamToken, done: true });
          resolver = null;
        }
      }
    })
    .catch((err: Error) => {
      error = err;
      done = true;
      EventBus.publish('Generation', { type: 'failed', error: err.message });
      if (resolver) {
        resolver({ value: undefined as unknown as StreamToken, done: true });
        resolver = null;
      }
    });

  while (!done || tokenQueue.length > 0) {
    if (tokenQueue.length > 0) {
      yield tokenQueue.shift()!;
    } else if (!done) {
      const next = await new Promise<IteratorResult<StreamToken>>((resolve) => {
        resolver = resolve;
      });
      if (next.done) break;
      yield next.value;
    }
  }
  if (error) throw error;
  // Allow callers to cancel via generator.return()
  void cancelled;
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

/**
 * Get the currently loaded LLM model ID, or `null` if none is loaded.
 *
 * Matches Swift: `RunAnywhere.currentLLMModel`.
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

/**
 * Generic helper that returns the currently loaded LLM model id.
 *
 * Matches Swift: `RunAnywhere.getCurrentModelId()`.
 */
export async function getCurrentModelId(): Promise<string | null> {
  return currentLLMModel();
}
