// bridge.ts — loads the native N-API addon and adapts its callback-based
// streaming into an AsyncIterable. The addon is resolved from (in order): the
// RUNANYWHERE_NATIVE_PATH env var, the local dev build output, or the packaged
// location. Sidecar DLLs (onnxruntime, sherpa, the QAIRT/QNN runtime) must sit
// next to the .node; on Windows that directory is put on PATH before the load.
import * as fs from 'fs';
import * as path from 'path';

import { asarUnpacked } from './backend/plugin-registry';
import { asSDKException } from './errors';

// Re-exported for existing importers (RunAnywhere.ts imports it from here); the
// implementation now lives in stream.ts so it stays addon-free and testable.
export { toAsyncIterable } from './stream';

/** Terminal payload every generation stream resolves with. */
export interface NativeGenerationMetrics {
  cancelled: boolean;
  hasMetrics: boolean;
  inputTokens: number;
  outputTokens: number;
  totalTokens: number;
  timeToFirstTokenMs: number;
  totalTimeMs: number;
  tokensPerSecond: number;
}

/** One backend commons refused to register, and the `rac_result_t` saying why. */
export interface UnavailablePlugin {
  /** Engine name ("sherpa"), or the library stem when the load failed before the vtable. */
  readonly name: string;
  /** Library path for a dynamic-load failure; empty for a statically linked backend. */
  readonly path: string;
  /** The raw negative `rac_result_t` — e.g. -811 RAC_ERROR_CAPABILITY_UNSUPPORTED. */
  readonly status: number;
}

