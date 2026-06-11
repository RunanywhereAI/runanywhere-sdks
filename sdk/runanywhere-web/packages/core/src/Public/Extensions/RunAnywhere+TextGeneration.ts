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
  StructuredOutputStreamEvent as StructuredOutputStreamEventMessage,
  StructuredOutputStreamEventKind,
  type StructuredOutputOptions,
  type StructuredOutputResult,
  type StructuredOutputStreamEvent,
} from '@runanywhere/proto-ts/structured_output';
import {
  inferenceFrameworkToJSON,
  ModelCategory,
  type ModelInfo,
} from '@runanywhere/proto-ts/model_types';
import type { LLMStreamingResult } from '../../types/index';
import { AsyncQueue } from '../../Foundation/AsyncQueue';
import { SDKException } from '../../Foundation/SDKException';
import { LLMProtoAdapter, StructuredOutputProtoAdapter } from '../../Adapters/ModalityProtoAdapter';
import { WebModelLifecycle } from './RunAnywhere+ModelLifecycle';

export type { LLMGenerationOptions, LLMGenerationResult };
export type { LLMStreamingResult };
export type { StructuredOutputResult, StructuredOutputStreamEvent };

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

/**
 * Structured-output mapping parity with Swift `toRALLMGenerateRequest`
 * (RALLMTypes+CppBridge.swift:66-74): when `structuredOutput` is set, the
 * request's `responseFormat` derives from its mode — `"json_object"` for
 * `STRUCTURED_OUTPUT_MODE_JSON_OBJECT`, `"json_schema"` for every other mode.
 */
function structuredOutputResponseFormat(
  structuredOutput: StructuredOutputOptions | undefined,
): string {
  if (structuredOutput == null) return '';
  return structuredOutput.mode === StructuredOutputMode.STRUCTURED_OUTPUT_MODE_JSON_OBJECT
    ? 'json_object'
    : 'json_schema';
}

function buildLLMGenerateRequest(
  prompt: string,
  options: Partial<LLMGenerationOptions> = {},
  streamingEnabled = false,
): LLMGenerateRequest {
  return {
    prompt,
    // Defaults mirror Swift `RALLMGenerationOptions.defaults()`
    // (RALLMTypes+CppBridge.swift:13-21): maxTokens 100, temperature 0.8,
    // topP 1.0, topK 0, repetitionPenalty 1.0.
    maxTokens: options.maxTokens ?? 100,
    temperature: options.temperature ?? 0.8,
    topP: options.topP ?? 1.0,
    topK: options.topK ?? 0,
    systemPrompt: options.systemPrompt ?? '',
    emitThoughts: options.thinkingPattern != null,
    repetitionPenalty: options.repetitionPenalty ?? 1.0,
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
    // Swift parity (RALLMTypes+CppBridge.swift:66-74): grammar and
    // responseFormat fall back to the structured-output configuration.
    grammar: options.grammar ?? options.structuredOutput?.grammar ?? '',
    responseFormat: options.responseFormat
      ?? structuredOutputResponseFormat(options.structuredOutput),
    echoPrompt: options.echoPrompt ?? false,
    nThreads: options.nThreads ?? 0,
    metadata: {},
  };
}

function isLLMGenerateRequest(
  value: LLMGenerateRequest | TextGenerationOptions,
): value is LLMGenerateRequest {
  // `requestId` is a required proto field on LLMGenerateRequest and does not
  // exist on LLMGenerationOptions, so its presence identifies the
  // request-shaped overload argument.
  return 'requestId' in value;
}

