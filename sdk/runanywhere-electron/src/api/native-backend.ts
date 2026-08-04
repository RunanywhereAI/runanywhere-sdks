// native-backend.ts — the in-process {@link RaBackend}: it owns the addon's
// integer handles, one per model slot, plus the RAG session table.
//
// This is the only file that holds a native handle. The main-process facade uses
// it directly; the renderer reaches it through the utility host, so a handle never
// crosses a process boundary.

import * as fs from 'fs';
import * as os from 'os';
import * as path from 'path';

import type { NativeAddon } from '../bridge';
import { ErrorCode, SDKException } from '../errors';
import {
  assertRemoteSupported,
  modelStatus as diskModelStatus,
  modelsRoot,
  pathExists as diskPathExists,
  resolveModel,
} from '../download';
import type { DownloadProgress, ModelKind, ResolvedModel } from '../download';
import type {
  NativeDiarizationOptions,
  NativeEmbedOptions,
  NativeGenerateOptions,
  NativeSttOptions,
  NativeTtsOptions,
  NativeVadConfig,
} from './options';
import type {
  BackendLoadOptions,
  LoadSlot,
  LoadedModel,
  NativeAudio,
  NativeAudioChunk,
  NativeDiarization,
  NativeImagePayload,
  NativeLoraEntry,
  NativeRanked,
  NativeSegmentation,
  NativeSttInfo,
  NativeSttPartial,
  NativeTranscription,
  NativeTtsInfo,
  RaBackend,
  StorageReport,
  NativeStreamResult,
} from './backend';

/** rac_model_category_t ordinals, for registry registration. */
export const RAC_CATEGORY = {
  LANGUAGE: 0,
  SPEECH_RECOGNITION: 1,
  SPEECH_SYNTHESIS: 2,
  VISION: 3,
  IMAGE_GENERATION: 4,
  EMBEDDING: 7,
  VOICE_ACTIVITY_DETECTION: 8,
  SPEAKER_DIARIZATION: 9,
  SEMANTIC_SEGMENTATION: 10,
  UNKNOWN: 99,
} as const;

/** rac_inference_framework_t ordinals, for registry registration. */
export const RAC_FRAMEWORK = {
  ONNX: 0,
  LLAMACPP: 1,
  SHERPA: 12,
  UNKNOWN: 99,
} as const;

/** Public {@link InferenceFramework} name to its rac_inference_framework_t ordinal. */
const RAC_FRAMEWORK_OF: Record<string, number> = {
  LLAMA_CPP: RAC_FRAMEWORK.LLAMACPP,
  ONNX: RAC_FRAMEWORK.ONNX,
  SHERPA: RAC_FRAMEWORK.SHERPA,
};

// Which slots reject a URL / HuggingFace source (the remote resolver is
// GGUF-single-file only, while these need a directory or an ONNX+vocab pair).
const SLOT_KIND: Partial<Record<LoadSlot, ModelKind>> = {
  llm: 'llm',
  vlm: 'vlm',
  stt: 'stt',
  tts: 'tts',
  embedder: 'embedder',
};

interface Slot {
  handle: number;
  model: LoadedModel;
}

/**
 * Translate {@link BackendLoadOptions} into the addon's rac_llm_config_t fields.
 * `threads` and `useGpu` have no equivalent on the component API — the thread
 * count and GPU-layer knobs live on `rac_llm_llamacpp_config_t`, reachable only
 * through the llamacpp-direct service that bypasses the plugin registry — so
 * they are rejected rather than silently dropped.
 */
function llmLoadConfig(
  options: BackendLoadOptions
): { framework?: number; contextLength?: number } | undefined {
  if (options.threads !== undefined || options.useGpu !== undefined) {
    throw SDKException.notImplemented(
      'LoadOptions.threads / LoadOptions.useGpu on Electron (rac_llm_config_t exposes neither; ' +
        'they exist only on rac_llm_llamacpp_config_t, which is not routed through the plugin registry)'
    );
  }
  const framework = options.framework ? RAC_FRAMEWORK_OF[options.framework] : undefined;
  if (framework === undefined && options.contextLength === undefined) return undefined;
  return {
    ...(framework !== undefined ? { framework } : {}),
    ...(options.contextLength !== undefined ? { contextLength: options.contextLength } : {}),
  };
}

