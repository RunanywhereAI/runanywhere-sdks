/**
 * RunAnywhere Web SDK - Text Generation Extension
 *
 * Adds LLM text generation capabilities to RunAnywhere.
 * Mirrors: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/
 *
 * Usage:
 *   import { RunAnywhere } from '@runanywhere/web';
 *
 *   await RunAnywhere.loadModel('tinyllama-1.1b-q4');
 *   const result = await RunAnywhere.generate('Hello!', { maxTokens: 100 });
 *   console.log(result.text);
 *
 *   // Streaming
 *   for await (const token of RunAnywhere.generateStream('Tell me a story')) {
 *     process.stdout.write(token);
 *   }
 */

import { RunAnywhere } from '../RunAnywhere';
import { WASMBridge } from '../../Foundation/WASMBridge';
import { SDKError, SDKErrorCode } from '../../Foundation/ErrorTypes';
import { SDKLogger } from '../../Foundation/SDKLogger';
import { EventBus } from '../../Foundation/EventBus';
import { SDKEventType, LLMFramework, HardwareAcceleration } from '../../types/enums';
import type { LLMGenerationOptions, LLMGenerationResult, LLMStreamingResult } from '../../types/LLMTypes';

const logger = new SDKLogger('TextGeneration');

// Internal state
let _llmComponentHandle = 0;

/**
 * Ensure the SDK is initialized and return the bridge.
 */
function requireBridge(): WASMBridge {
  if (!RunAnywhere.isInitialized) {
    throw SDKError.notInitialized();
  }
  return WASMBridge.shared;
}

/**
 * Ensure the LLM component is created.
 */
function ensureLLMComponent(): number {
  if (_llmComponentHandle !== 0) {
    return _llmComponentHandle;
  }

  const bridge = requireBridge();
  const m = bridge.module;

  // Allocate pointer for output handle
  const handlePtr = m._malloc(4);
  const result = m._rac_llm_component_create(handlePtr);

  if (result !== 0) {
    m._free(handlePtr);
    bridge.checkResult(result, 'rac_llm_component_create');
  }

  _llmComponentHandle = m.getValue(handlePtr, 'i32');
  m._free(handlePtr);

  logger.debug('LLM component created');
  return _llmComponentHandle;
}

// ---------------------------------------------------------------------------
// Text Generation Extension
// ---------------------------------------------------------------------------

