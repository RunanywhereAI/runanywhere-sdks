/**
 * Input value types of the v3 public API — audio, images, chat messages,
 * model references, and RAG documents.
 */

import { VLMImageFormat, type VLMImage } from '@runanywhere/proto-ts/vlm_options';
import {
  vlmImageFromBase64,
  vlmImageFromEncoded,
  vlmImageFromFilePath,
  vlmImageFromRawRGB,
  vlmImageFromRawRGBA,
} from '../Extensions/RAVLMImage+Helpers.js';
import { AudioFileLoader } from '../../Infrastructure/AudioFileLoader.js';

/** Sample encoding of an [AudioInput] payload. */
export type AudioEncoding = 'pcm16' | 'float32' | 'wav';

/** Wire description of an audio payload. */
export interface AudioFormatSpec {
  encoding: AudioEncoding;
  sampleRate: number;
  channels: number;
}

/** Audio payload accepted by every speech verb. */
export interface AudioInput {
  readonly bytes: Uint8Array;
  readonly format: AudioFormatSpec;
}

const DEFAULT_SAMPLE_RATE = 16_000;

function float32ToPcm16(samples: Float32Array): Uint8Array {
  const out = new Uint8Array(samples.length * 2);
  const view = new DataView(out.buffer);
  for (let i = 0; i < samples.length; i += 1) {
    const clamped = Math.max(-1, Math.min(1, samples[i] ?? 0));
    view.setInt16(i * 2, Math.round(clamped * 0x7fff), true);
  }
  return out;
}

/** Construct audio payloads from the shapes a browser can produce. */
export const AudioInput = {
  /** Wrap signed 16-bit little-endian PCM bytes. */
  pcm16(bytes: Uint8Array, sampleRate = DEFAULT_SAMPLE_RATE, channels = 1): AudioInput {
    return { bytes, format: { encoding: 'pcm16', sampleRate, channels } };
  },

  /** Wrap Float32 samples in [-1, 1]. */
  float32(samples: Float32Array, sampleRate = DEFAULT_SAMPLE_RATE, channels = 1): AudioInput {
    return {
      bytes: new Uint8Array(samples.buffer, samples.byteOffset, samples.byteLength),
      format: { encoding: 'float32', sampleRate, channels },
    };
  },

  /** Wrap a complete RIFF/WAVE container. */
  wav(bytes: Uint8Array, sampleRate = DEFAULT_SAMPLE_RATE, channels = 1): AudioInput {
    return { bytes, format: { encoding: 'wav', sampleRate, channels } };
  },

  /**
   * Decode a picked audio file into mono Float32 samples.
   *
   * Browsers have no filesystem paths, so the `file` constructor takes the
   * `File` the user picked and resolves asynchronously through the Web Audio
   * decoder.
   *
   * @throws DOMException when the browser cannot decode the container.
   */
  async file(file: File, targetSampleRate = DEFAULT_SAMPLE_RATE): Promise<AudioInput> {
    const loaded = await AudioFileLoader.toFloat32Array(file, targetSampleRate);
    return AudioInput.float32(loaded.samples, loaded.sampleRate, 1);
  },
};

/** Float32 samples of an audio payload, converting encodings when needed. */
export function audioInputToFloat32(audio: AudioInput): Float32Array {
  if (audio.format.encoding === 'float32') {
    const count = Math.floor(audio.bytes.byteLength / 4);
    const view = new DataView(audio.bytes.buffer, audio.bytes.byteOffset, count * 4);
    const out = new Float32Array(count);
    for (let i = 0; i < count; i += 1) out[i] = view.getFloat32(i * 4, true);
    return out;
  }
  // WAV headers are stripped by commons; both remaining encodings decode as
  // signed 16-bit little-endian frames here.
  const count = Math.floor(audio.bytes.byteLength / 2);
  const view = new DataView(audio.bytes.buffer, audio.bytes.byteOffset, count * 2);
  const out = new Float32Array(count);
  for (let i = 0; i < count; i += 1) out[i] = view.getInt16(i * 2, true) / 0x8000;
  return out;
}

