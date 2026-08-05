// RunAnywhere.ts — the main-process entry point.
//
// The v3 surface is built by `createRunAnywhere` over a `NativeBackend`, so it is
// the same object shape the renderer gets from the preload. The pre-v3 members
// below stay for one release as deprecated forwarders that behave exactly as they
// did; new code should use the namespaces.
import * as os from 'os';
import * as path from 'path';

import { createRunAnywhere } from './api/facade';
import type { InitializeOptions, RunAnywhereApi, SecureStore } from './api/facade';
import { NativeBackend } from './api/native-backend';
import { addon, toAsyncIterable } from './bridge';
import { streamWithMetrics } from './stream';
import type { LLMStreamEvent, LLMGenerationResult } from './stream';
import { resolveModel, assertRemoteSupported } from './download';
import type { DownloadProgress, ResolvedModel } from './download';
import { VoiceAgent } from './VoiceAgent';
import type { VoiceAgentModels, VoiceAgentOptions } from './VoiceAgent';
import { Chat } from './Chat';
import type { ChatOptions } from './Chat';
import type { JsonSchema } from './grammar';
import {
  objectGrammar,
  toolCallSchema,
  toolCallPrompt,
  parseStructured,
} from './structured';
import type { ToolSpec, ToolCall as LegacyToolCall, ToolRun } from './structured';
import { SDKException } from './errors';
import { bus } from './events';
import type { EventBus } from './events';

import { toNativeGenerateOptions as toLegacyNativeOptions } from './legacy-options';
import type { GenerateOptions } from './legacy-options';

export type { GenerateOptions } from './legacy-options';

/** Options for schema-constrained structured generation. @deprecated Use {@link RunAnywhereApi.llm}.generateStructured. */
export interface GenerateObjectOptions extends GenerateOptions {
  schema: JsonSchema;
}

export type { ToolSpec, ToolRun } from './structured';
export type { LLMStreamEvent, LLMGenerationResult } from './stream';

/** @deprecated Use the `Environment` constants from the v3 types module. */
export type Environment = 'development' | 'staging' | 'production';

/** @deprecated Use {@link InitializeOptions}. */
export interface InitOptions {
  /** Directory for the encrypted secure store. */
  secureDir?: string;
  /** Base dir for model storage / RunAnywhere home. */
  baseDir?: string;
  /** Accepted and ignored — Electron has no control plane yet. */
  apiKey?: string;
  /** Accepted and ignored — Electron has no control plane yet. */
  baseURL?: string;
  /** Deployment environment (default: production). */
  environment?: Environment;
}

/** @deprecated Use {@link LoadOptions} from the v3 options module. */
export interface LoadOptions {
  id?: string;
  name?: string;
}

/** @deprecated Use `models.download`. */
export interface DownloadOptions {
  /** Base dir for downloads (default: ~/.runanywhere/models). */
  dir?: string;
  onProgress?: (p: DownloadProgress) => void;
}

