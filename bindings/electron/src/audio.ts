// audio.ts — audio I/O for the voice pipeline.
//
// PCM conversion, WAV codec, resample, and RMS are owned by commons
// (`rac_audio_*`) and reached through the N-API addon. This module only
// forwards typed arrays — it does not re-implement DSP.
//
// Ownership of the native addon stays in the utility process (or an in-process
// NativeBackend). Callers bind a {@link AudioDspBackend} via
// {@link bindAudioBackend} (done by `createRunAnywhere`); the preload never
// `require`s `./bridge` / `resolveAddon`. Unit tests may inject a sync fake
// with {@link setAudioNativeForTests}.
//
// Renderer-only helpers (MicRecorder / SpeakerPlayer) sit on top of Web Audio
// and call the same commons-backed converters. They reference browser globals
// only inside methods so importing this module in Node is safe.

import { audioCaptureDefaults } from '@runanywhere/proto-ts/defaults/pool';

import { ErrorCategory, ErrorCode, SDKException } from './errors';

/**
 * `AudioCaptureDefaults.mic_sample_rate_hz` from `idl/sdk_defaults.proto` — the
 * rate every speech path in this SDK normalizes to.
 */
const CAPTURE_SAMPLE_RATE = audioCaptureDefaults.micSampleRateHz;

/** Sync DSP surface exported by runanywhere_native.node (audio_bridge.cpp). */
export interface AudioNative {
  audioFloat32ToPcm16(samples: Float32Array): Int16Array;
  audioPcm16ToFloat32(samples: Int16Array): Float32Array;
  audioResampleF32(samples: Float32Array, inRate: number, outRate: number): Float32Array;
  audioComputeRms(samples: Float32Array): number;
  audioFloat32ToWav(samples: Float32Array, sampleRate: number): Uint8Array;
  audioWavToFloat32(bytes: Uint8Array): { sampleRate: number; samples: Float32Array };
  /** Commons `rac_audio_pcm_bytes_to_ms`. Invalid/missing format returns 0. */
  audioPcmBytesToMs(
    byteCount: number,
    format: { sampleRate: number; channels?: number; bitsPerSample?: number }
  ): number;
}

/** Promise-shaped DSP surface — NativeBackend or RpcBackend. */
export interface AudioDspBackend {
  audioFloat32ToPcm16(samples: Float32Array): Promise<Int16Array>;
  audioPcm16ToFloat32(samples: Int16Array): Promise<Float32Array>;
  audioResampleF32(
    samples: Float32Array,
    inRate: number,
    outRate: number
  ): Promise<Float32Array>;
  audioComputeRms(samples: Float32Array): Promise<number>;
  audioFloat32ToWav(samples: Float32Array, sampleRate: number): Promise<Uint8Array>;
  audioWavToFloat32(
    bytes: Uint8Array
  ): Promise<{ sampleRate: number; samples: Float32Array }>;
  audioPcmBytesToMs(
    byteCount: number,
    format: { sampleRate: number; channels?: number; bitsPerSample?: number }
  ): Promise<number>;
}

let injected: AudioNative | null = null;
let backend: AudioDspBackend | null = null;

/** Test hook — unit tests inject a fake so they do not need the .node. */
export function setAudioNativeForTests(native: AudioNative | null): void {
  injected = native;
}

/**
 * Bind the process that owns `rac_audio_*` (utility host via RpcBackend, or
 * in-process NativeBackend). Called by `createRunAnywhere`.
 */
export function bindAudioBackend(dsp: AudioDspBackend | null): void {
  backend = dsp;
}

function audioUnavailable(): never {
  throw SDKException.of(
    ErrorCode.ERROR_CODE_SERVICE_NOT_AVAILABLE,
    'audio DSP unavailable — inference utility not connected (bindAudioBackend / setAudioNativeForTests)',
    { category: ErrorCategory.ERROR_CATEGORY_COMPONENT }
  );
}

