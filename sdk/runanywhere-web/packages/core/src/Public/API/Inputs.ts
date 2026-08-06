/**
 * Input value types of the v4 public API — audio, images, chat messages,
 * model references, and RAG documents.
 */

import { audioCaptureDefaults } from '@runanywhere/proto-ts/defaults/pool';
import type { VLMImage } from '@runanywhere/proto-ts/vlm_options';
import {
  vlmImageFromBase64,
  vlmImageFromEncoded,
  vlmImageFromFilePath,
  vlmImageFromRawRGB,
  vlmImageFromRawRGBA,
} from '../Extensions/RAVLMImage+Helpers.js';
import { AudioFileLoader } from '../../Infrastructure/AudioFileLoader.js';

/** Sample encoding of an [AudioFormatSpec]. `container` needs a decoder; live streams never use it. */
export type AudioEncoding = 'pcmS16Le' | 'pcmF32Le' | 'container';

/** Encoded container carried when `encoding` is `'container'`. */
export type AudioContainerFormat = 'pcm' | 'wav' | 'mp3' | 'opus' | 'flac' | 'm4a';

/** Wire description of an audio payload, established once per live stream. */
export interface AudioFormatSpec {
  encoding: AudioEncoding;
  sampleRate: number;
  /** Defaults to `1` (mono) when unset. */
  channels?: number;
  /** Required when `encoding` is `'container'`. */
  container?: AudioContainerFormat;
}

/** One chunk of PCM samples pushed into an open `SttStream`/`VadStream`. */
export interface AudioFrame {
  /** PCM bytes for the stream's established format — never a container. */
  samples: Uint8Array;
  sampleCount: number;
  timestampMs?: number;
}

/** Audio payload accepted by every batch speech verb. */
export interface AudioInput {
  readonly bytes: Uint8Array;
  readonly format: AudioFormatSpec;
}

const DEFAULT_SAMPLE_RATE = audioCaptureDefaults.micSampleRateHz;

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
    return { bytes, format: { encoding: 'pcmS16Le', sampleRate, channels } };
  },

  /** Wrap Float32 samples in [-1, 1]. */
  float32(samples: Float32Array, sampleRate = DEFAULT_SAMPLE_RATE, channels = 1): AudioInput {
    return {
      bytes: new Uint8Array(samples.buffer, samples.byteOffset, samples.byteLength),
      format: { encoding: 'pcmF32Le', sampleRate, channels },
    };
  },

  /** Wrap a complete RIFF/WAVE container; decoded on demand, never fed to a model as raw PCM. */
  wav(bytes: Uint8Array, sampleRate = DEFAULT_SAMPLE_RATE, channels = 1): AudioInput {
    return { bytes, format: { encoding: 'container', sampleRate, channels, container: 'wav' } };
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

/**
 * Decode a complete audio container (WAV, MP3, etc.) to mono Float32 samples
 * through the browser's own decoder, resampling to `targetSampleRate` when
 * the container's native rate differs.
 *
 * @throws DOMException when the browser cannot decode the container.
 */
async function decodeContainerToFloat32(
  bytes: Uint8Array,
  targetSampleRate: number,
): Promise<Float32Array> {
  const context = new AudioContext();
  try {
    // Copy into a fresh ArrayBuffer: decodeAudioData detaches the buffer it
    // is given, and callers must not have their own bytes silently emptied.
    const copy = bytes.slice().buffer;
    const decoded = await context.decodeAudioData(copy);
    if (decoded.sampleRate === targetSampleRate) {
      return new Float32Array(decoded.getChannelData(0));
    }
    const targetLength = Math.ceil(decoded.duration * targetSampleRate);
    const offline = new OfflineAudioContext(1, targetLength, targetSampleRate);
    const source = offline.createBufferSource();
    source.buffer = decoded;
    source.connect(offline.destination);
    source.start();
    const rendered = await offline.startRendering();
    return new Float32Array(rendered.getChannelData(0));
  } finally {
    await context.close();
  }
}

/**
 * Float32 samples of an audio payload, converting encodings when needed.
 *
 * A `'container'` payload (e.g. `AudioInput.wav`) is decoded through the
 * browser's own audio decoder rather than reinterpreted as raw PCM.
 */
export async function audioInputToFloat32(audio: AudioInput): Promise<Float32Array> {
  if (audio.format.encoding === 'pcmF32Le') {
    const count = Math.floor(audio.bytes.byteLength / 4);
    const view = new DataView(audio.bytes.buffer, audio.bytes.byteOffset, count * 4);
    const out = new Float32Array(count);
    for (let i = 0; i < count; i += 1) out[i] = view.getFloat32(i * 4, true);
    return out;
  }
  if (audio.format.encoding === 'container') {
    return decodeContainerToFloat32(audio.bytes, audio.format.sampleRate);
  }
  const count = Math.floor(audio.bytes.byteLength / 2);
  const view = new DataView(audio.bytes.buffer, audio.bytes.byteOffset, count * 2);
  const out = new Float32Array(count);
  for (let i = 0; i < count; i += 1) out[i] = view.getInt16(i * 2, true) / 0x8000;
  return out;
}

/**
 * Signed 16-bit little-endian bytes of an audio payload.
 *
 * A `'container'` payload is decoded through the browser's own audio decoder
 * (see [audioInputToFloat32]) before conversion to PCM16 — it is never fed to
 * a model as if its RIFF/container bytes were raw samples.
 */
export async function audioInputToPcm16(audio: AudioInput): Promise<Uint8Array> {
  if (audio.format.encoding === 'pcmS16Le') return audio.bytes;
  return float32ToPcm16(await audioInputToFloat32(audio));
}

/** Image payload accepted by the vision and segmentation verbs. */
export type ImageInput = VLMImage;

function normalizedMediaType(mimeType: string): string {
  if (mimeType.includes('png')) return 'image/png';
  if (mimeType.includes('webp')) return 'image/webp';
  return 'image/jpeg';
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
  return vlmImageFromEncoded(bytes, 'image/png');
}

/** Construct image payloads from the shapes a browser can produce. */
export const ImageInput = {
  /** Reference an image already staged in the WASM filesystem. */
  file(path: string): ImageInput {
    return vlmImageFromFilePath(path);
  },

  /** Wrap encoded JPEG, PNG, or WebP bytes. */
  bytes(data: Uint8Array, mimeType = 'image/jpeg'): ImageInput {
    return vlmImageFromEncoded(data, normalizedMediaType(mimeType));
  },

  /** Wrap a base64-encoded image, with or without a data-URL prefix. */
  base64(value: string, mediaType = 'image/jpeg'): ImageInput {
    const comma = value.indexOf(',');
    return vlmImageFromBase64(
      value.startsWith('data:') && comma >= 0 ? value.slice(comma + 1) : value,
      mediaType,
    );
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
    return vlmImageFromEncoded(bytes, normalizedMediaType(source.type));
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