/** A loaded LLM. @deprecated Use `RunAnywhere.llm`. */
export class LLMModel {
  constructor(private readonly handle: number) {}
  /** Stream the completion token-by-token. */
  generate(prompt: string, options: GenerateOptions = {}): AsyncIterableIterator<string> {
    const native = toLegacyNativeOptions(options);
    return toAsyncIterable((onToken) => addon.generate(this.handle, prompt, native, onToken));
  }
  /** Stream generation as events carrying tokens then aggregated metrics. */
  generateStream(prompt: string, options: GenerateOptions = {}): AsyncIterableIterator<LLMStreamEvent> {
    const source = streamWithMetrics(this.generate(prompt, options));
    return (async function* () {
      for await (const event of source) {
        if (event.isFinal && event.result) bus.emit({ type: 'generation', result: event.result });
        yield event;
      }
    })();
  }
  /** Collect the full completion. */
  async generateText(prompt: string, options: GenerateOptions = {}): Promise<string> {
    let out = '';
    for await (const t of this.generate(prompt, options)) out += t;
    return out;
  }
  /** Constrain decoding to JSON matching `schema` and return the parsed object. */
  async generateStructured<T = unknown>(prompt: string, options: GenerateObjectOptions): Promise<T> {
    const { schema, ...rest } = options;
    const grammar = objectGrammar(schema);
    let out = '';
    for await (const t of this.generate(prompt, { ...rest, grammar })) out += t;
    return parseStructured<T>(out, 'generateStructured');
  }
  /** @deprecated Use {@link generateStructured}. */
  generateObject<T = unknown>(prompt: string, options: GenerateObjectOptions): Promise<T> {
    return this.generateStructured<T>(prompt, options);
  }
  /** Force the model to emit one well-formed `{ name, arguments }` tool call. */
  async generateToolCall(
    prompt: string,
    tools: ToolSpec[],
    options: GenerateOptions = {}
  ): Promise<LegacyToolCall> {
    if (!tools.length) {
      throw SDKException.validationFailed({ fieldPath: 'tools', message: 'at least one tool is required' });
    }
    const grammar = objectGrammar(toolCallSchema(tools));
    let out = '';
    for await (const t of this.generate(toolCallPrompt(prompt, tools), { ...options, grammar })) {
      out += t;
    }
    return parseStructured<LegacyToolCall>(out, 'generateToolCall');
  }
  /** Pick a tool and run its `execute`, returning `{ name, arguments, result }`. */
  async generateWithTools(
    prompt: string,
    tools: ToolSpec[],
    options: GenerateOptions = {}
  ): Promise<ToolRun> {
    const call = await this.generateToolCall(prompt, tools, options);
    const tool = tools.find((t) => t.name === call.name);
    if (tool?.execute) {
      const result = await tool.execute(call.arguments);
      return { name: call.name, arguments: call.arguments, result };
    }
    return { name: call.name, arguments: call.arguments };
  }
  unload(): void {
    addon.unloadModel(this.handle);
    bus.emit({ type: 'modelUnloaded', modality: 'llm' });
  }
}

/** A loaded vision-language model. @deprecated Use `RunAnywhere.vlm`. */
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
    bus.emit({ type: 'modelUnloaded', modality: 'vlm' });
  }
}

/** A loaded text embedder. @deprecated Use `RunAnywhere.embeddings`. */
export class Embedder {
  constructor(private readonly handle: number) {}
  /** Return the L2-normalized embedding of `text`. */
  embed(text: string): Float32Array {
    return addon.embed(this.handle, text);
  }
  unload(): void {
    addon.unloadEmbeddingModel(this.handle);
    bus.emit({ type: 'modelUnloaded', modality: 'embedder' });
  }
}

/** A loaded speech-to-text model. @deprecated Use `RunAnywhere.stt`. */
export class STTModel {
  constructor(private readonly handle: number) {}
  /** Transcribe 16 kHz mono PCM16 audio bytes. */
  transcribe(pcm16: Uint8Array): string {
    return addon.transcribe(this.handle, pcm16).text;
  }
  unload(): void {
    addon.unloadSttModel(this.handle);
    bus.emit({ type: 'modelUnloaded', modality: 'stt' });
  }
}

/** A loaded text-to-speech voice. @deprecated Use `RunAnywhere.tts`. */
export class TTSVoice {
  constructor(private readonly handle: number) {}
  /** Synthesize `text` to float32 PCM at the voice's native sample rate. */
  synthesize(text: string): { sampleRate: number; samples: Float32Array } {
    const out = addon.synthesize(this.handle, text);
    return { sampleRate: out.sampleRate, samples: out.samples };
  }
  unload(): void {
    addon.unloadTtsVoice(this.handle);
    bus.emit({ type: 'modelUnloaded', modality: 'tts' });
  }
}

/** @deprecated Use the v3 `VadOptions`. */
export interface VadOptions {
  /** Energy activation threshold in [0,1] for the built-in energy VAD. */
  activationThreshold?: number;
}

/** Built-in energy VAD over 16 kHz mono float frames. @deprecated Use `RunAnywhere.vad`. */
export class Vad {
  constructor(private readonly handle: number) {}
  /** True if this frame of float samples contains speech. */
  detect(samples: Float32Array): boolean {
    return addon.vadProcess(this.handle, samples);
  }
  /** True if speech is currently active (debounced across frames). */
  isSpeechActive(): boolean {
    return addon.vadIsActive(this.handle);
  }
  /** Adjust the energy activation threshold. */
  setActivationThreshold(activationThreshold: number): void {
    addon.vadSetThreshold(this.handle, activationThreshold);
  }
  /** Reset detector state (e.g. between utterances). */
  reset(): void {
    addon.vadReset(this.handle);
  }
  /** Release the detector. */
  close(): void {
    addon.unloadVad(this.handle);
  }
}

