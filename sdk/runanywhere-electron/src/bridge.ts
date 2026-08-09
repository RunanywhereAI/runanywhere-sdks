// bridge.ts — loads the native N-API addon and adapts its callback-based
// streaming into an AsyncIterable. The addon is resolved from (in order): the
// RUNANYWHERE_NATIVE_PATH env var, the local dev build output, or the packaged
// location. Sidecar DLLs (onnxruntime, sherpa) must sit next to the .node.
import * as fs from 'fs';
import * as path from 'path';

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

/** Raw surface exported by runanywhere_native.node. */
export interface NativeAddon {
  readonly version: string;
  initialize(secureDir: string, baseDir?: string): Promise<void>;
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
  storageInfoProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  storageAvailabilityProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  storageDeletePlanProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  storageDeleteProto(requestBytes: Uint8Array): Promise<Uint8Array>;

  // LoRA over the lifecycle ABI (native/lora_bridge.cpp). Handle-free: these
  // act on the language model rac_model_lifecycle_load_proto made resident.
  loraApplyProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  loraRemoveProto(requestBytes: Uint8Array): Promise<Uint8Array>;
  loraListProto(stateBytes: Uint8Array): Promise<Uint8Array>;
  loraStateProto(stateBytes: Uint8Array): Promise<Uint8Array>;
}

function resolveAddon(): NativeAddon {
  const candidates = [
    process.env.RUNANYWHERE_NATIVE_PATH,
    // Packaged prebuild bundled by scripts/bundle-native.js (dist -> pkg root).
    path.resolve(
      __dirname, '..', 'prebuilds', `${process.platform}-${process.arch}`,
      'runanywhere_native.node'
    ),
    // Local dev build (repo build dir): dist -> electron -> sdk -> repo root.
    path.resolve(
      __dirname, '..', '..', '..', 'build', 'windows-release', 'sdk',
      'runanywhere-electron', 'native', 'Release', 'runanywhere_native.node'
    ),
    // Packaged (cmake-js default output next to the native package).
    path.resolve(__dirname, '..', 'native', 'build', 'Release', 'runanywhere_native.node'),
  ].filter((p): p is string => Boolean(p));

  for (const p of candidates) {
    if (fs.existsSync(p)) {
      // eslint-disable-next-line @typescript-eslint/no-var-requires
      return require(p) as NativeAddon;
    }
  }
  throw new Error(
    'runanywhere_native.node not found. Set RUNANYWHERE_NATIVE_PATH to the built addon.\nTried:\n  ' +
      candidates.join('\n  ')
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

export const addon: NativeAddon = wrapNative(resolveAddon());
