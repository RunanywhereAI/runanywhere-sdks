// The raw surface exported by runanywhere_native.node.
//
// Every method is proto-byte: it takes serialized runanywhere.v1 request protos
// and returns serialized response protos (or streams them through a sink). The
// addon owns the commons handles and the streaming leases; this interface is the
// exact C++/JS seam, and NativeBackend is the only thing that talks to it.
//
// Sync vs Promise mirrors the addon: cheap, non-blocking calls return a value;
// anything that runs on a worker thread (load, inference, download) returns a
// Promise. NativeBackend awaits uniformly, so either is fine to consume.

/** Encoded protobuf message. */
export type ProtoBytes = Uint8Array;

/** Receives one encoded event/chunk proto per stream item. */
export type ProtoSink = (eventBytes: ProtoBytes) => void;

export interface NativeAddon {
  readonly version: string;

  // lifecycle + control plane
  /** Core bring-up: fill the platform adapter, rac_init, register backends. */
  initialize(secureDir: string, baseDir: string): void;
  shutdown(): void;
  readonly hasControlPlane: boolean;
  devicePersistentId(): string;
  devStagingBaseUrl(): string;
  /** Present only on a desktop-control-plane build; runs the two-phase init off-thread. */
  configureControlPlane?(
    environment: number,
    apiKey: string,
    baseUrl: string,
    deviceId: string,
    platform: string,
    sdkVersion: string,
    sdkBinding: string,
    appIdentifier: string,
    appName: string,
    appVersion: string,
    phase1Bytes: ProtoBytes,
    phase2Bytes: ProtoBytes
  ): Promise<ProtoBytes>;

  // capabilities + registry
  frameworksForCapability(request: ProtoBytes): ProtoBytes;
  deviceType(): string;
  registerModel(request: ProtoBytes): ProtoBytes;
  registerModelFromUrl(request: ProtoBytes): ProtoBytes;
  registerMultiFile(request: ProtoBytes): ProtoBytes;
  modelRegistryList(request?: ProtoBytes): ProtoBytes;
  modelRegistryQuery(request: ProtoBytes): ProtoBytes;
  modelList(request: ProtoBytes): ProtoBytes;
  modelGet(request: ProtoBytes): ProtoBytes;
  deleteModel(modelId: string): void;
  loraApply(request: ProtoBytes): ProtoBytes;
  loraRemove(request: ProtoBytes): ProtoBytes;
  loraList(request: ProtoBytes): ProtoBytes;
  loraState(request: ProtoBytes): ProtoBytes;
  imageGenerate(request: ProtoBytes): Promise<ProtoBytes>;

  // model lifecycle
  loadModel(request: ProtoBytes): Promise<ProtoBytes>;
  resolveModelPaths(request: ProtoBytes): ProtoBytes;
  unloadModel(request: ProtoBytes): Promise<ProtoBytes>;
  currentModel(request: ProtoBytes): ProtoBytes;

  // download
  downloadPlan(request: ProtoBytes): ProtoBytes;
  downloadStart(request: ProtoBytes): Promise<ProtoBytes>;
  downloadCancel(request: ProtoBytes): ProtoBytes;
  downloadResume(request: ProtoBytes): ProtoBytes;
  downloadProgressPoll(request: ProtoBytes): ProtoBytes;

  // llm
  llmGenerate(request: ProtoBytes): Promise<ProtoBytes>;
  llmGenerateStream(request: ProtoBytes, onEvent: ProtoSink): Promise<void>;
  llmCancel(): void;
  structuredPreparePrompt(request: ProtoBytes): ProtoBytes;
  structuredParse(request: ProtoBytes): ProtoBytes;
  toolRunLoop(
    request: ProtoBytes,
    onExecute: (toolCall: ProtoBytes) => ProtoBytes | Promise<ProtoBytes>
  ): Promise<ProtoBytes>;
  toolCancel(): void;

  // vlm
  vlmGenerate(request: ProtoBytes): Promise<ProtoBytes>;
  vlmGenerateStream(request: ProtoBytes, onEvent: ProtoSink): Promise<void>;
  vlmCancel(): void;

  // stt
  sttTranscribe(request: ProtoBytes): Promise<ProtoBytes>;
  sttTranscribeStream(request: ProtoBytes, onEvent: ProtoSink): Promise<void>;
  sttStreamStart(request: ProtoBytes): number;
  sttStreamFeed(session: number, pcm: ProtoBytes): void;
  sttStreamStop(session: number): void;
  sttStreamCancel(session: number): void;
  sttStreamSubscribe(session: number, onEvent: ProtoSink): Promise<void>;
  sttState(): ProtoBytes;

  // tts
  ttsSynthesize(request: ProtoBytes): Promise<ProtoBytes>;
  ttsSynthesizeStream(request: ProtoBytes, onEvent: ProtoSink): Promise<void>;
  ttsStop(): ProtoBytes;
  ttsListVoices(): ProtoBytes;

  // vad
  vadConfigure(request: ProtoBytes): ProtoBytes;
  vadProcess(request: ProtoBytes): ProtoBytes;
  vadStart(): ProtoBytes;
  vadStop(): ProtoBytes;
  vadReset(): ProtoBytes;

  // embeddings + rerank
  embed(request: ProtoBytes): Promise<ProtoBytes>;
  rerank(request: ProtoBytes): Promise<ProtoBytes>;

  // diarization + segmentation
  diarize(request: ProtoBytes): Promise<ProtoBytes>;
  segment(request: ProtoBytes): Promise<ProtoBytes>;

  // rag (native handles are integers)
  ragCreateSession(config: ProtoBytes): Promise<number>;
  ragIngest(handle: number, document: ProtoBytes): Promise<ProtoBytes>;
  ragQuery(handle: number, query: ProtoBytes): Promise<ProtoBytes>;
  ragQueryStream(handle: number, query: ProtoBytes, onEvent: ProtoSink): Promise<void>;
  ragSearch(handle: number, request: ProtoBytes): Promise<ProtoBytes>;
  ragStats(handle: number): ProtoBytes;
  ragClear(handle: number): ProtoBytes;
  ragCancel(handle: number): void;
  ragDestroySession(handle: number): void;

  // secure store
  secureSet(key: string, value: string): void;
  secureGet(key: string): string | null;
  secureDelete(key: string): void;
}
