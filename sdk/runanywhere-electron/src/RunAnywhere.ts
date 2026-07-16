// RunAnywhere.ts — the public Electron SDK facade over the native addon.
//
// Mirrors the other RunAnywhere SDKs (one entry point per feature) but stays
// intentionally small for M2: model handles are returned as typed objects with
// methods; text generation streams as an AsyncIterable.
import * as os from 'os';
import * as path from 'path';

import { addon, toAsyncIterable } from './bridge';
import { resolveModel } from './download';
import type { DownloadProgress, ResolvedModel } from './download';

export interface InitOptions {
  /** Directory for the (encrypted, in a future release) secure store. */
  secureDir?: string;
  /** Base dir for model storage / RunAnywhere home. */
  baseDir?: string;
}

export interface LoadOptions {
  id?: string;
  name?: string;
}

export interface DownloadOptions {
  /** Base dir for downloads (default: ~/.runanywhere/models). */
  dir?: string;
  onProgress?: (p: DownloadProgress) => void;
}

/** A loaded LLM. */
export class LLMModel {
  constructor(private readonly handle: number) {}
  /** Stream the completion token-by-token. */
  generate(prompt: string): AsyncIterableIterator<string> {
    return toAsyncIterable((onToken) => addon.generate(this.handle, prompt, onToken));
  }
  /** Convenience: collect the full completion. */
  async generateText(prompt: string): Promise<string> {
    let out = '';
    for await (const t of this.generate(prompt)) out += t;
    return out;
  }
  unload(): void {
    addon.unloadModel(this.handle);
  }
}

/** A loaded vision-language model. */
export class VLMModel {
  constructor(private readonly handle: number) {}
  /** Stream a caption/answer over an image (JPEG/PNG path) + prompt. */
  caption(imagePath: string, prompt: string): AsyncIterableIterator<string> {
    return toAsyncIterable((onToken) =>
      addon.generateVlm(this.handle, imagePath, prompt, onToken)
    );
  }
  async captionText(imagePath: string, prompt: string): Promise<string> {
    let out = '';
    for await (const t of this.caption(imagePath, prompt)) out += t;
    return out;
  }
  unload(): void {
    addon.unloadVlmModel(this.handle);
  }
}

/** A loaded text embedder. */
export class Embedder {
  constructor(private readonly handle: number) {}
  /** Return the L2-normalized embedding of `text`. */
  embed(text: string): Float32Array {
    return addon.embed(this.handle, text);
  }
  unload(): void {
    addon.unloadEmbeddingModel(this.handle);
  }
}

/** A loaded speech-to-text model. */
export class STTModel {
  constructor(private readonly handle: number) {}
  /** Transcribe 16 kHz mono PCM16 audio bytes. */
  transcribe(pcm16: Uint8Array): string {
    return addon.transcribe(this.handle, pcm16);
  }
  unload(): void {
    addon.unloadSttModel(this.handle);
  }
}

/** A loaded text-to-speech voice. */
export class TTSVoice {
  constructor(private readonly handle: number) {}
  /** Synthesize `text` to float32 PCM at the voice's native sample rate. */
  synthesize(text: string): { sampleRate: number; samples: Float32Array } {
    return addon.synthesize(this.handle, text);
  }
  unload(): void {
    addon.unloadTtsVoice(this.handle);
  }
}

let initialized = false;

export const RunAnywhere = {
  /** The bundled commons/runtime version. */
  get version(): string {
    return addon.version;
  },

  /** Bring the runtime up (Win32 platform adapter + engine registration). Idempotent. */
  initialize(opts: InitOptions = {}): void {
    if (initialized) return;
    const home = path.join(os.homedir(), '.runanywhere');
    const base = opts.baseDir ?? home;
    const secure = opts.secureDir ?? path.join(base, 'secure');
    addon.initialize(secure, base);
    initialized = true;
  },

  /** Download a catalog model (or resolve a local path) to concrete file paths. */
  downloadModel(idOrPath: string, opts: DownloadOptions = {}): Promise<ResolvedModel> {
    return resolveModel(idOrPath, opts);
  },

  // load* accept a catalog id (auto-downloaded if missing) OR a local path.
  async loadLLM(idOrPath: string, opts: LoadOptions & DownloadOptions = {}): Promise<LLMModel> {
    const m = await resolveModel(idOrPath, opts);
    return new LLMModel(addon.loadModel(m.primary, opts.id, opts.name));
  },
  async loadVLM(
    idOrPath: string,
    mmprojPath?: string,
    opts: LoadOptions & DownloadOptions = {}
  ): Promise<VLMModel> {
    const m = await resolveModel(idOrPath, opts);
    const mmproj = mmprojPath ?? m.mmproj;
    if (!mmproj) throw new Error('loadVLM needs an mmproj path (or a catalog id that includes one)');
    return new VLMModel(addon.loadVlmModel(m.primary, mmproj, opts.id, opts.name));
  },
  async loadEmbedder(idOrPath: string, opts: DownloadOptions = {}): Promise<Embedder> {
    const m = await resolveModel(idOrPath, opts);
    return new Embedder(addon.loadEmbeddingModel(m.primary));
  },
  async loadSTT(idOrPath: string, opts: LoadOptions & DownloadOptions = {}): Promise<STTModel> {
    const m = await resolveModel(idOrPath, opts);
    return new STTModel(addon.loadSttModel(m.primary, opts.id, opts.name));
  },
  async loadTTS(idOrPath: string, opts: LoadOptions & DownloadOptions = {}): Promise<TTSVoice> {
    const m = await resolveModel(idOrPath, opts);
    return new TTSVoice(addon.loadTtsVoice(m.primary, opts.id, opts.name));
  },

  /** Tear down the runtime. Idempotent. */
  shutdown(): void {
    if (!initialized) return;
    addon.shutdown();
    initialized = false;
  },
};