export const TextGeneration = {
  /**
   * Load an LLM model for text generation.
   *
   * @param modelPath - Path to the model file (in Emscripten FS)
   * @param modelId - Model identifier
   * @param modelName - Human-readable model name
   */
  async loadModel(modelPath: string, modelId: string, modelName?: string): Promise<void> {
    const bridge = requireBridge();
    const m = bridge.module;
    const handle = ensureLLMComponent();

    logger.info(`Loading LLM model: ${modelId} from ${modelPath}`);

    EventBus.shared.emit('model.loadStarted', SDKEventType.Model, { modelId });

    const pathPtr = bridge.allocString(modelPath);
    const idPtr = bridge.allocString(modelId);
    const namePtr = bridge.allocString(modelName ?? modelId);

    try {
      const result = m._rac_llm_component_load_model(handle, pathPtr, idPtr, namePtr);
      bridge.checkResult(result, 'rac_llm_component_load_model');

      logger.info(`LLM model loaded: ${modelId}`);
      EventBus.shared.emit('model.loadCompleted', SDKEventType.Model, { modelId });
    } catch (error) {
      EventBus.shared.emit('model.loadFailed', SDKEventType.Model, {
        modelId,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    } finally {
      bridge.free(pathPtr);
      bridge.free(idPtr);
      bridge.free(namePtr);
    }
  },

  /**
   * Unload the currently loaded LLM model.
   */
  async unloadModel(): Promise<void> {
    if (_llmComponentHandle === 0) return;

    const bridge = requireBridge();
    const m = bridge.module;

    const result = m._rac_llm_component_unload(_llmComponentHandle);
    bridge.checkResult(result, 'rac_llm_component_unload');

    logger.info('LLM model unloaded');
  },

  /**
   * Check if an LLM model is currently loaded.
   */
  get isModelLoaded(): boolean {
    if (_llmComponentHandle === 0) return false;
    try {
      const m = WASMBridge.shared.module;
      return m._rac_llm_component_is_loaded(_llmComponentHandle) === 1;
    } catch {
      return false;
    }
  },

  /**
   * Generate text from a prompt (non-streaming).
   *
   * Uses `ccall` with `{async: true}` so that Emscripten's JSPI / Asyncify
   * can suspend the WASM stack for async WebGPU buffer operations. Without
   * this the blocking C function traps with `RuntimeError: unreachable` on
   * WebGPU builds because the browser event-loop cannot pump GPU command
   * buffers while the main thread is blocked in a synchronous ccall.
   *
   * @param prompt - Input text prompt
   * @param options - Generation options (temperature, maxTokens, etc.)
   * @returns Generation result with text and metrics
   */
  async generate(prompt: string, options: LLMGenerationOptions = {}): Promise<LLMGenerationResult> {
    const bridge = requireBridge();
    const m = bridge.module;
    const handle = ensureLLMComponent();

    if (!TextGeneration.isModelLoaded) {
      throw new SDKError(SDKErrorCode.ModelNotLoaded, 'No LLM model loaded. Call loadModel() first.');
    }

    logger.debug(`Generating from prompt (${prompt.length} chars)`);
    const startTime = performance.now();

    EventBus.shared.emit('generation.started', SDKEventType.Generation, {
      prompt: prompt.substring(0, 100),
    });

    // Allocate prompt string
    const promptPtr = bridge.allocString(prompt);

    // Create default options struct
    const optionsPtr = m._rac_wasm_create_llm_options_default();
    if (optionsPtr === 0) {
      bridge.free(promptPtr);
      throw new SDKError(SDKErrorCode.WASMMemoryError, 'Failed to allocate LLM options');
    }

    // Override options if provided
    // rac_llm_options_t layout: { max_tokens, temperature, top_p, ... }
    if (options.maxTokens !== undefined) {
      m.setValue(optionsPtr, options.maxTokens, 'i32');
    }
    if (options.temperature !== undefined) {
      m.setValue(optionsPtr + 4, options.temperature, 'float');
    }
    if (options.topP !== undefined) {
      m.setValue(optionsPtr + 8, options.topP, 'float');
    }

    // Allocate and zero-initialise the result struct so any C++ code that
    // reads a field before writing (e.g. checking `text != NULL`) does not
    // encounter garbage memory.
    const resultSize = m._rac_wasm_sizeof_llm_result();
    const resultPtr = m._malloc(resultSize);
    for (let i = 0; i < resultSize; i++) m.setValue(resultPtr + i, 0, 'i8');

    try {
      // Call with {async: true} so Emscripten's JSPI / Asyncify can yield
      // to the browser event-loop during WebGPU buffer map operations.
      // On CPU-only builds this is harmless (the result is simply wrapped
      // in an already-resolved Promise).
      let result: number;
      try {
        result = await m.ccall(
          'rac_llm_component_generate',
          'number',
          ['number', 'number', 'number', 'number'],
          [handle, promptPtr, optionsPtr, resultPtr],
          { async: true },
        ) as number;
      } catch (wasmErr: unknown) {
        // Emscripten converts unhandled C++ exceptions into JS throws.
        // The thrown value is typically the __cxa_exception pointer (a number).
        const detail = typeof wasmErr === 'number'
          ? `WASM C++ exception (ptr=${wasmErr}). The model's chat template may be unsupported.`
          : String(wasmErr);
        throw new SDKError(
          SDKErrorCode.GenerationFailed,
          `LLM generation crashed: ${detail}`,
        );
      }
      bridge.checkResult(result, 'rac_llm_component_generate');

      // Read result struct
      // rac_llm_result_t layout:
      //   offset 0:  char*   text
      //   offset 4:  int32   prompt_tokens
      //   offset 8:  int32   completion_tokens
      //   offset 12: int32   total_tokens
      //   offset 16: int64   time_to_first_token_ms
      //   offset 24: int64   total_time_ms
      //   offset 32: float   tokens_per_second
      const textPtr = m.getValue(resultPtr, '*');
      const text = bridge.readString(textPtr);
      const inputTokens = m.getValue(resultPtr + 4, 'i32');
      const outputTokens = m.getValue(resultPtr + 8, 'i32');

      const latencyMs = performance.now() - startTime;
      const tokensPerSecond = outputTokens > 0 ? (outputTokens / (latencyMs / 1000)) : 0;

      const genResult: LLMGenerationResult = {
        text,
        inputTokens,
        tokensUsed: outputTokens,
        modelUsed: bridge.readString(m._rac_llm_component_get_model_id(handle)),
        latencyMs,
        framework: LLMFramework.LlamaCpp,
        hardwareUsed: bridge.accelerationMode as HardwareAcceleration,
        tokensPerSecond,
        thinkingTokens: 0,
        responseTokens: outputTokens,
      };

      EventBus.shared.emit('generation.completed', SDKEventType.Generation, {
        tokensUsed: outputTokens,
        latencyMs,
      });

      // Free the text string allocated inside the result by the C++ side
      m._rac_llm_result_free(resultPtr);

      return genResult;
    } catch (error) {
      EventBus.shared.emit('generation.failed', SDKEventType.Generation, {
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    } finally {
      bridge.free(promptPtr);
      m._free(optionsPtr);
      // Free the result struct itself (separate from _rac_llm_result_free
      // which only frees the inner `text` string).
      m._free(resultPtr);
    }
  },

  /**
   * Generate text with streaming (returns AsyncIterable of tokens).
   *
   * @param prompt - Input text prompt
   * @param options - Generation options
   * @returns Streaming result with async token stream and final result promise
   */
  generateStream(prompt: string, options: LLMGenerationOptions = {}): LLMStreamingResult {
    const bridge = requireBridge();
    const m = bridge.module;
    const handle = ensureLLMComponent();

    if (!TextGeneration.isModelLoaded) {
      throw new SDKError(SDKErrorCode.ModelNotLoaded, 'No LLM model loaded. Call loadModel() first.');
    }

    // Token queue for async iteration
    const tokenQueue: string[] = [];
    let resolveNext: ((value: IteratorResult<string>) => void) | null = null;
    let isDone = false;
    let streamError: Error | null = null;

    // Result promise
    let resolveResult: ((result: LLMGenerationResult) => void) | null = null;
    let rejectResult: ((error: Error) => void) | null = null;

    const resultPromise = new Promise<LLMGenerationResult>((resolve, reject) => {
      resolveResult = resolve;
      rejectResult = reject;
    });

    const startTime = performance.now();
    let tokenCount = 0;
    let fullText = '';
    let timeToFirstToken: number | undefined;

    // Register token callback
    const tokenCbPtr = m.addFunction((tokenPtr: number, _userData: number): number => {
      const token = m.UTF8ToString(tokenPtr);
      tokenCount++;
      fullText += token;

      if (timeToFirstToken === undefined) {
        timeToFirstToken = performance.now() - startTime;
      }

      if (resolveNext) {
        const resolve = resolveNext;
        resolveNext = null;
        resolve({ value: token, done: false });
      } else {
        tokenQueue.push(token);
      }

      return 1; // RAC_TRUE = continue
    }, 'iii');

    // Register complete callback
    const completeCbPtr = m.addFunction((_resultPtr: number, _userData: number): void => {
      isDone = true;
      if (resolveNext) {
        const resolve = resolveNext;
        resolveNext = null;
        resolve({ value: undefined as unknown as string, done: true });
      }

      const latencyMs = performance.now() - startTime;
      const tokensPerSecond = tokenCount > 0 ? (tokenCount / (latencyMs / 1000)) : 0;

      resolveResult?.({
        text: fullText,
        inputTokens: 0,
        tokensUsed: tokenCount,
        modelUsed: '',
        latencyMs,
        framework: LLMFramework.LlamaCpp,
        hardwareUsed: bridge.accelerationMode as HardwareAcceleration,
        tokensPerSecond,
        timeToFirstTokenMs: timeToFirstToken,
        thinkingTokens: 0,
        responseTokens: tokenCount,
      });

      // Cleanup callback pointers
      m.removeFunction(tokenCbPtr);
      m.removeFunction(completeCbPtr);
      m.removeFunction(errorCbPtr);
    }, 'vii');

    // Register error callback
    const errorCbPtr = m.addFunction((errorCode: number, errorMsgPtr: number, _userData: number): void => {
      isDone = true;
      const errorMsg = m.UTF8ToString(errorMsgPtr);
      streamError = SDKError.fromRACResult(errorCode, errorMsg);

      if (resolveNext) {
        const resolve = resolveNext;
        resolveNext = null;
        resolve({ value: undefined as unknown as string, done: true });
      }

      rejectResult?.(streamError);

      m.removeFunction(tokenCbPtr);
      m.removeFunction(completeCbPtr);
      m.removeFunction(errorCbPtr);
    }, 'viii');

    // Start streaming generation
    const promptPtr = bridge.allocString(prompt);
    const optionsPtr = m._rac_wasm_create_llm_options_default();

    if (options.maxTokens !== undefined) {
      m.setValue(optionsPtr, options.maxTokens, 'i32');
    }
    if (options.temperature !== undefined) {
      m.setValue(optionsPtr + 4, options.temperature, 'float');
    }

    let startResult: number;
    try {
      startResult = m.ccall(
        'rac_llm_component_generate_stream',
        'number',
        ['number', 'number', 'number', 'number', 'number', 'number', 'number'],
        [handle, promptPtr, optionsPtr, tokenCbPtr, completeCbPtr, errorCbPtr, 0],
      ) as number;
    } catch (wasmErr: unknown) {
      bridge.free(promptPtr);
      m._free(optionsPtr);
      m.removeFunction(tokenCbPtr);
      m.removeFunction(completeCbPtr);
      m.removeFunction(errorCbPtr);
      const detail = typeof wasmErr === 'number'
        ? `WASM C++ exception (ptr=${wasmErr}). The model's chat template may be unsupported.`
        : String(wasmErr);
      throw new SDKError(
        SDKErrorCode.GenerationFailed,
        `LLM streaming generation crashed: ${detail}`,
      );
    }

    bridge.free(promptPtr);
    m._free(optionsPtr);

    if (startResult !== 0) {
      m.removeFunction(tokenCbPtr);
      m.removeFunction(completeCbPtr);
      m.removeFunction(errorCbPtr);
      throw SDKError.fromRACResult(startResult, 'Failed to start streaming generation');
    }

    // Create async iterable
    const stream: AsyncIterable<string> = {
      [Symbol.asyncIterator](): AsyncIterator<string> {
        return {
          next(): Promise<IteratorResult<string>> {
            if (streamError) {
              return Promise.reject(streamError);
            }
            if (tokenQueue.length > 0) {
              return Promise.resolve({ value: tokenQueue.shift()!, done: false });
            }
            if (isDone) {
              return Promise.resolve({ value: undefined as unknown as string, done: true });
            }
            return new Promise((resolve) => {
              resolveNext = resolve;
            });
          },
        };
      },
    };

    return {
      stream,
      result: resultPromise,
      cancel: () => {
        m._rac_llm_component_cancel(handle);
      },
    };
  },

  /**
   * Cancel any in-progress generation.
   */
  cancel(): void {
    if (_llmComponentHandle === 0) return;
    try {
      const m = WASMBridge.shared.module;
      m._rac_llm_component_cancel(_llmComponentHandle);
    } catch {
      // Ignore cancel errors
    }
  },

  /**
   * Clean up the LLM component (frees memory).
   */
  cleanup(): void {
    if (_llmComponentHandle !== 0) {
      try {
        const m = WASMBridge.shared.module;
        m._rac_llm_component_destroy(_llmComponentHandle);
      } catch {
        // Ignore cleanup errors
      }
      _llmComponentHandle = 0;
    }
  },
};
