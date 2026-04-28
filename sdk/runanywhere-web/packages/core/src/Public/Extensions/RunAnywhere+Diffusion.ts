/**
 * RunAnywhere+Diffusion.ts
 *
 * Image diffusion namespace — mirrors Swift's `RunAnywhere+Diffusion.swift`.
 * Provides `RunAnywhere.diffusion.*` capability surface for image generation.
 */

import type {
  DiffusionGenerationOptions,
  DiffusionResult,
  DiffusionConfiguration,
  DiffusionCapabilities,
} from '@runanywhere/proto-ts/diffusion_options';
export type { DiffusionGenerationOptions, DiffusionResult, DiffusionConfiguration, DiffusionCapabilities };

import { ExtensionPoint } from '../../Infrastructure/ExtensionPoint';
import { SDKException } from '../../Foundation/SDKException';

export const Diffusion = {
  async generate(options: DiffusionGenerationOptions): Promise<DiffusionResult> {
    const provider = ExtensionPoint.getProvider('llm') as {
      generateImage?: (opts: DiffusionGenerationOptions) => Promise<DiffusionResult>;
    } | undefined;
    if (provider?.generateImage) {
      return provider.generateImage(options);
    }
    throw SDKException.backendNotAvailable('Diffusion', 'Install @runanywhere/web-llamacpp and call LlamaCPP.register().');
  },
};
