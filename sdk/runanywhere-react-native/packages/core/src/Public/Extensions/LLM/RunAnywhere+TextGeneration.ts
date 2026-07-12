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
} from '../../../native';
import { ensureServicesReady } from '../../../Foundation/Initialization/ServicesReadyGuard';
import {
  isSDKInitialized,
  requireInitialized,
} from '../../../Foundation/Initialization/InitializedGuard';
import { SDKException } from '../../../Foundation/Errors/SDKException';
import type {
  LLMGenerationOptions,
  LLMGenerationResult,
} from '@runanywhere/proto-ts/llm_options';
import {
  LLMGenerationOptions as LLMGenerationOptionsMessage,
} from '@runanywhere/proto-ts/llm_options';
import {
  LLMGenerationResult as LLMGenerationResultMessage,
} from '@runanywhere/proto-ts/llm_options';
import {
  LLMGenerateRequest,
  LLMStreamEvent as LLMStreamEventMessage,
  type LLMStreamEvent as LLMStreamEventType,
} from '@runanywhere/proto-ts/llm_service';
import { inferenceFrameworkToJSON, ModelCategory } from '@runanywhere/proto-ts/model_types';
import { modelInfoForCategory } from '../Models/RunAnywhere+ModelLifecycle';
import { arrayBufferToBytes } from '../../../services/ProtoBytes';
import { encodeProtoMessage } from '../../../services/ProtoWire';

function buildLLMGenerateRequest(
  prompt: string,
  options?: LLMGenerationOptions,
  streamingEnabled: boolean = false
): LLMGenerateRequest {
  const canonicalOptions = generationOptionsForRequest(options, streamingEnabled);

  return LLMGenerateRequest.fromPartial({
    prompt,
    emitThoughts: !!options?.thinkingPattern,
    options: canonicalOptions,
  });
}

function generationOptionsForRequest(
  options: LLMGenerationOptions | undefined,
  streamingEnabled: boolean
): LLMGenerationOptions {
  return LLMGenerationOptionsMessage.fromPartial({
    maxTokens: options?.maxTokens ?? 100,
    temperature: options?.temperature ?? 0.8,
    topP: options?.topP ?? 1.0,
    topK: options?.topK ?? 0,
    repetitionPenalty: options?.repetitionPenalty ?? 1.0,
    ...options,
    streamingEnabled,
    jsonSchema: options?.jsonSchema ?? options?.structuredOutput?.jsonSchema,
    grammar: options?.grammar ?? options?.structuredOutput?.grammar,
  });
}

function encodeLLMGenerateRequest(request: LLMGenerateRequest): ArrayBuffer {
  return encodeProtoMessage(request, LLMGenerateRequest);
}

function decodeLLMGenerationResult(buffer: ArrayBuffer): LLMGenerationResult {
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) {
    throw SDKException.protoDecodeFailed('llmGenerateProto');
  }
  return LLMGenerationResultMessage.decode(bytes);
}

function normalizeLLMGenerateRequest(
  requestOrPrompt: LLMGenerateRequest | string,
  options: LLMGenerationOptions | undefined,
  streamingEnabled: boolean
): LLMGenerateRequest {
  if (typeof requestOrPrompt === 'string') {
    return buildLLMGenerateRequest(requestOrPrompt, options, streamingEnabled);
  }
  return LLMGenerateRequest.fromPartial({
    ...requestOrPrompt,
    options: generationOptionsForRequest(requestOrPrompt.options, streamingEnabled),
  });
}

/**
 * Text generation with full proto request/result metrics.
 * Matches Swift SDK: `RunAnywhere.generate(_ request: RALLMGenerateRequest)`.
 */
export async function generate(
  request: LLMGenerateRequest
): Promise<LLMGenerationResult>;
export async function generate(
  prompt: string,
  options?: LLMGenerationOptions
): Promise<LLMGenerationResult>;
export async function generate(
  requestOrPrompt: LLMGenerateRequest | string,
  options?: LLMGenerationOptions
): Promise<LLMGenerationResult> {
  // Swift parity: guard isInitialized (RunAnywhere+TextGeneration.swift:44-46).
  requireInitialized();
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  await ensureServicesReady();
  const native = requireNativeModule();
  const requestBytes = encodeLLMGenerateRequest(
    normalizeLLMGenerateRequest(requestOrPrompt, options, false)
  );
  const resultBytes = await native.llmGenerateProto(requestBytes);
  return decodeLLMGenerationResult(resultBytes);
}

