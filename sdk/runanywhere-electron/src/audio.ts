// audio.ts — audio I/O for the voice pipeline.
//
// Two layers:
//   1. Pure DSP + WAV codec (float32<->pcm16, resample, encode/decode WAV) that
//      work identically in Node and the browser and are fully unit-tested.
//   2. Renderer-only helpers (MicRecorder / SpeakerPlayer) over the Web Audio API
//      — the Electron-native way to capture the mic and play TTS output. They
//      only touch browser globals inside methods, so importing this module in
//      Node (e.g. via the SDK index) is safe; instantiating them there throws a
//      clear error.
//
// The STT model wants 16 kHz mono PCM16 bytes; the TTS model returns float32 at
// its own sample rate. These helpers bridge to/from those formats.

/** Clamp+scale float32 samples in [-1,1] to signed 16-bit PCM. */
export function float32ToPcm16(input: Float32Array): Int16Array {
  const out = new Int16Array(input.length);
  for (let i = 0; i < input.length; i++) {
    const s = Math.max(-1, Math.min(1, input[i]));
    // Symmetric scale (round(s * 32768)) clamped to the int16 range — round-trip
    // error stays within half a quantization step except at exactly +1.0.
    out[i] = Math.max(-32768, Math.min(32767, Math.round(s * 0x8000)));
  }
  return out;
}

/** Convert signed 16-bit PCM samples back to float32 in [-1,1]. */
export function pcm16ToFloat32(input: Int16Array): Float32Array {
  const out = new Float32Array(input.length);
  for (let i = 0; i < input.length; i++) out[i] = input[i] / 0x8000;
  return out;
}

/** Little-endian int16 bytes for float32 samples — the shape STT.transcribe wants. */
export function pcm16Bytes(input: Float32Array): Uint8Array {
  const pcm = float32ToPcm16(input);
  return new Uint8Array(pcm.buffer, pcm.byteOffset, pcm.byteLength);
}

/**
 * Resample mono float32 audio from `inRate` to `outRate` by block averaging.
 * Returns a copy unchanged when the rates match or when upsampling (we only need
 * downsampling, e.g. a 48 kHz mic capture down to the 16 kHz the STT model wants).
 */
export function downsample(input: Float32Array, inRate: number, outRate: number): Float32Array {
  if (outRate <= 0 || inRate <= 0) throw new Error('downsample: rates must be positive');
  if (outRate >= inRate) return input.slice();
  const ratio = inRate / outRate;
  const outLen = Math.floor(input.length / ratio);
  const out = new Float32Array(outLen);
  for (let i = 0; i < outLen; i++) {
    const start = Math.floor(i * ratio);
    const end = Math.min(input.length, Math.floor((i + 1) * ratio));
    let sum = 0;
    let n = 0;
    for (let j = start; j < end; j++) {
      sum += input[j];
      n++;
    }
    out[i] = n ? sum / n : 0;
  }
  return out;
}

/** Root-mean-square level of a frame — a cheap energy gate for VAD. */
export function rms(input: Float32Array): number {
  if (!input.length) return 0;
  let sum = 0;
  for (let i = 0; i < input.length; i++) sum += input[i] * input[i];
  return Math.sqrt(sum / input.length);
}

const RIFF_HEADER_BYTES = 44;

function writeAscii(view: DataView, offset: number, text: string): void {
  for (let i = 0; i < text.length; i++) view.setUint8(offset + i, text.charCodeAt(i));
}

/** Encode mono float32 samples as a 16-bit PCM WAV file (RIFF) byte array. */
export function encodeWav(samples: Float32Array, sampleRate: number): Uint8Array {
  const pcm = float32ToPcm16(samples);
  const dataBytes = pcm.byteLength;
  const buffer = new ArrayBuffer(RIFF_HEADER_BYTES + dataBytes);
  const view = new DataView(buffer);
  writeAscii(view, 0, 'RIFF');
  view.setUint32(4, 36 + dataBytes, true);
  writeAscii(view, 8, 'WAVE');
  writeAscii(view, 12, 'fmt ');
  view.setUint32(16, 16, true); // fmt chunk size
  view.setUint16(20, 1, true); // PCM
  view.setUint16(22, 1, true); // mono
  view.setUint32(24, sampleRate, true);
  view.setUint32(28, sampleRate * 2, true); // byte rate (mono, 16-bit)
  view.setUint16(32, 2, true); // block align
  view.setUint16(34, 16, true); // bits per sample
  writeAscii(view, 36, 'data');
  view.setUint32(40, dataBytes, true);
  const out = new Uint8Array(buffer);
  out.set(new Uint8Array(pcm.buffer, pcm.byteOffset, pcm.byteLength), RIFF_HEADER_BYTES);
  return out;
}

/**
 * Decode a 16-bit PCM WAV byte array to `{ sampleRate, samples }` (mono float32).
 * Scans RIFF sub-chunks for `fmt ` and `data`; stereo is down-mixed to mono.
 */
export function decodeWav(bytes: Uint8Array): { sampleRate: number; samples: Float32Array } {
  const view = new DataView(bytes.buffer, bytes.byteOffset, bytes.byteLength);
  const tag = (o: number) => String.fromCharCode(bytes[o], bytes[o + 1], bytes[o + 2], bytes[o + 3]);
  if (bytes.length < 12 || tag(0) !== 'RIFF' || tag(8) !== 'WAVE') {
    throw new Error('decodeWav: not a RIFF/WAVE file');
  }
  let channels = 1;
  let sampleRate = 16000;
  let bits = 16;
  let dataOffset = -1;
  let dataLen = 0;
  let p = 12;
  while (p + 8 <= bytes.length) {
    const id = tag(p);
    const size = view.getUint32(p + 4, true);
    const body = p + 8;
    if (id === 'fmt ') {
      channels = view.getUint16(body + 2, true) || 1;
      sampleRate = view.getUint32(body + 4, true) || 16000;
      bits = view.getUint16(body + 14, true) || 16;
    } else if (id === 'data') {
      dataOffset = body;
      dataLen = size;
      break;
    }
    p = body + size + (size % 2); // chunks are word-aligned
  }
  if (dataOffset < 0) throw new Error('decodeWav: no data chunk');
  if (bits !== 16) throw new Error(`decodeWav: only 16-bit PCM supported (got ${bits}-bit)`);
  const frames = Math.floor(dataLen / 2 / channels);
  const out = new Float32Array(frames);
  for (let i = 0; i < frames; i++) {
    let sum = 0;
    for (let c = 0; c < channels; c++) {
      sum += view.getInt16(dataOffset + (i * channels + c) * 2, true) / 0x8000;
    }
    out[i] = sum / channels;
  }
  return { sampleRate, samples: out };
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
  /** Target rate for the captured PCM16 (default 16000, what STT wants). */
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
    this.targetRate = opts.targetSampleRate ?? 16000;
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
  stop(): Uint8Array {
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
    const resampled = downsample(merged, this.inRate, this.targetRate);
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
