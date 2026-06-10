/**
 * RunAnywhere+VisionLanguage.ts
 *
 * Vision Language Model (VLM) extension for the RunAnywhere core SDK.
 * Uses proto-canonical VLM shapes and the RN core Nitro bridge over commons
 * `rac_vlm_process_proto`, `rac_vlm_process_stream_proto`, and
 * `rac_vlm_cancel_proto`.
 *
 * Backend packages register providers only; core owns the public VLM
 * lifecycle/process surface.
 */

import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';
import { SDKException } from '../../../Foundation/Errors/SDKException';
import {
  requireNativeModule,
  isNativeModuleAvailable,
} from '../../../native';
import { arrayBufferToBytes } from '../../../services/ProtoBytes';
import { ensureServicesReady } from '../../../Foundation/Initialization/ServicesReadyGuard';
import { requireInitialized } from '../../../Foundation/Initialization/InitializedGuard';
import { encodeProtoMessage } from '../../../services/ProtoWire';
import {
  VLMGenerationOptions as VLMGenerationOptionsMessage,
  VLMGenerationRequest,
  VLMImage as VLMImageMessage,
  VLMResult as VLMResultMessage,
  VLMStreamEvent as VLMStreamEventMessage,
  VLMStreamEventKind,
} from '@runanywhere/proto-ts/vlm_options';
import type {
  VLMGenerationOptions,
  VLMImage,
  VLMResult,
  VLMStreamEvent,
} from '@runanywhere/proto-ts/vlm_options';

const logger = new SDKLogger('RunAnywhere.VisionLanguage');
let requestCounter = 0;

function ensureNative() {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  return requireNativeModule();
}

function buildVLMOptions(
  options: Partial<VLMGenerationOptions> | undefined,
  streamingEnabled: boolean
): VLMGenerationOptions {
  return VLMGenerationOptionsMessage.fromPartial({
    ...options,
    prompt: options?.prompt ?? '',
    // Defaults mirror Swift RAVLMGenerationOptions.defaults()
    // (RAVLMImage+Helpers.swift): maxTokens 256, temperature 0.7,
    // topP 0.9, topK 40; no useGpu override (proto default).
    maxTokens: options?.maxTokens ?? 256,
    temperature: options?.temperature ?? 0.7,
    topP: options?.topP ?? 0.9,
    topK: options?.topK ?? 40,
    stopSequences: options?.stopSequences ?? [],
    streamingEnabled,
    systemPrompt: options?.systemPrompt,
    maxImageSize: options?.maxImageSize ?? 0,
    nThreads: options?.nThreads ?? 0,
    useGpu: options?.useGpu ?? false,
    modelFamily: options?.modelFamily ?? 0,
    customChatTemplate: options?.customChatTemplate,
    imageMarkerOverride: options?.imageMarkerOverride,
    seed: options?.seed ?? 0,
    repetitionPenalty: options?.repetitionPenalty ?? 0,
    minP: options?.minP ?? 0,
    emitImageEmbeddings: options?.emitImageEmbeddings ?? false,
  });
}

function nextVLMRequestId(): string {
  requestCounter += 1;
  return `rn-vlm-${Date.now()}-${requestCounter}`;
}

function encodeVLMRequest(
  image: VLMImage,
  options: Partial<VLMGenerationOptions> | undefined,
  streamingEnabled: boolean
): ArrayBuffer {
  const request = VLMGenerationRequest.fromPartial({
    requestId: nextVLMRequestId(),
    images: [VLMImageMessage.fromPartial(image)],
    options: buildVLMOptions(options, streamingEnabled),
    metadata: {},
  });
  return encodeProtoMessage(request, VLMGenerationRequest);
}

function decodeVLMResult(buffer: ArrayBuffer, operation: string): VLMResult {
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) {
    throw SDKException.protoDecodeFailed(operation);
  }
  return VLMResultMessage.decode(bytes);
}

/**
 * Process an image with full options and metrics.
 *
 * Canonical form matches iOS: `RunAnywhere.processImage(_:options:)` where
 * `options.prompt` carries the prompt text.
 *
 * Ergonomic overload: `processImage(image, prompt, options?)` — prompt is
 * merged into options.prompt so existing call sites continue to compile.
 */
