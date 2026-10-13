// facade.ts — assembles the v3 surface over a backend.
//
// `createRunAnywhere` is called exactly twice: once with `NativeBackend` for the
// main process and once with `RpcBackend` in the preload. Both produce the same
// object shape, which is why `RunAnywhere.llm.generate` and
// `window.runanywhere.llm.generate` are the same function written once.

import { catalogEntries, catalogModelInfo } from '../catalog';
import { ErrorCategory, SDKException, asSDKException } from '../errors';
import { bindAudioBackend } from '../audio';
import { ModelAbi } from './model-abi';
import type { ComponentLifecycleSnapshot, SDKComponent } from './model-abi';
import {
  IMAGES_GAP,
  createImagesNamespace,
  createLoraNamespace,
  createModelsNamespace,
  createSegmentationNamespace,
} from './assets';
import type { ImagesNamespace, LoraNamespace, ModelsNamespace, SegmentationNamespace } from './assets';
import type { AuthState, RaBackend } from './backend';
import {
  backendsForRegistry,
  unavailableCapabilities,
  type EngineRegistrySnapshot,
} from '../backend/engines';
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
import { createStorageNamespace } from './storage';
import type { StorageNamespace } from './storage';
import { createLoggingNamespace } from './logging';
import type { LoggingNamespace } from './logging';
import { createLlmNamespace, createVlmNamespace } from './text';
import type { LlmNamespace, VlmNamespace } from './text';
import { AudioFormat, Environment, InferenceFramework, audio, image, ragDocument } from './types';
import { SDKEnvironment } from '@runanywhere/proto-ts/model_types';
import {
  SdkInitPhase1Request,
  SdkInitPhase2Request,
  SdkInitResult,
} from '@runanywhere/proto-ts/sdk_init';
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
  /**
   * Development-mode device registration token. Commons passes it on the
   * registration payload only when `environment` is development, and ignores it
   * otherwise. Nothing in the SDK can mint one — a build that has no token
   * leaves this unset rather than sending an empty string.
   */
  buildToken?: string;
}

/**
 * How the control plane ended up, for an app that wants to say so in its UI.
 *
 * - `disabled` — this build has no control plane, or no credentials were given.
 *   Local inference is fully usable; there is nothing to retry.
 * - `authenticated` — the handshake completed and the token is live.
 * - `offline` — the handshake ran and could not reach the backend. Tokens from a
 *   previous run may still be valid; {@link AuthNamespace.retry} is the fix.
 * - `rejected` — the backend answered and refused. Usually a bad API key, and
 *   retrying with the same credentials will fail the same way.
 */
export type AuthStatus = 'disabled' | 'authenticated' | 'offline' | 'rejected';

/** {@link AuthState} plus how initialization went. */
export interface AuthInfo extends AuthState {
  status: AuthStatus;
  /** Commons' warning or error text; empty when there is nothing to say. */
  message: string;
}

/**
 * Control-plane authentication. An Electron platform extra, like
 * {@link SecureStore} — the cross-SDK spec has no auth namespace, but a desktop
 * app has to be able to tell an offline run from a rejected key.
 */
export interface AuthNamespace {
  /** Current token, expiry, and device registration. */
  state(): Promise<AuthInfo>;
  /** Re-run the HTTP setup an offline start skipped, then report the new state. */
  retry(): Promise<AuthInfo>;
  /** Forget the stored tokens; the next `initialize` authenticates from scratch. */
  clear(): Promise<void>;
}

/** Telemetry control. Batches also flush on a timer and at shutdown. */
export interface TelemetryNamespace {
  /** Send what is queued now — useful before the app quits on its own terms. */
  flush(): Promise<void>;
}

/**
 * Platform secure storage for small credentials. An Electron platform extra,
 * not part of the cross-SDK spec — the other SDKs expose their platform
 * keystore differently.
 *
 * How well it is protected is a property of the platform adapter, and this is
 * where that is said plainly rather than assumed: on Win32 values are DPAPI
 * ciphertext, encrypted with the current user's key; on macOS and Linux they
 * are 0600 files inside a 0700 directory — unreadable by another local user,
 * but NOT encrypted at rest. Treat it as "owner-only", not as a keychain.
 */
