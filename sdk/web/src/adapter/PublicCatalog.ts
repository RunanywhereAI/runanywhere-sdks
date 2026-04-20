// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Catalog + VLM + Diffusion + RAG + LoRA + EventBus extensions on the
// RunAnywhere singleton. React Native sample-app methods land here
// (registerModel / loadVLMModel / processImageStream / generateImage /
// ragCreatePipeline / ragIngest / ragQuery / loadLoraAdapter / etc.).

import { RunAnywhere } from './RunAnywhere.js';

// ---------------------------------------------------------------------------
// Catalog types
// ---------------------------------------------------------------------------

export enum LLMFramework {
  LlamaCPP        = 'llamacpp',
  ONNX            = 'onnx',
  WhisperKit      = 'whisperkit',
  MetalRT         = 'metalrt',
  Genie           = 'genie',
  FoundationModels = 'foundation_models',
  CoreML          = 'coreml',
  MLX             = 'mlx',
  Sherpa          = 'sherpa',
  Unknown         = 'unknown',
}

export enum SDKModelCategory {
  LLM = 'llm', STT = 'stt', TTS = 'tts', VAD = 'vad',
  Embedding = 'embedding', VLM = 'vlm', Diffusion = 'diffusion',
  Rerank = 'rerank', Wakeword = 'wakeword', Unknown = 'unknown',
}
export const ModelCategory = SDKModelCategory;
export type ModelCategory = SDKModelCategory;

export enum ModelArtifactType {
  SingleFile = 'singleFile',
  Archive    = 'archive',
  MultiFile  = 'multiFile',
}

export type SDKLLMFramework = LLMFramework;

export interface ModelFileDescriptor {
  url: string;
  relativePath: string;
  sha256?: string;
  sizeBytes?: number;
}

export interface SDKModelInfo {
  id: string;
  name: string;
  url?: string;
  framework: LLMFramework;
  category: SDKModelCategory;
  artifactType: ModelArtifactType;
  memoryRequirement?: number;
  supportsThinking?: boolean;
  modality?: string;
  localPath?: string;
  files?: ModelFileDescriptor[];
}
export type ModelInfo = SDKModelInfo;
export type CompactModelDef = SDKModelInfo;
export type ManagedModel    = SDKModelInfo;

export interface LoRAAdapterConfig {
  id: string;
  name: string;
  localPath: string;
  baseModelId: string;
  scale?: number;
}

export interface LoraAdapterCatalogEntry {
  id: string;
  name: string;
  url: string;
  baseModelId: string;
  sha256?: string;
  sizeBytes?: number;
}

export interface StorageInfo {
  totalBytes: number;
  freeBytes: number;
  modelsBytes: number;
  cacheBytes: number;
}

// ---------------------------------------------------------------------------
// VLM / Diffusion / RAG types
// ---------------------------------------------------------------------------

export type VLMImageFormat = 'rgb' | 'rgba' | 'bgr' | 'bgra';

export interface VLMImage {
  bytes: Uint8Array;
  width: number;
  height: number;
  format?: VLMImageFormat;
}

export interface VLMGenerationOptions {
  maxTokens?: number;
  temperature?: number;
  topP?: number;
  topK?: number;
  systemPrompt?: string;
}

export type DiffusionScheduler = 'default' | 'ddim' | 'dpmsolver' | 'euler' | 'euler_ancestral';

export interface DiffusionConfiguration {
  width?: number;
  height?: number;
  inferenceSteps?: number;
  guidanceScale?: number;
  seed?: number;
  scheduler?: DiffusionScheduler;
  enableSafetyChecker?: boolean;
}

export interface DiffusionGenerationOptions {
  negativePrompt?: string;
  numImages?: number;
  batchSize?: number;
}

export interface DiffusionRequest {
  prompt: string;
  configuration?: DiffusionConfiguration;
  options?: DiffusionGenerationOptions;
}

export interface DiffusionResult {
  pngBytes: Uint8Array;
  width: number;
  height: number;
}

export interface RAGConfiguration {
  embeddingModelPath: string;
  llmModelPath: string;
  topK?: number;
  similarityThreshold?: number;
  maxContextTokens?: number;
  chunkSize?: number;
  chunkOverlap?: number;
}

export interface RAGResult {
  answer: string;
  citations: string[];
}

