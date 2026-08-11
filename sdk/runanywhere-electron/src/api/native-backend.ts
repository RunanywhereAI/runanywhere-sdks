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
  pathExists as diskPathExists,
  resolveModel,
} from '../download';
import type { DownloadProgress, ModelKind, ResolvedModel } from '../download';
import { StorageDeleteRequest, StorageInfoRequest } from '@runanywhere/proto-ts/storage_types';
import { StorageAbi } from './storage-abi';
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
  AuthState,
  MemoryInfo,
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
  ControlPlaneRequest,
  NativeTtsInfo,
  RaBackend,
  StorageReport,
  NativeStreamResult,
  ToolRunLoopEvent,
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

/**
 * rac_inference_framework_t ordinals, for registry registration.
 *
 * These are the C enum's values, NOT the proto's — `runanywhere.v1.InferenceFramework`
 * numbers the same engines differently (QHexRT is 13 here and 24 there), so the two
 * maps in this repo are deliberately not interchangeable.
 */
export const RAC_FRAMEWORK = {
  ONNX: 0,
  LLAMACPP: 1,
  SHERPA: 12,
  QHEXRT: 13,
  UNKNOWN: 99,
} as const;

/** Public {@link InferenceFramework} name to its rac_inference_framework_t ordinal. */
const RAC_FRAMEWORK_OF: Record<string, number> = {
  LLAMA_CPP: RAC_FRAMEWORK.LLAMACPP,
  ONNX: RAC_FRAMEWORK.ONNX,
  SHERPA: RAC_FRAMEWORK.SHERPA,
  QHEXRT: RAC_FRAMEWORK.QHEXRT,
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
  private voiceSessions = new Map<string, number>();
  private voiceCounter = 0;
  private readonly storageAbi = new StorageAbi(this);
  private downloadWatchDone: (() => void) | null = null;

  constructor(private readonly addon: NativeAddon) {}

  // ---- lifecycle ----

  async version(): Promise<string> {
    return this.addon.version;
  }

  async initialize(opts: { secureDir?: string; baseDir?: string } = {}): Promise<void> {
    const base = opts.baseDir ?? path.join(os.homedir(), '.runanywhere');
    const secure = opts.secureDir ?? path.join(base, 'secure');
    await this.addon.initialize(secure, base);
  }

  async shutdown(): Promise<void> {
    this.slots.clear();
    this.vadHandle = null;
    this.ragSessions.clear();
    // Voice agents are destroyed rather than dropped: the destroy is what
    // unregisters the event callback and releases the stream, so a session left
    // open here would leave its `voiceEvents` promise pending forever.
    for (const session of [...this.voiceSessions.keys()]) {
      await this.voiceClose(session).catch(() => undefined);
    }
    await this.addon.shutdown();
  }

  async memoryInfo(): Promise<MemoryInfo> {
    return this.addon.memoryInfo();
  }

  // ---- desktop control plane (telemetry + auth) ----

  async hasControlPlane(): Promise<boolean> {
    return this.addon.hasControlPlane === true;
  }

  async devicePersistentId(): Promise<string> {
    return this.addon.devicePersistentId ? this.addon.devicePersistentId() : '';
  }

  async devStagingBaseUrl(): Promise<string> {
    return this.addon.devStagingBaseUrl ? this.addon.devStagingBaseUrl() : '';
  }

  async configureControlPlane(req: ControlPlaneRequest): Promise<Uint8Array> {
    if (!this.addon.configureControlPlane) {
      throw new Error('control plane unavailable: addon built without RAC_DESKTOP_ADAPTER');
    }
    return this.addon.configureControlPlane(
      req.environment,
      req.apiKey,
      req.baseUrl,
      req.deviceId,
      req.platform,
      req.sdkVersion,
      req.sdkBinding,
      req.appIdentifier,
      req.appName,
      req.appVersion,
      req.phase1Bytes,
      req.phase2Bytes
    );
  }

  async retryControlPlane(): Promise<Uint8Array> {
    if (!this.addon.retryControlPlane) {
      throw new Error('control plane unavailable: addon built without RAC_DESKTOP_ADAPTER');
    }
    return this.addon.retryControlPlane();
  }

  async authState(): Promise<AuthState> {
    // A build with no control plane has no auth to report, and saying so beats
    // throwing at every caller that just wants to render a status.
    return (
      this.addon.authState?.() ?? {
        authenticated: false,
        needsRefresh: false,
        expiresAtUnixSec: 0,
        userId: '',
        organizationId: '',
        deviceRegistered: false,
      }
    );
  }

  async clearAuth(): Promise<void> {
    await this.addon.clearAuth?.();
  }

  async telemetryFlush(): Promise<void> {
    await this.addon.telemetryFlush?.();
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

  // Both of these are the commons storage analyzer now, not a filesystem walk:
  // `storage()` reads what rac_storage_analyzer_info_proto measured over the
  // registry's rows, and `deleteModel()` lets commons pick the paths, run the
  // adapter's delete callback, and clear the registry entry in one pass so the
  // registry and disk cannot disagree.
  async storage(): Promise<StorageReport> {
    const result = await this.storageAbi.info(
      StorageInfoRequest.fromPartial({
        includeDevice: true,
        includeApp: false,
        includeModels: true,
        includeCache: false,
      })
    );
    if (result.error) throw SDKException.fromProto(result.error);
    return {
      usedBytes: Number(result.info?.totalModelsBytes ?? 0),
      freeBytes: Number(result.info?.device?.freeBytes ?? 0),
    };
  }

  async deleteModel(id: string): Promise<void> {
    const result = await this.storageAbi.delete(
      StorageDeleteRequest.fromPartial({
        modelIds: [id],
        keepFilesOnDisk: false,
        clearRegistryPaths: true,
        unloadIfLoaded: true,
        dryRun: false,
        // The opt-in commons requires before it will call the adapter's
        // delete_path callback. Without it every model comes back skipped.
        allowPlatformDelete: true,
      })
    );
    if (result.error) throw SDKException.fromProto(result.error);
  }

  async registerModel(
    id: string,
    localPath: string,
    category: number,
    framework: number
  ): Promise<void> {
    this.addon.registerModel(id, localPath, category, framework);
  }

  // ---- downloads over the commons orchestrator ----

  downloadPlan(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.downloadPlanProto(requestBytes);
  }

  downloadStart(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.downloadStartProto(requestBytes);
  }

  downloadCancel(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.downloadCancelProto(requestBytes);
  }

  downloadProgress(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.downloadProgressProto(requestBytes);
  }

  downloadCleanup(): Promise<number> {
    return this.addon.downloadCleanupProto();
  }

  downloadProgressPercent(
    overallProgress: number,
    bytesDownloaded: number,
    totalBytes: number,
  ): number {
    return this.addon.downloadProgressPercent(overallProgress, bytesDownloaded, totalBytes);
  }

  // The commons progress callback is process-wide, so this promise stands in
  // for a stream that has no natural end: it settles when downloadUnwatch runs,
  // which is also what the RPC transport needs to close the channel.
  downloadWatch(onProgress: (progressBytes: Uint8Array) => void): Promise<void> {
    this.downloadWatchDone?.();
    this.addon.downloadSubscribeProgress(onProgress);
    return new Promise<void>((resolve) => {
      this.downloadWatchDone = resolve;
    });
  }

  async downloadUnwatch(): Promise<void> {
    this.addon.downloadUnsubscribeProgress();
    const done = this.downloadWatchDone;
    this.downloadWatchDone = null;
    done?.();
  }

  // ---- storage over the commons analyzer ----

  storageInfoProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.storageInfoProto(requestBytes);
  }

  storageAvailabilityProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.storageAvailabilityProto(requestBytes);
  }

  storageDeletePlanProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.storageDeletePlanProto(requestBytes);
  }

  storageDeleteProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.storageDeleteProto(requestBytes);
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
    const handle = await this.load(slot, source, resolved, options);
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
      await this.unloadHandle(s, entry.handle);
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


  // ---- lora over the lifecycle proto ABI ----

  loraApplyProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.loraApplyProto(requestBytes);
  }

  loraRemoveProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.loraRemoveProto(requestBytes);
  }

  loraStateProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.loraStateProto(requestBytes);
  }

  async loraApply(adapterPath: string, scale: number): Promise<void> {
    await this.addon.loraApply(this.handleFor('llm'), adapterPath, scale);
  }

  async loraRemove(adapterPath?: string): Promise<void> {
    await this.addon.loraRemove(this.handleFor('llm'), adapterPath);
  }

  async loraList(): Promise<NativeLoraEntry[]> {
    const entry = this.slots.get('llm');
    return entry ? this.addon.loraList(entry.handle) : [];
  }

  // ---- vlm over the proto ABI ----

  vlmGenerateProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.vlmGenerateProto(requestBytes);
  }

  vlmStreamProto(
    requestBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void> {
    return this.addon.vlmStreamProto(requestBytes, onEvent);
  }

  vlmCancelProto(): Promise<Uint8Array> {
    return this.addon.vlmCancelProto();
  }


  // ---- stt / tts / vad over the lifecycle proto ABI ----

  sttTranscribeProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.sttTranscribeProto(requestBytes);
  }

  ttsSynthesizeProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.ttsSynthesizeProto(requestBytes);
  }

  vadProcessProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.vadProcessProto(requestBytes);
  }

  vadConfigureProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.vadConfigureProto(requestBytes);
  }

  sttTranscribeStreamProto(
    requestBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void> {
    return this.addon.sttTranscribeStreamProto(requestBytes, onEvent);
  }

  ttsSynthesizeStreamProto(
    requestBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void> {
    return this.addon.ttsSynthesizeStreamProto(requestBytes, onEvent);
  }

  sttStateProto(): Promise<Uint8Array> {
    return this.addon.sttStateProto();
  }

  ttsStopProto(): Promise<Uint8Array> {
    return this.addon.ttsStopProto();
  }

  ttsListVoicesProto(): Promise<Uint8Array> {
    return this.addon.ttsListVoicesProto();
  }

  ttsStateProto(): Promise<Uint8Array> {
    return this.addon.ttsStateProto();
  }

  vadStartProto(): Promise<Uint8Array> {
    return this.addon.vadStartProto();
  }

  vadStopProto(): Promise<Uint8Array> {
    return this.addon.vadStopProto();
  }

  vadResetProto(): Promise<Uint8Array> {
    return this.addon.vadResetProto();
  }

  // ---- voice agent ----
  //
  // The second place in this file that owns a native handle, and the only one
  // besides RAG whose lifetime the caller controls. The handle never leaves:
  // the session id is what crosses a process boundary.

  async voiceOpen(configBytes: Uint8Array): Promise<string> {
    const handle = await this.addon.voiceCreateProto(configBytes);
    this.voiceCounter += 1;
    const id = `voice_${this.voiceCounter}`;
    this.voiceSessions.set(id, handle);
    return id;
  }

  voiceInitialize(session: string, configBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.voiceInitializeProto(this.voiceHandle(session), configBytes);
  }

  voiceStates(session: string): Promise<Uint8Array> {
    return this.addon.voiceStatesProto(this.voiceHandle(session));
  }

  voiceFeed(session: string, frameBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.voiceFeedAudioProto(this.voiceHandle(session), frameBytes);
  }

  voiceTurn(session: string, pcm16: Uint8Array): Promise<Uint8Array> {
    return this.addon.voiceProcessVoiceTurnProto(this.voiceHandle(session), pcm16);
  }

  voiceProcessTurn(
    session: string,
    requestBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void> {
    return this.addon.voiceProcessTurnProto(this.voiceHandle(session), requestBytes, onEvent);
  }

  voiceCancelTurn(session: string, requestBytes: Uint8Array): Promise<void> {
    return this.addon.voiceCancelTurnProto(this.voiceHandle(session), requestBytes);
  }

  voiceEvents(session: string, onEvent: (eventBytes: Uint8Array) => void): Promise<void> {
    return this.addon.voiceEventsProto(this.voiceHandle(session), onEvent);
  }

  async voiceClose(session: string): Promise<void> {
    const handle = this.voiceSessions.get(session);
    if (handle == null) return;
    this.voiceSessions.delete(session);
    await this.addon.voiceDestroyProto(handle);
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
    if (this.vadHandle != null) await this.addon.unloadVad(this.vadHandle);
    this.vadHandle = await this.addon.createVad(config);
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
    const handle = this.vadHandle;
    this.vadHandle = null;
    await this.addon.unloadVad(handle);
  }

  vadSetStreamCallback(onEvent: (eventBytes: Uint8Array) => void): void {
    if (this.vadHandle == null) throw SDKException.invalidState('no VAD is open');
    this.addon.vadSetStreamCallback(this.vadHandle, onEvent);
  }

  async vadUnsetStreamCallback(): Promise<void> {
    if (this.vadHandle == null) return;
    await this.addon.vadUnsetStreamCallback(this.vadHandle);
  }

  async vadStreamStart(optionsBytes: Uint8Array): Promise<number> {
    if (this.vadHandle == null) throw SDKException.invalidState('no VAD is open');
    return this.addon.vadStreamStart(this.vadHandle, optionsBytes);
  }

  vadStreamFeed(sessionId: number, audioBytes: Uint8Array): Promise<void> {
    return this.addon.vadStreamFeed(sessionId, audioBytes);
  }

  vadStreamStop(sessionId: number): Promise<void> {
    return this.addon.vadStreamStop(sessionId);
  }

  vadStreamCancel(sessionId: number): Promise<void> {
    return this.addon.vadStreamCancel(sessionId);
  }

  // ---- embeddings / rerank / diarization / segmentation over the proto ABI ----

  embedBatchProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.embedBatchProto(requestBytes);
  }

  // The only proto entry point in this group that still needs a handle: there
  // is no rac_rerank_*_lifecycle_proto, so the slot's handle is threaded in.
  rerankProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.rerankProto(this.handleFor('rerank'), requestBytes);
  }

  diarizeProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.diarizeProto(requestBytes);
  }

  segmentProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.segmentProto(requestBytes);
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

  // ---- model lifecycle and registry ----

  modelLoad(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.modelLoad(requestBytes);
  }

  modelResolvePaths(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.modelResolvePaths(requestBytes);
  }

  modelUnload(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.modelUnload(requestBytes);
  }

  modelCurrent(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.modelCurrent(requestBytes);
  }

  modelRegistryRegister(modelInfoBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.modelRegistryRegister(modelInfoBytes);
  }

  modelRegistryUpdate(modelInfoBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.modelRegistryUpdate(modelInfoBytes);
  }

  modelRegistryGet(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.modelRegistryGet(requestBytes);
  }

  modelRegistryList(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.modelRegistryList(requestBytes);
  }

  modelRegistryRemove(modelId: string): Promise<Uint8Array> {
    return this.addon.modelRegistryRemove(modelId);
  }

  modelRegistryRefresh(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.modelRegistryRefresh(requestBytes);
  }

  modelRegistryDiscover(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.modelRegistryDiscover(requestBytes);
  }

  modelCompatibility(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.modelCompatibility(requestBytes);
  }

  modelRegisterFromUrl(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.modelRegisterFromUrl(requestBytes);
  }

  modelRegisterMultiFile(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.modelRegisterMultiFile(requestBytes);
  }

  // ---- llm over the proto ABI ----

  llmGenerateProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.llmGenerateProto(requestBytes);
  }

  llmGenerateStreamProto(
    requestBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void> {
    return this.addon.llmGenerateStreamProto(requestBytes, onEvent);
  }

  llmCancelProto(): Promise<Uint8Array> {
    return this.addon.llmCancelProto();
  }

  structuredGenerate(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.structuredGenerate(requestBytes);
  }

  structuredParse(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.structuredParse(requestBytes);
  }

  structuredValidate(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.addon.structuredValidate(requestBytes);
  }

  // ---- tool calling ----

  toolRunLoop(
    requestBytes: Uint8Array,
    onEvent: (event: ToolRunLoopEvent) => Promise<Uint8Array | undefined>
  ): Promise<Uint8Array> {
    return this.addon.toolRunLoopProto(requestBytes, onEvent);
  }

  async toolRunLoopCancel(handle: number): Promise<void> {
    this.addon.toolRunLoopCancelProto(handle);
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
    await this.addon.secureSet(key, value);
  }

  async secureGet(key: string): Promise<string | null> {
    return this.addon.secureGet(key);
  }

  async secureDelete(key: string): Promise<void> {
    await this.addon.secureDelete(key);
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

  private voiceHandle(session: string): number {
    const handle = this.voiceSessions.get(session);
    if (handle == null) throw SDKException.invalidState(`voice session ${session} is closed`);
    return handle;
  }

  private load(
    slot: LoadSlot,
    source: string,
    resolved: ResolvedModel,
    options: BackendLoadOptions
  ): Promise<number> {
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

  private unloadHandle(slot: LoadSlot, handle: number): Promise<void> {
    switch (slot) {
      case 'llm':
        return this.addon.unloadModel(handle);
      case 'vlm':
        return this.addon.unloadVlmModel(handle);
      case 'stt':
        return this.addon.unloadSttModel(handle);
      case 'tts':
        return this.addon.unloadTtsVoice(handle);
      case 'embedder':
        return this.addon.unloadEmbeddingModel(handle);
      case 'rerank':
        return this.addon.unloadRerankModel(handle);
      case 'diarization':
        return this.addon.unloadDiarizationModel(handle);
      case 'segmentation':
        return this.addon.unloadSegmentationModel(handle);
    }
  }
}
