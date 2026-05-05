/**
 * RunAnywhere Web SDK - Main Entry Point
 *
 * The public API for the RunAnywhere Web SDK.
 * Core is pure TypeScript — no WASM. Backend packages ship their own WASM
 * and install proto-byte adapters via `setRunanywhereModule(...)`.
 *
 * After the V2 cleanup, model lifecycle, registry, downloads, and provider
 * routing are all owned by the commons C ABI through the proto-byte adapters.
 * This file no longer dispatches through ExtensionPoint or ModelManager.
 *
 * Usage:
 *   import { RunAnywhere } from '@runanywhere/web';
 *
 *   await RunAnywhere.initialize({ environment: 'development' });
 *   // Backend packages register their WASM module via setRunanywhereModule();
 *   // typed adapters (ModelLifecycleAdapter, DownloadAdapter, ...) become live.
 */

import { SDKEnvironment } from '@runanywhere/proto-ts/model_types';
import type { LLMGenerationOptions, LLMGenerationResult } from '@runanywhere/proto-ts/llm_options';
import type { STTOutput } from '@runanywhere/proto-ts/stt_options';
import type { TTSOutput } from '@runanywhere/proto-ts/tts_options';
import type { VADResult } from '@runanywhere/proto-ts/vad_options';
import { SDKEventType } from '../types/enums';
import type { SDKInitOptions } from '../types/models';
import type { LLMStreamingResult } from '../types/index';
import { EventBus } from '../Foundation/EventBus';
import { SDKLogger, LogLevel } from '../Foundation/SDKLogger';
import { LocalFileStorage } from '../Infrastructure/LocalFileStorage';
import { OPFSStorage } from '../Infrastructure/OPFSStorage';
import { SDKErrorCode, SDKException } from '../Foundation/SDKException';
import { Runtime } from '../Foundation/RuntimeConfig';
import { solutions as SolutionsCapability } from './Extensions/RunAnywhere+Solutions';
import { LoRA as LoRACapability } from './Extensions/RunAnywhere+LoRA';
import * as RAGExt from './Extensions/RunAnywhere+RAG';
import * as VoiceAgentExt from './Extensions/RunAnywhere+VoiceAgent';
import { Downloads as DownloadsCapability } from './Extensions/RunAnywhere+Downloads';
import { SDKEvents as SDKEventsCapability } from './Extensions/RunAnywhere+SDKEvents';
import { ModelRegistry as ModelRegistryCapability } from './Extensions/RunAnywhere+ModelRegistry';
import { ModelLifecycle as ModelLifecycleCapability } from './Extensions/RunAnywhere+ModelLifecycle';
import { Hardware as HardwareCapability } from './Extensions/RunAnywhere+Hardware';
import {
  TextGeneration as TextGenerationCapability,
  generateStructuredStream,
  extractStructuredOutput,
} from './Extensions/RunAnywhere+TextGeneration';
import { StructuredOutput as StructuredOutputCapability } from './Extensions/RunAnywhere+StructuredOutput';
import { ToolCalling as ToolCallingCapability } from './Extensions/RunAnywhere+ToolCalling';
import { Logging as LoggingCapability } from './Extensions/RunAnywhere+Logging';
import {
  STT as STTCapability,
  transcribe as transcribeImpl,
  type TranscribeOptions,
} from './Extensions/RunAnywhere+STT';
import {
  TTS as TTSCapability,
  synthesize as synthesizeImpl,
  type SynthesizeOptions,
} from './Extensions/RunAnywhere+TTS';
import {
  VAD as VADCapability,
  detectVoice as detectVoiceImpl,
  type DetectVoiceOptions,
} from './Extensions/RunAnywhere+VAD';
import { ModelRegistryAdapter } from '../Adapters/ModelRegistryAdapter';
import { ModelLifecycleAdapter } from '../Adapters/ModelLifecycleAdapter';
import { DownloadAdapter } from '../Adapters/DownloadAdapter';
import { SDKEventStreamAdapter } from '../Adapters/SDKEventStreamAdapter';
import { StorageAdapter } from '../Adapters/StorageAdapter';
import { HTTPAdapter } from '../Adapters/HTTPAdapter';
import { LlmThinking } from '../Features/LLM/LlmThinking';
import { SDK_VERSION } from '../Foundation/Version';
import { tryRunanywhereModule } from '../runtime/EmscriptenModule';

