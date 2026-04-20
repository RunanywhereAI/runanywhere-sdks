// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Canonical RunAnywhere top-level public API — these are the methods
// RunAnywhere.initialize / .chat / .generate / .generateStream /
// .transcribe / .synthesize / .loadModel / .registerTool / .generateWithTools
// / .generateStructured — all delegate to the new session-based classes.

import { ModelFormat, Environment, type AuthData } from './Types.js';
import { SDKState } from './SDKState.js';
import { LLMSession } from './LLMSession.js';
import { STTSession, TTSSession } from './PrimitiveSessions.js';
import { ChatSession, ChatMessage } from './ChatSession.js';
import {
  ToolCallingAgent, type ToolDefinition, type ToolExecutor,
} from './ToolCalling.js';
import { generateStructured as _generateStructured } from './StructuredOutput.js';
import { RunAnywhere } from './RunAnywhere.js';

export interface LLMGenerationOptions {
  maxTokens?: number;
  temperature?: number;
  topP?: number;
  stopSequences?: string[];
  streamingEnabled?: boolean;
  systemPrompt?: string;
}

export interface LLMGenerationResult {
  text: string;
  tokensUsed: number;
  modelUsed: string;
  latencyMs: number;
  tokensPerSecond: number;
}

export interface LLMStreamingResult {
  stream: AsyncIterable<string>;
}

export interface STTOptions { language?: string; enablePartials?: boolean }
export interface STTOutput  { text: string; isFinal: boolean; confidence: number }
export interface TTSOptions { voice?: string; speakingRate?: number }
export interface TTSResult  { pcm: Float32Array; sampleRateHz: number }

interface Registry {
  llm: LLMSession | null;
  chat: ChatSession | null;
  stt: STTSession | null;
  tts: TTSSession | null;
  modelId: string;
  modelPath: string;
  tools: ToolDefinition[];
  executors: Map<string, ToolExecutor>;
}

const registry: Registry = {
  llm: null, chat: null, stt: null, tts: null,
  modelId: '', modelPath: '',
  tools: [], executors: new Map(),
};

// --- Attach legacy surface to the RunAnywhere singleton --------------------

type RAType = typeof RunAnywhere;

interface LegacyExtensions {
  initialize(opts: {
    apiKey: string;
    baseURL?: string;
    environment?: Environment;
    deviceId?: string;
  }): void;
  readonly isSDKInitialized: boolean;
  readonly isActive: boolean;
  readonly version: string;
  readonly currentEnvironment: Environment | null;
  setAuth(data: AuthData): void;
  clearAuth(): void;
  readonly isAuthenticated: boolean;
  shutdown(): void;
  loadModel(modelId: string, modelPath: string, format?: ModelFormat): void;
  unloadModel(): void;
  getCurrentModelId(): string;
  chat(prompt: string, options?: LLMGenerationOptions): Promise<string>;
  generate(prompt: string, options?: LLMGenerationOptions): Promise<LLMGenerationResult>;
  generateStream(prompt: string, options?: LLMGenerationOptions): Promise<LLMStreamingResult>;
  loadSTT(modelId: string, modelPath: string, format?: ModelFormat): void;
  transcribe(audio: Float32Array, sampleRateHz?: number): Promise<string>;
  transcribeWithOptions(audio: Float32Array, options?: STTOptions, sampleRateHz?: number): Promise<STTOutput>;
  loadTTS(modelId: string, modelPath: string, format?: ModelFormat): void;
  synthesize(text: string, options?: TTSOptions): TTSResult;
  registerTool(definition: ToolDefinition, executor: ToolExecutor): void;
  generateWithTools(prompt: string, options?: LLMGenerationOptions): Promise<LLMGenerationResult>;
  generateStructured<T>(prompt: string, schemaHint: string,
                         options?: LLMGenerationOptions): Promise<T>;
}

