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
import type { GenerationOptions, GenerationResult } from '../../types';
import { ExecutionTarget, HardwareAcceleration } from '../../types';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import type {
  LLMStreamingResult,
  LLMGenerationResult,
} from '../../types/LLMTypes';

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
 * Text generation with options and full metrics
 * Matches Swift SDK: RunAnywhere.generate(_:options:)
 */
export async function generate(
  prompt: string,
  options?: GenerationOptions
): Promise<GenerationResult> {
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
      tokensUsed: result.tokensUsed ?? 0,
      modelUsed: result.modelUsed ?? 'unknown',
      latencyMs: result.latencyMs ?? 0,
      executionTarget: result.executionTarget ?? 0,
      savedAmount: result.savedAmount ?? 0,
      framework: result.framework,
      hardwareUsed: result.hardwareUsed ?? 0,
      memoryUsed: result.memoryUsed ?? 0,
      performanceMetrics: {
        timeToFirstTokenMs: result.performanceMetrics?.timeToFirstTokenMs,
        tokensPerSecond: result.performanceMetrics?.tokensPerSecond,
        inferenceTimeMs:
          result.performanceMetrics?.inferenceTimeMs ?? result.latencyMs ?? 0,
      },
      thinkingTokens: result.thinkingTokens,
      responseTokens: result.responseTokens ?? result.tokensUsed ?? 0,
    };
  } catch {
    if (resultJson.includes('error')) {
      throw new Error(resultJson);
    }
    return {
      text: resultJson,
      tokensUsed: 0,
      modelUsed: 'unknown',
      latencyMs: 0,
      executionTarget: ExecutionTarget.OnDevice,
      savedAmount: 0,
      hardwareUsed: HardwareAcceleration.CPU,
      memoryUsed: 0,
      performanceMetrics: {
        inferenceTimeMs: 0,
      },
      responseTokens: 0,
    };
  }
}

/**
 * Streaming text generation with async iterator
 *
 * Returns a LLMStreamingResult containing:
 * - stream: AsyncIterable<string> for consuming tokens
 * - result: Promise<LLMGenerationResult> for final metrics
 * - cancel: Function to cancel generation
 *
 * Matches Swift SDK: RunAnywhere.generateStream(_:options:)
 *
 * Wire-up: tokens are pushed by C++ via the struct-callback
 * `(token: string, isComplete: boolean) => void` passed to
 * `native.generateStream(...)`. The callback batches at ~50 ms inside
 * `HybridRunAnywhereLlama.cpp` and emits a terminal call with
 * `isComplete = true`. We adopt the same single-channel pattern as the
 * VLM streaming path (`RunAnywhere+VLM.ts::processImageStream`) — no
 * separate proto-byte channel, no `LLMStreamAdapter`. This fixes
 * B-RN-4-001 where the LLM `LLMStreamAdapter`/`subscribeProtoEvents`
 * channel never delivered tokens, leaving awaiters hung even though
 * C++ generation completed.
 *
 * Example usage:
 * ```typescript
 * const streaming = await generateStream(prompt);
 *
 * // Display tokens in real-time
 * for await (const token of streaming.stream) {
 *   console.log(token);
 * }
 *
 * // Get complete analytics after streaming finishes
 * const metrics = await streaming.result;
 * console.log(`Speed: ${metrics.tokensPerSecond} tok/s`);
 * ```
 */
export async function generateStream(
  prompt: string,
  options?: GenerationOptions
): Promise<LLMStreamingResult> {
  if (!isNativeModuleAvailable()) {
    throw new Error('Native module not available');
  }

  const native = requireNativeModule();
  const startTime = Date.now();
  let firstTokenTime: number | null = null;
  let fullText = '';
  let tokenCount = 0;
  let cancelled = false;

  const optionsJson = JSON.stringify({
    max_tokens: options?.maxTokens ?? 1000,
    temperature: options?.temperature ?? 0.7,
    system_prompt: options?.systemPrompt ?? null,
  });

  let resolveResult!: (result: LLMGenerationResult) => void;
  let rejectResult!: (error: Error) => void;
  const resultPromise = new Promise<LLMGenerationResult>((resolve, reject) => {
    resolveResult = resolve;
    rejectResult = reject;
  });

  // Producer/consumer queue fed by the C++ struct-callback. When a token
  // arrives we either hand it directly to a pending awaiter or buffer it.
  const tokenQueue: string[] = [];
  let resolver: ((value: IteratorResult<string>) => void) | null = null;
  let done = false;
  let error: Error | null = null;

  const finalizeResult = (): void => {
    const latencyMs = Date.now() - startTime;
    const tokensPerSecond =
      latencyMs > 0 ? (tokenCount / latencyMs) * 1000 : 0;
    resolveResult({
      text: fullText,
      thinkingContent: undefined,
      inputTokens: Math.ceil(prompt.length / 4),
      tokensUsed: tokenCount,
      modelUsed: 'unknown',
      latencyMs,
      framework: 'unknown', // Backend-agnostic
      tokensPerSecond,
      timeToFirstTokenMs:
        firstTokenTime !== null ? firstTokenTime - startTime : undefined,
      thinkingTokens: 0,
      responseTokens: tokenCount,
    });
    EventBus.publish('Generation', { type: 'completed' });
  };

  // Drive the C++ engine. Tokens flow through the struct-callback —
  // this is the same pattern used by VLM streaming (RN-14 confirmed).
  native
    .generateStream(prompt, optionsJson, (token: string, isComplete: boolean) => {
      if (cancelled) return;

      if (token) {
        if (firstTokenTime === null) firstTokenTime = Date.now();
        fullText += token;
        tokenCount++;

        if (resolver) {
          resolver({ value: token, done: false });
          resolver = null;
        } else {
          tokenQueue.push(token);
        }
      }

      if (isComplete) {
        done = true;
        finalizeResult();

        if (resolver) {
          resolver({ value: undefined as unknown as string, done: true });
          resolver = null;
        }
      }
    })
    .catch((err: Error) => {
      error = err;
      done = true;
      rejectResult(err);
      EventBus.publish('Generation', { type: 'failed', error: err.message });
      if (resolver) {
        resolver({ value: undefined as unknown as string, done: true });
        resolver = null;
      }
    });

  async function* tokenGenerator(): AsyncGenerator<string> {
    while (!done || tokenQueue.length > 0) {
      if (tokenQueue.length > 0) {
        yield tokenQueue.shift()!;
      } else if (!done) {
        const next = await new Promise<IteratorResult<string>>((resolve) => {
          resolver = resolve;
        });
        if (next.done) break;
        yield next.value;
      }
    }
    if (error) {
      throw error;
    }
  }

  const cancel = (): void => {
    cancelled = true;
    cancelGeneration();
    if (resolver) {
      done = true;
      resolver({ value: undefined as unknown as string, done: true });
      resolver = null;
    }
  };

  return {
    stream: tokenGenerator(),
    result: resultPromise,
    cancel,
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
