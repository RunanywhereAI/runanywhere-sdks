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
import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';
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
  LLMStreamEvent,
  type LLMStreamEvent as LLMStreamEventType,
} from '@runanywhere/proto-ts/llm_service';
import { inferenceFrameworkToJSON } from '@runanywhere/proto-ts/model_types';
import { arrayBufferToBytes } from '../../../services/ProtoBytes';
import { encodeProtoMessage } from '../../../services/ProtoWire';

const logger = new SDKLogger('RunAnywhere.TextGeneration');

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
 * Matches Swift SDK:
 * `RunAnywhere.generateStream(_ request: RALLMGenerateRequest)`.
 *
 * Wire-up: events are pushed by C++ via the proto-byte callback registered
 * directly here (through `LLM.subscribeProtoEvents`) against the LLM
 * handle returned by `RunAnywhereCore.getLLMHandle()`.
 *
 * The native generation is kicked off lazily once the consumer starts
 * iterating; cancellation propagates back through `for-await break` →
 * `iterator.return()` → unsubscribe → `cancelGeneration()`.
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
  const requestBytes = encodeLLMGenerateRequest(
    normalizeLLMGenerateRequest(requestOrPrompt, options, true)
  );

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

      const start = (): void => {
        if (started) return;
        started = true;
        native
          .llmGenerateStreamProto(requestBytes, (eventBytes: ArrayBuffer) => {
            try {
              const event = LLMStreamEvent.decode(arrayBufferToBytes(eventBytes));
              if (event.errorMessage) {
                streamError = new Error(event.errorMessage);
              }
              if (resolver) {
                resolver({ value: event, done: false });
                resolver = null;
              } else {
                queue.push(event);
              }
              if (event.isFinal) finish();
            } catch (error) {
              streamError = error instanceof Error ? error : new Error(String(error));
              finish();
            }
          })
          .then(() => {
            if (!done) finish();
          })
          .catch((err: Error) => {
            streamError = err;
            logger.warning(`llmGenerateStreamProto rejected: ${err.message}`);
            finish();
          });
      };

      return {
        async next(): Promise<IteratorResult<LLMStreamEventType>> {
          start();
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
  if (!isNativeModuleAvailable()) {
    return;
  }
  const native = requireNativeModule();
  await native.llmCancelProto();
}
