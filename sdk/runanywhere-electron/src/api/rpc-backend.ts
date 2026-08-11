// rpc-backend.ts — the {@link RaBackend} a renderer uses.
//
// Every operation is a forward over the MessagePort to the utility host, which
// runs the real `NativeBackend`. Because the shapes on both sides are identical,
// the namespaces built on top are the same code as in the main process.

import type { DownloadProgress, ResolvedModel } from '../download';
import type {
  NativeDiarizationOptions,
  NativeEmbedOptions,
  NativeGenerateOptions,
  NativeSttOptions,
  NativeTtsOptions,
  NativeVadConfig,
} from './options';
import { rpcMethodFor } from './backend';
import type {
  BackendLoadOptions,
  ControlPlaneRequest,
  LoadSlot,
  LoadedModel,
  NativeAudio,
  NativeAudioChunk,
  NativeDiarization,
  NativeImagePayload,
  NativeLogRecord,
  NativeLoraEntry,
  NativeRanked,
  NativeSegmentation,
  NativeSttInfo,
  NativeSttPartial,
  NativeStreamResult,
  NativeTranscription,
  NativeTtsInfo,
  RaBackend,
  AuthState,
  MemoryInfo,
  StorageReport,
  ToolRunLoopEvent,
} from './backend';

/** Sends one RPC and resolves its reply; `onChunk` receives streamed items. */
export type RpcSend = (
  method: string,
  args: unknown[],
  onChunk?: (chunk: unknown) => void
) => Promise<unknown>;

/** Renderer-side backend that forwards every operation to the utility host. */
export class RpcBackend implements RaBackend {
  constructor(private readonly send: RpcSend) {}

  private call<T>(op: string, args: unknown[], onChunk?: (chunk: unknown) => void): Promise<T> {
    return this.send(rpcMethodFor(op), args, onChunk) as Promise<T>;
  }

  // ---- lifecycle ----
  version(): Promise<string> {
    return this.call('version', []);
  }
  initialize(opts: { secureDir?: string; baseDir?: string }): Promise<void> {
    return this.call('initialize', [opts]);
  }
  shutdown(): Promise<void> {
    return this.call('shutdown', []);
  }
  memoryInfo(): Promise<MemoryInfo> {
    return this.call('memoryInfo', []);
  }
  listPlugins(): Promise<string[]> {
    return this.call('listPlugins', []);
  }
  isThinAddon(): Promise<boolean> {
    return this.call('isThinAddon', []);
  }

  // ---- desktop control plane (telemetry + auth) ----
  hasControlPlane(): Promise<boolean> {
    return this.call('hasControlPlane', []);
  }
  devicePersistentId(): Promise<string> {
    return this.call('devicePersistentId', []);
  }
  devStagingBaseUrl(): Promise<string> {
    return this.call('devStagingBaseUrl', []);
  }
  configureControlPlane(req: ControlPlaneRequest): Promise<Uint8Array> {
    return this.call('configureControlPlane', [req]);
  }
  retryControlPlane(): Promise<Uint8Array> {
    return this.call('retryControlPlane', []);
  }
  authState(): Promise<AuthState> {
    return this.call('authState', []);
  }
  clearAuth(): Promise<void> {
    return this.call('clearAuth', []);
  }
  telemetryFlush(): Promise<void> {
    return this.call('telemetryFlush', []);
  }

  // ---- hugging face auth ----
  hfTokenSet(token: string | null): Promise<void> {
    return this.call('hfTokenSet', [token]);
  }

  // ---- model store ----
  resolveModel(
    source: string,
    onProgress?: (p: DownloadProgress) => void
  ): Promise<ResolvedModel> {
    return this.call('resolveModel', [source], onProgress as (c: unknown) => void);
  }
  modelStatus(): Promise<Record<string, { downloaded: boolean; sizeBytes: number }>> {
    return this.call('modelStatus', []);
  }
  pathExists(path: string): Promise<boolean> {
    return this.call('pathExists', [path]);
  }
  storage(): Promise<StorageReport> {
    return this.call('storage', []);
  }
  deleteModel(id: string): Promise<void> {
    return this.call('deleteModel', [id]);
  }
  registerModel(
    id: string,
    localPath: string,
    category: number,
    framework: number
  ): Promise<void> {
    return this.call('registerModel', [id, localPath, category, framework]);
  }

