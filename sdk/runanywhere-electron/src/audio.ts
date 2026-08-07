// Audio helpers for the desktop build. Pure DSP utilities the renderer uses to
// prepare microphone samples, plus the AudioInput -> proto converters the stt,
// vad, and diarization namespaces share. Commons owns decoding of container and
// file inputs; the raw-PCM path here just packages samples the caller already has.

import { AudioEncoding } from '@runanywhere/proto-ts/model_types';

import { SDKException } from './errors.js';
import type { AudioInput } from './types.js';

/** Float samples in [-1, 1] to little-endian 16-bit PCM bytes. */
export function toPcm16(samples: Float32Array): Uint8Array {
  const out = new Int16Array(samples.length);
  for (let i = 0; i < samples.length; i++) {
    const s = Math.max(-1, Math.min(1, samples[i]));
    out[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
  }
  return new Uint8Array(out.buffer);
}

/**
 * Block-average resample from `fromRate` to `toRate`. Averaging (not
 * nearest-neighbour) matters going down: dropping samples folds energy above the
 * new Nyquist back into the band a model reads.
 */
export function downsample(samples: Float32Array, fromRate: number, toRate: number): Float32Array {
  if (fromRate === toRate || !samples.length) return samples;
  const ratio = fromRate / toRate;
  const outLen = Math.floor(samples.length / ratio);
  const out = new Float32Array(outLen);
  for (let i = 0; i < outLen; i++) {
    const start = Math.floor(i * ratio);
    const end = Math.min(samples.length, Math.floor((i + 1) * ratio));
    let sum = 0;
    for (let j = start; j < end; j++) sum += samples[j];
    out[i] = end > start ? sum / (end - start) : 0;
  }
  return out;
}

/**
 * Resample a raw-PCM AudioInput to `targetRate` (16 kHz for speech models). The
 * sherpa STT/VAD/diarization models expect 16 kHz; feeding a mic's native rate
 * (often 48 kHz) unresampled makes recognizers hallucinate. `wav`/`file` inputs
 * are returned untouched (commons decodes and resamples those).
 */
export function resampleInput(input: AudioInput, targetRate = 16000): AudioInput {
  if (input.kind === 'float32') {
    if (input.sampleRate === targetRate) return input;
    return { kind: 'float32', samples: downsample(input.samples, input.sampleRate, targetRate), sampleRate: targetRate, channels: input.channels };
  }
  if (input.kind === 'pcm16') {
    if (input.sampleRate === targetRate) return input;
    const f = new Float32Array(input.samples.length);
    for (let i = 0; i < f.length; i++) f[i] = input.samples[i] / 32768;
    return { kind: 'float32', samples: downsample(f, input.sampleRate, targetRate), sampleRate: targetRate, channels: input.channels };
  }
  return input;
}

/**
 * Normalize a raw-PCM AudioInput to 16 kHz PCM16 — the format the sherpa speech
 * models actually consume. They mis-decode float32 PCM (it transcribes as noise),
 * so stt/diarization convert through here. `wav`/`file` inputs are left for commons.
 */
export function to16kPcm16(input: AudioInput): AudioInput {
  if (input.kind === 'wav' || input.kind === 'file') return input;
  const channels = input.channels;
  const r = resampleInput(input, 16000);
  if (r.kind !== 'float32') return r; // already pcm16 at 16 kHz
  const out = new Int16Array(r.samples.length);
  for (let i = 0; i < r.samples.length; i++) {
    const s = Math.max(-1, Math.min(1, r.samples[i]));
    out[i] = s < 0 ? s * 0x8000 : s * 0x7fff;
  }
  return { kind: 'pcm16', samples: out, sampleRate: 16000, channels };
}

/** Root-mean-square amplitude of a frame, a cheap level/energy estimate. */
export function rms(frame: Float32Array): number {
  if (!frame.length) return 0;
  let sum = 0;
  for (let i = 0; i < frame.length; i++) sum += frame[i] * frame[i];
  return Math.sqrt(sum / frame.length);
}

function viewBytes(a: Int16Array | Float32Array): Uint8Array {
  return new Uint8Array(a.buffer.slice(a.byteOffset, a.byteOffset + a.byteLength));
}

/** Raw-PCM view of an AudioInput for the request protos that carry bytes directly. */
export interface RawAudio {
  audioData: Uint8Array;
  encoding: AudioEncoding;
  sampleRate: number;
  channels: number;
}

/** Package an AudioInput as raw bytes + format. `file` is unsupported here (no decoder in the renderer). */
export function audioToRaw(input: AudioInput): RawAudio {
  switch (input.kind) {
    case 'pcm16':
      return {
        audioData: viewBytes(input.samples),
        encoding: AudioEncoding.AUDIO_ENCODING_PCM_S16_LE,
        sampleRate: input.sampleRate,
        channels: input.channels ?? 1,
      };
    case 'float32':
      return {
        audioData: viewBytes(input.samples),
        encoding: AudioEncoding.AUDIO_ENCODING_PCM_F32_LE,
        sampleRate: input.sampleRate,
        channels: input.channels ?? 1,
      };
    case 'wav':
      return {
        audioData: input.bytes,
        encoding: AudioEncoding.AUDIO_ENCODING_CONTAINER,
        sampleRate: 0,
        channels: 0,
      };
    case 'file':
      throw SDKException.invalidInput(
        'file audio input is not supported on this path; pass pcm16/float32/wav bytes, or use stt.transcribe which accepts a file'
      );
  }
}

/** Fields for an STT/VAD audio-source proto. STT also accepts a file via `fileUri`. */
export interface AudioSourceFields {
  audioData?: Uint8Array;
  fileUri?: string;
  encoding: AudioEncoding;
  sampleRate: number;
  channels: number;
}

/** AudioInput -> STTAudioSource fields; `file` maps to fileUri so commons decodes it. */
export function audioToSource(input: AudioInput): AudioSourceFields {
  if (input.kind === 'file') {
    return {
      fileUri: input.path,
      encoding: AudioEncoding.AUDIO_ENCODING_CONTAINER,
      sampleRate: 0,
      channels: 0,
    };
  }
  const raw = audioToRaw(input);
  return { audioData: raw.audioData, encoding: raw.encoding, sampleRate: raw.sampleRate, channels: raw.channels };
}