function normalizeLLMGenerateRequest(
  requestOrOptions: LLMGenerateRequest | TextGenerationOptions,
  streamingEnabled: boolean,
): LLMGenerateRequest {
  if (isLLMGenerateRequest(requestOrOptions)) {
    // Proto-request overload — mirrors Swift `generate(_ request:)` /
    // `generateStream(_ request:)` (RunAnywhere+TextGeneration.swift:43-87):
    // bypass option-building and submit the request as-is, with only the
    // streaming flag forced for the chosen entry point.
    return { ...requestOrOptions, streamingEnabled };
  }
  return buildLLMGenerateRequest(requestOrOptions.prompt, requestOrOptions, streamingEnabled);
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
              // Swift taxonomy: failed operations throw `.processingFailed`.
              throw SDKException.processingFailed(event.errorMessage);
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
// Core generation verbs
// ---------------------------------------------------------------------------

/**
 * Generate text through the generated-proto C++ LLM service ABI.
 *
 * The request overload mirrors Swift
 * `RunAnywhere.generate(_ request: RALLMGenerateRequest)`
 * (RunAnywhere+TextGeneration.swift:43-58); the options overload mirrors the
 * prompt convenience entry point and assembles the request with the Swift
 * defaults applied.
 */
async function generate(request: LLMGenerateRequest): Promise<LLMGenerationResult>;
async function generate(options: TextGenerationOptions): Promise<LLMGenerationResult>;
async function generate(
  requestOrOptions: LLMGenerateRequest | TextGenerationOptions,
): Promise<LLMGenerationResult> {
  const adapter = requireProtoLLM('TextGeneration.generate');
  const result = adapter.generate(normalizeLLMGenerateRequest(requestOrOptions, false));
  if (!result) {
    throw SDKException.backendNotAvailable(
      'TextGeneration.generate',
      'Native LLM proto path returned no result.',
    );
  }
  return result;
}

/**
 * Stream text generation through the generated-proto C++ LLM service ABI.
 *
 * The request overload mirrors Swift
 * `RunAnywhere.generateStream(_ request: RALLMGenerateRequest)`
 * (RunAnywhere+TextGeneration.swift:72-87).
 */
async function generateStream(request: LLMGenerateRequest): Promise<LLMStreamingResult>;
async function generateStream(options: TextGenerationOptions): Promise<LLMStreamingResult>;
async function generateStream(
  requestOrOptions: LLMGenerateRequest | TextGenerationOptions,
): Promise<LLMStreamingResult> {
  const adapter = requireProtoLLM('TextGeneration.generateStream');
  const events = adapter.generateStream(normalizeLLMGenerateRequest(requestOrOptions, true));
  return streamingResultFromEvents(events, () => {
    adapter.cancel();
  });
}

// ---------------------------------------------------------------------------
// `aggregateStream` — fold a streaming handle into a final result
// ---------------------------------------------------------------------------

/**
 * Fold an `LLMStreamingResult` into a canonical final `LLMGenerationResult`.
 *
 * Port of Swift `RunAnywhere.aggregateStream(prompt:events:onToken:)`
 * (RunAnywhere+TextGeneration.swift:129-198): consumes the token stream —
 * invoking `onToken` with the aggregated transcript so far — then awaits the
 * terminal aggregate and applies the Swift fallback chain: `text` falls back
 * to the concatenated tokens, `inputTokens` to the `max(1, prompt/4)`
 * estimate, `totalTokens` to `inputTokens + tokensGenerated`, timing and
 * throughput to local wall-clock measurements, while `promptEvalTimeMs` /
 * `decodeTimeMs` carry the backend's terminal metrics (0 when absent).
 * `modelUsed`/`framework` resolve from the currently-loaded language model
 * (Swift `currentModel(_:)`; RN `modelInfoForCategory`).
 */
export async function aggregateStream(
  prompt: string,
  streaming: LLMStreamingResult,
  onToken?: (transcript: string) => void | Promise<void>,
): Promise<LLMGenerationResult> {
  let fullResponse = '';
  let tokenCount = 0;
  let firstTokenAtMs: number | undefined;
  const startedAtMs = performance.now();

  for await (const token of streaming.stream) {
    if (!token) continue;
    if (firstTokenAtMs === undefined) firstTokenAtMs = performance.now();
    fullResponse += token;
    tokenCount += 1;
    if (onToken) await onToken(fullResponse);
  }

  // Terminal aggregate — already prefers the backend's final-event metrics
  // and falls back to the queue-tracked tokens (see finalLLMResult).
  const result = await streaming.result;

  const totalLatencyMs = performance.now() - startedAtMs;
  const ttftMs = firstTokenAtMs === undefined ? undefined : firstTokenAtMs - startedAtMs;

  // Swift resolves the loaded language model via `currentModel(_:)`
  // (RunAnywhere+TextGeneration.swift:162-168).
  let model: ModelInfo | null = null;
  try {
    model = WebModelLifecycle.modelInfoForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE);
  } catch {
    model = null;
  }

  // Swift parity (RunAnywhere+TextGeneration.swift:179-182): estimate
  // inputTokens as max(1, prompt/4) when the backend did not report them and
  // recompute totalTokens from that estimate when absent.
  const inputTokens = result.inputTokens || Math.max(1, Math.floor(prompt.length / 4));
  const tokensGenerated = result.tokensGenerated || tokenCount;
  return {
    ...result,
    text: result.text || fullResponse,
    inputTokens,
    tokensGenerated,
    responseTokens: tokensGenerated,
    totalTokens: result.totalTokens || inputTokens + tokensGenerated,
    modelUsed: model?.id ?? '',
    framework: model ? inferenceFrameworkToJSON(model.framework) : '',
    generationTimeMs: result.generationTimeMs || totalLatencyMs,
    tokensPerSecond: result.tokensPerSecond
      || (totalLatencyMs > 0 ? tokenCount / (totalLatencyMs / 1000) : 0),
    ttftMs: result.ttftMs ?? ttftMs,
    promptEvalTimeMs: result.promptEvalTimeMs ?? 0,
    decodeTimeMs: result.decodeTimeMs ?? 0,
  };
}