/** In-process backend over the N-API addon. */
export class NativeBackend implements RaBackend {
  private readonly slots = new Map<LoadSlot, Slot>();
  private vadHandle: number | null = null;
  private ragSessions = new Map<string, number>();
  private ragCounter = 0;

  constructor(private readonly addon: NativeAddon) {}

  // ---- lifecycle ----

  async version(): Promise<string> {
    return this.addon.version;
  }

  async initialize(opts: { secureDir?: string; baseDir?: string } = {}): Promise<void> {
    const base = opts.baseDir ?? path.join(os.homedir(), '.runanywhere');
    const secure = opts.secureDir ?? path.join(base, 'secure');
    this.addon.initialize(secure, base);
  }

  async shutdown(): Promise<void> {
    this.slots.clear();
    this.vadHandle = null;
    this.ragSessions.clear();
    this.addon.shutdown();
  }

  // ---- model store ----

  resolveModel(
    source: string,
    onProgress?: (p: DownloadProgress) => void
  ): Promise<ResolvedModel> {
    return resolveModel(source, { onProgress });
  }

  async modelStatus(): Promise<Record<string, { downloaded: boolean; sizeBytes: number }>> {
    return diskModelStatus();
  }

  async pathExists(p: string): Promise<boolean> {
    return diskPathExists(p);
  }

  async storage(): Promise<StorageReport> {
    const status = await this.modelStatus();
    let usedBytes = 0;
    for (const entry of Object.values(status)) usedBytes += entry.sizeBytes;
    let freeBytes = 0;
    try {
      // statfs is the only portable free-space probe in Node; a missing root
      // simply means nothing has been downloaded yet.
      const root = modelsRoot();
      const probe = fs.existsSync(root) ? root : path.dirname(root);
      const stats = fs.statfsSync(probe);
      freeBytes = Number(stats.bavail) * Number(stats.bsize);
    } catch {
      freeBytes = 0;
    }
    return { usedBytes, freeBytes };
  }

  async deleteModel(id: string): Promise<void> {
    const dir = path.join(modelsRoot(), id);
    if (!dir.startsWith(modelsRoot())) {
      throw SDKException.validationFailed({
        fieldPath: 'id',
        message: `refusing to delete outside the model store: ${id}`,
      });
    }
    await fs.promises.rm(dir, { recursive: true, force: true });
  }

  async registerModel(
    id: string,
    localPath: string,
    category: number,
    framework: number
  ): Promise<void> {
    this.addon.registerModel(id, localPath, category, framework);
  }

  async ensure(
    slot: LoadSlot,
    source: string,
    options: BackendLoadOptions = {}
  ): Promise<LoadedModel> {
    const current = this.slots.get(slot);
    if (current && current.model.id === source) return current.model;
    const kind = SLOT_KIND[slot];
    if (kind) assertRemoteSupported(source, kind);
    const resolved = await resolveModel(source);
    // Every slot holds one artifact: release the previous occupant before the new
    // load so two multi-GB models are never resident at once.
    if (current) await this.unload(slot);
    const handle = this.load(slot, source, resolved, options);
    const model: LoadedModel = { id: source, path: resolved.primary };
    this.slots.set(slot, { handle, model });
    return model;
  }

  async loaded(slot: LoadSlot): Promise<LoadedModel | null> {
    return this.slots.get(slot)?.model ?? null;
  }

  async unload(slot?: LoadSlot): Promise<void> {
    const targets: LoadSlot[] = slot ? [slot] : [...this.slots.keys()];
    for (const s of targets) {
      const entry = this.slots.get(s);
      if (!entry) continue;
      this.slots.delete(s);
      this.unloadHandle(s, entry.handle);
    }
  }

  // ---- llm ----

  llmGenerate(
    prompt: string,
    options: NativeGenerateOptions,
    onToken: (token: string) => void
  ): Promise<NativeStreamResult> {
    return this.addon.generate(
      this.handleFor('llm'),
      prompt,
      options,
      onToken
    ) as Promise<NativeStreamResult>;
  }

  async llmCancel(): Promise<void> {
    const entry = this.slots.get('llm');
    if (entry) this.addon.cancelGenerate(entry.handle);
  }

  async loraApply(adapterPath: string, scale: number): Promise<void> {
    this.addon.loraApply(this.handleFor('llm'), adapterPath, scale);
  }

