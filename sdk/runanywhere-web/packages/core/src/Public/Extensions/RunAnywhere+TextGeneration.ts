/**
 * RunAnywhere+TextGeneration.ts
 *
 * Text generation namespace — mirrors Swift's `RunAnywhere+TextGeneration.swift`.
 * Provides `RunAnywhere.textGeneration.*` capability surface (generate / generateStream / chat).
 * Also exposes the canonical §3 verbs `generateStructuredStream` and
 * `extractStructuredOutput` as flat top-level functions for use by RunAnywhere.ts.
 *
 * All paths go through proto-byte adapters — there is no JS provider routing.
 */

import type { LLMGenerateRequest, LLMStreamEvent } from '@runanywhere/proto-ts/llm_service';
import type {
  LLMGenerationOptions,
  LLMGenerationResult,
} from '@runanywhere/proto-ts/llm_options';
import type { ToolCall } from '@runanywhere/proto-ts/tool_calling';
import {
  StructuredOutputMode,
  type StructuredOutputOptions,
  type StructuredOutputResult,
} from '@runanywhere/proto-ts/structured_output';
import type { LLMStreamingResult } from '../../types/index';
import { AsyncQueue } from '../../Foundation/AsyncQueue';
import { SDKException } from '../../Foundation/SDKException';
import { LLMProtoAdapter, StructuredOutputProtoAdapter } from '../../Adapters/ModalityProtoAdapter';

export type { LLMGenerationOptions, LLMGenerationResult };
export type { LLMStreamingResult };
export type { StructuredOutputResult };

export type TextGenerationOptions = Partial<LLMGenerationOptions> & {
  prompt: string;
};

// ---------------------------------------------------------------------------
// Schema type accepted by the canonical structured-output verbs.
// ---------------------------------------------------------------------------