export async function processImage(
  image: VLMImage,
  optionsOrPrompt: Partial<VLMGenerationOptions> | string,
  legacyOptions?: Partial<VLMGenerationOptions>
): Promise<VLMResult> {
  // Swift parity: guard isInitialized (RunAnywhere+VisionLanguage.swift:28-30).
  requireInitialized();
  const native = ensureNative();
  // Swift parity: RunAnywhere+VisionLanguage.swift:31 gates on ensureServicesReady.
  await ensureServicesReady();
  const resolvedOptions: Partial<VLMGenerationOptions> =
    typeof optionsOrPrompt === 'string'
      ? { ...legacyOptions, prompt: optionsOrPrompt }
      : optionsOrPrompt;
  const resultBytes = await native.vlmProcessProto(
    encodeVLMRequest(image, resolvedOptions, false)
  );
  return decodeVLMResult(resultBytes, 'vlmProcessProto');
}

/**
 * Stream image processing with canonical proto stream events.
 *
 * Canonical form matches iOS: `RunAnywhere.processImageStream(_:options:)` where
 * `options.prompt` carries the prompt text. RN exposes the native VLM stream
 * event proto as AsyncIterable.
 *
 * Ergonomic overload: `processImageStream(image, prompt, options?)` — prompt is
 * merged into options.prompt so existing call sites continue to compile.
 */
export async function processImageStream(
  image: VLMImage,
  optionsOrPrompt: Partial<VLMGenerationOptions> | string,
  legacyOptions?: Partial<VLMGenerationOptions>
): Promise<AsyncIterable<VLMStreamEvent>> {
  // Swift parity: guard isInitialized (RunAnywhere+VisionLanguage.swift:56-58).
  requireInitialized();
  const native = ensureNative();
  // Swift parity: RunAnywhere+VisionLanguage.swift:59 gates on ensureServicesReady.
  await ensureServicesReady();
  const resolvedOptions: Partial<VLMGenerationOptions> =
    typeof optionsOrPrompt === 'string'
      ? { ...legacyOptions, prompt: optionsOrPrompt }
      : optionsOrPrompt;
  const requestBytes = encodeVLMRequest(image, resolvedOptions, true);

  return {
    [Symbol.asyncIterator](): AsyncIterator<VLMStreamEvent> {
      const queue: VLMStreamEvent[] = [];
      let resolver: ((value: IteratorResult<VLMStreamEvent>) => void) | null = null;
      let done = false;
      let started = false;
      let streamError: Error | null = null;

      const finish = (): void => {
        done = true;
        if (resolver) {
          resolver({ value: undefined as unknown as VLMStreamEvent, done: true });
          resolver = null;
        }
      };

      const push = (event: VLMStreamEvent): void => {
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
        native
          .vlmProcessStreamProto(
            requestBytes,
            (eventBytes: ArrayBuffer) => {
              try {
                const event = VLMStreamEventMessage.decode(arrayBufferToBytes(eventBytes));
                if (event.errorMessage) {
                  streamError = new Error(event.errorMessage);
                }
                push(event);
                if (
                  event.kind === VLMStreamEventKind.VLM_STREAM_EVENT_KIND_COMPLETED ||
                  event.result
                ) {
                  finish();
                }
              } catch (error) {
                streamError =
                  error instanceof Error ? error : new Error(String(error));
                finish();
              }
            }
          )
          .then(() => {
            if (!done) finish();
          })
          .catch((err: Error) => {
            streamError = err;
            logger.warning(`vlmProcessStreamProto rejected: ${err.message}`);
            finish();
          });
      };

      return {
        async next(): Promise<IteratorResult<VLMStreamEvent>> {
          start();
          if (queue.length > 0) {
            return { value: queue.shift()!, done: false };
          }
          if (streamError) {
            throw streamError;
          }
          if (done) {
            return { value: undefined as unknown as VLMStreamEvent, done: true };
          }
          return new Promise<IteratorResult<VLMStreamEvent>>((resolve) => {
            resolver = resolve;
          }).then((result) => {
            if (streamError) {
              throw streamError;
            }
            return result;
          });
        },
        async return(): Promise<IteratorResult<VLMStreamEvent>> {
          await native.vlmCancelProto().catch((error: Error) => {
            logger.warning(`vlmCancelProto failed: ${error.message}`);
          });
          finish();
          return { value: undefined as unknown as VLMStreamEvent, done: true };
        },
      };
    },
  };
}

/**
 * Cancel ongoing VLM generation.
 *
 * Matches iOS: `RunAnywhere.cancelVLMGeneration()`.
 */
export async function cancelVLMGeneration(): Promise<void> {
  if (!isNativeModuleAvailable()) {
    return;
  }
  await requireNativeModule().vlmCancelProto().catch((error: Error) => {
    logger.warning(`vlmCancelProto failed: ${error.message}`);
  });
}
