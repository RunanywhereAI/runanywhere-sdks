// facade.ts — assembles the v3 surface over a backend.
//
// `createRunAnywhere` is called exactly twice: once with `NativeBackend` for the
// main process and once with `RpcBackend` in the preload. Both produce the same
// object shape, which is why `RunAnywhere.llm.generate` and
// `window.runanywhere.llm.generate` are the same function written once.

import { SDKException } from '../errors';
import { bus } from '../events';
import {
  IMAGES_GAP,
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
import { AudioFormat, Environment, InferenceFramework, audio, image, ragDocument } from './types';
import {
  SdkInitEnvironment,
  SdkInitPhase1Request,
  SdkInitPhase2Request,
} from '../proto/sdk_init';
import type { SDKCapabilities, SdkEvent, UnavailableCapability } from './types';

/** Everything {@link RunAnywhereApi.initialize} accepts. */
export interface InitializeOptions {
  /**
   * Control-plane API key. On a desktop-control-plane build (RAC_DESKTOP_ADAPTER=ON)
   * with a `baseUrl`, this drives authentication + telemetry via the two-phase init.
   */
  apiKey?: string;
  /** Control-plane base URL. Required (with `apiKey`) to enable auth + telemetry. */
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
  /**
   * Installed, packaged, and executable surface of this build. Generated
   * from packaging facts about the linked addon, never from namespace
   * presence alone — an unavailable modality is reported honestly in
   * `unavailable` instead of failing with a generic error the first time
   * it is used.
   */
  capabilities(): Promise<SDKCapabilities>;
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

// Modality ids not part of the v4 public API surface on any platform, plus the
// mobile-only runtimes this native addon never links — honest even before
// `initialize()` runs, since these are packaging facts, not runtime state.
const UNAVAILABLE_CAPABILITIES: UnavailableCapability[] = [
  { name: 'agents', reason: 'RunAnywhere.agents is not part of the v4 public API surface.' },
  { name: 'wakeword', reason: 'RunAnywhere.wakeword is not part of the v4 public API surface.' },
  {
    name: 'realtime',
    reason: 'RunAnywhere.realtime is not part of the v4 public API surface (no WebRTC/SIP/S2S transport namespace).',
  },
  {
    name: 'litert',
    reason: 'LiteRT is an Android/mobile inference runtime; the Electron addon links llama.cpp, ONNX Runtime, and sherpa-onnx only.',
  },
  {
    name: 'executorch',
    reason: 'ExecuTorch is a mobile inference runtime; the Electron addon links llama.cpp, ONNX Runtime, and sherpa-onnx only.',
  },
  { name: 'images', reason: IMAGES_GAP },
];

/**
 * Honest snapshot of what this Electron build can actually reach.
 *
 * The three engines (`InferenceFramework.LLAMA_CPP`/`ONNX`/`SHERPA`) and the
 * modalities built on them are statically linked into every build of this
 * addon (see `native-backend.ts`'s per-slot `load()`/`unloadHandle()`), so
 * their presence is a packaging fact rather than something that needs a
 * runtime probe. `images` is the one modality with namespace code but no
 * linked backend — reported in `unavailable` with the exact missing symbol,
 * matching the gap `images.ts` itself throws for.
 */
function capabilitiesSnapshot(): SDKCapabilities {
  return {
    modalities: [
      'llm', 'vlm', 'stt', 'tts', 'vad', 'embeddings', 'rerank',
      'diarization', 'segmentation', 'rag', 'lora',
    ],
    backends: [InferenceFramework.LLAMA_CPP, InferenceFramework.ONNX, InferenceFramework.SHERPA],
    // Only formats this SDK can actually round-trip: raw PCM for live streams,
    // plus WAV through the built-in RIFF codec (audio.ts's encodeWav/decodeWav).
    audioFormats: [AudioFormat.PCM, AudioFormat.WAV],
    streaming: { llm: true, vlm: true, stt: true, tts: true, vad: true, rag: true, images: false },
    tools: {
      registry: true,
      // llm.tools runs one grammar-constrained selection round at a time (text.ts's runToolLoop).
      parallel: false,
      cancellation: true,
    },
    rag: {
      // Each rag.open() gets its own native session handle (native-backend.ts's ragSessions map).
      multiSession: true,
      persistent: true,
    },
    unavailable: UNAVAILABLE_CAPABILITIES,
  };
}

const DEVICE_ID_KEY = 'runanywhere.deviceId';

/** The host OS as the backend's platform enum (macos/linux/windows) — NOT the
 * SDK binding name. The binding ("electron") is reported separately as sdk_binding. */
function osPlatform(): string {
  if (process.platform === 'darwin') return 'macos';
  if (process.platform === 'win32') return 'windows';
  return 'linux';
}

/** Run the desktop two-phase init (telemetry + auth) when creds allow. Best-effort:
 * HTTP/auth failures are non-fatal (the SDK stays usable offline). Returns the
 * persistent device id when the control plane ran, else null. */
async function runControlPlane(
  backend: RaBackend,
  options: InitializeOptions,
  environment: Environment,
  version: string
): Promise<string | null> {
  if (!(await backend.hasControlPlane())) {
    if (options.apiKey || options.baseUrl) {
      // eslint-disable-next-line no-console
      console.warn(
        'RunAnywhere.initialize: apiKey/baseUrl supplied but this build has no desktop ' +
          'control plane (RAC_DESKTOP_ADAPTER=OFF) — no auth or telemetry'
      );
    }
    return null;
  }
  const isProd = environment === Environment.PRODUCTION;
  let baseUrl = (options.baseUrl ?? '').trim();
  if (!baseUrl && !isProd) baseUrl = await backend.devStagingBaseUrl();
  const apiKey = (options.apiKey ?? '').trim();
  if (!baseUrl) return null;
  if (isProd && !apiKey) return null;

  const deviceId = await backend.devicePersistentId();
  const platform = osPlatform();
  const protoEnv = isProd
    ? SdkInitEnvironment.SDK_INIT_ENVIRONMENT_PRODUCTION
    : SdkInitEnvironment.SDK_INIT_ENVIRONMENT_DEVELOPMENT;
  const phase1 = SdkInitPhase1Request.encode({
    environment: protoEnv,
    apiKey,
    baseUrl,
    deviceId,
    platform,
    sdkVersion: version,
  }).finish();
  const phase2 = SdkInitPhase2Request.encode({
    buildToken: '',
    forceRefreshAssignments: false,
    flushTelemetry: true,
    discoverDownloadedModels: true,
    rescanLocalModels: true,
  }).finish();
  await backend.configureControlPlane({
    environment: isProd ? 2 : 0,
    apiKey,
    baseUrl,
    deviceId,
    platform,
    sdkVersion: version,
    sdkBinding: 'electron',
    appIdentifier: 'ai.runanywhere.electron',
    appName: 'RunAnywhere Electron',
    appVersion: version,
    phase1Bytes: phase1,
    phase2Bytes: phase2,
  });
  return deviceId || null;
}

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
      // Desktop control plane: telemetry + auth via the two-phase init. Prefer the
      // persistent device id commons mints (what the backend keys on) over the
      // locally-minted fallback above. Best-effort — never blocks local inference.
      try {
        const persistentId = await runControlPlane(backend, options, environment, version);
        if (persistentId) deviceId = persistentId;
      } catch {
        // telemetry/auth failure must not block local inference
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
    capabilities: () => Promise.resolve(capabilitiesSnapshot()),
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
