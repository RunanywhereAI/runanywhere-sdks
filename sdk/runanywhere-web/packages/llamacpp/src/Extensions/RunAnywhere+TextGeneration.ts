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

import { RunAnywhere, SDKError, SDKErrorCode, SDKLogger, EventBus, SDKEventType, LLMFramework, HardwareAcceleration } from '@runanywhere/web';
import type { ModelLoadContext } from '@runanywhere/web';
import { LlamaCppBridge } from '../Foundation/LlamaCppBridge';
import { Offsets } from '../Foundation/LlamaCppOffsets';
import type { LLMGenerationOptions, LLMGenerationResult, LLMStreamingResult } from '../types/LLMTypes';

const logger = new SDKLogger('TextGeneration');

// ---------------------------------------------------------------------------
// Text Generation Extension
// ---------------------------------------------------------------------------

class TextGenerationImpl {
  readonly extensionName = 'TextGeneration';
  private _llmComponentHandle = 0;
  private _mountedPath: string | null = null;

  /** Ensure the SDK is initialized and return the bridge. */
  private requireBridge(): LlamaCppBridge {
    if (!RunAnywhere.isInitialized) {
      throw SDKError.notInitialized();
    }
    return LlamaCppBridge.shared;
  }

  /** Ensure the LLM component is created. */
  private async ensureLLMComponent(): Promise<number> {
    if (this._llmComponentHandle !== 0) {
      return this._llmComponentHandle;
    }

    const bridge = this.requireBridge();
    const m = bridge.module;

    // Allocate pointer for output handle
    const handlePtr = m._malloc(4);
    // {async: true} for JSPI -- component creation may init WebGPU context
    const result = await bridge.callFunction<number | Promise<number>>(
      'rac_llm_component_create', 'number', ['number'], [handlePtr], { async: true },
    ) as number;

    if (result !== 0) {
      m._free(handlePtr);
      bridge.checkResult(result, 'rac_llm_component_create');
    }

    this._llmComponentHandle = m.getValue(handlePtr, 'i32');
    m._free(handlePtr);

    logger.debug('LLM component created');
    return this._llmComponentHandle;
  }

  /**
   * Load an LLM model from raw data or stream via ModelLoadContext.
   * Implements LLMModelLoader interface for ModelManager integration.
   */
  async loadModelFromData(ctx: ModelLoadContext): Promise<void> {
    const bridge = this.requireBridge();
    let modelPath: string | null = null;
    let isMounted = false;

    if (ctx.file) {
      modelPath = bridge.mountFile(ctx.file);
      if (modelPath) {
        isMounted = true;
        this._mountedPath = modelPath;
      } else {
        logger.warning('Mounting failed, falling back to reading file as stream');
        modelPath = `/models/${ctx.model.id}.gguf`;
        await bridge.writeFileStream(modelPath, ctx.file.stream() as unknown as ReadableStream<Uint8Array>);
      }
    } else if (ctx.dataStream) {
      modelPath = `/models/${ctx.model.id}.gguf`;
      await bridge.writeFileStream(modelPath, ctx.dataStream);
    } else if (ctx.data) {
      modelPath = `/models/${ctx.model.id}.gguf`;
      bridge.writeFile(modelPath, ctx.data);
    } else {
      throw new Error('No data provided to loadModelFromData');
    }

    if (!modelPath) throw new Error('Failed to determine model path');

    try {
      await this.loadModel(modelPath, ctx.model.id, ctx.model.name);
    } catch (err) {
      if (isMounted && modelPath) {
        bridge.unmount(modelPath);
        this._mountedPath = null;
      }
      throw err;
    }
  }