async function withAudioDsp<T>(
  syncCall: (native: AudioNative) => T,
  asyncCall: (dsp: AudioDspBackend) => Promise<T>
): Promise<T> {
  if (injected) return syncCall(injected);
  if (backend) return asyncCall(backend);
  audioUnavailable();
}

/** Clamp+scale float32 samples in [-1,1] to signed 16-bit PCM via commons. */
export function float32ToPcm16(input: Float32Array): Promise<Int16Array> {
  return withAudioDsp(
    (n) => n.audioFloat32ToPcm16(input),
    (b) => b.audioFloat32ToPcm16(input)
  );
}

/** Convert signed 16-bit PCM samples back to float32 in [-1,1] via commons. */
export function pcm16ToFloat32(input: Int16Array): Promise<Float32Array> {
  return withAudioDsp(
    (n) => n.audioPcm16ToFloat32(input),
    (b) => b.audioPcm16ToFloat32(input)
  );
}

/** Little-endian int16 bytes for float32 samples — the shape STT.transcribe wants. */
export async function pcm16Bytes(input: Float32Array): Promise<Uint8Array> {
  const pcm = await float32ToPcm16(input);
  return new Uint8Array(pcm.buffer, pcm.byteOffset, pcm.byteLength);
}

/**
 * Resample mono float32 audio from `inRate` to `outRate` via commons
 * (`rac_audio_resample_f32`, linear interpolation).
 */
export function downsample(
  input: Float32Array,
  inRate: number,
  outRate: number
): Promise<Float32Array> {
  if (outRate <= 0 || inRate <= 0) {
    return Promise.reject(
      SDKException.validationFailed({
        fieldPath: inRate <= 0 ? 'inRate' : 'outRate',
        message: 'downsample: sample rates must be positive',
      })
    );
  }
  return withAudioDsp(
    (n) => n.audioResampleF32(input, inRate, outRate),
    (b) => b.audioResampleF32(input, inRate, outRate)
  );
}

/** Root-mean-square level of a frame via commons (`rac_audio_compute_rms`). */
export async function rms(input: Float32Array): Promise<number> {
  if (!input.length) return 0;
  return withAudioDsp(
    (n) => n.audioComputeRms(input),
    (b) => b.audioComputeRms(input)
  );
}

/** Encode mono float32 samples as a 16-bit PCM WAV via commons. */
export function encodeWav(samples: Float32Array, sampleRate: number): Promise<Uint8Array> {
  return withAudioDsp(
    (n) => n.audioFloat32ToWav(samples, sampleRate),
    (b) => b.audioFloat32ToWav(samples, sampleRate)
  );
}

/**
 * Decode a 16-bit PCM WAV byte array to `{ sampleRate, samples }` (mono float32)
 * via commons (`rac_audio_wav_to_float32`).
 */
export function decodeWav(
  bytes: Uint8Array
): Promise<{ sampleRate: number; samples: Float32Array }> {
  return withAudioDsp(
    (n) => n.audioWavToFloat32(bytes),
    (b) => b.audioWavToFloat32(bytes)
  );
}

/**
 * Duration of a raw PCM payload in milliseconds via commons
 * (`rac_audio_pcm_bytes_to_ms`). Returns 0 when the format is missing/invalid.
 */
export async function pcmDurationMs(
  byteCount: number,
  format: { sampleRate: number; channels?: number; bitsPerSample?: number }
): Promise<number> {
  if (byteCount <= 0 || !format?.sampleRate) return 0;
  const ms = await withAudioDsp(
    (n) => n.audioPcmBytesToMs(byteCount, format),
    (b) => b.audioPcmBytesToMs(byteCount, format)
  );
  return ms || 0;
}

/**
 * Duration of mono float32 samples in milliseconds via commons.
 * Returns 0 when the rate is missing.
 */
export function float32DurationMs(samples: number, sampleRate: number): Promise<number> {
  if (samples <= 0 || sampleRate <= 0) return Promise.resolve(0);
  return pcmDurationMs(samples * 4, { sampleRate, channels: 1, bitsPerSample: 32 });
}

