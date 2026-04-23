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
import { LLMStreamAdapter } from '../../Adapters/LLMStreamAdapter';
import type { LLMStreamEvent } from '../../generated/llm_service';

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
 * v2 close-out / GAP 09: events flow through `LLMStreamAdapter`
 *   C-callback → proto bytes → `LLMStreamEvent` → token string
 * The struct-callback arg passed to `native.generateStream(...)` is a
 * no-op driver — we consume tokens via the adapter's proto subscription
 * and only need the underlying call to keep the C++ engine loop alive.
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

  const optionsJson = JSON.stringify({
    max_tokens: options?.maxTokens ?? 1000,
    temperature: options?.temperature ?? 0.7,
    system_prompt: options?.systemPrompt ?? null,
  });

  // Subscribe BEFORE driving the engine so we never miss early tokens
  // emitted synchronously from inside the native generate call.
  const handle = await native.getLLMHandle();
  const eventIterator = new LLMStreamAdapter(handle)
    .stream({
      prompt,
      maxTokens: options?.maxTokens ?? 1000,
      temperature: options?.temperature ?? 0.7,
      topP: 0,
      topK: 0,
      systemPrompt: options?.systemPrompt ?? '',
      emitThoughts: false,
    })
    [Symbol.asyncIterator]();

  let resolveResult!: (result: LLMGenerationResult) => void;
  let rejectResult!: (error: Error) => void;
  const resultPromise = new Promise<LLMGenerationResult>((resolve, reject) => {
    resolveResult = resolve;
    rejectResult = reject;
  });

  // Drive the C++ engine loop. Tokens are delivered to `eventIterator`
  // via the adapter's proto-byte callback; the struct-callback is a
  // no-op because we consume events via the adapter, not per-token.
  native
    .generateStream(prompt, optionsJson, () => {
      /* events delivered via LLMStreamAdapter */
    })
    .catch((err: Error) => {
      rejectResult(err);
      EventBus.publish('Generation', { type: 'failed', error: err.message });
      void eventIterator.return?.();
    });

  async function* tokenGenerator(): AsyncGenerator<string> {
    try {
      while (true) {
        const next = await eventIterator.next();
        if (next.done) break;
        const event: LLMStreamEvent = next.value;

        if (event.token) {
          if (firstTokenTime === null) firstTokenTime = Date.now();
          fullText += event.token;
          tokenCount++;
          yield event.token;
        }

        if (event.isFinal) {
          if (event.errorMessage) {
            const err = new Error(event.errorMessage);
            rejectResult(err);
            EventBus.publish('Generation', { type: 'failed', error: err.message });
            throw err;
          }
          break;
        }
      }

      const latencyMs = Date.now() - startTime;
      resolveResult({
        text: fullText,
        thinkingContent: undefined,
        inputTokens: Math.ceil(prompt.length / 4),
        tokensUsed: tokenCount,
        modelUsed: 'unknown',
        latencyMs,
        framework: 'unknown', // Backend-agnostic
        tokensPerSecond: latencyMs > 0 ? (tokenCount / latencyMs) * 1000 : 0,
        timeToFirstTokenMs:
          firstTokenTime !== null ? firstTokenTime - startTime : undefined,
        thinkingTokens: 0,
        responseTokens: tokenCount,
      });
      EventBus.publish('Generation', { type: 'completed' });
    } finally {
      await eventIterator.return?.();
    }
  }

  const cancel = (): void => {
    cancelGeneration();
    void eventIterator.return?.();
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