/**
 * Streaming text generation — canonical cross-SDK signature.
 *
 * Returns an AsyncIterable<LLMStreamEvent> where each event carries
 * `seq`, `timestampUs`, `token`, `isFinal`, `kind`, `tokenId`, `logprob`,
 * `finishReason`, and `errorMessage` (proto `LLMStreamEvent` shape).
 *
 * Matches Swift SDK: `RunAnywhere.generateStream(_ request: RALLMGenerateRequest)`.
 *
 * Wire-up: events arrive via `native.llmGenerateStreamProto(bytes, onEvent)`
 * — the dedicated callback-streaming method (same path as STT/TTS/VLM). Each
 * `onEvent` delivers one proto-encoded `LLMStreamEvent`; the wrapper buffers
 * them into this AsyncIterable. Cancellation propagates through
 * `iterator.return()` → `native.llmCancelProto()`.
 */
export function generateStream(
  request: LLMGenerateRequest,
): AsyncIterable<LLMStreamEventType>;
export function generateStream(
  prompt: string,
  options?: LLMGenerationOptions,
): AsyncIterable<LLMStreamEventType>;
export function generateStream(
  requestOrPrompt: LLMGenerateRequest | string,
  options?: LLMGenerationOptions,
): AsyncIterable<LLMStreamEventType> {
  // Swift parity: guard isInitialized (RunAnywhere+TextGeneration.swift:73-75).
  requireInitialized();
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }

  const native = requireNativeModule();
  const llmRequest = normalizeLLMGenerateRequest(requestOrPrompt, options, true);
  const requestBytes = encodeLLMGenerateRequest(llmRequest);

  // Stream via the dedicated callback method `llmGenerateStreamProto(bytes, cb)`
  // — the same path STT/TTS/VLM use. The earlier handle-subscribe variant paired
  // with the BLOCKING `llmGenerateProto` never fed the subscription (native
  // generated, returned the aggregate, and emitted no per-token events), so the
  // UI hung "generating" forever. Mirrors RunAnywhere+VisionLanguage.processStream.
  return {
    [Symbol.asyncIterator](): AsyncIterator<LLMStreamEventType> {
      const queue: LLMStreamEventType[] = [];
      let resolver: ((v: IteratorResult<LLMStreamEventType>) => void) | null = null;
      let done = false;
      let started = false;
      let streamError: Error | null = null;

      const finish = (): void => {
        done = true;
        if (resolver) {
          resolver({ value: undefined as unknown as LLMStreamEventType, done: true });
          resolver = null;
        }
      };

      const push = (event: LLMStreamEventType): void => {
        if (resolver) {
          resolver({ value: event, done: false });
          resolver = null;
        } else {
          queue.push(event);
        }
      };

      const start = async (): Promise<void> => {
        if (started) return;
        started = true;
        await ensureServicesReady();
        native
          .llmGenerateStreamProto(requestBytes, (eventBytes: ArrayBuffer) => {
            try {
              const event = LLMStreamEventMessage.decode(
                arrayBufferToBytes(eventBytes)
              );
              if (event.errorMessage) {
                streamError = new Error(event.errorMessage);
              }
              push(event);
              if (event.isFinal) {
                finish();
              }
            } catch (error) {
              streamError =
                error instanceof Error ? error : new Error(String(error));
              finish();
            }
          })
          .then(() => {
            if (!done) finish();
          })
          .catch((err: Error) => {
            streamError = err;
            finish();
          });
      };

      return {
        async next(): Promise<IteratorResult<LLMStreamEventType>> {
          await start();
          if (queue.length > 0) {
            return { value: queue.shift()!, done: false };
          }
          if (streamError) throw streamError;
          if (done) {
            return { value: undefined as unknown as LLMStreamEventType, done: true };
          }
          return new Promise<IteratorResult<LLMStreamEventType>>((resolve) => {
            resolver = resolve;
          }).then((result) => {
            if (streamError) throw streamError;
            return result;
          });
        },
        async return(): Promise<IteratorResult<LLMStreamEventType>> {
          // Await the native cancel before resolving so back-to-back
          // cancel → generate sequences are race-free.
          try { await native.llmCancelProto(); } catch { /* noop */ }
          finish();
          return { value: undefined as unknown as LLMStreamEventType, done: true };
        },
      };
    },
  };
}

/**
 * Cancel ongoing text generation.
 *
 * Matches Swift SDK: `RunAnywhere.cancelGeneration() async`.
 */
export async function cancelGeneration(): Promise<void> {
  // Swift parity: `guard isInitialized else { return }`
  // (RunAnywhere+TextGeneration.swift:98).
  if (!isSDKInitialized()) {
    return;
  }
  if (!isNativeModuleAvailable()) {
    return;
  }
  const native = requireNativeModule();
  await native.llmCancelProto();
}

