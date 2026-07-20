/**
 * Public diffusion facade — Swift/Kotlin parity.
 *
 * Calls the commons lifecycle ABI (`rac_diffusion_generate_lifecycle_proto`).
 * A browser diffusion engine must register its WASM module under the
 * `diffusion` capability; until then every verb throws FEATURE_NOT_AVAILABLE.
 */

import {
  DiffusionGenerationOptions as DiffusionGenerationOptionsMessage,
  DiffusionGenerationRequest as DiffusionGenerationRequestMessage,
  DiffusionMode,
  DiffusionStreamEventKind,
  type DiffusionGenerationOptions,
  type DiffusionProgress,
  type DiffusionResult,
  type DiffusionStreamEvent,
} from '@runanywhere/proto-ts/diffusion_options';
import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import {
  ErrorCategory as ProtoErrorCategory,
  ErrorCode as ProtoErrorCode,
  ErrorSeverity as ProtoErrorSeverity,
} from '@runanywhere/proto-ts/errors';
import { DiffusionProtoAdapter } from '../../Adapters/DiffusionProtoAdapter.js';
import { SDKException } from '../../Foundation/SDKException.js';
import { WebModelLifecycle } from './RunAnywhere+ModelLifecycle.js';

export interface DiffusionAvailability {
  available: boolean;
  reason?: string;
  acceleration?: 'auto' | 'webgpu' | 'cpu';
}

export type DiffusionAvailabilityProvider = () => DiffusionAvailability;

let availabilityProvider: DiffusionAvailabilityProvider | null = null;
let activeCancel: (() => void) | null = null;

/** @internal Optional diagnostic provider for engines that are registered but not yet capable. */
export function setDiffusionAvailabilityProvider(
  provider: DiffusionAvailabilityProvider | null,
): void {
  availabilityProvider = provider;
}

const ENGINE_UNAVAILABLE =
  'Web diffusion is not available. A browser WebGPU/WASM diffusion engine must be registered with the core SDK.';

function featureNotAvailable(operation: string): SDKException {
  return SDKException.fromCode(
    -ProtoErrorCode.ERROR_CODE_FEATURE_NOT_AVAILABLE,
    `Feature not available: ${operation}`,
    ENGINE_UNAVAILABLE,
  );
}

function adapterOrThrow(operation: string): DiffusionProtoAdapter {
  const adapter = DiffusionProtoAdapter.tryDefault();
  if (!adapter?.supportsProtoDiffusion()) {
    throw featureNotAvailable(operation);
  }
  return adapter;
}

function normalizedOptions(
  options: Partial<DiffusionGenerationOptions>,
): DiffusionGenerationOptions {
  return DiffusionGenerationOptionsMessage.fromPartial({
    ...options,
    prompt: options.prompt ?? '',
  });
}

function modelNotLoadedException(message: string): SDKException {
  return new SDKException({
    category: ProtoErrorCategory.ERROR_CATEGORY_COMPONENT,
    code: ProtoErrorCode.ERROR_CODE_MODEL_NOT_LOADED,
    cAbiCode: -ProtoErrorCode.ERROR_CODE_MODEL_NOT_LOADED,
    message,
    nestedMessage: undefined,
    context: undefined,
    timestampMs: Date.now(),
    severity: ProtoErrorSeverity.ERROR_SEVERITY_ERROR,
    component: 'diffusion',
    retryable: false,
    remediationHint: '',
    correlationId: '',
  });
}

function assertLifecycleImageModel(modelId?: string): void {
  const loaded = WebModelLifecycle.currentModel({
    category: ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION,
    includeModelMetadata: false,
  });
  if (!loaded?.found || !loaded.modelId) {
    throw modelNotLoadedException(
      modelId
        ? `Image-generation model '${modelId}' is not loaded`
        : 'No image-generation model is loaded',
    );
  }
  if (modelId && loaded.modelId !== modelId) {
    throw SDKException.validationFailed(
      `Loaded image-generation model '${loaded.modelId}' does not match '${modelId}'`,
    );
  }
}

function encodedImageMediaType(bytes: Uint8Array): string | null {
  if (
    bytes.length >= 8
    && bytes[0] === 0x89
    && bytes[1] === 0x50
    && bytes[2] === 0x4e
    && bytes[3] === 0x47
  ) {
    return 'image/png';
  }
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) {
    return 'image/jpeg';
  }
  return null;
}

/**
 * Generate an image from the lifecycle-selected diffusion model.
 * Mirrors Swift `RunAnywhere.generateImage` / Kotlin `generateImage`.
 */
