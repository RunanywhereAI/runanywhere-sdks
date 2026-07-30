// facade.ts — assembles the v3 surface over a backend.
//
// `createRunAnywhere` is called exactly twice: once with `NativeBackend` for the
// main process and once with `RpcBackend` in the preload. Both produce the same
// object shape, which is why `RunAnywhere.llm.generate` and
// `window.runanywhere.llm.generate` are the same function written once.

import { SDKException } from '../errors';
import { bus } from '../events';
import {
  createImagesNamespace,
  createLoraNamespace,
  createModelsNamespace,
  createSegmentationNamespace,
} from './assets';
import type { ImagesNamespace, LoraNamespace, ModelsNamespace, SegmentationNamespace } from './assets';
import type { RaBackend } from './backend';
import {
  createEmbeddingsNamespace,
  createRagNamespace,
  createRerankNamespace,
} from './data';
import type { EmbeddingsNamespace, RagNamespace, RerankNamespace } from './data';
import { SdkEventHub } from './hub';
import {
  createDiarizationNamespace,
  createSttNamespace,
  createTtsNamespace,
  createVadNamespace,
  createVoiceNamespace,
} from './speech';
import type {
  DiarizationNamespace,
  SttNamespace,
  TtsNamespace,
  VadNamespace,
  VoiceNamespace,
} from './speech';
import { createLlmNamespace, createVlmNamespace } from './text';
import type { LlmNamespace, VlmNamespace } from './text';
import { Environment, audio, image, ragDocument } from './types';
import type { SdkEvent } from './types';

/** Everything {@link RunAnywhereApi.initialize} accepts. */
export interface InitializeOptions {
  /**
   * Control-plane key. Accepted and stored, but unused: Electron has no control
   * plane yet, so nothing authenticates, registers a device, or reports telemetry.
   */
  apiKey?: string;
  /** Control-plane base URL. Accepted and stored, but unused for the same reason. */
  baseUrl?: string;
  /** Deployment environment. Defaults to production. */
  environment?: Environment;
  /** Root for model storage and the secure store. Defaults to `~/.runanywhere`. */
  baseDir?: string;
  /** Secure-store directory. Defaults to `<baseDir>/secure`. */
  secureDir?: string;
}

/**
 * Encrypted key-value storage. An Electron platform extra, not part of the
 * cross-SDK spec — the other SDKs expose their platform keystore differently.
 */
export interface SecureStore {
  /** Store `value` under `key`, encrypted at rest. */
  set(key: string, value: string): Promise<void>;
  /** Read `key`, or null when absent. */
  get(key: string): Promise<string | null>;
  /** Delete `key`; a missing key is a no-op. */
  delete(key: string): Promise<void>;
}

/** The public RunAnywhere surface. */
export interface RunAnywhereApi {
  /**
   * Bring the SDK up: platform adapter, native load, engine registration, and the
   * model store. One call, no second phase.
   *
   * @throws SDKException when the native runtime cannot start.
   */
  initialize(options?: InitializeOptions): Promise<void>;
  /** Tear down: unload models, close sessions, clear state. */
  reset(): Promise<void>;
  /** True once local inference is usable. */
  readonly isReady: boolean;
  /** The bundled commons version; empty until {@link initialize} resolves. */
  readonly version: string;
  /** Stable per-install identifier; empty until {@link initialize} resolves. */
  readonly deviceId: string;
  /** The configured deployment environment. */
  readonly environment: Environment;
  /** Lifecycle, model, and error breadcrumbs. */
  readonly events: AsyncIterableIterator<SdkEvent>;

  readonly llm: LlmNamespace;
  readonly vlm: VlmNamespace;
  readonly stt: SttNamespace;
  readonly tts: TtsNamespace;
  readonly vad: VadNamespace;
  readonly embeddings: EmbeddingsNamespace;
  readonly rerank: RerankNamespace;
  readonly images: ImagesNamespace;
  readonly diarization: DiarizationNamespace;
  readonly segmentation: SegmentationNamespace;
  readonly voice: VoiceNamespace;
  readonly rag: RagNamespace;
  readonly models: ModelsNamespace;
  readonly lora: LoraNamespace;
  /** Electron platform extra; see {@link SecureStore}. */
  readonly secure: SecureStore;

