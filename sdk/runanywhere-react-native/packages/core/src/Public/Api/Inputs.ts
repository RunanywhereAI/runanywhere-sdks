/**
 * Constructors for the public audio/image/message inputs, plus the converters
 * that turn them into the proto sources the native bridge expects.
 */

import { audioCaptureDefaults } from '@runanywhere/proto-ts/defaults/pool';
import { MessageRole, ChatMessage as ChatMessageProto } from '@runanywhere/proto-ts/chat';
import { AudioEncoding } from '@runanywhere/proto-ts/model_types';
import { STTAudioSource } from '@runanywhere/proto-ts/stt_options';
import { VADAudioSource } from '@runanywhere/proto-ts/vad_options';
import {
  SegmentationImage,
  SegmentationPixelFormat,
} from '@runanywhere/proto-ts/segmentation';
import { VLMImage } from '@runanywhere/proto-ts/vlm_options';

import { SDKException } from '../../Foundation/Errors/SDKException';
import type { AudioInput, ChatMessage, ImageInput } from './Types';

const DEFAULT_SAMPLE_RATE = audioCaptureDefaults.micSampleRateHz;

/** Factories for {@link AudioInput}. */
export const AudioInputs = {
  /** Wrap signed 16-bit little-endian PCM samples. */
  pcm16(
    data: Uint8Array,
    sampleRate: number = DEFAULT_SAMPLE_RATE,
    channels = 1
  ): AudioInput {
    return { data, encoding: 'pcm16', sampleRate, channels };
  },

  /** Wrap 32-bit float samples. */
  float32(
    samples: Float32Array,
    sampleRate: number = DEFAULT_SAMPLE_RATE,
    channels = 1
  ): AudioInput {
    const data = new Uint8Array(
      samples.buffer.slice(
        samples.byteOffset,
        samples.byteOffset + samples.byteLength
      )
    );
    return { data, encoding: 'float32', sampleRate, channels };
  },

  /** Wrap a complete WAV blob, header included. */
  wav(data: Uint8Array, sampleRate: number = DEFAULT_SAMPLE_RATE): AudioInput {
    return { data, encoding: 'container', sampleRate, channels: 1 };
  },

  /** Reference an audio file on disk. */
  file(path: string, sampleRate: number = DEFAULT_SAMPLE_RATE): AudioInput {
    return { filePath: path, encoding: 'container', sampleRate, channels: 1 };
  },
};

/** Factories for {@link ImageInput}. */
export const ImageInputs = {
  /** Reference an image file on disk. */
  file(path: string): ImageInput {
    return { filePath: path };
  },

  /** Wrap encoded JPEG/PNG/WebP bytes. */
  bytes(data: Uint8Array): ImageInput {
    return { bytes: data };
  },

  /** Wrap a base64-encoded image, as React Native camera and picker APIs return. */
  base64(value: string): ImageInput {
    return { base64: value };
  },

  /** Wrap a raw RGB pixel buffer. */
  rawRgb(data: Uint8Array, width: number, height: number): ImageInput {
    return { rawPixels: data, width, height, pixelFormat: 'rgb8' };
  },

  /** Wrap a raw RGBA pixel buffer. */
  rawRgba(data: Uint8Array, width: number, height: number): ImageInput {
    return { rawPixels: data, width, height, pixelFormat: 'rgba8' };
  },
};

const roleByName: Record<ChatMessage['role'], MessageRole> = {
  system: MessageRole.MESSAGE_ROLE_SYSTEM,
  user: MessageRole.MESSAGE_ROLE_USER,
  assistant: MessageRole.MESSAGE_ROLE_ASSISTANT,
  tool: MessageRole.MESSAGE_ROLE_TOOL,
};

/** Map public chat turns onto the proto message list. */
export function toChatMessages(messages: ChatMessage[]): ChatMessageProto[] {
  return messages.map((message) =>
    ChatMessageProto.fromPartial({
      role: roleByName[message.role],
      content: message.content,
      ...(message.toolCallId ? { toolCallId: message.toolCallId } : {}),
    })
  );
}

function decodeBase64(value: string): Uint8Array {
  const binary = atob(value);
  const bytes = new Uint8Array(binary.length);
  for (let i = 0; i < binary.length; i++) bytes[i] = binary.charCodeAt(i);
  return bytes;
}

function requireAudioBytes(audio: AudioInput, operation: string): Uint8Array {
  if (audio.data) return audio.data;
  throw SDKException.invalidInput(
    `${operation} needs audio bytes; read the file into an AudioInput first`
  );
}