const backend = new NativeBackend(addon);
const v3 = createRunAnywhere(backend);

/** The deprecated pre-v3 members, kept for one release. */
interface LegacySurface {
  readonly legacyEvents: EventBus;
  readonly isInitialized: boolean;
  readonly areServicesReady: boolean;
  completeServicesInitialization(): Promise<void>;
  downloadModel(idOrPath: string, opts?: DownloadOptions): Promise<ResolvedModel>;
  loadLLM(idOrPath: string, opts?: LoadOptions & DownloadOptions): Promise<LLMModel>;
  loadVLM(
    idOrPath: string,
    mmprojPath?: string,
    opts?: LoadOptions & DownloadOptions
  ): Promise<VLMModel>;
  loadEmbedder(idOrPath: string, opts?: DownloadOptions): Promise<Embedder>;
  loadSTT(idOrPath: string, opts?: LoadOptions & DownloadOptions): Promise<STTModel>;
  loadTTS(idOrPath: string, opts?: LoadOptions & DownloadOptions): Promise<TTSVoice>;
  createChat(llm: LLMModel, opts?: ChatOptions): Chat;
  createVoiceAgent(models: VoiceAgentModels, opts?: VoiceAgentOptions): VoiceAgent;
  createVad(opts?: VadOptions): Vad;
  secureSet(key: string, value: string): void;
  secureGet(key: string): string | null;
  secureDelete(key: string): void;
  shutdown(): void;
}