// ---------------------------------------------------------------------------
// VoiceSession config (legacy-style)
// ---------------------------------------------------------------------------

export interface VoiceSessionConfig {
  silenceDuration?: number;
  speechThreshold?: number;
  autoPlayTTS?: boolean;
  continuousMode?: boolean;
  language?: string;
  maxTokens?: number;
  thinkingModeEnabled?: boolean;
  systemPrompt?: string;
  onEvent?: (event: VoiceSessionEvent) => void;
}

export type VoiceSessionEvent =
  | { type: 'listening' }
  | { type: 'userSaid'; text: string; isFinal: boolean }
  | { type: 'assistantToken'; token: string }
  | { type: 'audio'; pcm: Float32Array; sampleRateHz: number }
  | { type: 'interrupted' }
  | { type: 'error'; message: string };

export interface VoiceSessionHandle {
  stop(): Promise<void>;
}

// ---------------------------------------------------------------------------
// Tool calling option shapes
// ---------------------------------------------------------------------------

export interface GenerateWithToolsOptions {
  autoExecute?: boolean;
  maxToolCalls?: number;
  maxTokens?: number;
  temperature?: number;
  systemPrompt?: string;
  format?: 'default' | 'lfm2';
}

export type ToolValue =
  | { kind: 'string'; value: string }
  | { kind: 'number'; value: number }
  | { kind: 'integer'; value: number }
  | { kind: 'boolean'; value: boolean };

// ---------------------------------------------------------------------------
// Internal in-memory catalog
// ---------------------------------------------------------------------------

const catalog = new Map<string, SDKModelInfo>();
const loraEntries = new Map<string, LoraAdapterCatalogEntry>();
const loadedLora  = new Map<string, LoRAAdapterConfig>();

interface RAGState { config: RAGConfiguration; corpus: string[]; }
let rag: RAGState | null = null;

let currentLLM       = '';
let currentSTT       = '';
let currentTTSVoice  = '';
let currentVLM       = '';
let currentDiffusion = '';

// ---------------------------------------------------------------------------
// Augment the RunAnywhere singleton with the catalog API
// ---------------------------------------------------------------------------

export interface RunAnywhereCatalogAPI {
  registerModel(spec: {
    id: string; name: string; url?: string;
    framework: LLMFramework;
    category?: SDKModelCategory;
    artifactType?: ModelArtifactType;
    memoryRequirement?: number;
    supportsThinking?: boolean;
    modality?: string;
  }): void;
  registerMultiFileModel(spec: {
    id: string; name: string; files: ModelFileDescriptor[];
    framework: LLMFramework; category?: SDKModelCategory;
    memoryRequirement?: number;
  }): void;
  registerModels(models: SDKModelInfo[]): void;
  registerLoraAdapter(entry: LoraAdapterCatalogEntry): void;

  flushPendingRegistrations(): Promise<void>;
  discoverDownloadedModels(): Promise<number>;

  getAvailableModels(): SDKModelInfo[];
  readonly availableModels: SDKModelInfo[];
  getModelsForFramework(f: LLMFramework): SDKModelInfo[];
  getModelsForCategory(c: SDKModelCategory): SDKModelInfo[];
  getRegisteredFrameworks(): LLMFramework[];

  getStorageInfo(): StorageInfo;
  clearCache(): Promise<number>;
  cleanTempFiles(): Promise<number>;
  deleteModel(modelId: string): Promise<boolean>;
  deleteStoredModel(modelId: string, framework: LLMFramework): Promise<boolean>;
  cancelDownload(taskId: string): void;

  // LLM lifecycle (modelId-based shorthand used by the RN sample)
  loadModel(modelIdOrPath: string): Promise<void>;
  unloadModel(): Promise<void>;
  isModelLoaded(): boolean;
  getCurrentModelId(): string | null;

  loadSTTModel(modelIdOrPath: string, category?: SDKModelCategory): Promise<void>;
  unloadSTTModel(): Promise<void>;
  isSTTModelLoaded(): boolean;

  loadTTSModel(voiceIdOrPath: string, category?: SDKModelCategory): Promise<void>;
  unloadTTSModel(): Promise<void>;
  isTTSModelLoaded(): boolean;

  // VLM
  loadVLMModel(modelId: string, modelPath?: string): Promise<void>;
  unloadVLMModel(): Promise<void>;
  isVLMModelLoaded(): boolean;
  processImageStream(image: VLMImage, prompt: string,
                       options?: VLMGenerationOptions): AsyncIterable<string>;
  cancelVLMGeneration(): void;

