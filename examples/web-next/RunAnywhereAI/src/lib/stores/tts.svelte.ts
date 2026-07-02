import { AudioFormat } from '@runanywhere/proto-ts/model_types';
import { TTSOptions } from '@runanywhere/proto-ts/tts_options';
import { models } from './models.svelte';

class TtsStore {
  busy = $state(false);
  speaking = $state(false);
  error = $state<string | null>(null);
  loadedModelId = $state<string | null>(null);

  private handle = $state<number | null>(null);
  private audioCtx: AudioContext | null = null;
  private source: AudioBufferSourceNode | null = null;
  private cancelled = false;

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
      const item = models.tts.find((m) => m.id === id);
      if (!item || (item.state !== 'downloaded' && item.state !== 'loaded')) {
        await models.download(id);
      }
      const { RunAnywhere } = await import('@runanywhere/web');
      if (this.handle != null) {
        await RunAnywhere.ttsDestroy(this.handle);
        this.handle = null;
      }
      this.handle = await RunAnywhere.ttsLoadModel(id);
      this.loadedModelId = id;
      models.markLoaded('tts', id);
    } catch (err) {
      this.error = err instanceof Error ? err.message : String(err);
    } finally {
      this.busy = false;
    }
  }

  async speak(text: string): Promise<void> {
    const t = text.trim();
    if (!t || this.handle == null || this.speaking) return;
    this.speaking = true;
    this.cancelled = false;
    this.error = null;
    try {
      const { RunAnywhere } = await import('@runanywhere/web');
      const options = TTSOptions.fromPartial({ speed: 1, pitch: 1, volume: 1, sampleRate: 0 });
      // Stream per-sentence: play each chunk as it is synthesized so audio
      // starts sooner and Stop can halt between chunks.
      let produced = false;
      const t0 = performance.now();
      let chunkIdx = 0;
      for await (const out of RunAnywhere.synthesizeStream(this.handle, t, options)) {
        if (this.cancelled) return;
        if (out?.audioData && out.audioData.byteLength > 0) {
          const samples = out.audioData.byteLength / (out.audioFormat === AudioFormat.AUDIO_FORMAT_PCM_S16LE ? 2 : 4);
          console.log(`[tts] chunk ${chunkIdx} synth+recv in ${(performance.now() - t0).toFixed(0)}ms (${samples} samples = ${(samples / (out.sampleRate || 22050)).toFixed(2)}s audio)`);
          chunkIdx += 1;
          produced = true;
          const p0 = performance.now();
          await this.play(out.audioData, out.sampleRate || 22050, out.audioFormat);
          console.log(`[tts] chunk played in ${(performance.now() - p0).toFixed(0)}ms`);
        }
        if (this.cancelled) return;
      }
      console.log(`[tts] total speak() wall-clock: ${(performance.now() - t0).toFixed(0)}ms`);
      if (!produced) throw new Error('No audio was produced');
    } catch (err) {
      if (!this.cancelled) this.error = err instanceof Error ? err.message : String(err);
    } finally {
      this.speaking = false;
    }
  }

  stop(): void {
    this.cancelled = true;
    this.stopSource();
    this.speaking = false;
  }

  private stopSource(): void {
    const src = this.source;
    this.source = null;
    if (src) {
      try {
        src.stop(); // fires onended, resolving any in-flight play()
      } catch {
        // already stopped
      }
    }
  }

  private decode(bytes: Uint8Array, format: AudioFormat): Float32Array {
    if (format === AudioFormat.AUDIO_FORMAT_PCM_S16LE) {
      const n = Math.floor(bytes.byteLength / 2);
      const out = new Float32Array(n);
      const view = new DataView(bytes.buffer, bytes.byteOffset, n * 2);
      for (let i = 0; i < n; i += 1) out[i] = view.getInt16(i * 2, true) / 0x8000;
      return out;
    }
    // AUDIO_FORMAT_PCM — native float32 little-endian samples.
    const n = Math.floor(bytes.byteLength / 4);
    const out = new Float32Array(n);
    const view = new DataView(bytes.buffer, bytes.byteOffset, n * 4);
    for (let i = 0; i < n; i += 1) out[i] = view.getFloat32(i * 4, true);
    return out;
  }

  private async play(bytes: Uint8Array, sampleRate: number, format: AudioFormat): Promise<void> {
    const samples = this.decode(bytes, format);
    if (samples.length === 0) return;
    if (!this.audioCtx) this.audioCtx = new AudioContext();
    if (this.audioCtx.state === 'suspended') await this.audioCtx.resume();

    const buffer = this.audioCtx.createBuffer(1, samples.length, sampleRate);
    buffer.getChannelData(0).set(samples);

    this.stopSource();
    const src = this.audioCtx.createBufferSource();
    src.buffer = buffer;
    src.connect(this.audioCtx.destination);
    this.source = src;
    await new Promise<void>((resolve) => {
      src.onended = () => resolve();
      src.start();
    });
    if (this.source === src) this.source = null;
  }
}

export const tts = new TtsStore();
