/**
 * helpers/visionLanguage — ergonomic helpers for proto-encoded VLM types.
 * Renamed from vlm.ts to match Swift's VisionLanguage namespace.
 */

import { VLMConfiguration, VLMGenerationOptions } from '@runanywhere/proto-ts/vlm_options';

export {
  VLMConfiguration,
  VLMGenerationOptions,
  type VLMImage,
  type VLMResult,
  VLMImageFormat,
  VLMErrorCode,
} from '@runanywhere/proto-ts/vlm_options';

/** Default `VLMConfiguration`. */
export function defaultVLMConfig(modelId = ''): VLMConfiguration {
  return VLMConfiguration.create({ modelId, maxImageSizePx: 0, maxTokens: 0 });
}

/** Default `VLMGenerationOptions` (matches Swift defaults). */
export function defaultVLMGenerationOptions(prompt = ''): VLMGenerationOptions {
  return VLMGenerationOptions.create({
    prompt,
    maxTokens: 2048,
    temperature: 0.7,
    topP: 0.9,
    topK: 0,
  });
}
