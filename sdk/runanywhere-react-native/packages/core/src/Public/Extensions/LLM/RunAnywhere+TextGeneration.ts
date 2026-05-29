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
import { SDKException } from '../../../Foundation/Errors/SDKException';
import type {
  LLMGenerationOptions,
  LLMGenerationResult,
} from '@runanywhere/proto-ts/llm_options';
import {
  executionTargetToJSON,
} from '@runanywhere/proto-ts/llm_options';
import {
  LLMGenerationResult as LLMGenerationResultMessage,
} from '@runanywhere/proto-ts/llm_options';
import {
  LLMGenerateRequest,
  type LLMStreamEvent as LLMStreamEventType,
} from '@runanywhere/proto-ts/llm_service';
import { inferenceFrameworkToJSON, ModelCategory } from '@runanywhere/proto-ts/model_types';
import { modelInfoForCategory } from '../Models/RunAnywhere+ModelLifecycle';
import { arrayBufferToBytes } from '../../../services/ProtoBytes';
import { encodeProtoMessage } from '../../../services/ProtoWire';
import { LLMStreamAdapter } from '../../../Adapters/LLMStreamAdapter';

function buildLLMGenerateRequest(
  prompt: string,
  options?: LLMGenerationOptions,
  streamingEnabled: boolean = false
): LLMGenerateRequest {
  return LLMGenerateRequest.fromPartial({
    prompt,
    maxTokens: options?.maxTokens ?? 1000,
    temperature: options?.temperature ?? 0.7,
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
 * Wire-up: events arrive via `LLMStreamAdapter` which calls
 * `NitroLLM.subscribeProtoEvents(handle, ...)` against the LLM handle
 * obtained from `RunAnywhereCore.getLLMHandle()`. Generation is triggered
 * by `native.llmGenerateProto` once the handle subscription is active.
 * Cancellation propagates through `for-await break` → `iterator.return()`
 * → `HandleFanOut.detach()` → `NitroLLM unsubscribe` → C++ callback cleared.
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
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }

  const native = requireNativeModule();
  const llmRequest = normalizeLLMGenerateRequest(requestOrPrompt, options, true);
  const requestBytes = encodeLLMGenerateRequest(llmRequest);

  return {
    [Symbol.asyncIterator](): AsyncIterator<LLMStreamEventType> {
      let inner: AsyncIterator<LLMStreamEventType> | null = null;
      let started = false;

      const ensureStarted = async (): Promise<AsyncIterator<LLMStreamEventType>> => {
        if (!started) {
          started = true;
          await ensureServicesReady();
          const handle = await native.getLLMHandle();
          const adapter = new LLMStreamAdapter(handle);
          // Kick off generation before entering the event loop so the C++ side
          // starts pushing proto-byte callbacks into the registered slot.
          native.llmGenerateProto(requestBytes).catch(() => { /* errors surface as stream events */ });
          inner = adapter.stream(llmRequest)[Symbol.asyncIterator]();
        }
        return inner!;
      };

      return {
        async next(): Promise<IteratorResult<LLMStreamEventType>> {
          const it = await ensureStarted();
          return it.next();
        },
        async return(): Promise<IteratorResult<LLMStreamEventType>> {
          // Await the native cancel before resolving so back-to-back
          // cancel → generate sequences are race-free. Matches Swift
          // cancelGeneration() which awaits CppBridge.LLM.shared.cancelProto().
          try { await native.llmCancelProto(); } catch { /* noop */ }
          if (inner) {
            try { await inner.return?.(); } catch { /* noop */ }
          }
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

  return LLMGenerationResultMessage.fromPartial({
    text: fullResponse,
    inputTokens: Math.max(1, Math.floor(prompt.length / 4)),
    tokensGenerated: tokenCount,
    responseTokens: tokenCount,
    modelUsed: modelId,
    generationTimeMs: totalLatencyMs,
    framework,
    tokensPerSecond:
      totalLatencyMs > 0 ? tokenCount / (totalLatencyMs / 1000) : 0,
    ...(ttftMs !== undefined ? { ttftMs } : {}),
    ...(finishReason.length > 0 ? { finishReason } : {}),
    ...(terminalError.length > 0 ? { errorMessage: terminalError } : {}),
  });
}