  async loraRemove(adapterPath?: string): Promise<void> {
    this.addon.loraRemove(this.handleFor('llm'), adapterPath);
  }

  async loraList(): Promise<NativeLoraEntry[]> {
    const entry = this.slots.get('llm');
    return entry ? this.addon.loraList(entry.handle) : [];
  }

  // ---- vlm ----

  vlmGenerate(
    image: NativeImagePayload,
    prompt: string,
    options: NativeGenerateOptions,
    onToken: (token: string) => void
  ): Promise<NativeStreamResult> {
    return this.addon.generateVlm(
      this.handleFor('vlm'),
      image,
      prompt,
      options,
      onToken
    ) as Promise<NativeStreamResult>;
  }

  async vlmCancel(): Promise<void> {
    const entry = this.slots.get('vlm');
    if (entry) this.addon.cancelVlm(entry.handle);
  }

  // ---- stt ----

  async sttTranscribe(
    pcm16: Uint8Array,
    options: NativeSttOptions
  ): Promise<NativeTranscription> {
    return this.addon.transcribe(this.handleFor('stt'), pcm16, options);
  }

  sttTranscribeStream(
    pcm16: Uint8Array,
    options: NativeSttOptions,
    onPartial: (p: NativeSttPartial) => void
  ): Promise<void> {
    return this.addon.transcribeStream(this.handleFor('stt'), pcm16, options, onPartial);
  }

  async sttInfo(): Promise<NativeSttInfo> {
    const entry = this.slots.get('stt');
    if (!entry) return { isReady: false, supportsStreaming: false };
    return this.addon.sttInfo(entry.handle);
  }

  // ---- tts ----

  async ttsSynthesize(text: string, options: NativeTtsOptions): Promise<NativeAudio> {
    return this.addon.synthesize(this.handleFor('tts'), text, options);
  }

  ttsSynthesizeStream(
    text: string,
    options: NativeTtsOptions,
    onChunk: (c: NativeAudioChunk) => void
  ): Promise<void> {
    return this.addon.synthesizeStream(this.handleFor('tts'), text, options, onChunk);
  }

  async ttsStop(): Promise<void> {
    const entry = this.slots.get('tts');
    if (entry) this.addon.ttsStop(entry.handle);
  }

  async ttsInfo(): Promise<NativeTtsInfo> {
    const entry = this.slots.get('tts');
    return entry ? this.addon.ttsInfo(entry.handle) : {};
  }

  // ---- vad ----

  async vadOpen(config: NativeVadConfig): Promise<void> {
    if (this.vadHandle != null) this.addon.unloadVad(this.vadHandle);
    this.vadHandle = this.addon.createVad(config);
  }

  async vadProcess(samples: Float32Array): Promise<boolean> {
    if (this.vadHandle == null) throw SDKException.invalidState('no VAD is open');
    return this.addon.vadProcess(this.vadHandle, samples);
  }

  async vadReset(): Promise<void> {
    if (this.vadHandle != null) this.addon.vadReset(this.vadHandle);
  }

  async vadClose(): Promise<void> {
    if (this.vadHandle == null) return;
    this.addon.unloadVad(this.vadHandle);
    this.vadHandle = null;
  }

  // ---- embeddings and rerank ----

  async embed(texts: string[], options: NativeEmbedOptions): Promise<Float32Array[]> {
    if (!texts.length) return [];
    return this.addon.embedBatch(this.handleFor('embedder'), texts, options);
  }

  async rerank(query: string, documents: string[], topN?: number): Promise<NativeRanked[]> {
    return this.addon.rerank(this.handleFor('rerank'), query, documents, topN);
  }

  // ---- diarization and segmentation ----

  async diarize(
    samples: Float32Array,
    options: NativeDiarizationOptions
  ): Promise<NativeDiarization> {
    return this.addon.diarize(this.handleFor('diarization'), samples, options);
  }

  async segment(
    img: { data: Uint8Array; width: number; height: number; pixelFormat?: number },
    options: { includeDiagnosticImage?: boolean }
  ): Promise<NativeSegmentation> {
    return this.addon.segment(this.handleFor('segmentation'), img, options);
  }

  // ---- rag ----

  async ragOpen(configBytes: Uint8Array): Promise<string> {
    const handle = await this.addon.ragCreateSession(configBytes);
    this.ragCounter += 1;
    const id = `rag_${this.ragCounter}`;
    this.ragSessions.set(id, handle);
    return id;
  }