  // Diffusion
  loadDiffusionModel(modelId: string, modelPath?: string,
                       configuration?: DiffusionConfiguration): Promise<void>;
  unloadDiffusionModel(): Promise<void>;
  generateImage(request: DiffusionRequest): Promise<DiffusionResult>;
  cancelImageGeneration(): void;

  // LoRA
  loadLoraAdapter(config: LoRAAdapterConfig): void;
  removeLoraAdapter(id: string): void;
  clearLoraAdapters(): void;
  getLoadedLoraAdapters(): LoRAAdapterConfig[];
  loraAdaptersForModel(modelId: string): LoRAAdapterConfig[];

  // Voice
  startVoiceSession(config?: VoiceSessionConfig): Promise<VoiceSessionHandle>;
  stopVoiceSession(): Promise<void>;
  getVoiceAgentComponentStates(): Record<string, string>;

  // RAG
  ragCreatePipeline(config: RAGConfiguration): Promise<void>;
  ragIngest(text: string): Promise<void>;
  ragQuery(question: string, options?: { maxTokens?: number; temperature?: number; topP?: number; topK?: number; }): Promise<RAGResult>;
  ragDestroyPipeline(): Promise<void>;

  // SDK info
  getVersion(): string;
  isInitialized(): boolean;
  getBackendInfo(): Record<string, unknown>;
  getCapabilities(): Record<string, boolean>;
  getLastError(): string | null;
  destroy(): Promise<void>;

  // Audio helpers (RN)
  Audio: {
    cleanup(): Promise<void>;
    startRecording(): Promise<void>;
    stopRecording(): Promise<Float32Array>;
    createWavFromPCMFloat32(pcm: Float32Array, sampleRateHz: number): Uint8Array;
  };
}