/**
 * Persistent storage backend active for the current SDK session.
 * - `fsAccess`: File System Access API (user picked a real directory, Chrome 122+).
 * - `opfs`: Origin Private File System (default persistent fallback).
 * - `memory`: No persistent backend — models live in volatile MEMFS.
 */
export type StorageBackend = 'fsAccess' | 'opfs' | 'memory';

const logger = new SDKLogger('RunAnywhere');

// ---------------------------------------------------------------------------
// Internal State
// ---------------------------------------------------------------------------

let _isInitialized = false;
let _initOptions: SDKInitOptions | null = null;
let _initializingPromise: Promise<void> | null = null;
let _localFileStorage: LocalFileStorage | null = null;
let _deviceId: string | null = null;

// Phase 2 (services) init state — mirrors Swift's
// `hasCompletedServicesInit` + `hasCompletedHTTPSetup` split.
let _hasCompletedServicesInit = false;
let _servicesInitPromise: Promise<void> | null = null;

/** Generate (and cache) a stable device ID, matching Swift's UUID-style. */
function generateDeviceId(): string {
  if (typeof crypto !== 'undefined' && typeof crypto.randomUUID === 'function') {
    return crypto.randomUUID();
  }
  return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, (c) => {
    const r = (Math.random() * 16) | 0;
    const v = c === 'x' ? r : (r & 0x3) | 0x8;
    return v.toString(16);
  });
}

/** Persist + retrieve a device ID across SDK sessions (best-effort localStorage). */
function ensureDeviceId(): string {
  if (_deviceId) return _deviceId;
  try {
    if (typeof localStorage !== 'undefined') {
      const stored = localStorage.getItem('runanywhere.deviceId');
      if (stored) {
        _deviceId = stored;
        return stored;
      }
    }
  } catch { /* ignore */ }
  const id = generateDeviceId();
  try {
    if (typeof localStorage !== 'undefined') {
      localStorage.setItem('runanywhere.deviceId', id);
    }
  } catch { /* ignore */ }
  _deviceId = id;
  return id;
}

// ---------------------------------------------------------------------------
// RunAnywhere Public API
// ---------------------------------------------------------------------------

