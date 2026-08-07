// The images namespace: text-to-image via the loaded diffusion model, mirroring
// Swift's Images.generate. Runs the real commons op; if no diffusion engine is
// linked in this build it surfaces FEATURE_NOT_AVAILABLE from commons rather than
// a static stub.
import {
  DiffusionGenerationOptions,
  DiffusionGenerationRequest,
  DiffusionResult,
} from '@runanywhere/proto-ts/diffusion_options';

import type { RaBackend } from '../backend.js';
import { SDKException } from '../errors.js';
import type { ModelResolver } from './llm.js';

export interface ImageOptions {
  /** Diffusion model id to run; loaded (and downloaded) first if not resident. */
  model?: string;
  negativePrompt?: string;
  width?: number;
  height?: number;
  steps?: number;
  guidanceScale?: number;
  seed?: number;
}

export interface ImageData {
  data: Uint8Array;
  width: number;
  height: number;
}

export interface ImageResult {
  images: ImageData[];
  seed: number;
}

export interface ImagesNamespace {
  generate(prompt: string, options?: ImageOptions): Promise<ImageResult>;
}

export function createImagesNamespace(backend: RaBackend, resolve: ModelResolver): ImagesNamespace {
  return {
    async generate(prompt, options) {
      if (options?.model) await resolve(options.model);
      const genOptions = DiffusionGenerationOptions.fromPartial({
        prompt,
        ...(options?.negativePrompt ? { negativePrompt: options.negativePrompt } : {}),
        ...(options?.width ? { width: options.width } : {}),
        ...(options?.height ? { height: options.height } : {}),
        ...(options?.steps ? { steps: options.steps } : {}),
        ...(options?.guidanceScale !== undefined ? { guidanceScale: options.guidanceScale } : {}),
        ...(options?.seed !== undefined ? { seed: options.seed } : {}),
      });
      const req = DiffusionGenerationRequest.fromPartial({
        options: genOptions,
        ...(options?.model ? { modelId: options.model } : {}),
      });
      const res = DiffusionResult.decode(
        await backend.imageGenerate(DiffusionGenerationRequest.encode(req).finish())
      );
      if (res.error?.message) throw SDKException.of(SDKException.unknown().code, res.error.message);
      const images =
        res.imageData && res.imageData.length
          ? [{ data: res.imageData, width: res.width, height: res.height }]
          : [];
      return { images, seed: res.seedUsed ?? 0 };
    },
  };
}