// ---------------------------------------------------------------------------
// Renderer-only helpers (Web Audio). These throw a clear error outside a browser
// / Electron renderer. They reference browser globals only inside methods so the
// module stays importable in Node.
// ---------------------------------------------------------------------------

/** The subset of AudioContext-like globals a renderer provides. */
type AudioCtor = new () => AudioContext;

function getAudioContextCtor(): AudioCtor {
  const g = globalThis as unknown as {
    AudioContext?: AudioCtor;
    webkitAudioContext?: AudioCtor;
  };
  const Ctor = g.AudioContext ?? g.webkitAudioContext;
  if (!Ctor) throw new Error('Web Audio API unavailable — use MicRecorder/SpeakerPlayer in an Electron renderer');
  return Ctor;
}

export interface MicRecorderOptions {
  /** Target rate for the captured PCM16; defaults to the IDL capture rate, which is what STT wants. */
  targetSampleRate?: number;
}

/**
 * Capture microphone audio in a renderer and return 16 kHz mono PCM16 bytes on
 * stop() — ready to hand to STT.transcribe (directly, or over the preload RPC).
 */
export class MicRecorder {
  private ctx: AudioContext | null = null;
  private stream: MediaStream | null = null;
  private node: ScriptProcessorNode | null = null;
  private chunks: Float32Array[] = [];
  private inRate = 48000;
  private readonly targetRate: number;

  constructor(opts: MicRecorderOptions = {}) {
    this.targetRate = opts.targetSampleRate ?? CAPTURE_SAMPLE_RATE;
  }

  /** Open the mic and begin buffering audio. */
  async start(): Promise<void> {
    const nav = (globalThis as unknown as { navigator?: Navigator }).navigator;
    if (!nav?.mediaDevices?.getUserMedia) {
      throw new Error('MicRecorder.start requires a renderer with navigator.mediaDevices');
    }
    this.stream = await nav.mediaDevices.getUserMedia({ audio: { channelCount: 1 } });
    const Ctx = getAudioContextCtor();
    this.ctx = new Ctx();
    this.inRate = this.ctx.sampleRate;
    const source = this.ctx.createMediaStreamSource(this.stream);
    const node = this.ctx.createScriptProcessor(4096, 1, 1);
    this.chunks = [];
    node.onaudioprocess = (e: AudioProcessingEvent) => {
      this.chunks.push(new Float32Array(e.inputBuffer.getChannelData(0)));
    };
    source.connect(node);
    node.connect(this.ctx.destination);
    this.node = node;
  }

  /** Stop capture and return the utterance as 16 kHz mono PCM16 bytes. */
  async stop(): Promise<Uint8Array> {
    this.node?.disconnect();
    this.stream?.getTracks().forEach((t) => t.stop());
    let total = 0;
    for (const c of this.chunks) total += c.length;
    const merged = new Float32Array(total);
    let off = 0;
    for (const c of this.chunks) {
      merged.set(c, off);
      off += c.length;
    }
    const resampled = await downsample(merged, this.inRate, this.targetRate);
    this.chunks = [];
    void this.ctx?.close();
    this.ctx = null;
    this.stream = null;
    this.node = null;
    return pcm16Bytes(resampled);
  }
}

/** Play float32 PCM (e.g. TTS output) through the renderer's speakers. */
export class SpeakerPlayer {
  private ctx: AudioContext | null = null;

  /** Play `samples` at `sampleRate`; resolves when playback finishes. */
  play(samples: Float32Array, sampleRate: number): Promise<void> {
    const Ctx = getAudioContextCtor();
    const ctx = this.ctx ?? (this.ctx = new Ctx());
    const buffer = ctx.createBuffer(1, samples.length, sampleRate);
    buffer.getChannelData(0).set(samples);
    const source = ctx.createBufferSource();
    source.buffer = buffer;
    source.connect(ctx.destination);
    return new Promise<void>((resolve) => {
      source.onended = () => resolve();
      source.start();
    });
  }

  /** Release the audio context. */
  close(): void {
    void this.ctx?.close();
    this.ctx = null;
  }
}
