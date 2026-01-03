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
 * Streaming text generation
 */
export function generateStream(
  prompt: string,
  options?: GenerationOptions,
  onToken?: (token: string) => void
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
