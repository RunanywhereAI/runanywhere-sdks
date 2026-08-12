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
 *
 * `VLMImage` is a plain oneof of `filePath`/`data`/`rawRgb`/`base64`/
 * `rawRgba` plus a required `mediaType` (MIME type, required when `data` or
 * `base64` is set) and `width`/`height` (required for the raw pixel forms).
 * There is no `VLMImageFormat` enum on the wire any more.
 */

import { VLMImage } from '@runanywhere/proto-ts/vlm_options';

/**
 * Create a proto VLM image from an encoded JPEG / PNG / WebP byte buffer.
 * Swift parity: `RAVLMImage.fromEncoded(_:mediaType:)` (RAVLMImage+Helpers.swift:52).
 */
export function vlmImageFromEncoded(data: Uint8Array, mediaType: string): VLMImage {
  return VLMImage.fromPartial({
    data,
    mediaType,
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
    width: 0,
    height: 0,
    mediaType: '',
  });
}

/**
 * Create a proto VLM image from a base64-encoded string.
 * Swift parity: `RAVLMImage.fromBase64(_:mediaType:)` (RAVLMImage+Helpers.swift:68).
 */
export function vlmImageFromBase64(base64: string, mediaType: string): VLMImage {
  return VLMImage.fromPartial({
    base64,
    mediaType,
    width: 0,
    height: 0,
  });
}

/**
 * Create a proto VLM image from raw 3-byte-per-pixel RGB bytes.
 * Swift parity: `RAVLMImage.fromRawRGB(_:width:height:)` (RAVLMImage+Helpers.swift:76).
 */
export function vlmImageFromRawRGB(data: Uint8Array, width: number, height: number): VLMImage {
  return VLMImage.fromPartial({
    rawRgb: data,
    width,
    height,
    mediaType: '',
  });
}

/**
 * Create a proto VLM image from raw 4-byte-per-pixel RGBA bytes. `rawRgba`
 * is now its own oneof arm (distinct from `rawRgb`), not a shared slot
 * distinguished by a format flag.
 * Swift parity: `RAVLMImage.fromRawRGBA(_:width:height:)` (RAVLMImage+Helpers.swift:87).
 */
export function vlmImageFromRawRGBA(data: Uint8Array, width: number, height: number): VLMImage {
  return VLMImage.fromPartial({
    rawRgba: data,
    width,
    height,
    mediaType: '',
  });
}
