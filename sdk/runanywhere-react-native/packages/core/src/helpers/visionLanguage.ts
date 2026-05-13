/**
 * helpers/visionLanguage
 *
 * Swift-parity conveniences for generated VLM proto types.
 */

import {
  VLMConfiguration,
  VLMGenerationOptions,
  VLMImage,
  VLMImageFormat,
} from '@runanywhere/proto-ts/vlm_options';

export {
  VLMConfiguration,
  VLMGenerationOptions,
  VLMImage,
  VLMImageFormat,
  VLMModelFamily,
  type VLMResult,
  type VLMServiceState,
  type VLMStreamEvent,
} from '@runanywhere/proto-ts/vlm_options';

export function defaultVLMConfig(modelId = ''): VLMConfiguration {
  return VLMConfiguration.create({
    modelId,
    maxImageSizePx: 1024,
    maxTokens: 0,
  });
}

export function defaultVLMGenerationOptions(
  prompt = ''
): VLMGenerationOptions {
  return VLMGenerationOptions.create({
    prompt,
    maxTokens: 256,
    temperature: 0.7,
    topP: 0.9,
    topK: 40,
  });
}

export function vlmImageFromEncoded(
  data: Uint8Array,
  format: VLMImageFormat
): VLMImage {
  return VLMImage.create({
    encoded: data,
    format,
  });
}

export function vlmImageFromFilePath(path: string): VLMImage {
  return VLMImage.create({
    filePath: path,
    format: VLMImageFormat.VLM_IMAGE_FORMAT_FILE_PATH,
  });
}

export function vlmImageFromBase64(base64: string): VLMImage {
  return VLMImage.create({
    base64,
    format: VLMImageFormat.VLM_IMAGE_FORMAT_BASE64,
  });
}

export function vlmImageFromRawRGB(
  data: Uint8Array,
  width: number,
  height: number
): VLMImage {
  return VLMImage.create({
    rawRgb: data,
    width,
    height,
    format: VLMImageFormat.VLM_IMAGE_FORMAT_RAW_RGB,
  });
}

export function vlmImageFromRawRGBA(
  data: Uint8Array,
  width: number,
  height: number
): VLMImage {
  return VLMImage.create({
    rawRgb: data,
    width,
    height,
    format: VLMImageFormat.VLM_IMAGE_FORMAT_RAW_RGBA,
  });
}