export interface SecureStore {
  /** Store `value` under `key`. */
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
  /**
   * Set the Hugging Face bearer token model downloads authenticate with, so a
   * gated or private repo stops answering 401.
   *
   * Pass `null` to fall back to the environment lookup commons resolves —
   * `HF_TOKEN`, then `$HF_TOKEN_PATH`, then `$HF_HOME/token`, then
   * `~/.cache/huggingface/token`, the order `huggingface_hub` uses, so
   * `hf auth login` is honoured. Pass an empty string to clear the token and
   * disable that fallback too.
   *
   * The token is held in the platform secure store, not in settings, and is
   * re-applied on the next {@link initialize} so a gated model still downloads
   * after a cold start. It is attached only to https requests whose host is
   * exactly `huggingface.co` or `hf.co` — never to a CDN or LFS redirect target.
   */
  setHfToken(token: string | null): Promise<void>;
  /**
   * What commons' lifecycle store holds for one component right now.
   *
   * An unloaded component is an answer rather than a failure: the snapshot comes
   * back with `COMPONENT_LIFECYCLE_STATE_NOT_LOADED` and no model id.
   */
  componentLifecycleSnapshot(component: SDKComponent): Promise<ComponentLifecycleSnapshot>;

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
  /** What is on disk and what it costs to reclaim; see {@link StorageNamespace}. */
  readonly storage: StorageNamespace;
  /** Log level, sinks, and the record stream; see {@link LoggingNamespace}. */
  readonly logging: LoggingNamespace;
  /** Electron platform extra; see {@link SecureStore}. */
  readonly secure: SecureStore;
  /** Electron platform extra; see {@link AuthNamespace}. */
  readonly auth: AuthNamespace;
  /** Electron platform extra; see {@link TelemetryNamespace}. */
  readonly telemetry: TelemetryNamespace;

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
 * Dual path:
 *   • Fat addon — backends are compile-linked; {@link backendsForRegistry}
 *     returns the three known frameworks regardless of the registry list.
 *   • Thin addon — backends come from `listPlugins()` after main-process
 *     `*.register()` + RUNANYWHERE_PLUGIN_PATHS. Core-alone → `backends: []`;
 *     model load throws typed {@link SDKException.noBackendEngines}.
 * `images` stays unavailable until a diffusion plugin exists.
 */
function capabilitiesSnapshot(registry: EngineRegistrySnapshot): SDKCapabilities {
  const backends = [...backendsForRegistry(registry)];
  const modalities = modalitiesForBackends(backends);
  const has = (name: string): boolean => modalities.includes(name);
  return {
    modalities,
    backends,
    // Only formats this SDK can actually round-trip: raw PCM for live streams,
    // plus WAV through the built-in RIFF codec (audio.ts's encodeWav/decodeWav).
    audioFormats: [AudioFormat.PCM, AudioFormat.WAV],
    streaming: {
      llm: has('llm'),
      vlm: has('vlm'),
      stt: has('stt'),
      tts: has('tts'),
      vad: has('vad'),
      rag: has('rag'),
      images: false,
    },
    tools: {
      registry: has('llm'),
      // llm.tools runs one grammar-constrained selection round at a time (text.ts's runToolLoop).
      parallel: false,
      cancellation: has('llm'),
    },
    rag: {
      // Each rag.open() gets its own native session handle (native-backend.ts's ragSessions map).
      multiSession: has('rag'),
      persistent: has('rag'),
    },
    // Static gaps (features this SDK has not built yet) plus the runtime ones
    // (backends that were refused registration on this machine). Both are the
    // same question to an app deciding whether to show a button.
    unavailable: [
      ...UNAVAILABLE_CAPABILITIES,
      ...unavailableCapabilities(registry.unavailablePlugins),
    ],
  };
}

/** Modalities reachable from the registered inference frameworks. */
function modalitiesForBackends(backends: readonly InferenceFramework[]): string[] {
  const mods = new Set<string>();
  for (const framework of backends) {
    switch (framework) {
      case InferenceFramework.LLAMA_CPP:
        mods.add('llm');
        mods.add('vlm');
        mods.add('lora');
        mods.add('rag');
        break;
      case InferenceFramework.ONNX:
        mods.add('embeddings');
        mods.add('rerank');
        mods.add('diarization');
        mods.add('segmentation');
        break;
      case InferenceFramework.SHERPA:
        mods.add('stt');
        mods.add('tts');
        mods.add('vad');
        break;
      case InferenceFramework.QHEXRT:
        mods.add('llm');
        mods.add('vlm');
        mods.add('stt');
        mods.add('tts');
        break;
      case InferenceFramework.COREML:
        // NeuRT serves LLM + STT + DIFFUSION; diffusion has no Electron facade
        // (no browser/desktop engine publishes RAC_PRIMITIVE_DIFFUSION here).
        mods.add('llm');
        mods.add('stt');
        break;
      default: {
        const _exhaustive: never = framework;
        void _exhaustive;
        break;
      }
    }
  }
  return [...mods];
}

async function readEngineRegistry(backend: RaBackend): Promise<EngineRegistrySnapshot> {
  const [thinAddon, pluginNames, unavailablePlugins] = await Promise.all([
    backend.isThinAddon(),
    backend.listPlugins(),
    backend.listUnavailablePlugins(),
  ]);
  return { thinAddon, pluginNames, unavailablePlugins };
}

// A bearer token is a credential, so it lives in the platform secure store and
// never in a settings file next to the app's window geometry. What that store
// is differs by platform and this SDK does not overstate it: Win32 is DPAPI
// (encrypted with the current user's key), while the POSIX adapter is an
// owner-only file store — 0600 files in a 0700 directory, restricted to the
// user but NOT encrypted at rest (see native/posix_platform_adapter.cpp).
const HF_TOKEN_KEY = 'runanywhere.hfToken';

/** The host OS as the backend's platform enum (macos/linux/windows) — NOT the
 * SDK binding name. The binding ("electron") is reported separately as sdk_binding. */
function osPlatform(): string {
  if (process.platform === 'darwin') return 'macos';
  if (process.platform === 'win32') return 'windows';
  return 'linux';
}

/** What the control plane did during `initialize`, kept so `auth.state()` can
 * explain a run that never reached the backend. */
interface ControlPlaneOutcome {
  status: AuthStatus;
  message: string;
  deviceId: string | null;
}

const CONTROL_PLANE_DISABLED: ControlPlaneOutcome = {
  status: 'disabled',
  message: '',
  deviceId: null,
};

/** Read an SdkInitResult the way commons means it: `httpApplicable` says whether
 * a control plane was reachable in principle, `hasCompletedHttpSetup` whether the
 * handshake actually landed, and a populated `error` means the backend refused. */
function outcomeOf(resultBytes: Uint8Array, deviceId: string): ControlPlaneOutcome {
  const result = SdkInitResult.decode(resultBytes);
  if (result.error) {
    const failure = SDKException.fromProto(result.error);
    return {
      status: failure.category === ErrorCategory.ERROR_CATEGORY_NETWORK ? 'offline' : 'rejected',
      message: failure.message,
      deviceId: deviceId || null,
    };
  }
  if (!result.httpApplicable) {
    return { status: 'disabled', message: result.warning, deviceId: deviceId || null };
  }
  return {
    status: result.hasCompletedHttpSetup ? 'authenticated' : 'offline',
    message: result.warning,
    deviceId: deviceId || null,
  };
}

/** Run the desktop two-phase init (telemetry + auth) when creds allow. Never
 * throws: the SDK stays fully usable offline, and the outcome is reported through
 * `auth.state()` rather than swallowed. */
async function runControlPlane(
  backend: RaBackend,
  options: InitializeOptions,
  environment: Environment,
  version: string
): Promise<ControlPlaneOutcome> {
  if (!(await backend.hasControlPlane())) {
    return {
      ...CONTROL_PLANE_DISABLED,
      message:
        options.apiKey || options.baseUrl
          ? 'apiKey/baseUrl supplied but this build has no desktop control plane ' +
            '(RAC_DESKTOP_ADAPTER=OFF): no auth or telemetry'
          : '',
    };
  }
  const isProd = environment === Environment.PRODUCTION;
  let baseUrl = (options.baseUrl ?? '').trim();
  if (!baseUrl && !isProd) baseUrl = await backend.devStagingBaseUrl();
  const apiKey = (options.apiKey ?? '').trim();
  if (!baseUrl) return { ...CONTROL_PLANE_DISABLED, message: 'no control-plane base URL' };
  if (isProd && !apiKey) {
    return { ...CONTROL_PLANE_DISABLED, message: 'production needs an apiKey' };
  }

  const deviceId = await backend.devicePersistentId();
  const platform = osPlatform();
  const protoEnv = isProd
    ? SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION
    : SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
  const phase1 = SdkInitPhase1Request.encode({
    environment: protoEnv,
    apiKey,
    baseUrl,
    deviceId,
    platform,
    sdkVersion: version,
  }).finish();
  // Commons only forwards the build token in development; elsewhere it sends
  // nothing rather than an empty credential.
  const phase2 = SdkInitPhase2Request.encode({
    buildToken: options.buildToken ?? '',
  }).finish();
  try {
    const resultBytes = await backend.configureControlPlane({
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
    return outcomeOf(resultBytes, deviceId);
  } catch (error) {
    const failure = asSDKException(error);
    return {
      status: failure.category === ErrorCategory.ERROR_CATEGORY_NETWORK ? 'offline' : 'rejected',
      message: failure.message,
      deviceId: deviceId || null,
    };
  }
}

/**
 * Push every staged catalog entry into the commons model registry.
 *
 * Best-effort per entry: one malformed row must not stop the SDK from coming up,
 * and a row that fails to register simply will not list.
 */
async function seedCatalog(backend: RaBackend): Promise<void> {
  const entries = Object.entries(catalogEntries());
  if (!entries.length) return;
  const abi = new ModelAbi(backend);
  for (const [id, entry] of entries) {
    try {
      await abi.register(catalogModelInfo(id, entry));
    } catch {
      // A rejected row is visible through models.list() being short, which is a
      // better failure than refusing to initialize.
    }
  }
  // Relink the rows whose files are already on disk from a previous run. A
  // seeded row carries no local_path (see `catalogModelInfo`), so this is what
  // turns "declared" into "downloaded" — commons walks its own storage layout
  // and only links a row whose declared files are all present, which is why
  // `downloaded` now tracks bytes rather than the fact of being catalogued.
  try {
    await abi.discover({
      linkDownloaded: true,
      includeUserImports: true,
      includeBuiltIn: false,
      purgeInvalid: false,
      recursive: false,
      searchRoots: [],
    });
  } catch {
    // A failed sweep costs the app a `downloaded` flag until the next refresh(),
    // which is not a reason to fail initialization.
  }
}

/** Build the public surface over `backend`. */
export function createRunAnywhere(backend: RaBackend): RunAnywhereApi {
  // Audio DSP + embeddings math are owned by whichever process holds the
  // native addon. Binding here means preload/RpcBackend never resolveAddon.
  bindAudioBackend(backend);

  const hub = new SdkEventHub();

  let ready = false;
  let version = '';
  let deviceId = '';
  let environment: Environment = Environment.PRODUCTION;
  let initializing: Promise<void> | null = null;
  let controlPlane: ControlPlaneOutcome = CONTROL_PLANE_DISABLED;
  let baseDir: string | undefined;

  const requireReady = (): void => {
    if (!ready) throw SDKException.notInitialized('RunAnywhere');
  };

  // baseDir is read through a function because the namespaces are built before
  // `initialize` has been told where the store is.
  const deps = { backend, hub, requireReady, baseDir: () => baseDir };
  // Only for `componentLifecycleSnapshot`, which Swift puts on the facade rather
  // than on `models`; everything else about the registry goes through `models`.
  const modelAbi = new ModelAbi(backend);
  // `models` comes first because the llm namespace loads through it: commons
  // reads the language model out of its lifecycle store, and putting it there is
  // the models namespace's job.
  const models = createModelsNamespace(deps);
  const loadModel = async (id: string): Promise<void> => {
    await models.load(id);
  };
  const llm = createLlmNamespace({ ...deps, loadModel });
  const vlm = createVlmNamespace({ ...deps, loadModel });
  const stt = createSttNamespace(deps);
  const tts = createTtsNamespace(deps);
  const vad = createVadNamespace(deps);
  const embeddings = createEmbeddingsNamespace(deps);
  const rerank = createRerankNamespace(deps);
  const images = createImagesNamespace(deps);
  const diarization = createDiarizationNamespace(deps);
  const segmentation = createSegmentationNamespace(deps);
  const rag = createRagNamespace(deps);
  const lora = createLoraNamespace({ ...deps, models });
  const storage = createStorageNamespace(deps);
  // Diagnostics are usable before `initialize()`: a level set now is the level
  // the native load itself logs at, which is exactly when a start-up failure
  // needs to be visible.
  const logging = createLoggingNamespace(deps);
  const voice = createVoiceNamespace({
    ...deps,
    stt,
    tts,
    generate: (prompt, options) => llm.generateStream(prompt, options),
    llmCancel: () => backend.llmCancelProto().then(() => undefined),
  });

  async function initialize(options: InitializeOptions = {}): Promise<void> {
    if (ready) return;
    if (initializing) return initializing;
    environment = options.environment ?? Environment.PRODUCTION;
    baseDir = options.baseDir;
    initializing = (async () => {
      await backend.initialize({ baseDir: options.baseDir, secureDir: options.secureDir });
      version = await backend.version();
      // A token a previous run stored is re-applied before anything can reach
      // HuggingFace, so a gated model still downloads on a cold start instead of
      // making the app ask for the token again. Nothing stored leaves commons on
      // its own environment fallback, which is the right default.
      try {
        const storedToken = await backend.secureGet(HF_TOKEN_KEY);
        if (storedToken) await backend.hfTokenSet(storedToken);
      } catch {
        // No keystore, or an addon predating the binding: public repos still
        // download, and setHfToken() reports the real reason if one is set.
      }
      // The app's staged catalog becomes registry rows here, before anything can
      // list or load. Commons' registry is in-memory per process, so this runs on
      // every start — the same reseed Swift does in ModelCatalogBootstrap.
      await seedCatalog(backend);
      // READY IS SET HERE, AFTER SEEDING — not before it.
      //
      // `ready` was set immediately after `backend.version()`, which made
      // `isReady` true ~40 ms into a start whose registry stays EMPTY for several
      // more seconds while `seedCatalog` pushes one `abi.register` per row over
      // RPC. Every consumer that lists on ready — a model picker, a Models view,
      // an `await initialize()` followed by `models.list()` — therefore saw ZERO
      // models and had no way to know more were coming. Measured on the Electron
      // example app: `isReady()` true at 43 ms with `models.list()` == 0, then 28
      // rows at +5.3 s, with nothing in between to react to. It reads exactly like
      // "the catalog never reached the host", which is the wrong thing to go and
      // debug — the catalog arrives fine, just after the app was told to look.
      //
      // Initialization now costs what seeding costs, and the promise means what
      // its name says. Nothing between `backend.initialize` and here needs `ready`
      // (ModelAbi does not go through `requireReady`), so ordering it last is free.
      ready = true;
      // Commons owns the stable install identifier even when no control plane is configured.
      try {
        deviceId = await backend.devicePersistentId();
      } catch {
        // A secure store that is unavailable must not block local inference.
        deviceId = '';
      }
      // Desktop control plane: telemetry + auth via the two-phase init. Prefer the
      // persistent device id commons mints (what the backend keys on) over the
      // locally-minted fallback above. Never blocks local inference — a failure
      // lands in `auth.state()` instead of being swallowed.
      controlPlane = await runControlPlane(backend, options, environment, version);
      if (controlPlane.deviceId) deviceId = controlPlane.deviceId;
      if (controlPlane.status === 'offline' || controlPlane.status === 'rejected') {
        hub.emit({
          type: 'authFailed',
          status: controlPlane.status,
          message: controlPlane.message,
        });
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
    await backend.unload();
    await backend.shutdown();
    ready = false;
    version = '';
    deviceId = '';
    controlPlane = CONTROL_PLANE_DISABLED;
    hub.clear();
  }

  const secure: SecureStore = {
    set: (key, value) => backend.secureSet(key, value),
    get: (key) => backend.secureGet(key),
    delete: (key) => backend.secureDelete(key),
  };

  async function setHfToken(token: string | null): Promise<void> {
    requireReady();
    const normalized = token === null ? null : token.trim();
    // The backend applies it to both transfer paths before anything is
    // persisted, so a rejected addon binding fails here rather than leaving a
    // stored token that nothing is using.
    await backend.hfTokenSet(normalized);
    // A cleared token forgets the stored one rather than persisting the
    // clearing: the next run then resolves the environment chain again, which
    // is what a machine-wide `hf auth login` is supposed to mean.
    if (!normalized) {
      await backend.secureDelete(HF_TOKEN_KEY);
      return;
    }
    await backend.secureSet(HF_TOKEN_KEY, normalized);
  }

  /** Commons' live token state wins over whatever initialize saw: a token loaded
   * from the previous run is real even when this run never reached the network. */
  async function authInfo(): Promise<AuthInfo> {
    const state: AuthState = await backend.authState();
    const status: AuthStatus = state.authenticated ? 'authenticated' : controlPlane.status;
    return { ...state, status, message: state.authenticated ? '' : controlPlane.message };
  }

  const auth: AuthNamespace = {
    state: authInfo,
    async retry() {
      requireReady();
      if (controlPlane.status === 'disabled') return authInfo();
      try {
        controlPlane = outcomeOf(await backend.retryControlPlane(), deviceId);
      } catch (error) {
        const failure = asSDKException(error);
        controlPlane = {
          status: failure.category === ErrorCategory.ERROR_CATEGORY_NETWORK ? 'offline' : 'rejected',
          message: failure.message,
          deviceId: deviceId || null,
        };
      }
      return authInfo();
    },
    async clear() {
      requireReady();
      await backend.clearAuth();
    },
  };

  const telemetry: TelemetryNamespace = {
    flush: () => backend.telemetryFlush(),
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
    capabilities: async () => capabilitiesSnapshot(await readEngineRegistry(backend)),
    get events() {
      return hub.stream();
    },
    setHfToken,
    componentLifecycleSnapshot: (component) => {
      requireReady();
      return modelAbi.componentSnapshot(component);
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
    storage,
    logging,
    secure,
    auth,
    telemetry,
    audio,
    image,
    ragDocument,
  };
}