  // ---- downloads and storage over the commons ABIs ----
  downloadPlan(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('downloadPlan', [requestBytes]);
  }
  downloadStart(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('downloadStart', [requestBytes]);
  }
  downloadCancel(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('downloadCancel', [requestBytes]);
  }
  downloadProgress(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('downloadProgress', [requestBytes]);
  }
  downloadCleanup(): Promise<number> {
    return this.call('downloadCleanup', []);
  }
  downloadWatch(onProgress: (progressBytes: Uint8Array) => void): Promise<void> {
    return this.call('downloadWatch', [], onProgress as (c: unknown) => void);
  }
  downloadUnwatch(): Promise<void> {
    return this.call('downloadUnwatch', []);
  }
  storageInfoProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('storageInfoProto', [requestBytes]);
  }
  storageAvailabilityProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('storageAvailabilityProto', [requestBytes]);
  }
  storageDeletePlanProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('storageDeletePlanProto', [requestBytes]);
  }
  storageDeleteProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('storageDeleteProto', [requestBytes]);
  }
  clearCache(): Promise<void> {
    return this.call('clearCache', []);
  }
  clearTemp(): Promise<void> {
    return this.call('clearTemp', []);
  }
  ensure(slot: LoadSlot, source: string, options?: BackendLoadOptions): Promise<LoadedModel> {
    return this.call('ensure', [slot, source, options]);
  }
  loaded(slot: LoadSlot): Promise<LoadedModel | null> {
    return this.call('loaded', [slot]);
  }
  unload(slot?: LoadSlot): Promise<void> {
    return this.call('unload', [slot]);
  }

  // ---- llm ----
  llmGenerate(
    prompt: string,
    options: NativeGenerateOptions,
    onToken: (token: string) => void
  ): Promise<NativeStreamResult> {
    return this.call('llmGenerate', [prompt, options], onToken as (c: unknown) => void);
  }
  llmCancel(): Promise<void> {
    return this.call('llmCancel', []);
  }

  // ---- lora over the lifecycle proto ABI ----

  loraApplyProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('loraApplyProto', [requestBytes]);
  }

  loraRemoveProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('loraRemoveProto', [requestBytes]);
  }

  loraListProto(stateBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('loraListProto', [stateBytes]);
  }

  loraStateProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('loraStateProto', [requestBytes]);
  }

  loraCompatibilityProto(configBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('loraCompatibilityProto', [configBytes]);
  }

  // ---- lora catalog ----

  loraRegisterProto(entryBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('loraRegisterProto', [entryBytes]);
  }

  loraCatalogListProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('loraCatalogListProto', [requestBytes]);
  }

  loraCatalogQueryProto(queryBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('loraCatalogQueryProto', [queryBytes]);
  }

  loraCatalogGetProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('loraCatalogGetProto', [requestBytes]);
  }

  loraApply(adapterPath: string, scale: number): Promise<void> {
    return this.call('loraApply', [adapterPath, scale]);
  }
  loraRemove(adapterPath?: string): Promise<void> {
    return this.call('loraRemove', [adapterPath]);
  }
  loraList(): Promise<NativeLoraEntry[]> {
    return this.call('loraList', []);
  }

  // ---- vlm ----
  vlmGenerateProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('vlmGenerateProto', [requestBytes]);
  }
  vlmStreamProto(
    requestBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void> {
    return this.call('vlmStreamProto', [requestBytes], (chunk) => onEvent(chunk as Uint8Array));
  }
  vlmCancelProto(): Promise<Uint8Array> {
    return this.call('vlmCancelProto', []);
  }


  // ---- stt / tts / vad over the lifecycle proto ABI ----
  sttTranscribeProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('sttTranscribeProto', [requestBytes]);
  }
  ttsSynthesizeProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('ttsSynthesizeProto', [requestBytes]);
  }
  vadProcessProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('vadProcessProto', [requestBytes]);
  }
  vadConfigureProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('vadConfigureProto', [requestBytes]);
  }
  sttTranscribeStreamProto(
    requestBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void> {
    return this.call('sttTranscribeStreamProto', [requestBytes], (chunk) => onEvent(chunk as Uint8Array));
  }
  ttsSynthesizeStreamProto(
    requestBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void> {
    return this.call('ttsSynthesizeStreamProto', [requestBytes], (chunk) => onEvent(chunk as Uint8Array));
  }
  sttStateProto(): Promise<Uint8Array> {
    return this.call('sttStateProto', []);
  }
  ttsStopProto(): Promise<Uint8Array> {
    return this.call('ttsStopProto', []);
  }
  ttsListVoicesProto(): Promise<Uint8Array> {
    return this.call('ttsListVoicesProto', []);
  }
  ttsStateProto(): Promise<Uint8Array> {
    return this.call('ttsStateProto', []);
  }
  vadStartProto(): Promise<Uint8Array> {
    return this.call('vadStartProto', []);
  }
  vadStopProto(): Promise<Uint8Array> {
    return this.call('vadStopProto', []);
  }
  vadResetProto(): Promise<Uint8Array> {
    return this.call('vadResetProto', []);
  }

  // ---- voice agent ----
  voiceOpen(configBytes: Uint8Array): Promise<string> {
    return this.call('voiceOpen', [configBytes]);
  }
  voiceInitialize(session: string, configBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('voiceInitialize', [session, configBytes]);
  }
  voiceStates(session: string): Promise<Uint8Array> {
    return this.call('voiceStates', [session]);
  }
  voiceFeed(session: string, frameBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('voiceFeed', [session, frameBytes]);
  }
  voiceTurn(session: string, pcm16: Uint8Array): Promise<Uint8Array> {
    return this.call('voiceTurn', [session, pcm16]);
  }
  voiceProcessTurn(
    session: string,
    requestBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void> {
    return this.call('voiceProcessTurn', [session, requestBytes], (chunk) =>
      onEvent(chunk as Uint8Array)
    );
  }
  voiceCancelTurn(session: string, requestBytes: Uint8Array): Promise<void> {
    return this.call('voiceCancelTurn', [session, requestBytes]);
  }
  voiceEvents(session: string, onEvent: (eventBytes: Uint8Array) => void): Promise<void> {
    return this.call('voiceEvents', [session], (chunk) => onEvent(chunk as Uint8Array));
  }
  voiceClose(session: string): Promise<void> {
    return this.call('voiceClose', [session]);
  }

  // ---- stt ----
  sttTranscribe(pcm16: Uint8Array, options: NativeSttOptions): Promise<NativeTranscription> {
    return this.call('sttTranscribe', [pcm16, options]);
  }
  sttTranscribeStream(
    pcm16: Uint8Array,
    options: NativeSttOptions,
    onPartial: (p: NativeSttPartial) => void
  ): Promise<void> {
    return this.call(
      'sttTranscribeStream',
      [pcm16, options],
      onPartial as (c: unknown) => void
    );
  }
  sttInfo(): Promise<NativeSttInfo> {
    return this.call('sttInfo', []);
  }

  // ---- tts ----
  ttsSynthesize(text: string, options: NativeTtsOptions): Promise<NativeAudio> {
    return this.call('ttsSynthesize', [text, options]);
  }
  ttsSynthesizeStream(
    text: string,
    options: NativeTtsOptions,
    onChunk: (c: NativeAudioChunk) => void
  ): Promise<void> {
    return this.call('ttsSynthesizeStream', [text, options], onChunk as (c: unknown) => void);
  }
  ttsStop(): Promise<void> {
    return this.call('ttsStop', []);
  }
  ttsInfo(): Promise<NativeTtsInfo> {
    return this.call('ttsInfo', []);
  }

  // ---- vad ----
  vadOpen(config: NativeVadConfig): Promise<void> {
    return this.call('vadOpen', [config]);
  }
  vadProcess(samples: Float32Array): Promise<boolean> {
    return this.call('vadProcess', [samples]);
  }
  vadReset(): Promise<void> {
    return this.call('vadReset', []);
  }
  vadClose(): Promise<void> {
    return this.call('vadClose', []);
  }

  // ---- embeddings / rerank / diarization / segmentation over the proto ABI ----
  embedBatchProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('embedBatchProto', [requestBytes]);
  }
  rerankProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('rerankProto', [requestBytes]);
  }
  diarizeProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('diarizeProto', [requestBytes]);
  }
  segmentProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('segmentProto', [requestBytes]);
  }

  // ---- embeddings and rerank ----
  embed(texts: string[], options: NativeEmbedOptions): Promise<Float32Array[]> {
    return this.call('embed', [texts, options]);
  }
  rerank(query: string, documents: string[], topN?: number): Promise<NativeRanked[]> {
    return this.call('rerank', [query, documents, topN]);
  }

  // ---- diarization and segmentation ----
  diarize(
    samples: Float32Array,
    options: NativeDiarizationOptions
  ): Promise<NativeDiarization> {
    return this.call('diarize', [samples, options]);
  }
  segment(
    image: { data: Uint8Array; width: number; height: number; pixelFormat?: number },
    options: { includeDiagnosticImage?: boolean }
  ): Promise<NativeSegmentation> {
    return this.call('segment', [image, options]);
  }

  // ---- model lifecycle and registry ----
  modelLoad(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('modelLoad', [requestBytes]);
  }
  modelResolvePaths(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('modelResolvePaths', [requestBytes]);
  }
  modelUnload(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('modelUnload', [requestBytes]);
  }
  modelCurrent(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('modelCurrent', [requestBytes]);
  }
  modelRegistryRegister(modelInfoBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('modelRegistryRegister', [modelInfoBytes]);
  }
  modelRegistryUpdate(modelInfoBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('modelRegistryUpdate', [modelInfoBytes]);
  }
  modelRegistryGet(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('modelRegistryGet', [requestBytes]);
  }
  modelRegistryList(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('modelRegistryList', [requestBytes]);
  }
  modelRegistryRemove(modelId: string): Promise<Uint8Array> {
    return this.call('modelRegistryRemove', [modelId]);
  }
  modelRegistryRefresh(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('modelRegistryRefresh', [requestBytes]);
  }
  modelRegistryDiscover(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('modelRegistryDiscover', [requestBytes]);
  }
  modelRegistryImport(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('modelRegistryImport', [requestBytes]);
  }
  modelCompatibility(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('modelCompatibility', [requestBytes]) as Promise<Uint8Array>;
  }
  modelComponentSnapshot(component: number): Promise<Uint8Array> {
    return this.call('modelComponentSnapshot', [component]);
  }

  modelRegisterFromUrl(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('modelRegisterFromUrl', [requestBytes]);
  }
  modelRegisterMultiFile(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('modelRegisterMultiFile', [requestBytes]);
  }

  // ---- llm over the proto ABI ----
  llmGenerateProto(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('llmGenerateProto', [requestBytes]);
  }
  llmGenerateStreamProto(
    requestBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void> {
    return this.call('llmGenerateStreamProto', [requestBytes], (chunk) =>
      onEvent(chunk as Uint8Array)
    );
  }
  llmCancelProto(): Promise<Uint8Array> {
    return this.call('llmCancelProto', []);
  }
  structuredGenerate(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('structuredGenerate', [requestBytes]);
  }
  structuredParse(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('structuredParse', [requestBytes]);
  }
  structuredValidate(requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('structuredValidate', [requestBytes]);
  }

  // ---- tool calling ----
  // The one duplex operation: the host posts each event and waits for what
  // this callback resolves to, because commons' loop is parked on it.
  toolRunLoop(
    requestBytes: Uint8Array,
    onEvent: (event: ToolRunLoopEvent) => Promise<Uint8Array | undefined>
  ): Promise<Uint8Array> {
    return this.call('toolRunLoop', [requestBytes], (event) =>
      onEvent(event as ToolRunLoopEvent)
    );
  }
  toolRunLoopCancel(handle: number): Promise<void> {
    return this.call('toolRunLoopCancel', [handle]);
  }

  // ---- rag ----
  ragOpen(configBytes: Uint8Array): Promise<string> {
    return this.call('ragOpen', [configBytes]);
  }
  ragIngest(session: string, documentBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('ragIngest', [session, documentBytes]);
  }
  ragQuery(session: string, queryBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('ragQuery', [session, queryBytes]);
  }
  ragSearch(session: string, requestBytes: Uint8Array): Promise<Uint8Array> {
    return this.call('ragSearch', [session, requestBytes]);
  }
  ragQueryStream(
    session: string,
    queryBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void> {
    return this.call('ragQueryStream', [session, queryBytes], onEvent as (c: unknown) => void);
  }
  ragStats(session: string): Promise<Uint8Array> {
    return this.call('ragStats', [session]);
  }
  ragClear(session: string): Promise<Uint8Array> {
    return this.call('ragClear', [session]);
  }
  ragCancel(session: string): Promise<void> {
    return this.call('ragCancel', [session]);
  }
  ragClose(session: string): Promise<void> {
    return this.call('ragClose', [session]);
  }

  // ---- secure store ----
  secureSet(key: string, value: string): Promise<void> {
    return this.call('secureSet', [key, value]);
  }
  secureGet(key: string): Promise<string | null> {
    return this.call('secureGet', [key]);
  }
  secureDelete(key: string): Promise<void> {
    return this.call('secureDelete', [key]);
  }

  // ---- logging ----
  loggingSetLevel(level: number): Promise<void> {
    return this.call('loggingSetLevel', [level]);
  }
  loggingLevel(): Promise<number> {
    return this.call('loggingLevel', []);
  }
  loggingSetLocalEnabled(enabled: boolean): Promise<void> {
    return this.call('loggingSetLocalEnabled', [enabled]);
  }
  loggingFlush(): Promise<void> {
    return this.call('loggingFlush', []);
  }
  loggingWatch(onRecord: (record: NativeLogRecord) => void): Promise<void> {
    return this.call('loggingWatch', [], onRecord as (c: unknown) => void);
  }
  loggingUnwatch(): Promise<void> {
    return this.call('loggingUnwatch', []);
  }
}
