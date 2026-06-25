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
  executionTargetToJSON,
  LLMGenerationOptions as LLMGenerationOptionsMessage,
} from '@runanywhere/proto-ts/llm_options';
import {
  LLMGenerationResult as LLMGenerationResultMessage,
} from '@runanywhere/proto-ts/llm_options';
import {
  LLMGenerateRequest,
  LLMStreamEvent,
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
  const canonicalOptions = options
    ? LLMGenerationOptionsMessage.fromPartial({
        ...options,
        streamingEnabled,
      })
    : undefined;

  return LLMGenerateRequest.fromPartial({
    prompt,
    // Defaults mirror Swift RALLMTypes+CppBridge.swift (maxTokens 100,
    // temperature 0.8, topP 1.0, topK 0, repetitionPenalty 1.0).
    maxTokens: options?.maxTokens ?? 100,
    temperature: options?.temperature ?? 0.8,
    topP: options?.topP ?? 1.0,
    topK: options?.topK ?? 0,
    systemPrompt: options?.systemPrompt ?? '',
    emitThoughts: !!options?.thinkingPattern,
    repetitionPenalty: options?.repetitionPenalty ?? 1.0,
    stopSequences: options?.stopSequences ?? [],
    streamingEnabled,
    preferredFramework:
      options?.preferredFramework !== undefined
        ? inferenceFrameworkToJSON(options.preferredFramework)
        : '',
    jsonSchema: options?.jsonSchema ?? options?.structuredOutput?.jsonSchema ?? '',
    executionTarget:
      options?.executionTarget !== undefined
        ? executionTargetToJSON(options.executionTarget)
        : '',
    seed: options?.seed ?? 0,
    frequencyPenalty: options?.frequencyPenalty ?? 0,
    presencePenalty: options?.presencePenalty ?? 0,
    minP: options?.minP ?? 0,
    grammar: options?.grammar ?? '',
    responseFormat: options?.responseFormat ?? '',
    echoPrompt: options?.echoPrompt ?? false,
    nThreads: options?.nThreads ?? 0,
    options: canonicalOptions,
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
    streamingEnabled,
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
 * Wire-up (iOS parity): a single atomic `native.llmGenerateStreamProto`
 * call — the RN binding for `rac_llm_generate_stream_proto` — wires the
 * per-request stream callback and runs generation together, exactly like
 * Swift's `CppBridge.LLM.generateStream` / `ProtoStreamContext.runRequestStream`.
 * Each invocation of the callback delivers one serialized
 * `runanywhere.v1.LLMStreamEvent`; the stream finishes on `event.isFinal`.
 *
 * This replaces the previous handle-subscription approach
 * (`NitroLLM.subscribeProtoEvents` + `native.llmGenerateProto`), which
 * registered a callback the *non-streaming* buffered generate path never
 * feeds — so no events were ever delivered and the UI hung "thinking
 * forever". `rac_llm_set_stream_proto_callback` is fed by the component
 * `generate_stream` path, not by the handleless `rac_llm_generate_proto`.
 *
 * Cancellation propagates through `for-await break` → `iterator.return()`
 * → `native.llmCancelProto()` → C++ generation observes the cancel signal.
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

  return {
    [Symbol.asyncIterator](): AsyncIterator<LLMStreamEventType> {
      const queue: LLMStreamEventType[] = [];
      let resolver: ((value: IteratorResult<LLMStreamEventType>) => void) | null = null;
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

      const start = (): void => {
        if (started) return;
        started = true;
        // iOS parity: one atomic streaming call wires the callback + runs
        // generation together (no register/generate race). The callback
        // receives one serialized LLMStreamEvent per token; `isFinal` ends it.
        ensureServicesReady()
          .then(() =>
            native.llmGenerateStreamProto(requestBytes, (eventBytes: ArrayBuffer) => {
              try {
                const event = LLMStreamEvent.decode(arrayBufferToBytes(eventBytes));
                push(event);
                if (event.isFinal) {
                  finish();
                }
              } catch (error) {
                streamError =
                  error instanceof Error ? error : new Error(String(error));
                finish();
              }
            }),
          )
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
          start();
          if (queue.length > 0) {
            return { value: queue.shift()!, done: false };
          }
          if (streamError) {
            throw streamError;
          }
          if (done) {
            return { value: undefined as unknown as LLMStreamEventType, done: true };
          }
          return new Promise<IteratorResult<LLMStreamEventType>>((resolve) => {
            resolver = resolve;
          }).then((result) => {
            if (streamError) {
              throw streamError;
            }
            return result;
          });
        },
        async return(): Promise<IteratorResult<LLMStreamEventType>> {
          // Await the native cancel before resolving so back-to-back
          // cancel → generate sequences are race-free. Matches Swift
          // cancelGeneration() which awaits CppBridge.LLM.shared.cancelProto().
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

  for await (const event of iterable) {
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