// ---------------------------------------------------------------------------
// §3 `generateStructuredStream` — canonical flat verb
// ---------------------------------------------------------------------------

/**
 * Streaming structured output (§3 `generateStructuredStream`).
 *
 * Mirrors Swift `RunAnywhere.generateStructuredStream(prompt:schema:options:)`
 * (RunAnywhere+StructuredOutput.swift:58-134): generation runs through the
 * real LLM streaming path with the structured-output options applied to the
 * request; each non-empty token is emitted as a `.token`
 * `StructuredOutputStreamEvent`, and once the producer finishes the
 * accumulated text is parsed via `extractStructuredOutput` and emitted as the
 * terminal `.completed` event carrying the validated `StructuredOutputResult`.
 *
 * In-flight failures (LLM driver errors, parse/validation errors) terminate
 * the iterable with a throw, matching the cross-SDK contract (Swift
 * `AsyncThrowingStream`, Kotlin `Flow` exception propagation).
 *
 * Cancellation parity: the native stream is cancelled only when the consumer
 * abandons iteration while the producer is still live — mirroring Swift's
 * `onTermination` switch (RunAnywhere+StructuredOutput.swift:113-132) that
 * fires `cancelGeneration()` solely on `.cancelled`, never after producer
 * completion.
 */
export async function* generateStructuredStream(
  prompt: string,
  schema: JSONSchemaDescriptor,
  options?: Partial<LLMGenerationOptions>,
): AsyncIterable<StructuredOutputStreamEvent> {
  const streaming = await generateStream({
    ...options,
    prompt,
    structuredOutput: structuredOutputOptionsFromSchema(schema),
  });

  let accumulated = '';
  let seq = 0;
  let nativeStreamDone = false;
  try {
    for await (const token of streaming.stream) {
      if (!token) continue;
      accumulated += token;
      seq += 1;
      yield StructuredOutputStreamEventMessage.fromPartial({
        kind: StructuredOutputStreamEventKind.STRUCTURED_OUTPUT_STREAM_EVENT_KIND_TOKEN,
        token,
        seq,
      });
    }
    nativeStreamDone = true;
    // Surface in-flight generation failures as throws before parsing.
    await streaming.result;
    const result = extractStructuredOutput(accumulated, schema);
    seq += 1;
    yield StructuredOutputStreamEventMessage.fromPartial({
      kind: StructuredOutputStreamEventKind.STRUCTURED_OUTPUT_STREAM_EVENT_KIND_COMPLETED,
      result,
      seq,
    });
  } catch (error) {
    // Producer self-terminated (stream/result/parse failure) — never fire
    // the native cancel for it. Swallow the duplicate rejection carried by
    // the terminal result promise before rethrowing the original error.
    nativeStreamDone = true;
    void streaming.result.catch(() => undefined);
    throw error;
  } finally {
    if (!nativeStreamDone) streaming.cancel();
  }
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

  generate,

  generateStream,

  aggregateStream,

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