export async function generateImage(
  options: Partial<DiffusionGenerationOptions>,
  modelId?: string,
): Promise<DiffusionResult> {
  assertLifecycleImageModel(modelId);
  const request = DiffusionGenerationRequestMessage.fromPartial({
    options: normalizedOptions(options),
    modelId: modelId ?? '',
  });
  const result = await adapterOrThrow('generateImage').generateLifecycle(request);
  if (!result) {
    throw featureNotAvailable('generateImage');
  }
  return result;
}

/**
 * Stream typed diffusion events. Until a native stream callback is registered
 * on a handle, this adapts the lifecycle generate into STARTED → COMPLETED /
 * ERROR — matching Swift `CppBridge.Diffusion.generateStream`.
 */
export async function* generateImageStream(
  options: Partial<DiffusionGenerationOptions>,
  modelId?: string,
): AsyncIterable<DiffusionStreamEvent | DiffusionProgress> {
  assertLifecycleImageModel(modelId);
  const adapter = adapterOrThrow('generateImageStream');
  let cancelled = false;
  activeCancel = () => {
    cancelled = true;
    adapter.cancel(0);
  };

  yield {
    seq: 0,
    timestampUs: Math.floor(performance.now() * 1000),
    requestId: '',
    kind: DiffusionStreamEventKind.DIFFUSION_STREAM_EVENT_KIND_STARTED,
    errorCode: 0,
  } satisfies DiffusionStreamEvent;

  try {
    const request = DiffusionGenerationRequestMessage.fromPartial({
      options: normalizedOptions(options),
      modelId: modelId ?? '',
    });
    const result = await adapter.generateLifecycle(request);
    if (cancelled) return;
    if (!result) {
      throw featureNotAvailable('generateImageStream');
    }
    yield {
      seq: 1,
      timestampUs: Math.floor(performance.now() * 1000),
      requestId: '',
      kind: DiffusionStreamEventKind.DIFFUSION_STREAM_EVENT_KIND_COMPLETED,
      result,
      errorCode: 0,
    } satisfies DiffusionStreamEvent;
  } catch (error) {
    if (cancelled) return;
    const message = error instanceof Error ? error.message : String(error);
    yield {
      seq: 1,
      timestampUs: Math.floor(performance.now() * 1000),
      requestId: '',
      kind: DiffusionStreamEventKind.DIFFUSION_STREAM_EVENT_KIND_ERROR,
      errorCode: -1,
      errorMessage: message,
    } satisfies DiffusionStreamEvent;
  } finally {
    activeCancel = null;
  }
}

/** Cancel the active image generation when a real diffusion engine is loaded. */
export async function cancelImageGeneration(): Promise<void> {
  if (activeCancel) {
    activeCancel();
    activeCancel = null;
    return;
  }
  if (!adapterOrThrow('cancelImageGeneration').cancel(0)) {
    throw featureNotAvailable('cancelImageGeneration');
  }
}

/**
 * Inpaint an encoded PNG/JPEG — Kotlin parity sugar over
 * `DIFFUSION_MODE_INPAINTING`. Commons validates media types.
 */
export async function inpaint(options: {
  inputImage: Uint8Array;
  maskImage: Uint8Array;
  prompt?: string;
  width?: number;
  height?: number;
  modelId?: string;
}): Promise<DiffusionResult> {
  if (options.inputImage.length === 0) {
    throw SDKException.validationFailed('inputImage must not be empty');
  }
  if (options.maskImage.length === 0) {
    throw SDKException.validationFailed('maskImage must not be empty');
  }
  const inputMediaType = encodedImageMediaType(options.inputImage);
  const maskMediaType = encodedImageMediaType(options.maskImage);
  if (!inputMediaType) {
    throw SDKException.validationFailed('inputImage must be encoded PNG or JPEG data');
  }
  if (!maskMediaType) {
    throw SDKException.validationFailed('maskImage must be encoded PNG or JPEG data');
  }
  return generateImage({
    prompt: options.prompt?.trim() || 'Remove the masked region.',
    width: options.width ?? 512,
    height: options.height ?? 512,
    mode: DiffusionMode.DIFFUSION_MODE_INPAINTING,
    inputImage: options.inputImage,
    maskImage: options.maskImage,
    inputImageMediaType: inputMediaType,
    maskImageMediaType: maskMediaType,
  }, options.modelId);
}

export const Diffusion = {
  availability(): DiffusionAvailability {
    const adapter = DiffusionProtoAdapter.tryDefault();
    if (adapter?.supportsProtoDiffusion()) {
      return { available: true };
    }
    return availabilityProvider?.() ?? {
      available: false,
      reason: ENGINE_UNAVAILABLE,
    };
  },
};
