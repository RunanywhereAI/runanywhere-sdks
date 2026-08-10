/**
 * `RunAnywhere.segmentation` — per-pixel semantic class masks.
 */

import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import {
  SegmentationPixelFormat,
  type SegmentationImage,
} from '@runanywhere/proto-ts/segmentation';
import { SDKException } from '../../../Foundation/SDKException.js';
import { segment } from '../../Extensions/RunAnywhere+Segmentation.js';
import type { ImageInput } from '../Inputs.js';
import type { SegmentationOptions } from '../Options.js';
import type { SegmentationResult } from '../Results.js';
import { toSegmentationResult } from '../Mapping.js';
import { ensureModelForCategory, ensureReady } from '../Runtime/Prerequisites.js';

/**
 * Reduce an image payload to the raw pixel buffer the segmentation ABI takes.
 * Encoded and base64 payloads are decoded through the browser's image decoder;
 * file-path payloads cannot be reached from the main thread's decoder.
 */
async function toSegmentationImage(image: ImageInput): Promise<SegmentationImage> {
  if (image.rawRgba && image.width > 0 && image.height > 0) {
    return {
      data: image.rawRgba,
      width: image.width,
      height: image.height,
      pixelFormat: SegmentationPixelFormat.SEGMENTATION_PIXEL_FORMAT_RGBA8,
    };
  }
  if (image.rawRgb && image.width > 0 && image.height > 0) {
    return {
      data: image.rawRgb,
      width: image.width,
      height: image.height,
      pixelFormat: SegmentationPixelFormat.SEGMENTATION_PIXEL_FORMAT_RGB8,
    };
  }

  const encoded = image.data
    ?? (image.base64 ? Uint8Array.from(atob(image.base64), (char) => char.charCodeAt(0)) : null);
  if (!encoded) {
    throw SDKException.invalidConfiguration(
      'segmentation.segment needs raw or encoded pixels; a WASM file path cannot be decoded in the browser.',
    );
  }

  const bitmap = await createImageBitmap(new Blob([encoded.slice()]));
  try {
    const canvas = new OffscreenCanvas(bitmap.width, bitmap.height);
    const context = canvas.getContext('2d');
    if (!context) {
      throw SDKException.invalidConfiguration('OffscreenCanvas 2D context is unavailable.');
    }
    context.drawImage(bitmap, 0, 0);
    const pixels = context.getImageData(0, 0, bitmap.width, bitmap.height);
    return {
      data: new Uint8Array(pixels.data.buffer),
      width: bitmap.width,
      height: bitmap.height,
      pixelFormat: SegmentationPixelFormat.SEGMENTATION_PIXEL_FORMAT_RGBA8,
    };
  } finally {
    bitmap.close();
  }
}

/** Semantic segmentation against the resident segmentation model. */
export const segmentation = {
  /**
   * Produce a per-pixel class mask for an image.
   *
   * @throws SDKException when no segmentation model is loaded or the image cannot be decoded.
   *
   * @example
   * const mask = await RunAnywhere.segmentation.segment(await RunAnywhere.ImageInput.blob(file));
   * console.log(mask.classes.map((entry) => entry.label));
   */
  async segment(image: ImageInput, options?: SegmentationOptions): Promise<SegmentationResult> {
    await ensureReady();
    await ensureModelForCategory(ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION);
    const result = await segment({
      image: await toSegmentationImage(image),
      options: {
        includeDiagnosticRgba: options?.includeDiagnosticImage ?? false,
        includeConfidence: false,
      },
    });
    return toSegmentationResult(result);
  },
};
