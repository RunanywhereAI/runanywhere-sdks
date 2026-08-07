// Assembles the public RunAnywhere surface over a backend. Called once with
// NativeBackend (main process) and once with RpcBackend (renderer); both produce
// the same object, which is why a namespace method is written once and runs in
// either host.
//
// All 14 Swift namespaces are on this surface. llm, vlm, stt, tts, vad,
// embeddings, diarization, segmentation, rag, and models are wired to their
// proto-byte backend ops; rerank, images, voice, and lora report NOT_IMPLEMENTED
// / FEATURE_NOT_AVAILABLE honestly until their backend paths land (see
// placeholders.ts and addon deferrals).

import type { RaBackend } from './backend.js';
import { runControlPlane } from './control-plane.js';
import { SdkEventHub } from './events.js';
import { createLlmNamespace } from './namespaces/llm.js';
import type { LlmNamespace } from './namespaces/llm.js';
import { createVlmNamespace } from './namespaces/vlm.js';
import type { VlmNamespace } from './namespaces/vlm.js';
import { createSttNamespace } from './namespaces/stt.js';
import type { SttNamespace } from './namespaces/stt.js';
import { createTtsNamespace } from './namespaces/tts.js';
import type { TtsNamespace } from './namespaces/tts.js';
import { createVadNamespace } from './namespaces/vad.js';
import type { VadNamespace } from './namespaces/vad.js';
import { createEmbeddingsNamespace } from './namespaces/embeddings.js';
import type { EmbeddingsNamespace } from './namespaces/embeddings.js';
import { createDiarizationNamespace } from './namespaces/diarization.js';
import type { DiarizationNamespace } from './namespaces/diarization.js';
import { createSegmentationNamespace } from './namespaces/segmentation.js';
import type { SegmentationNamespace } from './namespaces/segmentation.js';
import { createRagNamespace } from './namespaces/rag.js';
import type { RagNamespace } from './namespaces/rag.js';
import { createModelsNamespace, ensureLoaded } from './namespaces/models.js';
import type { ModelsNamespace } from './namespaces/models.js';
import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import { createRerankNamespace } from './namespaces/placeholders.js';
import type { RerankNamespace } from './namespaces/placeholders.js';
import { createImagesNamespace } from './namespaces/images.js';
import type { ImagesNamespace } from './namespaces/images.js';
import { createLoraNamespace } from './namespaces/lora.js';
import type { LoraNamespace } from './namespaces/lora.js';
import { createVoiceNamespace } from './namespaces/voice.js';
import type { VoiceNamespace } from './namespaces/voice.js';
import { Environment } from './types.js';
import type { SDKCapabilities, SdkEvent } from './types.js';

/** Everything {@link RunAnywhereApi.initialize} accepts. */
export interface InitializeOptions {
  /** Root for model storage and the secure store. Defaults to ~/.runanywhere. */
  baseDir?: string;
  /** Secure-store directory. Defaults to <baseDir>/secure. */
  secureDir?: string;
  /** Deployment environment. Defaults to production. */
  environment?: Environment;
  /** Control-plane API key; with a base URL, enables auth + telemetry (desktop builds). */
  apiKey?: string;
  /** Control-plane base URL. */
  baseUrl?: string;
}

/** The public RunAnywhere surface. */
export interface RunAnywhereApi {
  /** Bring the SDK up: platform adapter, native load, engine registration. */
  initialize(options?: InitializeOptions): Promise<void>;
  /** Tear down: unload models, close sessions, clear state. */
  reset(): Promise<void>;
  /** True once local inference is usable. */
  readonly isReady: boolean;
  /** The bundled commons version; empty until initialize resolves. */
  readonly version: string;
  /** Stable per-install identifier; empty until initialize resolves. */
  readonly deviceId: string;
  /** The configured deployment environment. */
  readonly environment: Environment;
  /** Honest snapshot of what this build can reach. */
  capabilities(): Promise<SDKCapabilities>;
  /** Lifecycle and model breadcrumbs. */
  readonly events: AsyncIterableIterator<SdkEvent>;

  readonly llm: LlmNamespace;
  readonly vlm: VlmNamespace;
  readonly stt: SttNamespace;
  readonly tts: TtsNamespace;
  readonly vad: VadNamespace;
  readonly embeddings: EmbeddingsNamespace;
  readonly rerank: RerankNamespace;
  readonly diarization: DiarizationNamespace;
  readonly segmentation: SegmentationNamespace;
  readonly rag: RagNamespace;
  readonly images: ImagesNamespace;
  readonly voice: VoiceNamespace;
  readonly lora: LoraNamespace;
  readonly models: ModelsNamespace;
}

