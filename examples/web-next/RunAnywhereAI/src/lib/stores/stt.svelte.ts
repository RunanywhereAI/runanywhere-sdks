import { AudioFormat } from '@runanywhere/proto-ts/model_types';
import { STTLanguage, STTOptions } from '@runanywhere/proto-ts/stt_options';
import { models } from './models.svelte';

const TARGET_RATE = 16000;

class SttStore {
  busy = $state(false);
  recording = $state(false);
  transcribing = $state(false);
  error = $state<string | null>(null);
  transcript = $state('');
  loadedModelId = $state<string | null>(null);

  private handle = $state<number | null>(null);
  private stream: MediaStream | null = null;
  private audioCtx: AudioContext | null = null;
  private source: MediaStreamAudioSourceNode | null = null;
  private processor: ScriptProcessorNode | null = null;
  private chunks: Float32Array[] = [];
  private captureRate = TARGET_RATE;

  get ready(): boolean {
    return this.handle != null;
  }

  private async ensureEngine(): Promise<void> {
    const { sdk } = await import('./sdk.svelte');
    await sdk.boot();
    if (!sdk.ready) throw new Error(sdk.message || 'Engine failed to start');
  }

  async load(id: string): Promise<void> {
    if (this.busy) return;
    this.busy = true;
    this.error = null;
    try {
      await this.ensureEngine();
      const item = models.stt.find((m) => m.id === id);
      if (!item || (item.state !== 'downloaded' && item.state !== 'loaded')) {
        await models.download(id);
      }
      const { RunAnywhere } = await import('@runanywhere/web');
      if (this.handle != null) {
        await RunAnywhere.sttDestroy(this.handle);
        this.handle = null;
      }
      this.handle = await RunAnywhere.sttLoadModel(id);
      this.loadedModelId = id;
      models.markLoaded('stt', id);
    } catch (err) {
      this.error = err instanceof Error ? err.message : String(err);
    } finally {
      this.busy = false;
    }
  }

  async record(): Promise<void> {
    if (this.handle == null || this.recording || this.transcribing) return;
    this.error = null;
    this.transcript = '';
    try {
      await this.startCapture();
      this.recording = true;
    } catch (err) {
      this.error = err instanceof Error ? err.message : String(err);
      this.teardownCapture();
    }
  }

  async stop(): Promise<void> {
    if (!this.recording) return;
    this.recording = false;
    const samples = this.finishCapture();
    if (this.handle == null || samples.length === 0) return;

    this.transcribing = true;
    try {
      this.transcript = await this.transcribeSamples(samples);
      if (!this.transcript) this.error = 'No speech detected';
    } catch (err) {
      this.error = err instanceof Error ? err.message : String(err);
    } finally {
      this.transcribing = false;
    }
  }

  // --- Shared capture/transcribe primitives (reused by the voice loop) ---
  // These let another orchestrator drive the mic without touching the STT
  // screen's `transcript`/`error` UI state.

  // Begin mic capture. Throws on permission denied / no device.
  async startCapture(): Promise<void> {
    if (this.stream) return;
    this.chunks = [];
    this.stream = await navigator.mediaDevices.getUserMedia({
      audio: { channelCount: 1, echoCancellation: true, noiseSuppression: true },
    });
    this.audioCtx = new AudioContext();
    if (this.audioCtx.state === 'suspended') await this.audioCtx.resume();
    this.captureRate = this.audioCtx.sampleRate;
    this.source = this.audioCtx.createMediaStreamSource(this.stream);
    this.processor = this.audioCtx.createScriptProcessor(4096, 1, 1);
    this.processor.onaudioprocess = (ev) => {
      const input = ev.inputBuffer.getChannelData(0);
      this.chunks.push(new Float32Array(input));
    };
    this.source.connect(this.processor);
    this.processor.connect(this.audioCtx.destination);
  }

  // Stop capture, tear down the graph, and return the merged raw samples.
  finishCapture(): Float32Array {
    const samples = this.mergeChunks();
    this.teardownCapture();
    return samples;
  }

  // Resample + PCM16-encode + transcribe a captured buffer. Returns trimmed text.
  async transcribeSamples(samples: Float32Array): Promise<string> {
    if (this.handle == null || samples.length === 0) return '';
    const resampled = this.resample(samples, this.captureRate, TARGET_RATE);
    const pcm = this.encodePcm16(resampled);
    const { RunAnywhere } = await import('@runanywhere/web');
    const options = STTOptions.fromPartial({
      language: STTLanguage.STT_LANGUAGE_EN,
      audioFormat: AudioFormat.AUDIO_FORMAT_PCM_S16LE,
      sampleRate: TARGET_RATE,
    });
    const t0 = performance.now();
    const out = await RunAnywhere.transcribe(this.handle, pcm, options);
    console.log(
      `[stt] transcribed ${(resampled.length / TARGET_RATE).toFixed(2)}s of audio in ${(performance.now() - t0).toFixed(0)}ms`,
    );
    return (out?.text ?? '').trim();
  }

  private mergeChunks(): Float32Array {
    const total = this.chunks.reduce((n, c) => n + c.length, 0);
    const merged = new Float32Array(total);
    let offset = 0;
    for (const c of this.chunks) {
      merged.set(c, offset);
      offset += c.length;
    }
    this.chunks = [];
    return merged;
  }

  private teardownCapture(): void {
    this.processor?.disconnect();
    this.source?.disconnect();
    this.stream?.getTracks().forEach((t) => t.stop());
    void this.audioCtx?.close();
    this.processor = null;
    this.source = null;
    this.stream = null;
    this.audioCtx = null;
  }

  // Linear resample to the target rate. The mic AudioContext typically runs at
  // 44.1/48 kHz; sherpa's offline recognizer expects 16 kHz mono.
  private resample(input: Float32Array, from: number, to: number): Float32Array {
    if (from === to) return input;
    const ratio = from / to;
    const outLen = Math.floor(input.length / ratio);
    const out = new Float32Array(outLen);
    for (let i = 0; i < outLen; i += 1) {
      const pos = i * ratio;
      const i0 = Math.floor(pos);
      const i1 = Math.min(i0 + 1, input.length - 1);
      const frac = pos - i0;
      out[i] = (input[i0] ?? 0) * (1 - frac) + (input[i1] ?? 0) * frac;
    }
    return out;
  }

  // Float32 [-1, 1] -> little-endian Int16 PCM. This is the byte layout the C
  // ABI transcribe path (sherpa) reads for audio_format = PCM/PCM_S16LE.
  private encodePcm16(samples: Float32Array): Uint8Array {
    const out = new Uint8Array(samples.length * 2);
    const view = new DataView(out.buffer);
    for (let i = 0; i < samples.length; i += 1) {
      let s = samples[i] ?? 0;
      if (s > 1) s = 1;
      if (s < -1) s = -1;
      view.setInt16(i * 2, Math.round(s * 0x7fff), true);
    }
    return out;
  }
}

export const stt = new SttStore();
