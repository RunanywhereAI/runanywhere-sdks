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
import {
  arrayBufferToBytes,
  bytesToArrayBuffer,
} from '../../../services/ProtoBytes';
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
} from '@runanywhere/proto-ts/vlm_options';

const logger = new SDKLogger('RunAnywhere.VisionLanguage');
let requestCounter = 0;

/**
 * RN-local streaming wrapper. The proto `VLMResult` carries final metrics; the
 * streaming surface adds `stream` (token AsyncIterable) and `cancel`.
 */
export interface VLMStreamingResult {
  stream: AsyncIterable<string>;
  result: Promise<VLMResult>;
  cancel: () => void;
}

function ensureNative() {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  return requireNativeModule();
}

function buildVLMOptions(
  prompt: string,
  options: Partial<VLMGenerationOptions> | undefined,
  streamingEnabled: boolean
): VLMGenerationOptions {
  const requestedPrompt =
    options?.prompt && options.prompt.length > 0 ? options.prompt : prompt;
  return VLMGenerationOptionsMessage.fromPartial({
    ...options,
    prompt: requestedPrompt,
    maxTokens: options?.maxTokens ?? 2048,
    temperature: options?.temperature ?? 0.7,
    topP: options?.topP ?? 0.9,
    topK: options?.topK ?? 0,
    stopSequences: options?.stopSequences ?? [],
    streamingEnabled,
    systemPrompt: options?.systemPrompt,
    maxImageSize: options?.maxImageSize ?? 0,
    nThreads: options?.nThreads ?? 0,
    useGpu: options?.useGpu ?? true,
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
  prompt: string,
  options: Partial<VLMGenerationOptions> | undefined,
  streamingEnabled: boolean
): ArrayBuffer {
  const request = VLMGenerationRequest.fromPartial({
    requestId: nextVLMRequestId(),
    images: [VLMImageMessage.fromPartial(image)],
    options: buildVLMOptions(prompt, options, streamingEnabled),
    metadata: {},
  });
  return bytesToArrayBuffer(
    VLMGenerationRequest.encode(request).finish()
  );
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
 * Matches iOS: `RunAnywhere.processImage(_:prompt:maxTokens:temperature:topP:)`.
 */
export async function processImage(
  image: VLMImage,
  prompt: string,
  options?: Partial<VLMGenerationOptions>
): Promise<VLMResult> {
  const native = ensureNative();
  const resultBytes = await native.vlmProcessProto(
    encodeVLMRequest(image, prompt, options, false)
  );
  return decodeVLMResult(resultBytes, 'vlmProcessProto');
}

/**
 * Stream image processing with real-time token text.
 *
 * Commons emits canonical `SDKEvent` proto bytes for token deltas and returns
 * a final `VLMResult` proto at stream completion.
 */
export async function processImageStream(
  image: VLMImage,
  prompt: string,
  options?: Partial<VLMGenerationOptions>
): Promise<VLMStreamingResult> {
  const native = ensureNative();
  const requestBytes = encodeVLMRequest(image, prompt, options, true);
  const queue: string[] = [];
  let done = false;
  let streamError: Error | null = null;
  let resolver: ((value: IteratorResult<string>) => void) | null = null;
  let finalResult: VLMResult | null = null;

  const finish = (): void => {
    done = true;
    if (resolver) {
      resolver({ value: undefined as unknown as string, done: true });
      resolver = null;
    }
  };

  const push = (token: string): void => {
    if (!token) {
      return;
    }
    if (resolver) {
      resolver({ value: token, done: false });
      resolver = null;
    } else {
      queue.push(token);
    }
  };

  const resultPromise = native
    .vlmProcessStreamProto(
      requestBytes,
      (eventBytes: ArrayBuffer) => {
        try {
          const event = VLMStreamEventMessage.decode(arrayBufferToBytes(eventBytes));
          if (event.errorMessage) {
            streamError = new Error(event.errorMessage);
          }
          if (event.kind === VLMStreamEventKind.VLM_STREAM_EVENT_KIND_TOKEN) {
            push(event.token);
          }
          if (event.result) {
            finalResult = event.result;
          }
        } catch (error) {
          streamError =
            error instanceof Error ? error : new Error(String(error));
          finish();
        }
      }
    )
    .then(() => {
      if (!finalResult) {
        throw SDKException.protoDecodeFailed('vlmProcessStreamProto');
      }
      return finalResult;
    })
    .catch((error: Error) => {
      streamError = error;
      throw error;
    })
    .finally(finish);

  const cancel = (): void => {
    native.vlmCancelProto().catch((error: Error) => {
      logger.warning(`vlmCancelProto failed: ${error.message}`);
    });
    finish();
  };

  return {
    stream: {
      [Symbol.asyncIterator](): AsyncIterator<string> {
        return {
          async next(): Promise<IteratorResult<string>> {
            if (queue.length > 0) {
              return { value: queue.shift()!, done: false };
            }
            if (streamError) {
              throw streamError;
            }
            if (done) {
              return { value: undefined as unknown as string, done: true };
            }
            return new Promise<IteratorResult<string>>((resolve) => {
              resolver = resolve;
            }).then((result) => {
              if (streamError) {
                throw streamError;
              }
              return result;
            });
          },
          async return(): Promise<IteratorResult<string>> {
            cancel();
            return { value: undefined as unknown as string, done: true };
          },
        };
      },
    },
    result: resultPromise,
    cancel,
  };
}

/**
 * Cancel ongoing VLM generation.
 *
 * Matches iOS: `RunAnywhere.cancelVLMGeneration()`.
 */
export function cancelVLMGeneration(): void {
  if (!isNativeModuleAvailable()) {
    return;
  }
  requireNativeModule().vlmCancelProto().catch((error: Error) => {
    logger.warning(`vlmCancelProto failed: ${error.message}`);
  });
}