  ragIngest(session: string, documentBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.ragIngest(this.ragHandle(session), documentBytes);
  }

  ragQuery(session: string, queryBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.ragQuery(this.ragHandle(session), queryBytes);
  }

  ragSearch(session: string, requestBytes: Uint8Array): Promise<Uint8Array> {
    if (typeof this.addon.ragSearch !== 'function') {
      throw SDKException.of(
        ErrorCode.FEATURE_NOT_AVAILABLE,
        'rag.search is unavailable — rebuild the native addon against commons with rac_rag_search_proto'
      );
    }
    return this.addon.ragSearch(this.ragHandle(session), requestBytes);
  }

  ragQueryStream(
    session: string,
    queryBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void> {
    // Resolves `cancelled` upstream; the backend contract only needs completion.
    return this.addon
      .ragQueryStream(this.ragHandle(session), queryBytes, onEvent)
      .then(() => undefined);
  }

  async ragStats(session: string): Promise<Uint8Array> {
    return this.addon.ragStats(this.ragHandle(session));
  }

  async ragClear(session: string): Promise<Uint8Array> {
    return this.addon.ragClear(this.ragHandle(session));
  }

  async ragCancel(session: string): Promise<void> {
    this.addon.ragCancel(this.ragHandle(session));
  }

  async ragClose(session: string): Promise<void> {
    const handle = this.ragSessions.get(session);
    if (handle == null) return;
    this.ragSessions.delete(session);
    this.addon.ragDestroySession(handle);
  }

  // ---- secure store ----

  async secureSet(key: string, value: string): Promise<void> {
    this.addon.secureSet(key, value);
  }

  async secureGet(key: string): Promise<string | null> {
    return this.addon.secureGet(key);
  }

  async secureDelete(key: string): Promise<void> {
    this.addon.secureDelete(key);
  }

  // ---- internals ----

  private handleFor(slot: LoadSlot): number {
    const entry = this.slots.get(slot);
    if (!entry) {
      throw SDKException.invalidState(
        `no ${slot} model is loaded — pass options.model or call models.load() first`
      );
    }
    return entry.handle;
  }

  private ragHandle(session: string): number {
    const handle = this.ragSessions.get(session);
    if (handle == null) throw SDKException.invalidState(`RAG session ${session} is closed`);
    return handle;
  }

  private load(
    slot: LoadSlot,
    source: string,
    resolved: ResolvedModel,
    options: BackendLoadOptions
  ): number {
    switch (slot) {
      case 'llm':
        return this.addon.loadModel(
          resolved.primary,
          source,
          undefined,
          llmLoadConfig(options)
        );
      case 'vlm': {
        if (!resolved.mmproj) {
          throw SDKException.validationFailed({
            fieldPath: 'model',
            message:
              'vision models need an mmproj — load a VLM by catalog id or HuggingFace repo ' +
              '(auto-resolved); a bare model URL has none',
          });
        }
        return this.addon.loadVlmModel(resolved.primary, resolved.mmproj, source);
      }
      case 'stt':
        return this.addon.loadSttModel(resolved.primary, source);
      case 'tts':
        return this.addon.loadTtsVoice(resolved.primary, source);
      case 'embedder':
        return this.addon.loadEmbeddingModel(resolved.primary);
      case 'rerank':
        return this.addon.loadRerankModel(resolved.primary, source);
      case 'diarization':
        return this.addon.loadDiarizationModel(resolved.primary, source);
      case 'segmentation':
        return this.addon.loadSegmentationModel(resolved.primary, source);
    }
  }

  private unloadHandle(slot: LoadSlot, handle: number): void {
    switch (slot) {
      case 'llm':
        this.addon.unloadModel(handle);
        return;
      case 'vlm':
        this.addon.unloadVlmModel(handle);
        return;
      case 'stt':
        this.addon.unloadSttModel(handle);
        return;
      case 'tts':
        this.addon.unloadTtsVoice(handle);
        return;
      case 'embedder':
        this.addon.unloadEmbeddingModel(handle);
        return;
      case 'rerank':
        this.addon.unloadRerankModel(handle);
        return;
      case 'diarization':
        this.addon.unloadDiarizationModel(handle);
        return;
      case 'segmentation':
        this.addon.unloadSegmentationModel(handle);
        return;
    }
  }
}