  /**
   * Load an LLM model for text generation.
   *
   * @param modelPath - Path to the model file (in Emscripten FS)
   * @param modelId - Model identifier
   * @param modelName - Human-readable model name
   */
  async loadModel(modelPath: string, modelId: string, modelName?: string): Promise<void> {
    const bridge = this.requireBridge();
    const handle = await this.ensureLLMComponent();

    logger.info(`Loading LLM model: ${modelId} from ${modelPath}`);

    EventBus.shared.emit('model.loadStarted', SDKEventType.Model, { modelId });

    const pathPtr = bridge.allocString(modelPath);
    const idPtr = bridge.allocString(modelId);
    const namePtr = bridge.allocString(modelName ?? modelId);

    try {
      // {async: true} allows JSPI to suspend during WebGPU device/buffer
      // initialization that happens inside load_model.
      const result = await bridge.callFunction<number | Promise<number>>(
        'rac_llm_component_load_model',
        'number',
        ['number', 'number', 'number', 'number'],
        [handle, pathPtr, idPtr, namePtr],
        { async: true },
      ) as number;
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
  }

  /**
   * Unload the currently loaded LLM model.
   */
  async unloadModel(): Promise<void> {
    if (this._llmComponentHandle === 0) return;

    const bridge = this.requireBridge();

    const result = await bridge.callFunction<number | Promise<number>>(
      'rac_llm_component_unload',
      'number',
      ['number'],
      [this._llmComponentHandle],
      { async: true },
    ) as number;
    bridge.checkResult(result, 'rac_llm_component_unload');

    logger.info('LLM model unloaded');

    // Clean up mounted file if applicable
    if (this._mountedPath) {
      bridge.unmount(this._mountedPath);
      this._mountedPath = null;
    }
  }

  /**
   * Check if an LLM model is currently loaded.
   */
  get isModelLoaded(): boolean {
    if (this._llmComponentHandle === 0) return false;
    try {
      const m = LlamaCppBridge.shared.module;
      return m._rac_llm_component_is_loaded(this._llmComponentHandle) === 1;
    } catch {
      return false;
    }
  }

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
    const bridge = this.requireBridge();
    const m = bridge.module;
    const handle = await this.ensureLLMComponent();

    if (!this.isModelLoaded) {
      throw new SDKError(SDKErrorCode.ModelNotLoaded, 'No LLM model loaded. Call loadModel() first.');
    }

    logger.debug(`Generating from prompt (${prompt.length} chars)`);
    const startTime = performance.now();

    EventBus.shared.emit('generation.started', SDKEventType.Generation, {
      prompt: prompt.substring(0, 100),
    });

    // If system_prompt WASM offset is not available (WASM not rebuilt yet),
    // inject the system prompt into the user prompt as a fallback.
    let effectivePrompt = prompt;
    const canSetSystemPromptNatively = Offsets.llmOptions.systemPrompt !== 0;
    if (options.systemPrompt && !canSetSystemPromptNatively) {
      effectivePrompt = `[System: ${options.systemPrompt}]\n\n${prompt}`;
      logger.debug('System prompt injected into user prompt (WASM offset not available)');
    }

    // Allocate prompt string
    const promptPtr = bridge.allocString(effectivePrompt);

    // Create default options struct
    const optionsPtr = m._rac_wasm_create_llm_options_default();
    if (optionsPtr === 0) {
      bridge.free(promptPtr);
      throw new SDKError(SDKErrorCode.WASMMemoryError, 'Failed to allocate LLM options');
    }

    // Override options if provided (offsets from compiler via StructOffsets)
    if (options.maxTokens !== undefined) {
      m.setValue(optionsPtr + Offsets.llmOptions.maxTokens, options.maxTokens, 'i32');
    }
    if (options.temperature !== undefined) {
      m.setValue(optionsPtr + Offsets.llmOptions.temperature, options.temperature, 'float');
    }
    if (options.topP !== undefined) {
      m.setValue(optionsPtr + Offsets.llmOptions.topP, options.topP, 'float');
    }
    // Set system_prompt if the WASM offset is available (non-zero = real offset)
    let systemPromptPtr = 0;
    if (options.systemPrompt && Offsets.llmOptions.systemPrompt) {
      systemPromptPtr = bridge.allocString(options.systemPrompt);
      m.setValue(optionsPtr + Offsets.llmOptions.systemPrompt, systemPromptPtr, '*');
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
        logger.debug('Calling rac_llm_component_generate via ccall({async:true})');
        const callResult = bridge.callFunction<number | Promise<number>>(
          'rac_llm_component_generate',
          'number',
          ['number', 'number', 'number', 'number'],
          [handle, promptPtr, optionsPtr, resultPtr],
          { async: true },
        );
        logger.debug(`ccall returned type=${typeof callResult}, isPromise=${callResult instanceof Promise}`);
        result = await callResult as number;
        logger.debug(`Generation returned result=${result}`);
      } catch (wasmErr: unknown) {
        // Log the full error details including stack trace
        if (wasmErr instanceof Error) {
          logger.error(`WASM generation error: ${wasmErr.message}\nStack: ${wasmErr.stack}`);
        } else {
          logger.error(`WASM generation error (raw): type=${typeof wasmErr}, value=${String(wasmErr)}`);
        }
        const detail = typeof wasmErr === 'number'
          ? `WASM C++ exception (ptr=${wasmErr}). The model's chat template may be unsupported.`
          : wasmErr instanceof Error ? wasmErr.message : String(wasmErr);
        throw new SDKError(
          SDKErrorCode.GenerationFailed,
          `LLM generation crashed: ${detail}`,
        );
      }
      bridge.checkResult(result, 'rac_llm_component_generate');

      // Read result struct (offsets from compiler via StructOffsets)
      const textPtr = m.getValue(resultPtr + Offsets.llmResult.text, '*');
      const text = bridge.readString(textPtr);
      const inputTokens = m.getValue(resultPtr + Offsets.llmResult.promptTokens, 'i32');
      const outputTokens = m.getValue(resultPtr + Offsets.llmResult.completionTokens, 'i32');

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
      if (systemPromptPtr) bridge.free(systemPromptPtr);
      m._free(optionsPtr);
      // Free the result struct itself (separate from _rac_llm_result_free
      // which only frees the inner `text` string).
      m._free(resultPtr);
    }
  }

  /**
   * Generate text with streaming (returns AsyncIterable of tokens).
   *
   * Async because the underlying C call uses `{async: true}` so Emscripten's
   * JSPI can suspend the WASM stack during WebGPU buffer operations.  On
   * CPU-only builds the result is simply an already-resolved Promise.
   *
   * @param prompt - Input text prompt
   * @param options - Generation options
   * @returns Streaming result with async token stream and final result promise
   */
  async generateStream(prompt: string, options: LLMGenerationOptions = {}): Promise<LLMStreamingResult> {
    const bridge = this.requireBridge();
    const m = bridge.module;
    const handle = await this.ensureLLMComponent();

    if (!this.isModelLoaded) {
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

      rejectResult?.(streamError!);

      m.removeFunction(tokenCbPtr);
      m.removeFunction(completeCbPtr);
      m.removeFunction(errorCbPtr);
    }, 'viii');

    // If system_prompt WASM offset is not available (WASM not rebuilt yet),
    // inject the system prompt into the user prompt as a fallback.
    let effectivePrompt = prompt;
    const canSetSystemPromptNatively = Offsets.llmOptions.systemPrompt !== 0;
    if (options.systemPrompt && !canSetSystemPromptNatively) {
      effectivePrompt = `[System: ${options.systemPrompt}]\n\n${prompt}`;
      logger.debug('System prompt injected into user prompt (WASM offset not available)');
    }

    // Start streaming generation
    const promptPtr = bridge.allocString(effectivePrompt);
    const optionsPtr = m._rac_wasm_create_llm_options_default();

    if (options.maxTokens !== undefined) {
      m.setValue(optionsPtr + Offsets.llmOptions.maxTokens, options.maxTokens, 'i32');
    }
    if (options.temperature !== undefined) {
      m.setValue(optionsPtr + Offsets.llmOptions.temperature, options.temperature, 'float');
    }
    // Set system_prompt if the WASM offset is available (non-zero = real offset)
    let systemPromptPtr = 0;
    if (options.systemPrompt && Offsets.llmOptions.systemPrompt) {
      systemPromptPtr = bridge.allocString(options.systemPrompt);
      m.setValue(optionsPtr + Offsets.llmOptions.systemPrompt, systemPromptPtr, '*');
    }

    let startResult: number;
    try {
      logger.debug('Calling rac_llm_component_generate_stream via ccall({async:true})');
      const callResult = bridge.callFunction<number | Promise<number>>(
        'rac_llm_component_generate_stream',
        'number',
        ['number', 'number', 'number', 'number', 'number', 'number', 'number'],
        [handle, promptPtr, optionsPtr, tokenCbPtr, completeCbPtr, errorCbPtr, 0],
        { async: true },
      );
      logger.debug(`ccall returned type=${typeof callResult}, isPromise=${callResult instanceof Promise}`);
      startResult = await callResult as number;
      logger.debug(`Stream generation returned result=${startResult}`);
    } catch (wasmErr: unknown) {
      bridge.free(promptPtr);
      if (systemPromptPtr) bridge.free(systemPromptPtr);
      m._free(optionsPtr);
      m.removeFunction(tokenCbPtr);
      m.removeFunction(completeCbPtr);
      m.removeFunction(errorCbPtr);
      if (wasmErr instanceof Error) {
        logger.error(`WASM stream generation error: ${wasmErr.message}\nStack: ${wasmErr.stack}`);
      } else {
        logger.error(`WASM stream generation error (raw): type=${typeof wasmErr}, value=${String(wasmErr)}`);
      }
      const detail = typeof wasmErr === 'number'
        ? `WASM C++ exception (ptr=${wasmErr}). The model's chat template may be unsupported.`
        : wasmErr instanceof Error ? wasmErr.message : String(wasmErr);
      throw new SDKError(
        SDKErrorCode.GenerationFailed,
        `LLM streaming generation crashed: ${detail}`,
      );
    }

    bridge.free(promptPtr);
    if (systemPromptPtr) bridge.free(systemPromptPtr);
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
  }

  /**
   * Cancel any in-progress generation.
   */
  cancel(): void {
    if (this._llmComponentHandle === 0) return;
    try {
      const m = LlamaCppBridge.shared.module;
      m._rac_llm_component_cancel(this._llmComponentHandle);
    } catch {
      // Ignore cancel errors
    }
  }

  /**
   * Clean up the LLM component (frees memory).
   */
  cleanup(): void {
    if (this._llmComponentHandle !== 0) {
      try {
        const m = LlamaCppBridge.shared.module;
        m._rac_llm_component_destroy(this._llmComponentHandle);
      } catch {
        // Ignore cleanup errors
      }
      this._llmComponentHandle = 0;
    }
  }
}

export const TextGeneration = new TextGenerationImpl();