/** Signed 16-bit little-endian bytes of an audio payload. */
export function audioInputToPcm16(audio: AudioInput): Uint8Array {
  if (audio.format.encoding === 'float32') {
    return float32ToPcm16(audioInputToFloat32(audio));
  }
  return audio.bytes;
}

/** Image payload accepted by the vision and segmentation verbs. */
export type ImageInput = VLMImage;

function encodedFormatFor(mimeType: string): VLMImageFormat {
  if (mimeType.includes('png')) return VLMImageFormat.VLM_IMAGE_FORMAT_PNG;
  if (mimeType.includes('webp')) return VLMImageFormat.VLM_IMAGE_FORMAT_WEBP;
  return VLMImageFormat.VLM_IMAGE_FORMAT_JPEG;
}

async function encodeElement(
  source: HTMLImageElement | HTMLCanvasElement | ImageBitmap,
): Promise<ImageInput> {
  const width = 'naturalWidth' in source ? source.naturalWidth : source.width;
  const height = 'naturalHeight' in source ? source.naturalHeight : source.height;
  const canvas = document.createElement('canvas');
  canvas.width = width;
  canvas.height = height;
  const context = canvas.getContext('2d');
  if (!context) {
    throw new Error('2D canvas context is unavailable in this browser context');
  }
  context.drawImage(source as CanvasImageSource, 0, 0, width, height);
  const blob = await new Promise<Blob | null>((resolve) => canvas.toBlob(resolve, 'image/png'));
  if (!blob) throw new Error('Canvas could not be encoded as PNG');
  const bytes = new Uint8Array(await blob.arrayBuffer());
  return vlmImageFromEncoded(bytes, VLMImageFormat.VLM_IMAGE_FORMAT_PNG);
}

/** Construct image payloads from the shapes a browser can produce. */
export const ImageInput = {
  /** Reference an image already staged in the WASM filesystem. */
  file(path: string): ImageInput {
    return vlmImageFromFilePath(path);
  },

  /** Wrap encoded JPEG, PNG, or WebP bytes. */
  bytes(data: Uint8Array, mimeType = 'image/jpeg'): ImageInput {
    return vlmImageFromEncoded(data, encodedFormatFor(mimeType));
  },

  /** Wrap a base64-encoded image, with or without a data-URL prefix. */
  base64(value: string): ImageInput {
    const comma = value.indexOf(',');
    return vlmImageFromBase64(value.startsWith('data:') && comma >= 0 ? value.slice(comma + 1) : value);
  },

  /** Wrap packed 3-byte-per-pixel RGB samples. */
  rawRgb(data: Uint8Array, width: number, height: number): ImageInput {
    return vlmImageFromRawRGB(data, width, height);
  },

  /** Wrap packed 4-byte-per-pixel RGBA samples. */
  rawRgba(data: Uint8Array, width: number, height: number): ImageInput {
    return vlmImageFromRawRGBA(data, width, height);
  },

  /** Encode a `Blob` or `File` picked in the browser. */
  async blob(source: Blob): Promise<ImageInput> {
    const bytes = new Uint8Array(await source.arrayBuffer());
    return vlmImageFromEncoded(bytes, encodedFormatFor(source.type));
  },

  /** Encode a DOM image, canvas, or decoded bitmap through a scratch canvas. */
  element(source: HTMLImageElement | HTMLCanvasElement | ImageBitmap): Promise<ImageInput> {
    return encodeElement(source);
  },
};

/** Author of a chat turn. */
export type ChatRole = 'system' | 'user' | 'assistant' | 'tool';

/** One turn of a chat transcript. */
export interface ChatMessage {
  role: ChatRole;
  content: string;
  toolCallId?: string;
}

/** Reference to a catalogued model, plus the voice to use for TTS. */
export interface ModelRef {
  id: string;
  voice?: string;
}

/** Text to index into a RAG session. */
export interface RagDocument {
  text: string;
  metadata?: Record<string, string>;
  /** Display name used by [RagSession.stats] and document listings. */
  name?: string;
}

/** Construct RAG documents from browser sources. */
export const RagDocument = {
  /** Read a picked text file into a document, keeping its filename. */
  async file(file: File): Promise<RagDocument> {
    return { text: await file.text(), name: file.name };
  },
};