const legacy: LegacyExtensions = {
  initialize({ apiKey, baseURL, environment, deviceId }) {
    SDKState.initialize({
      apiKey,
      baseUrl: baseURL,
      environment: environment ?? Environment.Production,
      deviceId,
    });
  },
  get isSDKInitialized() { return SDKState.isInitialized; },
  get isActive()          { return SDKState.isInitialized; },
  get version()           { return '2.0.0'; },
  get currentEnvironment() {
    return SDKState.isInitialized ? SDKState.environment : null;
  },
  setAuth(data)    { SDKState.setAuth(data); },
  clearAuth()      { SDKState.clearAuth(); },
  get isAuthenticated() { return SDKState.isAuthenticated; },
  shutdown()       { SDKState.reset(); },

  loadModel(modelId, modelPath, format = ModelFormat.GGUF) {
    registry.llm?.close();
    registry.chat?.close();
    registry.llm = new LLMSession(modelId, modelPath, format);
    registry.chat = null;
    registry.modelId = modelId;
    registry.modelPath = modelPath;
  },

  unloadModel() {
    registry.llm?.close(); registry.chat?.close();
    registry.llm = null; registry.chat = null;
    registry.modelId = ''; registry.modelPath = '';
  },

  getCurrentModelId(): string { return registry.modelId; },

  async chat(prompt, options = {}) {
    const chat = ensureChat(options.systemPrompt);
    return chat.generateText([ChatMessage.user(prompt)]);
  },

  async generate(prompt, _options = {}) {
    const llm = requireLLM();
    const start = Date.now();
    let text = '';
    let tokens = 0;
    for await (const t of llm.generate(prompt)) {
      if (t.kind === 1) text += t.text;  // LLMTokenKind.Answer
      tokens++;
    }
    const elapsed = Date.now() - start;
    const tps = elapsed > 0 ? tokens / (elapsed / 1000) : 0;
    return {
      text, tokensUsed: tokens, modelUsed: registry.modelId,
      latencyMs: elapsed, tokensPerSecond: tps,
    };
  },

  async generateStream(prompt, _options = {}) {
    const llm = requireLLM();
    async function* stream(): AsyncIterable<string> {
      for await (const t of llm.generate(prompt)) {
        if (t.kind === 1) yield t.text;
      }
    }
    return { stream: stream() };
  },

  loadSTT(modelId, modelPath, format = ModelFormat.WhisperKit) {
    registry.stt?.close();
    registry.stt = new STTSession(modelId, modelPath, format);
  },

  async transcribe(audio, sampleRateHz = 16000) {
    const stt = requireSTT();
    stt.feedAudio(audio, sampleRateHz);
    stt.flush();
    for await (const chunk of stt.transcripts()) {
      if (!chunk.isPartial) return chunk.text;
    }
    return '';
  },

  async transcribeWithOptions(audio, _options = {}, sampleRateHz = 16000) {
    const text = await this.transcribe(audio, sampleRateHz);
    return { text, isFinal: true, confidence: 1.0 };
  },

  loadTTS(modelId, modelPath, format = ModelFormat.ONNX) {
    registry.tts?.close();
    registry.tts = new TTSSession(modelId, modelPath, format);
  },

  synthesize(text, _options = {}) {
    const tts = requireTTS();
    return tts.synthesize(text);
  },

  registerTool(definition, executor) {
    registry.tools.push(definition);
    registry.executors.set(definition.name, executor);
  },

  async generateWithTools(prompt, options = {}) {
    if (!registry.modelId) {
      throw new Error('no model loaded — call RunAnywhere.loadModel(...) first');
    }
    const agent = new ToolCallingAgent(
      registry.modelId, registry.modelPath,
      registry.tools, options.systemPrompt ?? '');
    let remaining = 4;
    let reply = await agent.send(prompt);
    while (remaining > 0) {
      if (reply.kind === 'assistant') {
        return { text: reply.text, tokensUsed: 0,
                 modelUsed: registry.modelId,
                 latencyMs: 0, tokensPerSecond: 0 };
      }
      const results: { name: string; result: string }[] = [];
      for (const call of reply.calls) {
        const exec = registry.executors.get(call.name);
        const r = exec ? await exec(call.arguments) : 'error';
        results.push({ name: call.name, result: r });
      }
      reply = await agent.continueAfter(results);
      remaining--;
    }
    throw new Error('tool-calling agent loop exceeded');
  },

  async generateStructured<T>(prompt: string, schemaHint: string,
                                 _options: LLMGenerationOptions = {}): Promise<T> {
    const chat = ensureChat(_options.systemPrompt);
    return _generateStructured<T>(chat, prompt, schemaHint);
  },
};

function requireLLM(): LLMSession {
  if (!registry.llm) throw new Error('no LLM loaded — call RunAnywhere.loadModel first');
  return registry.llm;
}
function requireSTT(): STTSession {
  if (!registry.stt) throw new Error('no STT loaded — call RunAnywhere.loadSTT first');
  return registry.stt;
}
function requireTTS(): TTSSession {
  if (!registry.tts) throw new Error('no TTS loaded — call RunAnywhere.loadTTS first');
  return registry.tts;
}
function ensureChat(systemPrompt?: string): ChatSession {
  if (registry.chat) return registry.chat;
  if (!registry.modelId) throw new Error('no model loaded');
  const chat = new ChatSession(registry.modelId, registry.modelPath, systemPrompt);
  registry.chat = chat;
  return chat;
}

// Copy legacy properties onto RunAnywhere, preserving getters (so they're
// not evaluated eagerly at import time when no native bindings are set).
const descriptors = Object.getOwnPropertyDescriptors(legacy);
Object.defineProperties(RunAnywhere as unknown as object, descriptors);