  // The input constructors also hang off the facade. A renderer cannot `require`
  // the package, so carrying them here is what lets page code build the same
  // AudioInput/ImageInput/RagDocument values main-process code builds.
  /** Constructors for {@link AudioInput}. */
  readonly audio: typeof audio;
  /** Constructors for {@link ImageInput}. */
  readonly image: typeof image;
  /** Constructors for {@link RagDocument}. */
  readonly ragDocument: typeof ragDocument;
}

const DEVICE_ID_KEY = 'runanywhere.deviceId';

/** Build the public surface over `backend`. */
export function createRunAnywhere(backend: RaBackend): RunAnywhereApi {
  const hub = new SdkEventHub();
  // Mirror into the pre-v3 EventBus so existing `RunAnywhere.legacyEvents`
  // listeners keep firing while the deprecated surface lives.
  hub.mirror((event) => {
    if (event.type === 'ready') bus.emit({ type: 'servicesReady' });
  });

  let ready = false;
  let version = '';
  let deviceId = '';
  let environment: Environment = Environment.PRODUCTION;
  let initializing: Promise<void> | null = null;

  const requireReady = (): void => {
    if (!ready) throw SDKException.notInitialized('RunAnywhere');
  };

  const deps = { backend, hub, requireReady };
  const llm = createLlmNamespace(deps);
  const vlm = createVlmNamespace(deps);
  const stt = createSttNamespace(deps);
  const tts = createTtsNamespace(deps);
  const vad = createVadNamespace(deps);
  const embeddings = createEmbeddingsNamespace(deps);
  const rerank = createRerankNamespace(deps);
  const images = createImagesNamespace(deps);
  const diarization = createDiarizationNamespace(deps);
  const segmentation = createSegmentationNamespace(deps);
  const rag = createRagNamespace(deps);
  const models = createModelsNamespace(deps);
  const lora = createLoraNamespace(deps);
  const voice = createVoiceNamespace({
    ...deps,
    stt,
    tts,
    generate: (prompt, options) => llm.generateStream(prompt, options),
    llmCancel: () => backend.llmCancel(),
  });

  async function initialize(options: InitializeOptions = {}): Promise<void> {
    if (ready) return;
    if (initializing) return initializing;
    environment = options.environment ?? Environment.PRODUCTION;
    initializing = (async () => {
      await backend.initialize({ baseDir: options.baseDir, secureDir: options.secureDir });
      version = await backend.version();
      ready = true;
      // A stable install identifier, minted locally. With no control plane there is
      // nothing to register it with; it exists so logs and telemetry have a key.
      try {
        const stored = await backend.secureGet(DEVICE_ID_KEY);
        if (stored) {
          deviceId = stored;
        } else {
          deviceId = `electron-${Math.random().toString(36).slice(2)}${Date.now().toString(36)}`;
          await backend.secureSet(DEVICE_ID_KEY, deviceId);
        }
      } catch {
        // A secure store that is unavailable must not block local inference.
        deviceId = '';
      }
      hub.emit({ type: 'ready' });
      bus.emit({ type: 'initialized' });
    })();
    try {
      await initializing;
    } finally {
      initializing = null;
    }
  }

  async function reset(): Promise<void> {
    if (!ready) return;
    await backend.unload();
    await backend.shutdown();
    ready = false;
    version = '';
    deviceId = '';
    hub.clear();
    bus.emit({ type: 'shutdown' });
  }

  const secure: SecureStore = {
    set: (key, value) => backend.secureSet(key, value),
    get: (key) => backend.secureGet(key),
    delete: (key) => backend.secureDelete(key),
  };

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
    images,
    diarization,
    segmentation,
    voice,
    rag,
    models,
    lora,
    secure,
    audio,
    image,
    ragDocument,
  };
}