/** Build the STT proto audio source for a public audio input. */
export function toSttAudioSource(audio: AudioInput): STTAudioSource {
  const encoding =
    audio.encoding === 'pcm16'
      ? AudioEncoding.AUDIO_ENCODING_PCM_S16_LE
      : audio.encoding === 'float32'
        ? AudioEncoding.AUDIO_ENCODING_PCM_F32_LE
        : AudioEncoding.AUDIO_ENCODING_CONTAINER;
  return STTAudioSource.fromPartial({
    ...(audio.data ? { audioData: audio.data } : {}),
    ...(audio.filePath ? { fileUri: audio.filePath } : {}),
    encoding,
    sampleRate: audio.sampleRate,
    channels: audio.channels,
  });
}

/** Build the VAD proto audio source for a public audio input. */
export function toVadAudioSource(audio: AudioInput): VADAudioSource {
  return VADAudioSource.fromPartial({
    audioData: requireAudioBytes(audio, 'vad.detect'),
    encoding:
      audio.encoding === 'float32'
        ? AudioEncoding.AUDIO_ENCODING_PCM_F32_LE
        : AudioEncoding.AUDIO_ENCODING_PCM_S16_LE,
    sampleRate: audio.sampleRate,
    channels: audio.channels,
  });
}

/** Pick the diarization encoding matching a public audio input. */
export function toDiarizationEncoding(
  audio: AudioInput
): AudioEncoding {
  return audio.encoding === 'float32'
    ? AudioEncoding.AUDIO_ENCODING_PCM_F32_LE
    : AudioEncoding.AUDIO_ENCODING_PCM_S16_LE;
}

/** Raw bytes of a public audio input, for verbs that take a bare buffer. */
export function toAudioBytes(
  audio: AudioInput,
  operation: string
): Uint8Array {
  return requireAudioBytes(audio, operation);
}

/** Default MIME type for encoded image bytes with no declared container. */
const DEFAULT_IMAGE_MEDIA_TYPE = 'image/jpeg';

/**
 * Build the VLM proto image for a public image input.
 *
 * `VLMImageFormat` is deleted outright: `VLMImage` is now a plain oneof
 * (`filePath`/`data`/`rawRgb`/`base64`/`rawRgba`) plus a required
 * `mediaType` (MIME type, required when `data`/`base64` is set) and
 * `width`/`height` (required for the raw pixel forms). `encoded` was
 * renamed `data`.
 */
export function toVlmImage(image: ImageInput): VLMImage {
  if (image.filePath) {
    return VLMImage.fromPartial({
      filePath: image.filePath,
    });
  }
  if (image.base64) {
    return VLMImage.fromPartial({
      base64: image.base64,
      mediaType: DEFAULT_IMAGE_MEDIA_TYPE,
    });
  }
  if (image.rawPixels) {
    const width = image.width ?? 0;
    const height = image.height ?? 0;
    return VLMImage.fromPartial({
      ...(image.pixelFormat === 'rgba8'
        ? { rawRgba: image.rawPixels }
        : { rawRgb: image.rawPixels }),
      width,
      height,
    });
  }
  if (image.bytes) {
    return VLMImage.fromPartial({
      data: image.bytes,
      mediaType: DEFAULT_IMAGE_MEDIA_TYPE,
    });
  }
  throw SDKException.invalidInput('ImageInput carries no image data');
}

/**
 * Encoded bytes of a public image input, for verbs that take a bare buffer.
 *
 * @throws SDKException when the input only names a file path, which the JS
 * layer cannot read.
 */
export function encodeImageBytes(image: ImageInput): Uint8Array {
  if (image.bytes) return image.bytes;
  if (image.base64) return decodeBase64(image.base64);
  if (image.rawPixels) return image.rawPixels;
  throw SDKException.invalidInput(
    'ImageInput needs bytes, base64, or raw pixels here; a file path cannot be read from JavaScript'
  );
}

/**
 * Build the segmentation proto image for a public image input.
 *
 * @throws SDKException when the input is not a raw pixel buffer — segmentation
 * needs decoded pixels and dimensions, which JavaScript cannot derive from an
 * encoded image.
 */
export function toSegmentationImage(image: ImageInput): SegmentationImage {
  if (!image.rawPixels || !image.width || !image.height) {
    throw SDKException.invalidInput(
      'segmentation.segment needs a raw pixel ImageInput with width and height'
    );
  }
  const pixelFormat =
    image.pixelFormat === 'bgra8'
      ? SegmentationPixelFormat.SEGMENTATION_PIXEL_FORMAT_BGRA8
      : image.pixelFormat === 'rgb8'
        ? SegmentationPixelFormat.SEGMENTATION_PIXEL_FORMAT_RGB8
        : SegmentationPixelFormat.SEGMENTATION_PIXEL_FORMAT_RGBA8;
  return SegmentationImage.fromPartial({
    data: image.rawPixels,
    width: image.width,
    height: image.height,
    pixelFormat,
  });
}
