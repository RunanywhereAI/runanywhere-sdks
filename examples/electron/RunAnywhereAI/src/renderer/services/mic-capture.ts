/**
 * Renderer-side microphone capture for Transcribe / VAD / Diarization.
 *
 * Voice owns its own mic inside `voice.createSession().start()` — this helper is
 * only for screens that push PCM into `stt` / `vad` / `diarization` themselves.
 * Leaving those routes must call {@link MicCapture.stop} so the mic closes.
 */
import { audioCaptureDefaults } from '@runanywhere/proto-ts/defaults/pool';

export const MIC_SAMPLE_RATE_HZ = audioCaptureDefaults.micSampleRateHz;

export interface MicCaptureResult {
  readonly samples: Float32Array;
  readonly sampleRate: number;
}

export type MicFrameHandler = (samples: Float32Array, sampleRate: number) => void;

/**
 * One live capture graph. ScriptProcessor is intentional: the Electron SDK's
 * voice path uses the same shape, and AudioWorklet would add packaging surface
 * for no product gain here.
 */
export class MicCapture {
  private stream: MediaStream | null = null;
  private ctx: AudioContext | null = null;
  private node: ScriptProcessorNode | null = null;
  private readonly chunks: Float32Array[] = [];
  private frameHandler: MicFrameHandler | null = null;

  get active(): boolean {
    return this.stream !== null;
  }

  async start(onFrame?: MicFrameHandler): Promise<void> {
    if (this.stream !== null) return;
    this.frameHandler = onFrame ?? null;
    this.chunks.length = 0;

    this.stream = await navigator.mediaDevices.getUserMedia({
      audio: { channelCount: 1 },
    });
    this.ctx = new AudioContext();
    const source = this.ctx.createMediaStreamSource(this.stream);
    const node = this.ctx.createScriptProcessor(4096, 1, 1);
    const rate = this.ctx.sampleRate;
    node.onaudioprocess = (event) => {
      const frame = new Float32Array(event.inputBuffer.getChannelData(0));
      this.chunks.push(frame);
      this.frameHandler?.(frame, rate);
    };
    source.connect(node);
    node.connect(this.ctx.destination);
    this.node = node;
  }

  /**
   * Tear down the graph. Never throws — a throw during leave-route cleanup
   * would leave the next screen unable to open the mic.
   */
  stop(): MicCaptureResult | null {
    if (this.stream === null || this.ctx === null) return null;

    const rate = this.ctx.sampleRate;
    const chunks = this.chunks.splice(0, this.chunks.length);
    try {
      this.node?.disconnect();
    } catch {
      /* already detached */
    }
    try {
      this.stream.getTracks().forEach((track) => track.stop());
    } catch {
      /* already stopped */
    }
    try {
      void this.ctx.close();
    } catch {
      /* already closed */
    }
    this.node = null;
    this.stream = null;
    this.ctx = null;
    this.frameHandler = null;

    let total = 0;
    for (const chunk of chunks) total += chunk.length;
    const samples = new Float32Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      samples.set(chunk, offset);
      offset += chunk.length;
    }
    return { samples, sampleRate: rate };
  }
}

/** Resample to the SDK capture rate when the device clock differs. */
export function toMicRate(samples: Float32Array, sampleRate: number): Float32Array {
  if (sampleRate === MIC_SAMPLE_RATE_HZ) return samples;
  return window.runanywhere.downsample(samples, sampleRate, MIC_SAMPLE_RATE_HZ);
}

/** Float32 samples as little-endian bytes for `openStream` push frames. */
export function float32FrameBytes(samples: Float32Array): Uint8Array {
  return new Uint8Array(samples.buffer, samples.byteOffset, samples.byteLength);
}
