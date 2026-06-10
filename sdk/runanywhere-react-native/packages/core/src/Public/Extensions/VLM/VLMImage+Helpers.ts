/**
 * VLMImage+Helpers.ts
 *
 * Ergonomic factory helpers for the canonical `VLMImage` proto.
 *
 * Mirrors Swift `RAVLMImage+Helpers.swift` (fromEncoded / fromFilePath /
 * fromBase64 / fromRawRGB / fromRawRGBA). The Apple-only pixel factories
 * (fromCGImage / fromUIImage / fromNSImage / fromPixelBuffer) have no RN
 * equivalent — JS callers should decode to raw RGB(A) bytes and use
 * `fromRawRGB` / `fromRawRGBA`.
 */

import {
  VLMImage as VLMImageMessage,
  VLMImageFormat,
} from '@runanywhere/proto-ts/vlm_options';
import type { VLMImage } from '@runanywhere/proto-ts/vlm_options';

/**
 * Factory helpers for `VLMImage` — Swift `RAVLMImage` static factories.
 */
export const VLMImages = {
  /** Create a proto VLM image from an encoded JPEG / PNG / WebP byte buffer. */
  fromEncoded(data: Uint8Array, format: VLMImageFormat): VLMImage {
    return VLMImageMessage.fromPartial({ encoded: data, format });
  },

  /** Create a proto VLM image from an on-disk file path. */
  fromFilePath(path: string): VLMImage {
    return VLMImageMessage.fromPartial({
      filePath: path,
      format: VLMImageFormat.VLM_IMAGE_FORMAT_FILE_PATH,
    });
  },

  /** Create a proto VLM image from a base64-encoded string. */
  fromBase64(base64: string): VLMImage {
    return VLMImageMessage.fromPartial({
      base64,
      format: VLMImageFormat.VLM_IMAGE_FORMAT_BASE64,
    });
  },

  /** Create a proto VLM image from raw RGB bytes. */
  fromRawRGB(data: Uint8Array, width: number, height: number): VLMImage {
    return VLMImageMessage.fromPartial({
      rawRgb: data,
      width,
      height,
      format: VLMImageFormat.VLM_IMAGE_FORMAT_RAW_RGB,
    });
  },

  /**
   * Create a proto VLM image from raw RGBA bytes.
   * (Stored in the same `rawRgb` oneof slot; format flag distinguishes it.)
   */
  fromRawRGBA(data: Uint8Array, width: number, height: number): VLMImage {
    return VLMImageMessage.fromPartial({
      rawRgb: data,
      width,
      height,
      format: VLMImageFormat.VLM_IMAGE_FORMAT_RAW_RGBA,
    });
  },
};
