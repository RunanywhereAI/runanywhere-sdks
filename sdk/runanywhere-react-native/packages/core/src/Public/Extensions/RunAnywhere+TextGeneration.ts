/**
 * RunAnywhere+TextGeneration.ts
 *
 * Text generation (LLM) extension for RunAnywhere SDK.
 * Matches iOS: RunAnywhere+TextGeneration.swift
 */

import { EventBus } from '../Events';
import {
  requireNativeModule,
  isNativeModuleAvailable,
} from '@runanywhere/native';
import type { GenerationOptions, GenerationResult } from '../../types';
import { ExecutionTarget, HardwareAcceleration } from '../../types';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import type {
  LLMStreamingResult,
  LLMGenerationResult,
  LLMTokenCallback,
} from '../../types/LLMTypes';

const logger = new SDKLogger('RunAnywhere.TextGeneration');

// ============================================================================
// Text Generation (LLM) Extension
// ============================================================================

/**
 * Load an LLM model by ID or path
 *
 * Matches iOS: `RunAnywhere.loadModel(_:)`
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
 * Load a text generation model
 * @deprecated Use `loadModel()` instead for iOS API parity
 */
export async function loadTextModel(
  modelPath: string,
  config?: Record<string, unknown>
): Promise<boolean> {
  return loadModel(modelPath, config);
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
 * Check if a text model is loaded
 * @deprecated Use `isModelLoaded()` instead for iOS API parity
 */
export async function isTextModelLoaded(): Promise<boolean> {
  return isModelLoaded();
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
 * Unload the current text model
 * @deprecated Use `unloadModel()` instead for iOS API parity
 */
export async function unloadTextModel(): Promise<boolean> {
  return unloadModel();
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
    max_tokens: options?.maxTokens ?? 256,
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
  let cancelled = false;
  let fullText = '';
  let tokenCount = 0;
  let resolveResult: ((result: LLMGenerationResult) => void) | null = null;
  let rejectResult: ((error: Error) => void) | null = null;

  const optionsJson = JSON.stringify({
    max_tokens: options?.maxTokens ?? 256,
    temperature: options?.temperature ?? 0.7,
    system_prompt: options?.systemPrompt ?? null,
  });

  // Create the result promise
  const resultPromise = new Promise<LLMGenerationResult>((resolve, reject) => {
    resolveResult = resolve;
    rejectResult = reject;
  });

  // Create async generator for tokens
  async function* tokenGenerator(): AsyncGenerator<string> {
    const tokenQueue: string[] = [];
    let resolver: ((value: IteratorResult<string>) => void) | null = null;
    let done = false;
    let error: Error | null = null;

    // Start streaming
    native.generateStream(
      prompt,
      optionsJson,
      (token: string, isComplete: boolean) => {
        if (cancelled) return;

        if (!isComplete && token) {
          // Track first token time
          if (firstTokenTime === null) {
            firstTokenTime = Date.now();
          }

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

          // Build final result
          const endTime = Date.now();
          const latencyMs = endTime - startTime;
          const timeToFirstTokenMs = firstTokenTime ? firstTokenTime - startTime : undefined;
          const tokensPerSecond = latencyMs > 0 ? (tokenCount / latencyMs) * 1000 : 0;

          const finalResult: LLMGenerationResult = {
            text: fullText,
            thinkingContent: undefined,
            inputTokens: Math.ceil(prompt.length / 4),
            tokensUsed: tokenCount,
            modelUsed: 'unknown',
            latencyMs,
            framework: 'llamacpp',
            tokensPerSecond,
            timeToFirstTokenMs,
            thinkingTokens: 0,
            responseTokens: tokenCount,
          };

          if (resolveResult) {
            resolveResult(finalResult);
          }

          if (resolver) {
            resolver({ value: undefined as unknown as string, done: true });
            resolver = null;
          }

          EventBus.publish('Generation', { type: 'completed' });
        }
      }
    ).catch((err: Error) => {
      error = err;
      done = true;
      if (rejectResult) {
        rejectResult(err);
      }
      if (resolver) {
        resolver({ value: undefined as unknown as string, done: true });
      }
      EventBus.publish('Generation', { type: 'failed', error: err.message });
    });

    // Yield tokens
    while (!done || tokenQueue.length > 0) {
      if (tokenQueue.length > 0) {
        yield tokenQueue.shift()!;
      } else if (!done) {
        const result = await new Promise<IteratorResult<string>>((resolve) => {
          resolver = resolve;
        });
        if (result.done) break;
        yield result.value;
      }
    }

    if (error) {
      throw error;
    }
  }

  // Cancel function
  const cancel = (): void => {
    cancelled = true;
    cancelGeneration();
  };

  return {
    stream: tokenGenerator(),
    result: resultPromise,
    cancel,
  };
}

/**
 * Streaming text generation with callback (legacy API)
 *
 * @deprecated Use generateStream() which returns an async iterator
 */
export function generateStreamWithCallback(
  prompt: string,
  options?: GenerationOptions,
  onToken?: LLMTokenCallback
): void {
  if (!isNativeModuleAvailable()) {
    EventBus.publish('Generation', {
      type: 'failed',
      error: 'Native module not available',
    });
    return;
  }
  const native = requireNativeModule();

  const optionsJson = JSON.stringify({
    max_tokens: options?.maxTokens ?? 256,
    temperature: options?.temperature ?? 0.7,
    system_prompt: options?.systemPrompt ?? null,
  });

  if (onToken) {
    const unsubscribe = EventBus.onGeneration((event) => {
      // eslint-disable-next-line @typescript-eslint/no-explicit-any
      const evt = event as any;
      if (evt.type === 'tokenGenerated' && evt.token) {
        onToken(evt.token);
      } else if (evt.type === 'completed' || evt.type === 'failed') {
        unsubscribe();
      }
    });
  }

  native.generateStream(
    prompt,
    optionsJson,
    (token: string, isComplete: boolean) => {
      if (onToken && !isComplete) {
        onToken(token);
      }
      if (isComplete) {
        EventBus.publish('Generation', { type: 'completed' });
      }
    }
  );
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
