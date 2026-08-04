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
  initialize(secureDir: string, baseDir?: string): void;
  secureSet(key: string, value: string): void;
  secureGet(key: string): string | null;
  secureDelete(key: string): void;
  // A bare threshold number (legacy) or a full config object.
  createVad(thresholdOrConfig?: number | object): number;
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
  unloadVad(handle: number): void;
  loadModel(
    modelPath: string,
    id?: string,
    name?: string,
    /** Load-time placement: rac_llm_config_t's preferred_framework / context_length. */
    config?: { framework?: number; contextLength?: number }
  ): number;
  // (handle, prompt, onToken) or (handle, prompt, options, onToken) — the addon
  // detects whether arg 3 is the callback or a generation-options object.
  generate(
    handle: number,
    prompt: string,
    optionsOrOnToken: object | ((t: string) => void),
    onToken?: (t: string) => void
  ): Promise<NativeGenerationMetrics>;
  cancelGenerate(handle: number): void;
  unloadModel(handle: number): void;
  loraApply(handle: number, adapterPath: string, scale?: number): void;
  loraRemove(handle: number, adapterPath?: string): void;
  loraList(handle: number): Array<{ id: string; scale: number }>;
  loadVlmModel(modelPath: string, mmprojPath: string, id?: string, name?: string): number;
  // The image is a path string or { path } | { base64 } | { rgb, width, height }.
  generateVlm(
    handle: number,
    image: string | object,
    prompt: string,
    optionsOrOnToken: object | ((t: string) => void),
    onToken?: (t: string) => void
  ): Promise<NativeGenerationMetrics>;
  cancelVlm(handle: number): void;
  unloadVlmModel(handle: number): void;
  loadEmbeddingModel(modelPath: string, configJson?: string): number;
  embed(handle: number, text: string, options?: object): Float32Array;
  embedBatch(handle: number, texts: string[], options?: object): Float32Array[];
  unloadEmbeddingModel(handle: number): void;
  loadSttModel(modelDir: string, id?: string, name?: string): number;
  transcribe(
    handle: number,
    pcm16: Uint8Array,
    options?: object
  ): {
    text: string;
    language?: string;
    confidence: number;
    processingTimeMs: number;
    words: Array<{ text: string; startMs: number; endMs: number; confidence: number }>;
  };
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
  unloadSttModel(handle: number): void;
  loadTtsVoice(voiceDir: string, id?: string, name?: string): number;
  synthesize(
    handle: number,
    text: string,
    options?: object
  ): { sampleRate: number; samples: Float32Array; audioFormat: number; durationMs: number };
  synthesizeStream(
    handle: number,
    text: string,
    options: object,
    onChunk: (c: { samples: Float32Array }) => void
  ): Promise<void>;
  ttsStop(handle: number): void;
  ttsInfo(handle: number): { voiceId?: string; languagesJson?: string };
  unloadTtsVoice(handle: number): void;
  loadRerankModel(modelPath: string, id?: string): number;
  rerank(
    handle: number,
    query: string,
    documents: string[],
    topN?: number
  ): Array<{ index: number; score: number; rank: number }>;
  unloadRerankModel(handle: number): void;
  loadDiarizationModel(modelPath: string, id?: string): number;
  diarize(
    handle: number,
    samples: Float32Array,
    options?: object
  ): {
    segments: Array<{ speakerId: string; speakerIndex: number; startMs: number; endMs: number }>;
    speakerCount: number;
    durationMs: number;
  };
  unloadDiarizationModel(handle: number): void;
  loadSegmentationModel(modelPath: string, id?: string): number;
  segment(
    handle: number,
    image: { data: Uint8Array; width: number; height: number; pixelFormat?: number },
    options?: object
  ): {
    width: number;
    height: number;
    classMask: Uint16Array;
    classes: Array<{ classId: number; label?: string; pixelCount: number; fraction: number }>;
    diagnosticRgba?: Uint8Array;
  };
  unloadSegmentationModel(handle: number): void;
  shutdown(): void;
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