/** Raw surface exported by runanywhere_native.node. */
export interface NativeAddon {
  readonly version: string;
  /**
   * True when this .node was built with RAC_ELECTRON_THIN_ADDON (no statically
   * linked backends). Engines then come from {@link loadPlugin} /
   * RUNANYWHERE_PLUGIN_PATHS — never from compile-time RAC_HAVE_BACKEND_* macros.
   */
  readonly thinAddon?: boolean;
  initialize(secureDir: string, baseDir?: string): Promise<void>;
  /**
   * Host / main only. Wraps `rac_registry_load_plugin`. Do NOT put this on the
   * RPC allowlist — plugin paths are injected via RUNANYWHERE_PLUGIN_PATHS by
   * main before the utility host fork.
   */
  loadPlugin(absolutePath: string): Promise<void>;
  /** Runtime registry snapshot — engine names currently registered. */
  listPlugins(): string[];
  /**
   * Backends that asked to register and were refused, from commons'
   * `rac_registry_list_unavailable_plugins`. The complement of
   * {@link listPlugins}: one tells you what is serving, this one tells you
   * what is missing and why, so a broken backend is a reported degradation
   * rather than a silently absent feature.
   *
   * Optional because an older prebuilt .node predates the export.
   */
  listUnavailablePlugins?(): UnavailablePlugin[];
  /** Commons `RAC_PLUGIN_API_VERSION` as a runtime number. */
  pluginApiVersion(): number;
  /** Free / total / used RAM from the platform adapter. Cheap enough to stay sync. */
  memoryInfo(): { totalBytes: number; availableBytes: number; usedBytes: number };
  // Desktop control plane (telemetry + auth). Present only when the addon is
  // built with the desktop libcurl transport (RAC_DESKTOP_ADAPTER=ON); guarded
  // by `hasControlPlane`. `configureControlPlane` runs the two-phase init off the
  // JS thread and resolves the serialized SdkInitResult bytes. `environment` is a
  // rac_environment_t (0=dev, 2=prod); phase bytes are SdkInit{Phase1,Phase2}Request.
  readonly hasControlPlane?: boolean;
  devicePersistentId?(): string;
  devStagingBaseUrl?(): string;
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
    phase1Bytes: Uint8Array,
    phase2Bytes: Uint8Array
  ): Promise<Uint8Array>;
  /** Re-run the auth handshake a run that started offline skipped. SdkInitResult bytes. */
  retryControlPlane?(): Promise<Uint8Array>;
  /** Drain the telemetry queue now; commons retries a failed batch on its own. */
  telemetryFlush?(): Promise<void>;
  /** In-memory reads from the auth manager and rac_state. */
  authState?(): {
    authenticated: boolean;
    needsRefresh: boolean;
    expiresAtUnixSec: number;
    userId: string;
    organizationId: string;
    deviceRegistered: boolean;
  };
  /** Drop tokens from memory and the secure store. */
  clearAuth?(): Promise<void>;
  // Process-wide HuggingFace bearer (rac_http_hf_token_set). Commons attaches it
  // to https requests whose host is exactly huggingface.co / hf.co and never
  // hands it back, so `hfTokenConfigured` is all a caller can read. `null`
  // restores the HF_TOKEN / token-file fallback; '' is an explicit opt-out.
  hfTokenSet(token: string | null): void;
  hfTokenConfigured(): boolean;
  secureSet(key: string, value: string): Promise<void>;
  secureGet(key: string): Promise<string | null>;
  secureDelete(key: string): Promise<void>;
  // A bare threshold number (legacy) or a full config object.
  createVad(thresholdOrConfig?: number | object): Promise<number>;
  vadProcess(handle: number, samples: Float32Array): boolean;
  vadIsActive(handle: number): boolean;
  vadSetThreshold(handle: number, threshold: number): void;
  vadReset(handle: number): void;
  vadStatistics(handle: number): {
    threshold?: number;
    ambientLevel?: number;
    recentAverage?: number;
    recentMax?: number;
  };
  unloadVad(handle: number): Promise<void>;
  /**
   * Register a SPEECH_ACTIVITY/FRAME callback for a VAD handle. Sync — the
   * callback is live before this returns. Cleared by {@link vadUnsetStreamCallback}.
   */
  vadSetStreamCallback(handle: number, onEvent: (eventBytes: Uint8Array) => void): void;
  vadUnsetStreamCallback(handle: number): Promise<void>;
  vadStreamStart(handle: number, optionsBytes: Uint8Array): Promise<number>;
  vadStreamFeed(sessionId: number, audioBytes: Uint8Array): Promise<void>;
  vadStreamStop(sessionId: number): Promise<void>;
  vadStreamCancel(sessionId: number): Promise<void>;
  loadModel(
    modelPath: string,
    id?: string,
    name?: string,
    /** Load-time placement: rac_llm_config_t's preferred_framework / context_length. */
    config?: { framework?: number; contextLength?: number }
  ): Promise<number>;
  // (handle, prompt, onToken) or (handle, prompt, options, onToken) — the addon
  // detects whether arg 3 is the callback or a generation-options object.
  generate(
    handle: number,
    prompt: string,
    optionsOrOnToken: object | ((t: string) => void),
    onToken?: (t: string) => void
  ): Promise<NativeGenerationMetrics>;
  cancelGenerate(handle: number): void;
  unloadModel(handle: number): Promise<void>;
  loraApply(handle: number, adapterPath: string, scale?: number): Promise<void>;
  loraRemove(handle: number, adapterPath?: string): Promise<void>;
  loraList(handle: number): Array<{ id: string; scale: number }>;
  loadVlmModel(modelPath: string, mmprojPath: string, id?: string, name?: string): Promise<number>;
  // The image is a path string or { path } | { base64 } | { rgb, width, height }.
  generateVlm(
    handle: number,
    image: string | object,
    prompt: string,
    optionsOrOnToken: object | ((t: string) => void),
    onToken?: (t: string) => void
  ): Promise<NativeGenerationMetrics>;
  cancelVlm(handle: number): void;
  unloadVlmModel(handle: number): Promise<void>;
  loadEmbeddingModel(modelPath: string, configJson?: string): Promise<number>;
  embed(handle: number, text: string, options?: object): Promise<Float32Array>;
  embedBatch(handle: number, texts: string[], options?: object): Promise<Float32Array[]>;
  unloadEmbeddingModel(handle: number): Promise<void>;
  loadSttModel(modelDir: string, id?: string, name?: string): Promise<number>;
  transcribe(
    handle: number,
    pcm16: Uint8Array,
    options?: object
  ): Promise<{
    text: string;
    language?: string;
    confidence: number;
    processingTimeMs: number;
    words: Array<{ text: string; startMs: number; endMs: number; confidence: number }>;
  }>;
  transcribeStream(
    handle: number,
    pcm16: Uint8Array,
    options: object,
    onPartial: (p: { text: string; isFinal: boolean }) => void
  ): Promise<void>;
  sttInfo(handle: number): {
    isReady: boolean;
    modelId?: string;
    supportsStreaming: boolean;
    languagesJson?: string;
  };
  unloadSttModel(handle: number): Promise<void>;
  loadTtsVoice(voiceDir: string, id?: string, name?: string): Promise<number>;
  synthesize(
    handle: number,
    text: string,
    options?: object
  ): Promise<{ sampleRate: number; samples: Float32Array; audioFormat: number; durationMs: number }>;
  synthesizeStream(
    handle: number,
    text: string,
    options: object,
    onChunk: (c: { samples: Float32Array }) => void
  ): Promise<void>;
  ttsStop(handle: number): void;
  ttsInfo(handle: number): { voiceId?: string; languagesJson?: string };
  unloadTtsVoice(handle: number): Promise<void>;
  loadRerankModel(modelPath: string, id?: string): Promise<number>;
  rerank(
    handle: number,
    query: string,
    documents: string[],
    topN?: number
  ): Promise<Array<{ index: number; score: number; rank: number }>>;
  unloadRerankModel(handle: number): Promise<void>;
  loadDiarizationModel(modelPath: string, id?: string): Promise<number>;
  diarize(
    handle: number,
    samples: Float32Array,
    options?: object
  ): Promise<{
    segments: Array<{ speakerId: string; speakerIndex: number; startMs: number; endMs: number }>;
    speakerCount: number;
    durationMs: number;
  }>;
  unloadDiarizationModel(handle: number): Promise<void>;
  loadSegmentationModel(modelPath: string, id?: string): Promise<number>;
  segment(
    handle: number,
    image: { data: Uint8Array; width: number; height: number; pixelFormat?: number },
    options?: object
  ): Promise<{
    width: number;
    height: number;
    classMask: Uint16Array;
    classes: Array<{ classId: number; label?: string; pixelCount: number; fraction: number }>;
    diagnosticRgba?: Uint8Array;
  }>;
  unloadSegmentationModel(handle: number): Promise<void>;
  shutdown(): Promise<void>;
  // Model registry + RAG (proto-byte). registerModel populates commons' global
  // registry so RAG can resolve embedding/LLM ids to paths; the rag* methods take
  // and return serialized runanywhere.v1 RAG protos as bytes.
  registerModel(id: string, localPath: string, category?: number, framework?: number): void;
  // create/ingest/query run on a worker thread (model load / embedding / LLM), so
  // they return a Promise; the utility-host dispatch awaits it.
  ragCreateSession(configProtoBytes: Uint8Array): Promise<number>;
  ragIngest(handle: number, documentProtoBytes: Uint8Array): Promise<Uint8Array>;
  ragQuery(handle: number, queryProtoBytes: Uint8Array): Promise<Uint8Array>;
  ragSearch(handle: number, requestProtoBytes: Uint8Array): Promise<Uint8Array>;
  // Resolves true when the stream ended because it was cancelled.
  ragQueryStream(
    handle: number,
    queryProtoBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<boolean>;
  ragCancel(handle: number): void;
  ragStats(handle: number): Uint8Array;
  ragClear(handle: number): Uint8Array;
  ragDestroySession(handle: number): void;

  // Model lifecycle + registry (native/model_bridge.cpp). Every entry point takes
  // serialized runanywhere.v1 request bytes and resolves the serialized reply on a
  // worker thread, so a multi-GB load never occupies the host's event loop.
  modelLoad(requestBytes: Uint8Array): Promise<Uint8Array>;
  modelResolvePaths(requestBytes: Uint8Array): Promise<Uint8Array>;
  modelUnload(requestBytes: Uint8Array): Promise<Uint8Array>;
  modelCurrent(requestBytes: Uint8Array): Promise<Uint8Array>;
  modelComponentSnapshot(component: number): Promise<Uint8Array>;
  modelLifecycleReset(): void;
  modelRegistryRegister(modelInfoBytes: Uint8Array): Promise<Uint8Array>;
  modelRegistryUpdate(modelInfoBytes: Uint8Array): Promise<Uint8Array>;
  modelRegistryGet(requestBytes: Uint8Array): Promise<Uint8Array>;
  modelRegistryList(requestBytes: Uint8Array): Promise<Uint8Array>;
  modelRegistryRemove(modelId: string): Promise<Uint8Array>;
  modelRegistryRefresh(requestBytes: Uint8Array): Promise<Uint8Array>;
  modelRegistryDiscover(requestBytes: Uint8Array): Promise<Uint8Array>;
  modelRegistryImport(requestBytes: Uint8Array): Promise<Uint8Array>;
  modelCompatibility(requestBytes: Uint8Array): Promise<Uint8Array>;
  modelRegisterFromUrl(requestBytes: Uint8Array): Promise<Uint8Array>;
  modelRegisterMultiFile(requestBytes: Uint8Array): Promise<Uint8Array>;

  // LLM over the proto ABI (native/llm_bridge.cpp). Handle-free: these read the
  // model the lifecycle load put in commons' own store. `llmGenerateStreamProto`
  // delivers one serialized LLMStreamEvent per callback.
  llmGenerateProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  llmGenerateStreamProto(
    requestBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void>;
  llmCancelProto(): Promise<Uint8Array>;
  structuredGenerate(requestBytes: Uint8Array): Promise<Uint8Array>;
  structuredParse(requestBytes: Uint8Array): Promise<Uint8Array>;
  structuredValidate(requestBytes: Uint8Array): Promise<Uint8Array>;

  // Tool calling over the commons run loop (native/tool_bridge.cpp). `onEvent`
  // is duplex: commons parks its loop on the reply to a `toolCall` event, so the
  // callback must resolve to serialized ToolResult bytes.
  toolRunLoopProto(
    requestBytes: Uint8Array,
    onEvent: (event: { handle?: number; toolCall?: Uint8Array }) =>
      | Uint8Array
      | undefined
      | Promise<Uint8Array | undefined>
  ): Promise<Uint8Array>;
  toolRunLoopCancelProto(handle: number): void;

  // VLM over the proto ABI (native/vlm_bridge.cpp). Handle-free; the image
  // travels inside the request as a VLMImage.
  vlmGenerateProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  vlmStreamProto(
    requestBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void>;
  vlmCancelProto(): Promise<Uint8Array>;

  // STT / TTS / VAD over the lifecycle proto ABI (native/speech_bridge.cpp).
  sttTranscribeProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  ttsSynthesizeProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  vadProcessProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  vadConfigureProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  sttTranscribeStreamProto(
    requestBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void>;
  ttsSynthesizeStreamProto(
    requestBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void>;
  sttStateProto(): Promise<Uint8Array>;
  ttsStopProto(): Promise<Uint8Array>;
  ttsListVoicesProto(): Promise<Uint8Array>;
  ttsStateProto(): Promise<Uint8Array>;
  vadStartProto(): Promise<Uint8Array>;
  vadStopProto(): Promise<Uint8Array>;
  vadResetProto(): Promise<Uint8Array>;

  // Composed voice agent (native/voice_bridge.cpp). The one migrated feature
  // that is handle-bound: `voiceCreateProto` resolves the agent handle as a
  // number and every other call takes it back. `voiceEventsProto` registers the
  // long-lived VoiceEvent stream and resolves when `voiceDestroyProto` tears the
  // agent down.
  voiceCreateProto(configBytes: Uint8Array): Promise<number>;
  voiceDestroyProto(handle: number): Promise<void>;
  voiceEventsProto(handle: number, onEvent: (eventBytes: Uint8Array) => void): Promise<void>;
  voiceInitializeProto(handle: number, configBytes: Uint8Array): Promise<Uint8Array>;
  voiceStatesProto(handle: number): Promise<Uint8Array>;
  voiceFeedAudioProto(handle: number, frameBytes: Uint8Array): Promise<Uint8Array>;
  voiceProcessVoiceTurnProto(handle: number, pcm16: Uint8Array): Promise<Uint8Array>;
  voiceProcessTurnProto(
    handle: number,
    requestBytes: Uint8Array,
    onEvent: (eventBytes: Uint8Array) => void
  ): Promise<void>;
  voiceCancelTurnProto(handle: number, requestBytes: Uint8Array): Promise<void>;

  // Embeddings / rerank / diarization / segmentation (native/data_bridge.cpp).
  // Only rerank takes a handle; commons has no lifecycle variant for it.
  embedBatchProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  rerankProto(handle: number, requestBytes: Uint8Array): Promise<Uint8Array>;
  diarizeProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  segmentProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  /** Sync `rac_embeddings_norm` — L2 norm of a dense float vector. */
  embeddingsNorm(vector: Float32Array): number;
  /** Sync `rac_embeddings_similarity` — cosine similarity of two dense vectors. */
  embeddingsSimilarity(lhs: Float32Array, rhs: Float32Array): number;

  // Downloads and storage (native/download_bridge.cpp). Downloads are keyed by
  // model/task id inside commons; progress arrives on one process-wide callback.
  // The storage entry points hide the analyzer handle the addon builds from its
  // rac_storage_callbacks_t.
  downloadPlanProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  downloadStartProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  downloadCancelProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  downloadProgressProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  downloadCleanupProto(): Promise<number>;
  downloadSubscribeProgress(onProgress: (progressBytes: Uint8Array) => void): void;
  downloadUnsubscribeProgress(): void;
  /** Sync `rac_download_progress_percent` — overall preferred when in [0,1]. */
  downloadProgressPercent(
    overallProgress: number,
    bytesDownloaded: number,
    totalBytes: number,
  ): number;
  storageInfoProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  storageAvailabilityProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  storageDeletePlanProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  storageDeleteProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  // The SDK's own Cache/ and Temp/ directories, which the analyzer above does
  // not own: commons resolves both paths from the base dir and clears them
  // (rac_file_manager_clear_cache / _clear_temp).
  fileManagerClearCache(): Promise<void>;
  fileManagerClearTemp(): Promise<void>;

  // Audio DSP over commons (native/audio_bridge.cpp). Sync — same shape as
  // downloadProgressPercent so TypeScript helpers never re-derive PCM math.
  audioFloat32ToPcm16(samples: Float32Array): Int16Array;
  audioPcm16ToFloat32(samples: Int16Array): Float32Array;
  audioResampleF32(samples: Float32Array, inRate: number, outRate: number): Float32Array;
  audioComputeRms(samples: Float32Array): number;
  audioFloat32ToWav(samples: Float32Array, sampleRate: number): Uint8Array;
  audioWavToFloat32(bytes: Uint8Array): { sampleRate: number; samples: Float32Array };
  audioPcmBytesToMs(
    byteCount: number,
    format: { sampleRate: number; channels?: number; bitsPerSample?: number }
  ): number;

  // LoRA over the lifecycle ABI (native/lora_bridge.cpp). Handle-free: these
  // act on the language model rac_model_lifecycle_load_proto made resident.
  loraApplyProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  loraRemoveProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  loraListProto(stateBytes: Uint8Array): Promise<Uint8Array>;
  loraStateProto(stateBytes: Uint8Array): Promise<Uint8Array>;
  loraCompatibilityProto(configBytes: Uint8Array): Promise<Uint8Array>;

  // LoRA adapter catalog (native/lora_bridge.cpp). Registry-bound: every one of
  // these acts on the process-wide registry `rac_get_lora_registry()` owns, so a
  // catalog entry outlives any loaded model.
  loraRegisterProto(entryBytes: Uint8Array): Promise<Uint8Array>;
  loraCatalogListProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  loraCatalogQueryProto(queryBytes: Uint8Array): Promise<Uint8Array>;
  loraCatalogGetProto(requestBytes: Uint8Array): Promise<Uint8Array>;

  // Logging (native/logging_bridge.cpp). `loggingSetLevel` is commons' own
  // `rac_logger_set_min_level`, read by every RAC_LOG_* macro before it formats.
  // `loggingSubscribe` replaces the platform adapter's stderr-only log slot with
  // one that also forwards each record here; `level` is a rac_log_level_t.
  loggingSetLevel(level: number): void;
  loggingLevel(): number;
  loggingSetLocalEnabled(enabled: boolean): void;
  loggingFlush(): void;
  loggingSubscribe(
    onRecord: (record: {
      level: number;
      category: string;
      message: string;
      timestampUnixMs: number;
    }) => void
  ): void;
  loggingUnsubscribe(): void;
}

/**
 * Make a directory reachable by the Windows loader (PATH prepend).
 *
 * The .node's STATIC imports (onnxruntime.dll, sherpa) already resolve from
 * beside it — the loader searches a module's own directory for its dependents.
 * A dependency the engine opens at RUNTIME by bare name does not: QHexRT calls
 * `LoadLibraryW("QnnHtp.dll")`, which takes the standard search order (the
 * EXECUTABLE's directory, the system dirs, then PATH) and never looks beside the
 * .node. In an Electron app that executable is electron.exe, buried in
 * node_modules — so a QAIRT runtime staged next to the addon would be invisible
 * and the NPU would silently look absent.
 *
 * PATH is the only entry in that order a library can move. Prepend, so a staged
 * runtime beats a differently-versioned QAIRT already on the machine's PATH; the
 * whole flat set (QnnHtp/QnnSystem/QnnHtpPrepare/QnnHtpV<arch>Stub plus the skel
 * and its .cat) then resolves out of that one directory, which is the invariant
 * the standard Hexagon HTP graph path requires on Windows. The Bonsai/Maple
 * ternary decoder's FastRPC skel is a SEPARATE mechanism that does read an
 * `ADSP_LIBRARY_PATH` env var on Windows (contrary to what an earlier version of
 * this comment claimed) — see `addSidecarDirToDspSearchPath` below, which this
 * function also calls.
 *
 * Thin-addon dual path: also prepend every registered plugin directory and the
 * directory that holds `librac_commons` / `rac_commons.dll` when present.
 */
function addSidecarDirToDllSearch(dir: string): void {
  if (process.platform !== 'win32') return;
  const current = process.env.PATH ?? '';
  const resolved = path.resolve(dir);
  const already = current
    .split(path.delimiter)
    .some((entry) => entry && path.resolve(entry).toLowerCase() === resolved.toLowerCase());
  if (already) return;
  process.env.PATH = current ? `${dir}${path.delimiter}${current}` : dir;
  addSidecarDirToDspSearchPath(dir);
}

/**
 * Also make a directory reachable by the Bonsai/Maple decoder's FastRPC skel loader
 * (QHexRT/src/bonsai/fastrpc_win.cpp), which is a SEPARATE search mechanism from the
 * Win32 DLL loader above and does not benefit from the PATH prepend at all.
 *
 * That native code seeds `ADSP_LIBRARY_PATH` itself, but its only fallback is
 * `exe_dir()` — the directory of the running EXECUTABLE. For a CLI tool the exe
 * sits beside the flat QAIRT/skel folder, so that fallback is correct. In a
 * packaged Electron app the executable is `RunAnywhere AI.exe`, nowhere near
 * `node_modules/@runanywhere/electron-qhexrt/prebuilds/…` — exactly the gap
 * `addSidecarDirToDllSearch` above exists to close for PATH. Left unset, the
 * custom ternary/bonsai skel (`librun_main_on_hexagon_skel.so`) fails to load
 * with a bare `HostOpFailed` at generate time — the model loads fine and only
 * this one decode path breaks, which is what makes it easy to miss: every other
 * QHexRT model resolves its runtime through the ordinary `LoadLibraryW`
 * search order and never touches this second mechanism.
 *
 * Must run before the utility-host fork so the child inherits it — `_putenv_s`
 * seeds a DLL's CRT at its OWN LoadLibrary time, but a forked child's env is a
 * snapshot taken at fork(), so setting this in the parent process (here, before
 * `require()` loads the addon that eventually forks) is what makes the timing
 * work at all.
 */
function addSidecarDirToDspSearchPath(dir: string): void {
  if (process.platform !== 'win32') return;
  const current = process.env.ADSP_LIBRARY_PATH ?? '';
  const resolved = path.resolve(dir);
  const already = current
    .split(path.delimiter)
    .some((entry) => entry && path.resolve(entry).toLowerCase() === resolved.toLowerCase());
  if (already) return;
  process.env.ADSP_LIBRARY_PATH = current ? `${dir}${path.delimiter}${current}` : dir;
}

function commonsLibraryFileName(platform: NodeJS.Platform = process.platform): string {
  if (platform === 'win32') return 'rac_commons.dll';
  if (platform === 'darwin') return 'librac_commons.dylib';
  return 'librac_commons.so';
}

/** Absolute path to shared commons beside a thin addon, or `undefined`. */
export function resolveCommonsLibrary(addonDir: string): string | undefined {
  // Same asar trap resolvePluginArtifactPath guards against: inside a packaged
  // app this path can point into app.asar, where fs.existsSync succeeds through
  // Electron's shim but the OS loader sees nothing. The result feeds
  // addSidecarDirToDllSearch, which is an OS-level call, so it has to be the
  // real file on disk.
  const candidate = asarUnpacked(path.join(addonDir, commonsLibraryFileName()));
  return fs.existsSync(candidate) ? candidate : undefined;
}

function repoBuildCandidates(): string[] {
  const root = path.resolve(__dirname, '..', '..', '..');
  const plat = process.platform;
  const arch = process.arch;
  const out: string[] = [];

  if (plat === 'darwin') {
    out.push(
      path.join(root, 'build', 'electron-macos', 'bindings', 'electron', 'native', 'runanywhere_native.node'),
      path.join(root, 'build', 'electron-macos-metal', 'bindings', 'electron', 'native', 'runanywhere_native.node'),
      path.join(root, 'build', 'electron-shared-macos', 'bindings', 'electron', 'native', 'runanywhere_native.node'),
      path.join(root, 'build', 'macos-debug', 'bindings', 'electron', 'native', 'runanywhere_native.node'),
      path.join(root, 'build', 'macos-release', 'bindings', 'electron', 'native', 'runanywhere_native.node')
    );
  } else if (plat === 'linux') {
    out.push(
      path.join(root, 'build', 'linux-release', 'bindings', 'electron', 'native', 'runanywhere_native.node'),
      path.join(root, 'build', 'linux-debug', 'bindings', 'electron', 'native', 'runanywhere_native.node'),
      path.join(root, 'build', 'linux-asan', 'bindings', 'electron', 'native', 'runanywhere_native.node')
    );
  } else if (plat === 'win32') {
    if (arch === 'arm64') {
      out.push(
        path.join(
          root,
          'build',
          'windows-arm64-release',
          'bindings',
          'electron',
          'native',
          'Release',
          'runanywhere_native.node'
        )
      );
    }
    out.push(
      path.join(
        root,
        'build',
        'windows-release',
        'bindings',
        'electron',
        'native',
        'Release',
        'runanywhere_native.node'
      )
    );
  }
  return out;
}

function pluginPathCandidatesFromEnv(): string[] {
  const raw = process.env.RUNANYWHERE_PLUGIN_PATHS;
  if (!raw) return [];
  return raw.split(path.delimiter).filter(Boolean);
}

function prepareNativeLoad(addonPath: string): void {
  // require() can load a .node out of app.asar because Electron patches
  // process.dlopen to extract it, so addonPath may still be an archive path
  // here. Everything below hands directories to the OS loader instead, which
  // cannot look inside the archive, so resolve to the unpacked copy first.
  const addonDir = path.dirname(asarUnpacked(addonPath));
  addSidecarDirToDllSearch(addonDir);
  const commons = resolveCommonsLibrary(addonDir);
  if (commons) addSidecarDirToDllSearch(path.dirname(commons));
  for (const pluginPath of pluginPathCandidatesFromEnv()) {
    addSidecarDirToDllSearch(path.dirname(pluginPath));
  }
}

// Platforms this release actually ships a prebuilt addon for. Kept next to the
// resolver so it cannot drift from what bundle-native staged.
const PREBUILT_PLATFORMS: readonly string[] = ['darwin-arm64', 'win32-x64', 'win32-arm64'];

function resolveAddon(): NativeAddon {
  const candidates = [
    process.env.RUNANYWHERE_NATIVE_PATH,
    // Packaged prebuild bundled by scripts/bundle-native (dist -> pkg root).
    path.resolve(
      __dirname,
      '..',
      'prebuilds',
      `${process.platform}-${process.arch}`,
      'runanywhere_native.node'
    ),
    ...repoBuildCandidates(),
    // Packaged (cmake-js default output next to the native package).
    path.resolve(__dirname, '..', 'native', 'build', 'Release', 'runanywhere_native.node'),
  ].filter((p): p is string => Boolean(p));

  const tried: string[] = [];
  for (const p of candidates) {
    tried.push(p);
    if (fs.existsSync(p)) {
      prepareNativeLoad(p);
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      return require(p) as NativeAddon;
    }
  }

  const pluginHints = pluginPathCandidatesFromEnv()
    .filter((p) => !fs.existsSync(p))
    .map((p) => `  missing backend plugin: ${p}`);

  // Say plainly when this platform ships no prebuild at all. Without this the
  // message reads as "your install is broken" on linux/win32, when the truth is
  // that the release never carried a binary for them. package.json deliberately
  // keeps os/cpu permissive, because the TypeScript facade IS cross-platform and
  // narrowing them would also block TS-only consumers and our own Linux CI.
  const here = `${process.platform}-${process.arch}`;
  const unsupported = !PREBUILT_PLATFORMS.includes(here);

  throw new Error(
    [
      'runanywhere_native.node not found (core addon).',
      ...(unsupported
        ? [
            `No prebuild ships for ${here}. This release carries ${PREBUILT_PLATFORMS.join(', ')} only.`,
            'This is a packaging gap, not a broken install: build the addon from source',
            'or use a supported platform.',
          ]
        : []),
      'Set RUNANYWHERE_NATIVE_PATH to the built addon, or run scripts/bundle-native.',
      'Tried:',
      ...tried.map((p) => `  ${p}`),
      ...(pluginHints.length > 0
        ? [
            'Backend packages were registered but their artifacts are missing (thin path):',
            ...pluginHints,
            'Install / stage @runanywhere/electron-{llamacpp,onnx,sherpa} prebuilds, or use the fat addon.',
          ]
        : []),
    ].join('\n')
  );
}

/**
 * Wrap every native binding so thrown / rejected values become SDKException
 * with `.code` / `.category` parsed from ``"… failed: -<rac>"`` messages.
 */
function wrapNative(raw: NativeAddon): NativeAddon {
  return new Proxy(raw, {
    get(target, prop, receiver) {
      const v = Reflect.get(target, prop, receiver);
      if (typeof v !== 'function') return v;
      return (...args: unknown[]) => {
        try {
          const r = (v as (...a: unknown[]) => unknown).apply(target, args);
          if (r != null && typeof (r as { then?: unknown }).then === 'function') {
            return (r as Promise<unknown>).catch((e) => {
              throw asSDKException(e);
            });
          }
          return r;
        } catch (e) {
          throw asSDKException(e);
        }
      };
    },
  }) as NativeAddon;
}

/** Lazy native load — resolution failure surfaces on first use, not on import. */
let _addon: NativeAddon | undefined;

export function getAddon(): NativeAddon {
  if (_addon === undefined) _addon = wrapNative(resolveAddon());
  return _addon;
}

/**
 * The loaded native addon. Property access triggers a one-shot resolve so
 * importing `bridge` never crashes the utility host before env is set.
 */
export const addon: NativeAddon = new Proxy({} as NativeAddon, {
  get(_target, prop, receiver) {
    return Reflect.get(getAddon(), prop, receiver);
  },
  has(_target, prop) {
    return Reflect.has(getAddon(), prop);
  },
  ownKeys() {
    return Reflect.ownKeys(getAddon() as object);
  },
  getOwnPropertyDescriptor(_target, prop) {
    return Reflect.getOwnPropertyDescriptor(getAddon() as object, prop);
  },
}) as NativeAddon;