/** The RunAnywhere SDK, in the main (or any Node) process. */
export const RunAnywhere: RunAnywhereApi & LegacySurface = {
  // ---- v3 core ----
  /**
   * Bring the SDK up: platform adapter, native load, engine registration, and the
   * model store. One call — there is no second phase.
   *
   * @throws SDKException when the native runtime cannot start.
   */
  initialize(options: InitializeOptions & InitOptions = {}): Promise<void> {
    if (options.apiKey || options.baseURL || options.baseUrl) {
      // Never imply a control plane that is not wired: Electron does no auth,
      // device registration, or telemetry. They are accepted for signature
      // parity and dropped.
      console.warn(
        'RunAnywhere.initialize: apiKey/baseURL are accepted for signature ' +
          'parity but Electron has no control plane, so no auth, device ' +
          'registration, or telemetry is performed'
      );
    }
    const home = path.join(os.homedir(), '.runanywhere');
    const base = options.baseDir ?? home;
    return v3.initialize({
      ...options,
      baseDir: base,
      secureDir: options.secureDir ?? path.join(base, 'secure'),
      baseUrl: options.baseUrl ?? options.baseURL,
    });
  },
  reset: () => v3.reset(),
  get isReady(): boolean {
    return v3.isReady;
  },
  get version(): string {
    return addon.version;
  },
  get deviceId(): string {
    return v3.deviceId;
  },
  get environment() {
    return v3.environment;
  },
  capabilities: () => v3.capabilities(),
  get events() {
    return v3.events;
  },

  // ---- v3 namespaces ----
  llm: v3.llm,
  vlm: v3.vlm,
  stt: v3.stt,
  tts: v3.tts,
  vad: v3.vad,
  embeddings: v3.embeddings,
  rerank: v3.rerank,
  images: v3.images,
  diarization: v3.diarization,
  segmentation: v3.segmentation,
  voice: v3.voice,
  rag: v3.rag,
  models: v3.models,
  lora: v3.lora,
  secure: v3.secure as SecureStore,
  audio: v3.audio,
  image: v3.image,
  ragDocument: v3.ragDocument,

  // ---- deprecated ----
  /** @deprecated Use {@link RunAnywhereApi.events}. */
  get legacyEvents(): EventBus {
    return bus;
  },
  /** @deprecated Use {@link RunAnywhereApi.isReady}. */
  get isInitialized(): boolean {
    return v3.isReady;
  },
  /** @deprecated Use {@link RunAnywhereApi.isReady}; initialize() has no second phase. */
  get areServicesReady(): boolean {
    return v3.isReady;
  },
  /** @deprecated initialize() does everything; this resolves immediately. */
  async completeServicesInitialization(): Promise<void> {},
  /** @deprecated Use `models.download`. */
  downloadModel(idOrPath: string, opts: DownloadOptions = {}): Promise<ResolvedModel> {
    return resolveModel(idOrPath, opts);
  },
  /** @deprecated Use `models.load` plus `llm.generate`. */
  async loadLLM(idOrPath: string, opts: LoadOptions & DownloadOptions = {}): Promise<LLMModel> {
    const m = await resolveModel(idOrPath, opts);
    const model = new LLMModel(addon.loadModel(m.primary, opts.id, opts.name));
    bus.emit({ type: 'modelLoaded', modality: 'llm', id: idOrPath });
    return model;
  },
  /** @deprecated Use `models.load` plus `vlm.generate`. */
  async loadVLM(
    idOrPath: string,
    mmprojPath?: string,
    opts: LoadOptions & DownloadOptions = {}
  ): Promise<VLMModel> {
    const m = await resolveModel(idOrPath, opts);
    const mmproj = mmprojPath ?? m.mmproj;
    if (!mmproj) {
      throw SDKException.validationFailed({
        fieldPath: 'mmproj',
        message: 'loadVLM needs an mmproj path (or a catalog id that includes one)',
      });
    }
    const model = new VLMModel(addon.loadVlmModel(m.primary, mmproj, opts.id, opts.name));
    bus.emit({ type: 'modelLoaded', modality: 'vlm', id: idOrPath });
    return model;
  },
  /** @deprecated Use `models.load` plus `embeddings.embed`. */
  async loadEmbedder(idOrPath: string, opts: DownloadOptions = {}): Promise<Embedder> {
    assertRemoteSupported(idOrPath, 'embedder');
    const m = await resolveModel(idOrPath, opts);
    const model = new Embedder(addon.loadEmbeddingModel(m.primary));
    bus.emit({ type: 'modelLoaded', modality: 'embedder', id: idOrPath });
    return model;
  },
  /** @deprecated Use `models.load` plus `stt.transcribe`. */
  async loadSTT(idOrPath: string, opts: LoadOptions & DownloadOptions = {}): Promise<STTModel> {
    assertRemoteSupported(idOrPath, 'stt');
    const m = await resolveModel(idOrPath, opts);
    const model = new STTModel(addon.loadSttModel(m.primary, opts.id, opts.name));
    bus.emit({ type: 'modelLoaded', modality: 'stt', id: idOrPath });
    return model;
  },
  /** @deprecated Use `models.load` plus `tts.synthesize`. */
  async loadTTS(idOrPath: string, opts: LoadOptions & DownloadOptions = {}): Promise<TTSVoice> {
    assertRemoteSupported(idOrPath, 'tts');
    const m = await resolveModel(idOrPath, opts);
    const voice = new TTSVoice(addon.loadTtsVoice(m.primary, opts.id, opts.name));
    bus.emit({ type: 'modelLoaded', modality: 'tts', id: idOrPath });
    return voice;
  },
  /** @deprecated Use `llm.generate(messages)`. */
  createChat(llm: LLMModel, opts?: ChatOptions): Chat {
    return new Chat(llm, opts);
  },
  /** @deprecated Use `voice.createSession`. */
  createVoiceAgent(models: VoiceAgentModels, opts?: VoiceAgentOptions): VoiceAgent {
    return new VoiceAgent(models, opts);
  },
  /** @deprecated Use `vad.detect` / `vad.detectStream`. */
  createVad(opts: VadOptions = {}): Vad {
    return new Vad(addon.createVad(opts.activationThreshold));
  },
  /** @deprecated Use `secure.set`. */
  secureSet(key: string, value: string): void {
    addon.secureSet(key, value);
  },
  /** @deprecated Use `secure.get`. */
  secureGet(key: string): string | null {
    return addon.secureGet(key);
  },
  /** @deprecated Use `secure.delete`. */
  secureDelete(key: string): void {
    addon.secureDelete(key);
  },
  /** @deprecated Use {@link RunAnywhereApi.reset}. */
  shutdown(): void {
    addon.shutdown();
    bus.emit({ type: 'shutdown' });
  },
};
