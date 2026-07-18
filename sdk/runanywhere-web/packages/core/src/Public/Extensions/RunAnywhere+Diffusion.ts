/**
 * Public diffusion facade. The Web package deliberately ships this API before
 * a WebGPU/WASM engine exists, so every unavailable path is explicit rather
 * than pretending that the CoreML-only commons implementation is portable.
 */

import {
  DiffusionGenerationOptions as DiffusionGenerationOptionsMessage,
  type DiffusionGenerationOptions,
  type DiffusionProgress,
  type DiffusionResult,
} from '@runanywhere/proto-ts/diffusion_options';
import { ErrorCode as ProtoErrorCode } from '@runanywhere/proto-ts/errors';
import { DiffusionProtoAdapter } from '../../Adapters/DiffusionProtoAdapter.js';
import { SDKException } from '../../Foundation/SDKException.js';

export interface DiffusionAvailability {
  available: boolean;
  reason?: string;
  acceleration?: 'auto' | 'webgpu' | 'cpu';
}

export type DiffusionAvailabilityProvider = () => DiffusionAvailability;

let availabilityProvider: DiffusionAvailabilityProvider | null = null;

/** @internal Backend packages may describe a registered shell without claiming a WASM capability. */
export function setDiffusionAvailabilityProvider(
  provider: DiffusionAvailabilityProvider | null,
): void {
  availabilityProvider = provider;
}

const ENGINE_UNAVAILABLE =
  'Web diffusion is not available. Install a WebGPU/WASM diffusion engine when one is released.';

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

/**
 * Generate an image from the lifecycle-selected diffusion model.
 *
 * The current adapter ABI takes a handle; future Web engines must resolve the
 * lifecycle model before registering their module. Until then, calling this
 * method throws FEATURE_NOT_AVAILABLE rather than manufacturing an image.
 */
export async function generateImage(
  options: Partial<DiffusionGenerationOptions>,
): Promise<DiffusionResult> {
  const result = adapterOrThrow('generateImage').generate(0, normalizedOptions(options));
  if (!result) {
    throw featureNotAvailable('generateImage');
  }
  return result;
}

/**
 * Generate an image and yield real native progress events when an engine
 * supports them. No synthetic progress is emitted by the Web shell.
 */
export async function* generateImageStream(
  options: Partial<DiffusionGenerationOptions>,
): AsyncIterable<DiffusionProgress> {
  const events: DiffusionProgress[] = [];
  const result = adapterOrThrow('generateImageStream').generateWithProgress(
    0,
    normalizedOptions(options),
    (progress) => {
      events.push(progress);
    },
  );
  if (!result) {
    throw featureNotAvailable('generateImageStream');
  }
  yield* events;
}

/** Cancel the active image generation when a real diffusion engine is loaded. */
export async function cancelImageGeneration(): Promise<void> {
  if (!adapterOrThrow('cancelImageGeneration').cancel(0)) {
    throw featureNotAvailable('cancelImageGeneration');
  }
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
