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

import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { SDKException } from '../../Foundation/ErrorTypes/SDKException';
import {
  requireNativeModule,
  isNativeModuleAvailable,
} from '../../native';
import {
  arrayBufferToBytes,
  bytesToArrayBuffer,
} from '../../services/ProtoBytes';
import {
  VLMGenerationOptions as VLMGenerationOptionsMessage,
  VLMImage as VLMImageMessage,
  VLMResult as VLMResultMessage,
} from '@runanywhere/proto-ts/vlm_options';
import type {
  VLMGenerationOptions,
  VLMImage,
  VLMResult,
} from '@runanywhere/proto-ts/vlm_options';
import {
  GenerationEventKind,
  SDKEvent as SDKEventMessage,
} from '@runanywhere/proto-ts/sdk_events';
import {
  CurrentModelRequest,
  ModelCategory,
  ModelLoadRequest,
} from '@runanywhere/proto-ts/model_types';
import {
  getCurrentModel,
  loadModelLifecycle,
  resolveVLMArtifactsFromLifecycleResult,
  type VLMResolvedLifecycleArtifacts,
} from './RunAnywhere+Lifecycle';

const logger = new SDKLogger('RunAnywhere.VisionLanguage');

/**
 * RN-local streaming wrapper. The proto `VLMResult` carries final metrics; the
 * streaming surface adds `stream` (token AsyncIterable) and `cancel`.
 */
export interface VLMStreamingResult {
  stream: AsyncIterable<string>;
  result: Promise<VLMResult>;
  cancel: () => void;
}

/**
 * Optional backend provider-registration hook. It is intentionally limited to
 * registration; load/process/cancel always route through RN core.
 */
export interface VLMBackendProvider {
  registerVLMBackend: () => boolean | Promise<boolean>;
}

function ensureNative() {
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  return requireNativeModule();
}

function encodeVLMImage(image: VLMImage): ArrayBuffer {
  return bytesToArrayBuffer(VLMImageMessage.encode(image).finish());
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

function encodeVLMOptions(
  prompt: string,
  options: Partial<VLMGenerationOptions> | undefined,
  streamingEnabled: boolean
): ArrayBuffer {
  return bytesToArrayBuffer(
    VLMGenerationOptionsMessage.encode(
      buildVLMOptions(prompt, options, streamingEnabled)
    ).finish()
  );
}

function decodeVLMResult(buffer: ArrayBuffer, operation: string): VLMResult {
  const bytes = arrayBufferToBytes(buffer);
  if (bytes.byteLength === 0) {
    throw SDKException.protoDecodeFailed(operation);
  }
  return VLMResultMessage.decode(bytes);
}

async function resolveVLMArtifacts(
  modelId: string
): Promise<VLMResolvedLifecycleArtifacts | null> {
  const loadResult = await loadModelLifecycle(
    ModelLoadRequest.fromPartial({
      modelId,
      validateAvailability: true,
    })
  );

  if (!loadResult.success) {
    logger.warning('VLM lifecycle load failed', {
      modelId,
      error: loadResult.errorMessage,
      warnings: loadResult.warnings,
    });
    return null;
  }

  const loadArtifacts = resolveVLMArtifactsFromLifecycleResult(loadResult);
  if (loadArtifacts) {
    return loadArtifacts;
  }

  const currentRequest = CurrentModelRequest.fromPartial({
    includeModelMetadata: true,
    ...(loadResult.category !== ModelCategory.MODEL_CATEGORY_UNSPECIFIED
      ? { category: loadResult.category }
      : {}),
  });
  const currentModel = await getCurrentModel(currentRequest);
  if (currentModel?.found && currentModel.modelId === modelId) {
    const currentArtifacts = resolveVLMArtifactsFromLifecycleResult(currentModel);
    if (currentArtifacts) {
      return currentArtifacts;
    }
  }

  logger.warning('VLM lifecycle did not resolve required artifacts', {
    modelId,
    resolvedArtifactCount: loadResult.resolvedArtifacts.length,
  });
  return null;
}

/**
 * Register a VLM backend provider. Calling without a provider is a no-op for
 * apps that already registered backends through package-level `register()`.
 */
export async function registerVLMBackend(
  provider?: VLMBackendProvider
): Promise<boolean> {
  if (!provider) {
    return true;
  }
  return !!(await provider.registerVLMBackend());
}

/**
 * Load a VLM model by registry ID. Model paths are resolved by commons
 * lifecycle and consumed through role-tagged resolved artifacts.
 */
export async function loadVLMModel(modelId: string): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    logger.warning('Native module not available for loadVLMModel');
    return false;
  }

  const artifacts = await resolveVLMArtifacts(modelId);
  if (!artifacts) {
    return false;
  }

  return requireNativeModule().loadVLMModelFromArtifacts(
    artifacts.primaryModelPath,
    artifacts.visionProjectorPath,
    modelId
  );
}

/**
 * Load a VLM model by its registered model ID.
 *
 * Matches iOS: `RunAnywhere.loadVLMModelById(_:)`.
 */
export async function loadVLMModelById(modelId: string): Promise<boolean> {
  return loadVLMModel(modelId);
}

/** Whether a VLM model is loaded. */
export async function isVLMModelLoaded(): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }
  return requireNativeModule().isVLMModelLoaded();
}

/** Unload the currently loaded VLM model. */
export async function unloadVLMModel(): Promise<boolean> {
  if (!isNativeModuleAvailable()) {
    return false;
  }
  return requireNativeModule().unloadVLMModel();
}

/**
 * Describe an image with an optional prompt.
 *
 * Matches iOS: `RunAnywhere.describeImage(_:prompt:)`.
 */
export async function describeImage(
  image: VLMImage,
  prompt?: string
): Promise<string> {
  const result = await processImage(image, prompt ?? "What's in this image?");
  return result.text;
}

/**
 * Ask a question about an image.
 *
 * Matches iOS: `RunAnywhere.askAboutImage(_:image:)`.
 */
export async function askAboutImage(
  question: string,
  image: VLMImage
): Promise<string> {
  const result = await processImage(image, question);
  return result.text;
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
    encodeVLMImage(image),
    encodeVLMOptions(prompt, options, false)
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
  const imageBytes = encodeVLMImage(image);
  const optionsBytes = encodeVLMOptions(prompt, options, true);
  const queue: string[] = [];
  let done = false;
  let streamError: Error | null = null;
  let resolver: ((value: IteratorResult<string>) => void) | null = null;

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
      imageBytes,
      optionsBytes,
      (eventBytes: ArrayBuffer) => {
        try {
          const event = SDKEventMessage.decode(arrayBufferToBytes(eventBytes));
          if (event.generation?.error) {
            streamError = new Error(event.generation.error);
          }
          if (
            event.generation?.kind ===
            GenerationEventKind.GENERATION_EVENT_KIND_TOKEN_GENERATED
          ) {
            push(event.generation.token);
          }
        } catch (error) {
          streamError =
            error instanceof Error ? error : new Error(String(error));
          finish();
        }
      }
    )
    .then((resultBytes) => decodeVLMResult(resultBytes, 'vlmProcessStreamProto'))
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
