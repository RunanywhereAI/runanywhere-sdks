/**
 * RunAnywhere+VisionLanguage.ts
 *
 * Vision Language Model (VLM) extension for the RunAnywhere core SDK.
 * Uses proto-canonical VLM shapes and the RN core Nitro bridge over commons
 * `rac_vlm_generate_proto`, `rac_vlm_stream_proto`, and
 * `rac_vlm_cancel_lifecycle_proto`.
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
import { vLMGenerationOptionsDefaults } from '@runanywhere/proto-ts/convenience/vlm_options_convenience';
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
  options: Partial<VLMGenerationOptions> | undefined
): VLMGenerationOptions {
  return VLMGenerationOptionsMessage.fromPartial({
    ...vLMGenerationOptionsDefaults(),
    ...options,
  });
}

function nextVLMRequestId(): string {
  requestCounter += 1;
  return `rn-vlm-${Date.now()}-${requestCounter}`;
}

function encodeVLMRequest(
  image: VLMImage,
  options: Partial<VLMGenerationOptions> | undefined
): ArrayBuffer {
  const request = VLMGenerationRequest.fromPartial({
    requestId: nextVLMRequestId(),
    images: [VLMImageMessage.fromPartial(image)],
    options: buildVLMOptions(options),
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
 * Matches iOS: `RunAnywhere.processImage(_:options:)`, where
 * `options.prompt` carries the prompt text.
 */
export async function processImage(
  image: VLMImage,
  options: Partial<VLMGenerationOptions>
): Promise<VLMResult> {
  // Swift parity: guard isInitialized (RunAnywhere+VisionLanguage.swift:28-30).
  requireInitialized();
  const native = ensureNative();
  // Swift parity: RunAnywhere+VisionLanguage.swift:31 gates on ensureServicesReady.
  await ensureServicesReady();
  const resultBytes = await native.vlmProcessProto(
    encodeVLMRequest(image, options)
  );
  return decodeVLMResult(resultBytes, 'vlmProcessProto');
}

/**
 * Stream image processing with canonical proto stream events.
 *
 * Matches iOS `RunAnywhere.processImageStream(_:options:)` and the ergonomic
 * `processImageStream(_:prompt:options:)` overload: the prompt travels in
 * `options.prompt`, and the prompt-first overload copies it there before
 * streaming. RN exposes the native VLM stream event proto as AsyncIterable.
 */
export function processImageStream(
  image: VLMImage,
  options: Partial<VLMGenerationOptions>
): Promise<AsyncIterable<VLMStreamEvent>>;
export function processImageStream(
  image: VLMImage,
  prompt: string,
  options?: Partial<VLMGenerationOptions>
): Promise<AsyncIterable<VLMStreamEvent>>;
export async function processImageStream(
  image: VLMImage,
  optionsOrPrompt: Partial<VLMGenerationOptions> | string,
  maybeOptions?: Partial<VLMGenerationOptions>
): Promise<AsyncIterable<VLMStreamEvent>> {
  const options: Partial<VLMGenerationOptions> =
    typeof optionsOrPrompt === 'string'
      ? { ...(maybeOptions ?? {}), prompt: optionsOrPrompt }
      : optionsOrPrompt;
  // Swift parity: guard isInitialized (RunAnywhere+VisionLanguage.swift:56-58).
  requireInitialized();
  const native = ensureNative();
  // Swift parity: RunAnywhere+VisionLanguage.swift:59 gates on ensureServicesReady.
  await ensureServicesReady();
  const requestBytes = encodeVLMRequest(image, options);

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