export const RunAnywhere = {
  // =========================================================================
  // SDK State
  // =========================================================================

  get isInitialized(): boolean {
    return _isInitialized;
  },

  /** Mirror Swift `RunAnywhere.isSDKInitialized` (Phase 1 complete). */
  get isSDKInitialized(): boolean {
    return _isInitialized;
  },

  /** Mirror Swift `RunAnywhere.areServicesReady` (Phase 2 complete). */
  get areServicesReady(): boolean {
    return _hasCompletedServicesInit;
  },

  /** Mirror Swift `RunAnywhere.isActive`. */
  get isActive(): boolean {
    return _isInitialized && _initOptions !== null;
  },

  get version(): string {
    return SDK_VERSION;
  },

  get environment(): SDKEnvironment | null {
    return _initOptions?.environment ?? null;
  },

  get events(): EventBus {
    return EventBus.shared;
  },

  /**
   * Stable device identifier. On the Web SDK this is persisted in
   * `localStorage` so it survives reloads.
   */
  get deviceId(): string {
    return ensureDeviceId();
  },

  /**
   * Returns true if the SDK currently holds a non-expired access token.
   *
   * Delegates to commons `rac_auth_is_authenticated()` via the WASM module
   * once a backend has installed it. Before any backend registers, no WASM
   * module exists and the SDK cannot be authenticated — this returns false.
   *
   * NOTE: the Web SDK does not yet call `rac_auth_init` + the
   * authenticate/refresh flow from the browser (no UI surface registers
   * credentials), so this will typically return false until a future auth
   * flow lands. The implementation here is the canonical bridge, so once
   * auth wiring arrives, this call will reflect the real state without
   * further changes.
   */
  isAuthenticated(): boolean {
    const mod = tryRunanywhereModule();
    if (!mod) return false;
    const fn = (mod as unknown as {
      _rac_auth_is_authenticated?: () => number;
    })._rac_auth_is_authenticated;
    if (typeof fn !== 'function') return false;
    try {
      return fn() !== 0;
    } catch {
      return false;
    }
  },

  /** Runtime configuration surface (acceleration mode etc.). */
  get runtime(): typeof Runtime {
    return Runtime;
  },

  /** Convenience setter for the preferred acceleration. */
  async setRuntime(mode: 'cpu' | 'webgpu' | 'auto'): Promise<void> {
    if (mode === 'auto') {
      Runtime.preferred = 'auto';
      return;
    }
    await Runtime.setAcceleration(mode);
  },

  // =========================================================================
  // Initialization (pure TypeScript — no WASM)
  // =========================================================================

  /**
   * Initialize the RunAnywhere SDK.
   *
   * This only initializes the TypeScript infrastructure:
   *   1. Configure logging
   *   2. Restore local file storage (if previously configured)
   *
   * WASM and proto-byte adapters are installed by backend packages once
   * their module loads.
   */
  async initialize(options: SDKInitOptions = {}): Promise<void> {
    if (_isInitialized) {
      logger.debug('Already initialized');
      return;
    }

    if (_initializingPromise) {
      logger.debug('Initialization already in progress, awaiting...');
      return _initializingPromise;
    }

    _initializingPromise = (async () => {
      try {
        const env = options.environment ?? SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
        _initOptions = { ...options, environment: env };

        if (options.debug) {
          SDKLogger.level = LogLevel.Debug;
        }

        logger.info(`Initializing RunAnywhere Web SDK (${env})...`);

        if (typeof ReadableStream === 'undefined') {
          throw SDKException.fromCode(
            SDKErrorCode.InitializationFailed,
            'ReadableStream is not available in this environment. ' +
            'The RunAnywhere Web SDK requires the Fetch Streams API ' +
            '(Chrome 43+, Firefox 65+, Safari 14.1+, Edge 79+).',
          );
        }

        try {
          await RunAnywhere.restoreLocalStorage();
        } catch (err) {
          logger.warning(`Failed to restore local storage: ${err instanceof Error ? err.message : String(err)}`);
        }

        _isInitialized = true;

        ensureDeviceId();

        logger.info('RunAnywhere Web SDK initialized successfully');
        EventBus.shared.emit('sdk.initialized', SDKEventType.Initialization, {
          environment: env,
        });

        void RunAnywhere.completeServicesInitialization().catch((err) => {
          logger.warning(
            `Phase 2 init failed (non-fatal): ${err instanceof Error ? err.message : String(err)}`,
          );
        });
      } finally {
        _initializingPromise = null;
      }
    })();

    return _initializingPromise;
  },

  /**
   * Complete the Phase 2 (services) initialization. Mirror of Swift's
   * `RunAnywhere.completeServicesInitialization()`. Idempotent — concurrent
   * callers share a single in-flight promise.
   */
  async completeServicesInitialization(): Promise<void> {
    if (_hasCompletedServicesInit) return;
    if (_servicesInitPromise) return _servicesInitPromise;

    _servicesInitPromise = (async () => {
      try {
        _hasCompletedServicesInit = true;
        logger.debug('Services initialization complete (Phase 2)');
      } finally {
        _servicesInitPromise = null;
      }
    })();
    return _servicesInitPromise;
  },

  /**
   * Internal-style guard used by extensions that need a fully-initialized SDK.
   */
  async ensureServicesReady(): Promise<void> {
    if (_hasCompletedServicesInit) return;
    return RunAnywhere.completeServicesInitialization();
  },

  // =========================================================================
  // Local File Storage (persistent model storage)
  // =========================================================================

  get isLocalStorageSupported(): boolean {
    return LocalFileStorage.isSupported;
  },

  get isLocalStorageReady(): boolean {
    return _localFileStorage?.isReady ?? false;
  },

  get hasLocalStorageHandle(): boolean {
    return _localFileStorage?.hasStoredHandle ?? false;
  },

  get localStorageDirectoryName(): string | null {
    return _localFileStorage?.directoryName ?? LocalFileStorage.storedDirectoryName;
  },

  /**
   * Which persistent storage backend is currently active.
   *
   * Resolution order:
   *   1. `fsAccess` — File System Access API with an active directory handle.
   *   2. `opfs` — Origin Private File System (default persistent fallback).
   *   3. `memory` — Neither backend is available; models live only in MEMFS.
   */
  get storageBackend(): StorageBackend {
    if (LocalFileStorage.isSupported && _localFileStorage?.isReady) {
      return 'fsAccess';
    }
    if (OPFSStorage.isSupported) {
      return 'opfs';
    }
    return 'memory';
  },

  async chooseLocalStorageDirectory(): Promise<boolean> {
    if (!LocalFileStorage.isSupported) {
      logger.warning('File System Access API not supported — using browser storage (OPFS)');
      return false;
    }

    if (!_localFileStorage) {
      _localFileStorage = new LocalFileStorage();
    }

    const success = await _localFileStorage.chooseDirectory();
    if (success) {
      EventBus.shared.emit('storage.localDirectorySelected', SDKEventType.Storage, {
        directoryName: _localFileStorage.directoryName,
      });
    }
    return success;
  },

  async restoreLocalStorage(): Promise<boolean> {
    if (!LocalFileStorage.isSupported) return false;

    if (!_localFileStorage) {
      _localFileStorage = new LocalFileStorage();
    }

    const success = await _localFileStorage.restoreDirectory();
    if (success) {
      logger.info(`Local storage restored: ${_localFileStorage.directoryName}`);
    }
    return success;
  },

  async requestLocalStorageAccess(): Promise<boolean> {
    if (!_localFileStorage) return false;
    return _localFileStorage.requestAccess();
  },

  // =========================================================================
  // Top-level convenience verbs that delegate to the proto-byte adapters.
  // =========================================================================

  /** Generate text via the LLM proto adapter. */
  async generate(
    prompt: string,
    options?: Partial<LLMGenerationOptions>,
  ): Promise<LLMGenerationResult> {
    return TextGenerationCapability.generate({
      ...(options ?? {}),
      prompt,
    } as Partial<LLMGenerationOptions>);
  },

  async generateStream(
    prompt: string,
    options?: Partial<LLMGenerationOptions>,
  ): Promise<LLMStreamingResult> {
    return TextGenerationCapability.generateStream({
      ...(options ?? {}),
      prompt,
    } as Partial<LLMGenerationOptions>);
  },

  async chat(
    prompt: string,
    options?: Partial<LLMGenerationOptions>,
  ): Promise<string> {
    return TextGenerationCapability.chat(prompt, options);
  },

  /**
   * Transcribe audio. Auto-creates an STT component handle, loads the current
   * STT model from lifecycle (if no `modelPath` is supplied), runs transcription,
   * and tears the handle down. Use `RunAnywhere.stt.*` directly when you want
   * to reuse a handle across multiple calls.
   */
  async transcribe(
    audio: Uint8Array | Float32Array,
    options?: TranscribeOptions,
  ): Promise<STTOutput> {
    return transcribeImpl(audio, options);
  },

  /**
   * Synthesize speech. Auto-creates a TTS component handle, loads the current
   * TTS voice from lifecycle (if no `voicePath` is supplied), synthesizes, and
   * tears the handle down.
   */
  async synthesize(
    text: string,
    options?: SynthesizeOptions,
  ): Promise<TTSOutput> {
    return synthesizeImpl(text, options);
  },

  /**
   * Detect speech activity in an audio buffer. Auto-creates a VAD handle,
   * configures + initializes it, runs one process pass, and destroys the handle.
   */
  async detectVoice(
    audio: Float32Array,
    options?: DetectVoiceOptions,
  ): Promise<VADResult> {
    return detectVoiceImpl(audio, options);
  },

  // Thinking token utilities — canonical §3 helpers.
  /** Extract thinking and response from LLM output (§3). */
  extractThinkingTokens(text: string): { response: string; thinking: string | null } {
    return LlmThinking.extract(text);
  },

  /** Strip all thinking tokens from LLM output (§3). */
  stripThinkingTokens(text: string): string {
    return LlmThinking.strip(text);
  },

  /** Split thinking and response sections (§3). */
  splitThinkingAndResponse(text: string): { thinking: string; response: string } {
    const { thinking, response } = LlmThinking.extract(text);
    return { thinking: thinking ?? '', response };
  },

  // RAG — flat (RAG is stateless from public-API view).
  ragCreatePipeline: RAGExt.ragCreatePipeline,
  ragDestroyPipeline: RAGExt.ragDestroyPipeline,
  ragIngest: RAGExt.ragIngest,
  ragAddDocumentsBatch: RAGExt.ragAddDocumentsBatch,
  ragQuery: RAGExt.ragQuery,
  ragClearDocuments: RAGExt.ragClearDocuments,
  ragGetDocumentCount: RAGExt.ragGetDocumentCount,
  ragGetStatistics: RAGExt.ragGetStatistics,
  ragListDocuments: RAGExt.ragListDocuments,
  ragRemoveDocument: RAGExt.ragRemoveDocument,
  ragGetCapabilities: RAGExt.ragGetCapabilities,
  createDefaultRAGConfiguration: RAGExt.createDefaultRAGConfiguration,
  getRAGAvailability: RAGExt.getRAGAvailability,
  isRAGAvailable: RAGExt.isRAGAvailable,

  // LLM structured stream + extraction — canonical §3 flat verbs.
  generateStructuredStream,
  extractStructuredOutput,

  // VoiceAgent C-ABI parity.
  initializeVoiceAgent: VoiceAgentExt.initializeVoiceAgent,
  initializeVoiceAgentWithLoadedModels: VoiceAgentExt.initializeVoiceAgentWithLoadedModels,
  isVoiceAgentReady: VoiceAgentExt.isVoiceAgentReady,
  getVoiceAgentComponentStates: VoiceAgentExt.getVoiceAgentComponentStates,
  areAllVoiceComponentsReady: VoiceAgentExt.areAllVoiceComponentsReady,
  processVoiceTurn: VoiceAgentExt.processVoiceTurn,
  voiceAgentTranscribe: VoiceAgentExt.voiceAgentTranscribe,
  voiceAgentGenerateResponse: VoiceAgentExt.voiceAgentGenerateResponse,
  voiceAgentSynthesizeSpeech: VoiceAgentExt.voiceAgentSynthesizeSpeech,
  streamVoiceAgent: VoiceAgentExt.streamVoiceAgent,
  cleanupVoiceAgent: VoiceAgentExt.cleanupVoiceAgent,
  getVoiceAgentAvailability: VoiceAgentExt.getVoiceAgentAvailability,
  isVoiceAgentAvailable: VoiceAgentExt.isVoiceAgentAvailable,

  // =========================================================================
  // Solutions namespace
  // =========================================================================

  solutions: SolutionsCapability,

  // =========================================================================
  // Namespace extensions — proto-byte adapter facades.
  // =========================================================================

  /** C++-owned download workflow — plan/start/cancel/resume/progress. */
  downloads: DownloadsCapability,

  /** C++ SDKEvent proto stream — subscribe/publish/poll/failure. */
  sdkEvents: SDKEventsCapability,

  /** C++ model registry proto bridge — list/query/listDownloaded/get/mutate. */
  modelRegistry: ModelRegistryCapability,

  /** C++ model lifecycle proto bridge — load/unload/current/snapshot. */
  modelLifecycle: ModelLifecycleCapability,

  /** Text generation — `RunAnywhere.textGeneration.generate(options)` etc. */
  textGeneration: TextGenerationCapability,

  /** Structured output — `RunAnywhere.structuredOutput.generate(prompt, schema)` */
  structuredOutput: StructuredOutputCapability,

  /** Tool calling — `RunAnywhere.toolCalling.generate(prompt, tools)` */
  toolCalling: ToolCallingCapability,

  /** Speech-to-text — `RunAnywhere.stt.create()` / `transcribe(handle, audio)` etc. */
  stt: STTCapability,

  /** Text-to-speech — `RunAnywhere.tts.create()` / `synthesize(handle, text)` etc. */
  tts: TTSCapability,

  /** Voice activity detection — `RunAnywhere.vad.create()` / `process(handle, samples)` etc. */
  vad: VADCapability,

  /** Logging control — `RunAnywhere.logging.setLevel(LogLevel.Debug)` */
  logging: LoggingCapability,

  /** LoRA adapter management — `RunAnywhere.lora.apply(handle, request)` etc. */
  lora: LoRACapability,

  /** RAG retrieval pipeline — `RunAnywhere.rag.query(...)` etc. */
  rag: RAGExt.RAG,

  /** Hardware profile — `RunAnywhere.hardware.getProfile()` etc. */
  hardware: HardwareCapability,

  // =========================================================================
  // Shutdown
  // =========================================================================

  shutdown(): void {
    logger.info('Shutting down RunAnywhere Web SDK...');

    // Clear WASM adapter singletons so stale module refs don't linger.
    HTTPAdapter.clearDefaultModule();
    ModelRegistryAdapter.clearDefaultModule();
    ModelLifecycleAdapter.clearDefaultModule();
    DownloadAdapter.clearDefaultModule();
    SDKEventStreamAdapter.clearDefaultModule();
    StorageAdapter.clearDefaultHandles();

    EventBus.reset();

    _isInitialized = false;
    _initOptions = null;
    _initializingPromise = null;
    _localFileStorage = null;
    _hasCompletedServicesInit = false;
    _servicesInitPromise = null;

    logger.info('RunAnywhere Web SDK shut down');
  },

  reset(): void {
    RunAnywhere.shutdown();
  },
};