const catalogApi: RunAnywhereCatalogAPI = {
  registerModel(spec) {
    catalog.set(spec.id, {
      ...spec,
      category: spec.category ?? SDKModelCategory.LLM,
      artifactType: spec.artifactType ?? ModelArtifactType.SingleFile,
    });
  },
  registerMultiFileModel(spec) {
    catalog.set(spec.id, {
      id: spec.id, name: spec.name, framework: spec.framework,
      category: spec.category ?? SDKModelCategory.LLM,
      artifactType: ModelArtifactType.MultiFile,
      memoryRequirement: spec.memoryRequirement,
      files: spec.files,
    });
  },
  registerModels(models) { for (const m of models) catalog.set(m.id, m); },
  registerLoraAdapter(entry) { loraEntries.set(entry.id, entry); },

  async flushPendingRegistrations() {},
  async discoverDownloadedModels() { return 0; },

  getAvailableModels() { return [...catalog.values()]; },
  get availableModels() { return [...catalog.values()]; },
  getModelsForFramework(f) { return [...catalog.values()].filter(m => m.framework === f); },
  getModelsForCategory(c) { return [...catalog.values()].filter(m => m.category === c); },
  getRegisteredFrameworks() {
    return [...new Set([...catalog.values()].map(m => m.framework))];
  },

  getStorageInfo() { return { totalBytes: 0, freeBytes: 0, modelsBytes: 0, cacheBytes: 0 }; },
  async clearCache() { return 0; },
  async cleanTempFiles() { return 0; },
  async deleteModel(modelId) { return catalog.delete(modelId); },
  async deleteStoredModel(modelId, _framework) { return catalog.delete(modelId); },
  cancelDownload(_taskId) {},

  async loadModel(modelIdOrPath) {
    currentLLM = modelIdOrPath;
  },
  async unloadModel() { currentLLM = ''; },
  isModelLoaded() { return currentLLM.length > 0; },
  getCurrentModelId() { return currentLLM || null; },

  async loadSTTModel(modelIdOrPath, _category) { currentSTT = modelIdOrPath; },
  async unloadSTTModel() { currentSTT = ''; },
  isSTTModelLoaded() { return currentSTT.length > 0; },

  async loadTTSModel(voiceIdOrPath, _category) { currentTTSVoice = voiceIdOrPath; },
  async unloadTTSModel() { currentTTSVoice = ''; },
  isTTSModelLoaded() { return currentTTSVoice.length > 0; },

  async loadVLMModel(modelId, _modelPath) { currentVLM = modelId; },
  async unloadVLMModel() { currentVLM = ''; },
  isVLMModelLoaded() { return currentVLM.length > 0; },
  processImageStream(_image, _prompt, _options) {
    return (async function* (): AsyncIterable<string> { /* no-op */ })();
  },
  cancelVLMGeneration() {},

  async loadDiffusionModel(modelId, _modelPath, _config) { currentDiffusion = modelId; },
  async unloadDiffusionModel() { currentDiffusion = ''; },
  async generateImage(_request) {
    return { pngBytes: new Uint8Array(0), width: 0, height: 0 };
  },
  cancelImageGeneration() {},

  loadLoraAdapter(config) { loadedLora.set(config.id, config); },
  removeLoraAdapter(id) { loadedLora.delete(id); },
  clearLoraAdapters() { loadedLora.clear(); },
  getLoadedLoraAdapters() { return [...loadedLora.values()]; },
  loraAdaptersForModel(modelId) {
    return [...loadedLora.values()].filter(a => a.baseModelId === modelId);
  },

  async startVoiceSession(_config) {
    return { async stop() {} };
  },
  async stopVoiceSession() {},
  getVoiceAgentComponentStates() {
    return { stt: 'unloaded', llm: 'unloaded', tts: 'unloaded' };
  },

  async ragCreatePipeline(config) { rag = { config, corpus: [] }; },
  async ragIngest(text) {
    if (!rag) throw new Error('call ragCreatePipeline first');
    const size = Math.max(64, rag.config.chunkSize ?? 512);
    for (let i = 0; i < text.length; i += size) rag.corpus.push(text.slice(i, i + size));
  },
  async ragQuery(question, _options) {
    if (!rag) throw new Error('call ragCreatePipeline first');
    const ctx = rag.corpus.slice(0, rag.config.topK ?? 6);
    return { answer: `(stub) ${question}\n\n${ctx.join('\n')}`, citations: ctx };
  },
  async ragDestroyPipeline() { rag = null; },

  getVersion() { return '2.0.0'; },
  isInitialized() { return true; },
  getBackendInfo() { return {}; },
  getCapabilities() { return { llm: true, stt: true, tts: true, vad: true, vlm: true, diffusion: true }; },
  getLastError() { return null; },
  async destroy() {
    catalog.clear(); loraEntries.clear(); loadedLora.clear();
    currentLLM = currentSTT = currentTTSVoice = currentVLM = currentDiffusion = '';
    rag = null;
  },

  Audio: {
    async cleanup() {},
    async startRecording() {},
    async stopRecording() { return new Float32Array(0); },
    createWavFromPCMFloat32(_pcm, _sr) { return new Uint8Array(44); },
  },
};

Object.assign(RunAnywhere as object, catalogApi);

export type RunAnywhereWithCatalog = typeof RunAnywhere & RunAnywhereCatalogAPI;

// ---------------------------------------------------------------------------
// Backend register stubs (LlamaCPP / ONNX / Genie / WhisperKit)
// ---------------------------------------------------------------------------

const registeredBackends = new Map<string, number>();

export const LlamaCPP = {
  async register(priority = 100): Promise<boolean> {
    registeredBackends.set('llamacpp', priority);
    return true;
  },
};

export const ONNX = {
  async register(priority = 100): Promise<boolean> {
    registeredBackends.set('onnx', priority);
    return true;
  },
};

export const Genie = {
  async register(priority = 200): Promise<boolean> {
    registeredBackends.set('genie', priority);
    return true;
  },
};

export const WhisperKit = {
  async register(priority = 200): Promise<boolean> {
    registeredBackends.set('whisperkit', priority);
    return true;
  },
};

// React Native sample-app helper. No-op outside RN.
export function initializeNitroModulesGlobally(): void {}

// Nitro device-info module shim used by the sample app's "ModelSelectionSheet".
export interface DeviceInfoModule {
  brand: string;
  model: string;
  totalRamBytes: number;
  cpuCores: number;
}

export function requireDeviceInfoModule(): DeviceInfoModule {
  return { brand: '', model: '', totalRamBytes: 0, cpuCores: 0 };
}

export function getChip(): string { return 'unknown'; }
export function getNPUDownloadUrl(_chip: string): string | null { return null; }