const MODALITIES = [
  'llm', 'vlm', 'stt', 'tts', 'vad', 'embeddings', 'diarization', 'segmentation', 'rag',
  'voice', 'lora',
];
const UNAVAILABLE = [
  { name: 'rerank', reason: 'handle-based in commons; the addon rerank path is not wired yet' },
  { name: 'images', reason: 'wired to the diffusion op, but no diffusion engine is linked in this build' },
];

/** Build the public surface over `backend`. */
export function createRunAnywhere(backend: RaBackend): RunAnywhereApi {
  const hub = new SdkEventHub();
  let ready = false;
  let version = '';
  let deviceId = '';
  let environment: Environment = Environment.PRODUCTION;
  let initializing: Promise<void> | null = null;

  const models = createModelsNamespace(backend);
  // Auto-load resolver bound per category (mirrors Swift's ensureLoaded): a
  // generation verb names a model in its options and the SDK loads + downloads it.
  const resolveFor = (category: ModelCategory) => (modelId: string) =>
    ensureLoaded(backend, models, modelId, category);

  const llm = createLlmNamespace(backend, resolveFor(ModelCategory.MODEL_CATEGORY_LANGUAGE));
  const vlm = createVlmNamespace(backend, resolveFor(ModelCategory.MODEL_CATEGORY_MULTIMODAL));
  const stt = createSttNamespace(backend, resolveFor(ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION));
  const tts = createTtsNamespace(backend, resolveFor(ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS));
  const vad = createVadNamespace(backend, resolveFor(ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION));
  const embeddings = createEmbeddingsNamespace(backend, resolveFor(ModelCategory.MODEL_CATEGORY_EMBEDDING));
  const rerank = createRerankNamespace(backend);
  const diarization = createDiarizationNamespace(
    backend,
    resolveFor(ModelCategory.MODEL_CATEGORY_SPEAKER_DIARIZATION)
  );
  const segmentation = createSegmentationNamespace(
    backend,
    resolveFor(ModelCategory.MODEL_CATEGORY_SEMANTIC_SEGMENTATION)
  );
  const rag = createRagNamespace(
    backend,
    resolveFor(ModelCategory.MODEL_CATEGORY_EMBEDDING),
    resolveFor(ModelCategory.MODEL_CATEGORY_LANGUAGE)
  );
  const images = createImagesNamespace(backend, resolveFor(ModelCategory.MODEL_CATEGORY_IMAGE_GENERATION));
  const voice = createVoiceNamespace(stt, llm, tts);
  const lora = createLoraNamespace(backend);

  async function initialize(options: InitializeOptions = {}): Promise<void> {
    if (ready) return;
    if (initializing) return initializing;
    environment = options.environment ?? Environment.PRODUCTION;
    initializing = (async () => {
      await backend.initialize({ baseDir: options.baseDir, secureDir: options.secureDir });
      version = await backend.version();
      ready = true;
      // Desktop control plane (auth + telemetry). Best-effort: never blocks local
      // inference. Only runs when creds are supplied and the build carries it.
      try {
        const id = await runControlPlane(
          backend,
          { apiKey: options.apiKey, baseUrl: options.baseUrl, environment },
          version
        );
        if (id) deviceId = id;
      } catch {
        // auth/telemetry failure must not fail initialize
      }
      hub.emit({ type: 'ready' });
    })();
    try {
      await initializing;
    } finally {
      initializing = null;
    }
  }

  async function reset(): Promise<void> {
    if (!ready) return;
    await backend.shutdown();
    ready = false;
    version = '';
    deviceId = '';
    hub.clear();
  }

  async function capabilities(): Promise<SDKCapabilities> {
    return { modalities: [...MODALITIES], device: await backend.deviceType(), unavailable: [...UNAVAILABLE] };
  }

  return {
    initialize,
    reset,
    get isReady() {
      return ready;
    },
    get version() {
      return version;
    },
    get deviceId() {
      return deviceId;
    },
    get environment() {
      return environment;
    },
    capabilities,
    get events() {
      return hub.stream();
    },
    llm,
    vlm,
    stt,
    tts,
    vad,
    embeddings,
    rerank,
    diarization,
    segmentation,
    rag,
    images,
    voice,
    lora,
    models,
  };
}