/** Minimal JSON Schema descriptor accepted by structured-output methods. */
export interface JSONSchemaDescriptor {
  jsonSchema: string;
  parse?: (text: string) => unknown;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function buildLLMGenerateRequest(
  prompt: string,
  options: Partial<LLMGenerationOptions> = {},
  streamingEnabled = false,
): LLMGenerateRequest {
  return {
    prompt,
    maxTokens: options.maxTokens ?? 0,
    temperature: options.temperature ?? 0,
    topP: options.topP ?? 0,
    topK: options.topK ?? 0,
    systemPrompt: options.systemPrompt ?? '',
    emitThoughts: options.thinkingPattern != null,
    repetitionPenalty: options.repetitionPenalty ?? 0,
    stopSequences: options.stopSequences ?? [],
    streamingEnabled,
    preferredFramework: options.preferredFramework == null
      ? ''
      : String(options.preferredFramework),
    jsonSchema: options.jsonSchema ?? options.structuredOutput?.jsonSchema ?? '',
    executionTarget: options.executionTarget == null
      ? ''
      : String(options.executionTarget),
    requestId: '',
    modelId: '',
    conversationId: '',
    seed: options.seed ?? 0,
    frequencyPenalty: options.frequencyPenalty ?? 0,
    presencePenalty: options.presencePenalty ?? 0,
    minP: options.minP ?? 0,
    grammar: options.grammar ?? '',
    responseFormat: options.responseFormat ?? '',
    echoPrompt: options.echoPrompt ?? false,
    nThreads: options.nThreads ?? 0,
    metadata: {},
  };
}

function structuredOutputOptionsFromSchema(
  schema: JSONSchemaDescriptor,
): StructuredOutputOptions {
  return {
    includeSchemaInPrompt: true,
    jsonSchema: schema.jsonSchema,
    mode: StructuredOutputMode.STRUCTURED_OUTPUT_MODE_JSON_SCHEMA,
    repairJson: false,
    maxRetries: 0,
  };
}

function streamingResultFromEvents(
  events: AsyncIterable<LLMStreamEvent>,
  cancelNative: () => void,
): LLMStreamingResult {
  const queue = new AsyncQueue<string>();
  let started = false;
  let cancelled = false;
  let fullText = '';
  let tokenCount = 0;
  let finalEvent: LLMStreamEvent | undefined;
  // pass2-syn-010-followup-web: surface LLMStreamEvent.toolCall (proto field 18)
  // on the final LLMGenerationResult.toolCalls list so callers driving tool
  // calling through the streaming path see the same shape they would see from
  // the non-streaming `generate()` call. C++ producer emits this field when the
  // backend supports streamed tool-call deltas (libprotobuf-enabled builds);
  // on WASM the field is currently always absent (see syn-010 evidence).
  const accumulatedToolCalls: ToolCall[] = [];
  const startedAt = performance.now();

  const result = new Promise<LLMGenerationResult>((resolve, reject) => {
    const start = (): void => {
      if (started) return;
      started = true;
      void (async () => {
        try {
          for await (const event of events) {
            finalEvent = event;
            if (event.token) {
              fullText += event.token;
              tokenCount += 1;
              queue.push(event.token);
            }
            if (event.toolCall) {
              accumulatedToolCalls.push(event.toolCall);
            }
            if (event.errorMessage) {
              throw SDKException.generationFailed(event.errorMessage);
            }
          }
          queue.complete();
          resolve(
            finalLLMResult(fullText, tokenCount, startedAt, finalEvent, accumulatedToolCalls),
          );
        } catch (error) {
          queue.fail(error instanceof Error ? error : new Error(String(error)));
          reject(error);
        }
      })();
    };

    const originalIterator = queue[Symbol.asyncIterator].bind(queue);
    queue[Symbol.asyncIterator] = () => {
      start();
      return originalIterator();
    };
    start();
  });

  return {
    stream: queue,
    result,
    cancel() {
      if (cancelled) return;
      cancelled = true;
      // Fire the native cancel proto. The underlying `events` async iter
      // terminates once the native stream finishes (immediately for sync
      // backends, on next yield for async ones). The producer IIFE above
      // calls `queue.complete()` when the upstream loop exits, so we
      // intentionally do NOT close the queue here — tokens already emitted
      // by the backend remain observable to consumers iterating after the
      // cancel call.
      cancelNative();
    },
  };
}

function finalLLMResult(
  fullText: string,
  tokenCount: number,
  startedAt: number,
  finalEvent?: LLMStreamEvent,
  streamedToolCalls: ToolCall[] = [],
): LLMGenerationResult {
  const final = finalEvent?.result;
  const generationTimeMs = final?.totalTimeMs ?? performance.now() - startedAt;
  const inputTokens = final?.promptTokens ?? 0;
  const tokensGenerated = final?.completionTokens ?? tokenCount;
  // Prefer tool_calls from the final LLMGenerationResult (whole-call snapshot)
  // when present; otherwise fall back to the per-event accumulator so callers
  // still see streamed tool calls on backends that don't emit a final result.
  const toolCalls = final?.toolCalls?.length ? final.toolCalls : streamedToolCalls;
  return {
    text: final?.text ?? fullText,
    thinkingContent: final?.thinkingContent,
    inputTokens,
    tokensGenerated,
    modelUsed: '',
    generationTimeMs,
    ttftMs: final?.timeToFirstTokenMs,
    tokensPerSecond: final?.tokensPerSecond
      ?? (generationTimeMs > 0 ? (tokensGenerated / generationTimeMs) * 1000 : 0),
    finishReason: finalEvent?.finishReason || final?.finishReason || '',
    thinkingTokens: 0,
    responseTokens: tokensGenerated,
    totalTokens: final?.totalTokens ?? inputTokens + tokensGenerated,
    errorMessage: finalEvent?.errorMessage || undefined,
    errorCode: final?.errorCode ?? finalEvent?.errorCode ?? 0,
    cachedPromptTokens: 0,
    promptEvalTimeMs: final?.promptEvalTimeMs ?? 0,
    decodeTimeMs: final?.decodeTimeMs ?? 0,
    toolCalls,
    toolResults: final?.toolResults ?? [],
  };
}

function requireProtoLLM(verb: string): NonNullable<ReturnType<typeof LLMProtoAdapter.tryDefault>> {
  const adapter = LLMProtoAdapter.tryDefault();
  if (!adapter || !adapter.supportsProtoLLM()) {
    throw SDKException.backendNotAvailable(
      verb,
      'No Web WASM backend with rac_llm_*_proto exports is registered. ' +
      'Install a backend package and call its register() before generating text.',
    );
  }
  return adapter;
}

// ---------------------------------------------------------------------------
// §3 `generateStructuredStream` — canonical flat verb
// ---------------------------------------------------------------------------

/**
 * Streaming structured output (§3 `generateStructuredStream`).
 *
 * Uses the generated-proto LLM request shape for generation, then routes
 * extraction and validation through the structured-output proto ABI.
 */
export async function* generateStructuredStream(
  prompt: string,
  schema: JSONSchemaDescriptor,
  options?: Partial<LLMGenerationOptions>,
): AsyncIterable<StructuredOutputResult> {
  const result = await TextGeneration.generate({
    ...options,
    prompt,
    jsonSchema: schema.jsonSchema,
  });
  yield extractStructuredOutput(
    result.text || result.jsonOutput || result.structuredOutputValidation?.extractedJson || '',
    schema,
  );
}

// ---------------------------------------------------------------------------
// §3 `extractStructuredOutput` — canonical flat verb
// ---------------------------------------------------------------------------

/**
 * Extract and validate structured output from already-generated text (§3).
 *
 * Native structured-output extraction is owned by the C++ modality layer.
 */
export function extractStructuredOutput(
  text: string,
  schema: JSONSchemaDescriptor,
): StructuredOutputResult {
  const adapter = StructuredOutputProtoAdapter.tryDefault();
  if (adapter?.supportsProtoParse()) {
    const result = adapter.parse({
      requestId: '',
      text,
      options: structuredOutputOptionsFromSchema(schema),
      metadata: {},
    });
    if (result) return result;
  }
  throw SDKException.backendNotAvailable(
    'extractStructuredOutput',
    'This Web WASM build does not export rac_structured_output_parse_proto.',
  );
}

// ---------------------------------------------------------------------------
// TextGeneration namespace object
// ---------------------------------------------------------------------------

export const TextGeneration = {
  /**
   * Returns true when a backend module's `register()` has installed a WASM
   * module that exports the proto-byte LLM ABI (`rac_llm_*_proto` symbols).
   * Mirrors `RunAnywhere.stt.supportsProtoSTT()` for the LLM modality.
   */
  supportsProtoLLM(): boolean {
    return LLMProtoAdapter.tryDefault()?.supportsProtoLLM() ?? false;
  },

  async generate(options: TextGenerationOptions): Promise<LLMGenerationResult> {
    const adapter = requireProtoLLM('TextGeneration.generate');
    const result = adapter.generate(buildLLMGenerateRequest(options.prompt, options, false));
    if (!result) {
      throw SDKException.backendNotAvailable(
        'TextGeneration.generate',
        'Native LLM proto path returned no result.',
      );
    }
    return result;
  },

  async generateStream(options: TextGenerationOptions): Promise<LLMStreamingResult> {
    const adapter = requireProtoLLM('TextGeneration.generateStream');
    const events = adapter.generateStream(buildLLMGenerateRequest(options.prompt, options, true));
    return streamingResultFromEvents(events, () => {
      adapter.cancel();
    });
  },

  cancelGeneration(): void {
    LLMProtoAdapter.tryDefault()?.cancel();
  },

  async chat(prompt: string, options?: Partial<LLMGenerationOptions>): Promise<string> {
    const result = await TextGeneration.generate({
      ...(options ?? {}),
      prompt,
    });
    return result.text;
  },

  generateStructuredStream,
  extractStructuredOutput,
};
