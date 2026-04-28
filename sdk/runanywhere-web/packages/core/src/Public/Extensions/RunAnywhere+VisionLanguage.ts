/**
 * RunAnywhere+VisionLanguage.ts
 *
 * Vision-language model namespace — mirrors Swift's `RunAnywhere+VisionLanguage.swift`.
 * Provides `RunAnywhere.visionLanguage.*` capability surface for VLM inference.
 */

import type {
  VLMGenerationOptions,
  VLMResult,
  VLMConfiguration,
} from '@runanywhere/proto-ts/vlm_options';
export { VLMImageFormat, VLMErrorCode } from '@runanywhere/proto-ts/vlm_options';
export type { VLMGenerationOptions, VLMResult, VLMConfiguration };

import { ExtensionPoint } from '../../Infrastructure/ExtensionPoint';
import { SDKException } from '../../Foundation/SDKException';

export const VisionLanguage = {
  async generate(options: VLMGenerationOptions): Promise<VLMResult> {
    const provider = ExtensionPoint.getProvider('llm') as {
      generateVLM?: (opts: VLMGenerationOptions) => Promise<VLMResult>;
    } | undefined;
    if (provider?.generateVLM) {
      return provider.generateVLM(options);
    }
    throw SDKException.backendNotAvailable('VisionLanguage', 'Install @runanywhere/web-llamacpp and call LlamaCPP.register().');
  },
};