/**
 * Drive an async-iterable LLM stream to completion, tallying tokens, TTFT,
 * and tokens/sec, and populating `framework` via the model registry.
 *
 * Mirrors Swift SDK: `RunAnywhere.aggregateStream(prompt:events:onToken:)`.
 *
 * @param prompt   The original prompt string (used to estimate input tokens
 *                 when the native side does not report them, matching Swift's
 *                 `max(1, prompt.count / 4)` heuristic).
 * @param iterable The `AsyncIterable<LLMStreamEvent>` returned by
 *                 `generateStream(...)`. Consumed until `isFinal == true`
 *                 or the stream ends.
 * @param onToken  Optional callback invoked after each non-empty token is
 *                 appended. Receives the full aggregated transcript so far —
 *                 suitable for live UI updates.
 * @returns A populated `LLMGenerationResult` with `text`, timing metrics,
 *          and `framework` resolved from the currently-loaded language model.
 */
export async function aggregateStream(
  prompt: string,
  iterable: AsyncIterable<LLMStreamEventType>,
  onToken?: (transcript: string) => void | Promise<void>,
): Promise<LLMGenerationResult> {
  let fullResponse = '';
  let tokenCount = 0;
  let firstTokenTimeMs: number | undefined;
  const startTimeMs = Date.now();
  let finishReason = '';
  let terminalError = '';
  let finalEvent: LLMStreamEventType | undefined;

  // Drive the stream with a manual `iterator.next()` loop, NOT `for await...of`.
  // Hermes does not support `for await...of` over the NitroModules-backed LLM
  // stream — it silently fails to iterate, so tokens never arrive and the UI
  // hangs "thinking" forever. `iterator.return()` in the finally tears the
  // native subscription down (cancel) when we break early or throw.
  const iterator = iterable[Symbol.asyncIterator]();
  try {
    for (;;) {
      const next = await iterator.next();
      if (next.done) break;
      const event = next.value;
      if (event.token && event.token.length > 0) {
        if (firstTokenTimeMs === undefined) {
          firstTokenTimeMs = Date.now();
        }
        fullResponse += event.token;
        tokenCount += 1;
        if (onToken) {
          await onToken(fullResponse);
        }
      }
      if (event.isFinal) {
        finalEvent = event;
        finishReason = event.finishReason ?? '';
        terminalError = event.errorMessage ?? '';
        break;
      }
    }
  } finally {
    await iterator.return?.();
  }

  const totalLatencyMs = Date.now() - startTimeMs;
  const ttftMs =
    firstTokenTimeMs !== undefined ? firstTokenTimeMs - startTimeMs : undefined;

  // Resolve the currently-loaded language model to populate `framework`.
  const modelInfo = await modelInfoForCategory(
    ModelCategory.MODEL_CATEGORY_LANGUAGE,
  ).catch(() => null);
  const modelId = modelInfo?.id ?? '';
  const framework =
    modelInfo?.framework !== undefined
      ? inferenceFrameworkToJSON(modelInfo.framework)
      : '';

  // Prefer the backend's terminal aggregate result (text + metrics) when the
  // final event carries one, matching the Web SDK; fall back to the locally
  // concatenated text / wall-clock metrics for backends that omit it.
  const final = finalEvent?.result;
  const inputTokens =
    final?.promptTokens ?? Math.max(1, Math.floor(prompt.length / 4));
  const tokensGenerated = final?.completionTokens ?? tokenCount;
  return LLMGenerationResultMessage.fromPartial({
    text: final?.text ?? fullResponse,
    // Swift parity (RunAnywhere+TextGeneration.swift:176-178): propagate the
    // backend's thinking content only when the final event carries it.
    ...(final?.thinkingContent !== undefined
      ? { thinkingContent: final.thinkingContent }
      : {}),
    inputTokens,
    tokensGenerated,
    responseTokens: tokensGenerated,
    // Swift parity (line 182): totalTokens falls back to input + generated.
    totalTokens: final?.totalTokens ?? inputTokens + tokensGenerated,
    modelUsed: modelId,
    generationTimeMs: final?.totalTimeMs ?? totalLatencyMs,
    framework,
    // Swift parity (lines 186-187): prompt/decode timings from the backend's
    // terminal aggregate, 0 when absent.
    promptEvalTimeMs: final?.promptEvalTimeMs ?? 0,
    decodeTimeMs: final?.decodeTimeMs ?? 0,
    tokensPerSecond:
      final?.tokensPerSecond ??
      (totalLatencyMs > 0 ? tokenCount / (totalLatencyMs / 1000) : 0),
    ...((final?.timeToFirstTokenMs ?? ttftMs) !== undefined
      ? { ttftMs: final?.timeToFirstTokenMs ?? ttftMs }
      : {}),
    ...(finishReason.length > 0 ? { finishReason } : {}),
    ...(terminalError.length > 0 ? { errorMessage: terminalError } : {}),
  });
}
