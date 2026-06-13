/**
 * RAVLMImage+Helpers.ts
 *
 * Ergonomic factories for the canonical generated `VLMImage` proto —
 * Web port of Swift `RAVLMImage+Helpers.swift` (cross-platform factories,
 * lines 52-94).
 *
 * Apple-only factories are intentionally NOT ported: `fromCGImage`,
 * `fromUIImage`, `fromNSImage`, and `fromPixelBuffer`
 * (RAVLMImage+Helpers.swift:97-213) depend on CoreGraphics / UIKit /
 * AppKit / CoreVideo pixel sources that do not exist in a browser. Web
 * callers convert canvases/blobs to encoded bytes, base64, or raw
 * RGB(A) buffers and use the factories below.
 */

import {
  VLMImage,
  VLMImageFormat,
} from '@runanywhere/proto-ts/vlm_options';

/**
 * Create a proto VLM image from an encoded JPEG / PNG / WebP byte buffer.
 * Swift parity: `RAVLMImage.fromEncoded(_:format:)` (RAVLMImage+Helpers.swift:52).
 */
export function vlmImageFromEncoded(data: Uint8Array, format: VLMImageFormat): VLMImage {
  return VLMImage.fromPartial({
    encoded: data,
    format,
    width: 0,
    height: 0,
  });
}

/**
 * Create a proto VLM image from an on-disk file path (WASM MEMFS / OPFS path
 * on Web). Swift parity: `RAVLMImage.fromFilePath(_:)` (RAVLMImage+Helpers.swift:60).
 */
export function vlmImageFromFilePath(path: string): VLMImage {
  return VLMImage.fromPartial({
    filePath: path,
    format: VLMImageFormat.VLM_IMAGE_FORMAT_FILE_PATH,
    width: 0,
    height: 0,
  });
}

/**
 * Create a proto VLM image from a base64-encoded string.
 * Swift parity: `RAVLMImage.fromBase64(_:)` (RAVLMImage+Helpers.swift:68).
 */
export function vlmImageFromBase64(base64: string): VLMImage {
  return VLMImage.fromPartial({
    base64,
    format: VLMImageFormat.VLM_IMAGE_FORMAT_BASE64,
    width: 0,
    height: 0,
  });
}

/**
 * Create a proto VLM image from raw RGB bytes.
 * Swift parity: `RAVLMImage.fromRawRGB(_:width:height:)` (RAVLMImage+Helpers.swift:76).
 */
export function vlmImageFromRawRGB(data: Uint8Array, width: number, height: number): VLMImage {
  return VLMImage.fromPartial({
    rawRgb: data,
    width,
    height,
    format: VLMImageFormat.VLM_IMAGE_FORMAT_RAW_RGB,
  });
}

/**
 * Create a proto VLM image from raw RGBA bytes.
 * (Stored in the same `rawRgb` oneof slot; format flag distinguishes it.)
 * Swift parity: `RAVLMImage.fromRawRGBA(_:width:height:)` (RAVLMImage+Helpers.swift:87).
 */
export function vlmImageFromRawRGBA(data: Uint8Array, width: number, height: number): VLMImage {
  return VLMImage.fromPartial({
    rawRgb: data,
    width,
    height,
    format: VLMImageFormat.VLM_IMAGE_FORMAT_RAW_RGBA,
  });
}
