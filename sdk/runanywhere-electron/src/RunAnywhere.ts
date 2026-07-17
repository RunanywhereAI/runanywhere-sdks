// RunAnywhere.ts — the public Electron SDK facade over the native addon.
//
// Mirrors the other RunAnywhere SDKs (one entry point per feature) but stays
// intentionally small for M2: model handles are returned as typed objects with
// methods; text generation streams as an AsyncIterable.
import * as os from 'os';
import * as path from 'path';

import { addon, toAsyncIterable } from './bridge';
import { streamWithMetrics } from './stream';
import type { LLMStreamEvent, LLMGenerationResult } from './stream';
import { resolveModel } from './download';
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
import type { ToolSpec, ToolCall, ToolRun } from './structured';
import { SDKException } from './errors';

/** Per-request generation controls (all optional). */
export interface GenerateOptions {
  maxTokens?: number;
  temperature?: number;
  topP?: number;
  topK?: number;
  /** System instruction passed to the backend for this request. */
  systemPrompt?: string;
  /** Raw GBNF grammar to constrain decoding (advanced; see generateObject). */
  grammar?: string;
}

/** Options for schema-constrained structured generation. */
export interface GenerateObjectOptions extends GenerateOptions {
  schema: JsonSchema;
}

export type { ToolSpec, ToolCall, ToolRun } from './structured';
export type { LLMStreamEvent, LLMGenerationResult } from './stream';

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
  generate(prompt: string, options: GenerateOptions = {}): AsyncIterableIterator<string> {
    return toAsyncIterable((onToken) => addon.generate(this.handle, prompt, options, onToken));
  }
  /**
   * Stream generation as events with metrics (mirrors the other SDKs'
   * `generateStream`): each event carries a `token`; the final event carries the
   * aggregated `result` (text, token count, time-to-first-token, tokens/second).
   */
  generateStream(prompt: string, options: GenerateOptions = {}): AsyncIterableIterator<LLMStreamEvent> {
    return streamWithMetrics(this.generate(prompt, options));
  }
  /** Convenience: collect the full completion. */
  async generateText(prompt: string, options: GenerateOptions = {}): Promise<string> {
    let out = '';
    for await (const t of this.generate(prompt, options)) out += t;
    return out;
  }
  /**
   * Structured output: constrain decoding to JSON matching `schema` (via a GBNF
   * grammar) and return the parsed object. Output is guaranteed parseable.
   * (House-uniform name; `generateObject` is a deprecated alias.)
   */
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
  /**
   * Tool calling primitive: force the model to pick one of `tools` and emit a
   * well-formed call `{ name, arguments }` (grammar-constrained). The caller
   * decides *whether* a tool is needed, and executes the call.
   */
  async generateToolCall(
    prompt: string,
    tools: ToolSpec[],
    options: GenerateOptions = {}
  ): Promise<ToolCall> {
    if (!tools.length) {
      throw SDKException.validationFailed({ fieldPath: 'tools', message: 'at least one tool is required' });
    }
    const grammar = objectGrammar(toolCallSchema(tools));
    let out = '';
    for await (const t of this.generate(toolCallPrompt(prompt, tools), { ...options, grammar })) {
      out += t;
    }
    return parseStructured<ToolCall>(out, 'generateToolCall');
  }
  /**
   * Tool calling (house-uniform): pick a tool AND run its `execute` function,
   * returning `{ name, arguments, result }`. Tools without an `execute` behave
   * like {@link generateToolCall} (no result). Whether-to-call remains the
   * caller's decision.
   */
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
    if (!mmproj) {
      throw SDKException.validationFailed({
        fieldPath: 'mmproj',
        message: 'loadVLM needs an mmproj path (or a catalog id that includes one)',
      });
    }
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

  /** Start a multi-turn chat session over a loaded LLM (keeps history). */
  createChat(llm: LLMModel, opts?: ChatOptions): Chat {
    return new Chat(llm, opts);
  },

  /** Compose loaded STT + LLM + TTS models into a voice turn pipeline. */
  createVoiceAgent(models: VoiceAgentModels, opts?: VoiceAgentOptions): VoiceAgent {
    return new VoiceAgent(models, opts);
  },

  /**
   * Encrypted key-value store (DPAPI-backed on Windows) for secrets like API
   * keys. Requires initialize(). Values are encrypted at rest with the current
   * user's credentials.
   */
  secureSet(key: string, value: string): void {
    addon.secureSet(key, value);
  },
  /** Read a value from the secure store, or null if absent. */
  secureGet(key: string): string | null {
    return addon.secureGet(key);
  },
  /** Delete a value from the secure store (a missing key is a no-op). */
  secureDelete(key: string): void {
    addon.secureDelete(key);
  },

  /** Tear down the runtime. Idempotent. */
  shutdown(): void {
    if (!initialized) return;
    addon.shutdown();
    initialized = false;
  },
};
