/**
 * RunAnywhere Web SDK - Main Entry Point
 *
 * The public API for the RunAnywhere Web SDK.
 * Core is pure TypeScript — no WASM. Each backend package ships its own WASM:
 *   - @runanywhere/web-llamacpp (racommons-llamacpp.wasm)
 *   - @runanywhere/web-onnx (sherpa-onnx.wasm)
 *
 * Usage:
 *   import { RunAnywhere } from '@runanywhere/web';
 *   import { LlamaCPP } from '@runanywhere/web-llamacpp';
 *   import { ONNX } from '@runanywhere/web-onnx';
 *
 *   await RunAnywhere.initialize({ environment: 'development' });
 *   await LlamaCPP.register();
 *   await ONNX.register();
 */

import type { ModelCategory } from '../types/enums';
import { SDKEnvironment, SDKEventType } from '../types/enums';
import type { SDKInitOptions } from '../types/models';
import { EventBus } from '../Foundation/EventBus';
import { SDKLogger, LogLevel } from '../Foundation/SDKLogger';
import { ModelManager } from '../Infrastructure/ModelManager';
import type { CompactModelDef, ManagedModel, VLMLoader } from '../Infrastructure/ModelManager';
import { ExtensionRegistry } from '../Infrastructure/ExtensionRegistry';
import { ExtensionPoint } from '../Infrastructure/ExtensionPoint';
import { LocalFileStorage } from '../Infrastructure/LocalFileStorage';
import { OPFSStorage } from '../Infrastructure/OPFSStorage';
import { SDKErrorCode, SDKException } from '../Foundation/SDKException';
import { Runtime } from '../Foundation/RuntimeConfig';
import { solutions as SolutionsCapability } from './Extensions/RunAnywhere+Solutions';
import * as Convenience from './Extensions/RunAnywhere+Convenience';
import { LoRA as LoRACapability } from './Extensions/RunAnywhere+LoRA';
import * as RAGExt from './Extensions/RunAnywhere+RAG';
import * as VoiceAgentExt from './Extensions/RunAnywhere+VoiceAgent';
import { Storage as StorageCapability } from './Extensions/RunAnywhere+Storage';
import { Downloads as DownloadsCapability } from './Extensions/RunAnywhere+Downloads';
import { SDKEvents as SDKEventsCapability } from './Extensions/RunAnywhere+SDKEvents';
import { ModelRegistry as ModelRegistryCapability } from './Extensions/RunAnywhere+ModelRegistry';
import { ModelLifecycle as ModelLifecycleCapability } from './Extensions/RunAnywhere+ModelLifecycle';
import { PluginLoader as PluginLoaderCapability } from './Extensions/RunAnywhere+PluginLoader';
import { Hardware as HardwareCapability } from './Extensions/RunAnywhere+Hardware';
import { VAD as VADCapability } from './Extensions/RunAnywhere+VAD';
import {
  TextGeneration as TextGenerationCapability,
  generateStructuredStream,
  extractStructuredOutput,
} from './Extensions/RunAnywhere+TextGeneration';
import { StructuredOutput as StructuredOutputCapability } from './Extensions/RunAnywhere+StructuredOutput';
import { ToolCalling as ToolCallingCapability } from './Extensions/RunAnywhere+ToolCalling';
import { STT as STTCapability } from './Extensions/RunAnywhere+STT';
import { TTS as TTSCapability } from './Extensions/RunAnywhere+TTS';
import { VisionLanguage as VisionLanguageCapability } from './Extensions/RunAnywhere+VisionLanguage';
import { VLMModels as VLMModelsCapability } from './Extensions/RunAnywhere+VLMModels';
import {
  Diffusion as DiffusionCapability,
  generateImage,
  generateImageStream,
  loadDiffusionModel,
  unloadDiffusionModel,
  getIsDiffusionModelLoaded,
  cancelImageGeneration,
  getDiffusionCapabilities,
} from './Extensions/RunAnywhere+Diffusion';
import { ModelManagement as ModelManagementCapability } from './Extensions/RunAnywhere+ModelManagement';
import { ModelAssignments as ModelAssignmentsCapability } from './Extensions/RunAnywhere+ModelAssignments';
import { Frameworks as FrameworksCapability } from './Extensions/RunAnywhere+Frameworks';
import { Logging as LoggingCapability } from './Extensions/RunAnywhere+Logging';
import { ModelRegistryAdapter } from '../Adapters/ModelRegistryAdapter';
import { ModelLifecycleAdapter } from '../Adapters/ModelLifecycleAdapter';
import { DownloadAdapter } from '../Adapters/DownloadAdapter';
import { SDKEventStreamAdapter } from '../Adapters/SDKEventStreamAdapter';
import { StorageAdapter } from '../Adapters/StorageAdapter';
import { HTTPAdapter } from '../Adapters/HTTPAdapter';
import { LlmThinking } from '../Features/LLM/LlmThinking';

/**
 * Persistent storage backend active for the current SDK session.
 * - `fsAccess`: File System Access API (user picked a real directory, Chrome 122+).
 * - `opfs`: Origin Private File System (default persistent fallback).
 * - `memory`: No persistent backend — models live in volatile MEMFS.
 */
export type StorageBackend = 'fsAccess' | 'opfs' | 'memory';

/** Options for showOpenFilePicker. */
interface OpenFilePickerOptions {
  types?: Array<{ description?: string; accept?: { [k: string]: string[] } }>;
  multiple?: boolean;
}
/** Window with File System Access API (showOpenFilePicker). */
interface WindowWithFilePicker extends Window {
  showOpenFilePicker?(options?: OpenFilePickerOptions): Promise<FileSystemFileHandle[]>;
}

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
// `hasCompletedServicesInit` + `hasCompletedHTTPSetup` split. On Web today
// there is no backend authentication or device registration step, so Phase 2
// mostly just marks "ready to issue API calls". Wired so `ensureServicesReady()`
// is symmetric with the other SDKs and apps can opt into a future-real Phase 2
// without code changes.
let _hasCompletedServicesInit = false;
let _servicesInitPromise: Promise<void> | null = null;

/** Generate (and cache) a stable device ID, matching Swift's UUID-style. */
function generateDeviceId(): string {
  // Try Web Crypto first; fall back to a Math-based UUID v4 if unavailable.
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
    return '0.1.0';
  },

  get environment(): SDKEnvironment | null {
    return _initOptions?.environment ?? null;
  },

  get events(): EventBus {
    return EventBus.shared;
  },

  /**
   * Stable device identifier (Swift `RunAnywhere.deviceId`).
   * On the Web SDK this is persisted in `localStorage` so it survives reloads.
   */
  get deviceId(): string {
    return ensureDeviceId();
  },

  /** Authentication hook — Web has no backend auth yet, so always false. */
  isAuthenticated(): boolean {
    return false;
  },

  /**
   * Runtime configuration surface (acceleration mode etc.).
   * Mirror of the unified `RunAnywhere.runtime` accessor.
   */
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
   *   2. Initialize storage (OPFS)
   *   3. Restore local file storage (if previously configured)
   *
   * WASM is loaded lazily by each backend package when you call:
   *   await LlamaCPP.register();  // loads racommons-llamacpp.wasm
   *   await ONNX.register();      // loads sherpa-onnx.wasm (on first use)
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
        const env = options.environment ?? SDKEnvironment.Development;
        _initOptions = { ...options, environment: env };

        if (options.debug) {
          SDKLogger.level = LogLevel.Debug;
        }

        logger.info(`Initializing RunAnywhere Web SDK (${env})...`);

        // Streaming downloads and WASM progress reporting require the
        // Fetch Streams API. Fail fast with a clear message in environments
        // where it's missing (very old browsers, some SSR contexts) instead
        // of surfacing a confusing error deep inside a model download.
        if (typeof ReadableStream === 'undefined') {
          // Phase C-prime: throw SDKException — wraps proto-typed wire envelope.
          throw SDKException.fromCode(
            SDKErrorCode.InitializationFailed,
            'ReadableStream is not available in this environment. ' +
            'The RunAnywhere Web SDK requires the Fetch Streams API ' +
            '(Chrome 43+, Firefox 65+, Safari 14.1+, Edge 79+).',
          );
        }

        // Restore local file storage from previous session (non-blocking)
        try {
          await RunAnywhere.restoreLocalStorage();
        } catch (err) {
          logger.warning(`Failed to restore local storage: ${err instanceof Error ? err.message : String(err)}`);
        }

        _isInitialized = true;

        // Eagerly resolve the device ID so `RunAnywhere.deviceId` is non-empty
        // before the first call.
        ensureDeviceId();

        logger.info('RunAnywhere Web SDK initialized successfully');
        EventBus.shared.emit('sdk.initialized', SDKEventType.Initialization, {
          environment: env,
        });

        // Kick off Phase 2 in the background so `ensureServicesReady()` is
        // a fast-path on the next API call. Failures are non-fatal.
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
   *
   * On Web this is currently a near-no-op (no auth, no device registration),
   * but the function is exposed so applications can `await` services-ready
   * before issuing time-sensitive calls. Future versions may perform real
   * backend work here.
   */
  async completeServicesInitialization(): Promise<void> {
    if (_hasCompletedServicesInit) return;
    if (_servicesInitPromise) return _servicesInitPromise;

    _servicesInitPromise = (async () => {
      try {
        // Future: HTTP/auth/device registration goes here.
        _hasCompletedServicesInit = true;
        logger.debug('Services initialization complete (Phase 2)');
      } finally {
        _servicesInitPromise = null;
      }
    })();
    return _servicesInitPromise;
  },

  /**
   * Internal-style guard used by extensions that need a fully-initialized
   * SDK. Mirror of Swift's `RunAnywhere.ensureServicesReady()`. Awaits Phase
   * 2 completion if it isn't already done.
   */
  async ensureServicesReady(): Promise<void> {
    if (_hasCompletedServicesInit) return;
    return RunAnywhere.completeServicesInitialization();
  },

  // =========================================================================
  // Model Management
  // =========================================================================

  /** Canonical single-model registration (CANONICAL_API.md §13). */
  registerModel(model: CompactModelDef): void {
    ModelManager.registerModel(model);
  },

  /**
   * Register a multi-file model (mmproj sidecars, sherpa-onnx archive bundles, etc.).
   * Per canonical §13. Internally identical to `registerModel` today; reserved
   * for future schema enforcement of multi-file-only fields.
   */
  registerMultiFileModel(model: CompactModelDef): void {
    ModelManager.registerMultiFileModel(model);
  },

  /**
   * Internal batch helper used by example apps that ship a predefined catalog.
   * Public callers should use `registerModel` / `registerMultiFileModel`.
   */
  registerCatalog(models: CompactModelDef[]): void {
    ModelManager.registerCatalog(models);
  },

  unregisterModel(modelId: string): void {
    ModelManager.unregisterModel(modelId);
  },

  setVLMLoader(loader: VLMLoader): void {
    ModelManager.setVLMLoader(loader);
  },

  async downloadModel(modelId: string): Promise<void> {
    return ModelManager.downloadModel(modelId);
  },

  cancelDownload(modelId: string): boolean {
    return ModelManager.cancelDownload(modelId);
  },

  async loadModel(modelId: string): Promise<boolean> {
    return ModelManager.loadModel(modelId);
  },

  availableModels(): ManagedModel[] {
    return ModelManager.getModels();
  },

  getModel(modelId: string): ManagedModel | undefined {
    return ModelManager.getModel(modelId);
  },

  getLoadedModel(category?: ModelCategory): ManagedModel | null {
    return ModelManager.getLoadedModel(category);
  },

  async unloadAll(): Promise<void> {
    return ModelManager.unloadAll();
  },

  async deleteModel(modelId: string): Promise<void> {
    return ModelManager.deleteModel(modelId);
  },

  async deleteAllModels(): Promise<void> {
    return ModelManager.deleteAllModels();
  },

  /**
   * Canonical 0-arg refresh per CANONICAL_API.md §13. Refreshes remote
   * catalog + local rescan. Apps that need finer control can call
   * `ModelRegistryAdapter.tryDefault()?.refresh(options)` directly.
   */
  refreshModelRegistry(): boolean {
    return ModelRegistryAdapter.tryDefault()?.refresh({
      includeRemoteCatalog: true,
      rescanLocal: true,
      pruneOrphans: false,
    }) ?? false;
  },

  /**
   * Fetch server-assigned model assignments (§13). Returns the locally
   * cached assignment list, refreshed through the proto-byte registry C ABI
   * when a Web WASM backend with those exports is loaded.
   */
  fetchModelAssignments(): ManagedModel[] {
    return ModelManager.getModels();
  },

  /**
   * Return the list of registered inference frameworks (§13). Web surfaces
   * registered backends via ExtensionRegistry — there is no `InferenceFramework`
   * proto enum wiring yet (CPP-BLOCKED: G-B1 hardware_profile.proto), so this
   * returns string names of registered backends as a best-effort.
   */
  getRegisteredFrameworks(): string[] {
    return ExtensionRegistry.getAll().map((ext) => ext.extensionName);
  },

  /**
   * Return frameworks capable of a given SDK component (§13). Delegates to
   * `getRegisteredFrameworks()` for now; real capability filtering requires
   * `rac_hardware_profile_*` C ABI (CPP-BLOCKED: G-C6).
   */
  getFrameworksForCapability(_capability: string): string[] {
    return RunAnywhere.getRegisteredFrameworks();
  },

  // =========================================================================
  // Model Import (file picker / drag-and-drop)
  // =========================================================================

  async importModelFromPicker(options?: { modelId?: string; accept?: string[] }): Promise<string | null> {
    const acceptExts = options?.accept ?? ['.gguf', '.onnx', '.bin'];

    if ('showOpenFilePicker' in window) {
      try {
        const [handle] = await (window as WindowWithFilePicker).showOpenFilePicker!({
          types: [{
            description: 'AI Model Files',
            accept: { 'application/octet-stream': acceptExts },
          }],
          multiple: false,
        });
        const file: File = await handle.getFile();
        return this.importModelFromFile(file, options);
      } catch (err) {
        if (err instanceof Error && err.name === 'AbortError') return null;
        logger.debug('showOpenFilePicker failed, using input fallback');
      }
    }

    return new Promise<string | null>((resolve) => {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = acceptExts.join(',');
      input.style.display = 'none';
      let settled = false;

      const cleanup = () => {
        if (input.parentNode) {
          document.body.removeChild(input);
        }
      };

      const settle = (value: string | null) => {
        if (settled) return;
        settled = true;
        cleanup();
        resolve(value);
      };

      input.onchange = async () => {
        const file = input.files?.[0];
        if (!file) { settle(null); return; }
        try {
          const id = await this.importModelFromFile(file, options);
          settle(id);
        } catch (err) {
          logger.error(`Import failed: ${err instanceof Error ? err.message : String(err)}`);
          settle(null);
        }
      };

      input.addEventListener('cancel', () => settle(null));

      // Safety net: on older browsers the `cancel` event may not fire when
      // the user dismisses the picker. Use a focus/visibilitychange listener
      // to detect that the picker was closed without selection.
      const fallbackCleanup = () => {
        // Wait a tick — onchange fires after focus returns
        setTimeout(() => {
          if (!settled) {
            settle(null);
          }
        }, 300);
        window.removeEventListener('focus', fallbackCleanup);
        document.removeEventListener('visibilitychange', fallbackCleanup);
      };

      window.addEventListener('focus', fallbackCleanup);
      document.addEventListener('visibilitychange', fallbackCleanup);

      document.body.appendChild(input);
      input.click();
    });
  },

  async importModelFromFile(file: File, options?: { modelId?: string }): Promise<string> {
    logger.info(`Importing model from file: ${file.name} (${(file.size / 1024 / 1024).toFixed(1)} MB)`);
    return ModelManager.importModel(file, options?.modelId);
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
   *   1. `fsAccess` — File System Access API with an active directory handle
   *      (user picked a folder via `chooseLocalStorageDirectory()` or a handle
   *      was restored from a previous session).
   *   2. `opfs` — Origin Private File System (default persistent fallback).
   *   3. `memory` — Neither backend is available; models live only in MEMFS.
   *
   * Apps can surface this to users (e.g. "Stored on disk" vs. "Stored in
   * browser storage") or gate features that assume real-filesystem semantics.
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
      ModelManager.setLocalFileStorage(_localFileStorage);
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
      ModelManager.setLocalFileStorage(_localFileStorage);
      logger.info(`Local storage restored: ${_localFileStorage.directoryName}`);
    }
    return success;
  },

  async requestLocalStorageAccess(): Promise<boolean> {
    if (!_localFileStorage) return false;

    const success = await _localFileStorage.requestAccess();
    if (success) {
      ModelManager.setLocalFileStorage(_localFileStorage);
    }
    return success;
  },

  // =========================================================================
  // Top-level convenience verbs — mirror Swift's `RunAnywhere.chat / generate /
  // transcribe / synthesize / speak / detectSpeech / setVADCallback / etc.`
  // Each delegates through ExtensionPoint to the appropriate backend.
  // =========================================================================

  // LLM
  chat: Convenience.chat,
  generate: Convenience.generate,
  generateStream: Convenience.generateStream,
  generateStructured: Convenience.generateStructured,

  // STT — flat canonical verbs (§4)
  transcribe: Convenience.transcribe,

  // TTS — flat canonical verbs (§5)
  synthesize: Convenience.synthesize,
  speak: Convenience.speak,
  isSpeaking: Convenience.isSpeaking,
  stopSpeaking: Convenience.stopSpeaking,

  // VAD — flat canonical verbs (§6)
  detectSpeech: Convenience.detectSpeech,
  /** Canonical §6 name for the speech-activity callback setter. */
  setVADSpeechActivityCallback: Convenience.setVADCallback,
  /** Set a callback for raw audio buffers (§6 `setVADAudioBufferCallback`). */
  setVADAudioBufferCallback(cb: (buffer: Uint8Array) => void): void {
    VADCapability.setVADAudioBufferCallback(cb);
  },
  /** Set a callback for VAD statistics (§6 `setVADStatisticsCallback`). */
  setVADStatisticsCallback(cb: (stats: unknown) => void): void {
    VADCapability.setVADStatisticsCallback(cb);
  },
  startVAD: Convenience.startVAD,
  stopVAD: Convenience.stopVAD,
  cleanupVAD: Convenience.cleanupVAD,
  isVADReady: Convenience.isVADReady,

  // LLM model management — canonical flat verbs (§3)
  async loadLLMModel(modelId: string): Promise<void> {
    await ModelManager.loadModel(modelId);
  },

  async unloadLLMModel(): Promise<void> {
    await ModelManager.unloadAll();
  },

  get isLLMModelLoaded(): boolean {
    return ModelManager.getLoadedModel(undefined as unknown as import('../types/enums').ModelCategory) != null;
  },

  currentLLMModel(): import('../Infrastructure/ModelManager').ManagedModel | null {
    return ModelManager.getLoadedModel(undefined as unknown as import('../types/enums').ModelCategory);
  },

  /**
   * Generate with tool calling — canonical §3 `generateWithTools`.
   * Delegates to the LLM provider's tool calling capability.
   */
  async generateWithTools(
    prompt: string,
    options?: Partial<import('@runanywhere/proto-ts/llm_options').LLMGenerationOptions>,
  ): Promise<import('@runanywhere/proto-ts/llm_options').LLMGenerationResult> {
    return Convenience.generate(prompt, options);
  },

  /**
   * Continue a conversation after a tool call result (§3 `continueWithToolResult`).
   * Appends the tool result to the context and generates the next response.
   */
  async continueWithToolResult(
    toolCallId: string,
    result: string,
    options?: Partial<import('@runanywhere/proto-ts/llm_options').LLMGenerationOptions>,
  ): Promise<import('@runanywhere/proto-ts/llm_options').LLMGenerationResult> {
    return Convenience.generate(`[Tool ${toolCallId} result]: ${result}`, options);
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

  /** Split thinking and response sections (§3). Returns `[thinking, response]`. */
  splitThinkingAndResponse(text: string): { thinking: string; response: string } {
    const { thinking, response } = LlmThinking.extract(text);
    return { thinking: thinking ?? '', response };
  },

  // RAG — flat (RAG is stateless from public-API view; the pipeline is a
  // managed handle, not a stateful object on RunAnywhere). Mirrors Swift
  // `RunAnywhere+RAG.swift`.
  ragCreatePipeline: RAGExt.ragCreatePipeline,
  ragDestroyPipeline: RAGExt.ragDestroyPipeline,
  ragIngest: RAGExt.ragIngest,
  ragAddDocumentsBatch: RAGExt.ragAddDocumentsBatch,
  ragQuery: RAGExt.ragQuery,
  ragClearDocuments: RAGExt.ragClearDocuments,
  ragGetDocumentCount: RAGExt.ragGetDocumentCount,
  ragGetStatistics: RAGExt.ragGetStatistics,
  getRAGAvailability: RAGExt.getRAGAvailability,
  isRAGAvailable: RAGExt.isRAGAvailable,

  // STT model management — canonical flat verbs (§4)
  loadSTTModel: STTCapability.loadSTTModel.bind(STTCapability),
  unloadSTTModel: STTCapability.unloadSTTModel.bind(STTCapability),

  get isSTTModelLoaded(): boolean {
    return STTCapability.isSTTModelLoaded;
  },

  // TTS model management — canonical flat verbs (§5)
  loadTTSVoice: TTSCapability.loadTTSVoice.bind(TTSCapability),
  unloadTTSVoice: TTSCapability.unloadTTSVoice.bind(TTSCapability),
  loadTTSModel: TTSCapability.loadTTSModel.bind(TTSCapability),
  unloadTTSModel: TTSCapability.unloadTTSModel.bind(TTSCapability),
  availableTTSVoices: TTSCapability.availableTTSVoices.bind(TTSCapability),

  get isTTSVoiceLoaded(): boolean {
    return TTSCapability.isTTSVoiceLoaded;
  },

  // VLM — canonical flat verbs (§7)
  describeImage: VisionLanguageCapability.describeImage.bind(VisionLanguageCapability),
  askAboutImage: VisionLanguageCapability.askAboutImage.bind(VisionLanguageCapability),
  processImage: VisionLanguageCapability.generate.bind(VisionLanguageCapability),
  processImageStream: VisionLanguageCapability.processImageStream.bind(VisionLanguageCapability),
  cancelVLMGeneration: VisionLanguageCapability.cancelVLMGeneration.bind(VisionLanguageCapability),
  loadVLMModel: VisionLanguageCapability.loadVLMModel.bind(VisionLanguageCapability),
  unloadVLMModel: VisionLanguageCapability.unloadVLMModel.bind(VisionLanguageCapability),

  get isVLMModelLoaded(): boolean {
    return VisionLanguageCapability.isVLMModelLoaded;
  },

  // Diffusion — canonical §8 flat verbs
  generateImage,
  generateImageStream,
  loadDiffusionModel,
  unloadDiffusionModel,
  cancelImageGeneration,
  getDiffusionCapabilities,

  get isDiffusionModelLoaded(): boolean {
    return getIsDiffusionModelLoaded();
  },

  // LLM structured stream + extraction — canonical §3 flat verbs
  generateStructuredStream,
  extractStructuredOutput,

  // VoiceAgent C-ABI parity — mirrors Swift `RunAnywhere+VoiceAgent.swift`.
  // Includes the canonical streamVoiceAgent verb (CANONICAL_API.md §10).
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

  // =========================================================================
  // Solutions (T4.7 / T4.8) — proto/YAML-driven L5 pipeline runtime.
  // Capability shape: `RunAnywhere.solutions.run({ config | configBytes | yaml })`
  // returns a `SolutionHandle` with start / stop / cancel / feed / closeInput /
  // destroy verbs. Mirrors the namespace exposed by every other RunAnywhere SDK.
  // =========================================================================

  solutions: SolutionsCapability,

  // =========================================================================
  // Phase C-prime namespace extensions — symmetric with Swift / Kotlin / RN.
  // =========================================================================

  /** Storage info / persistence — `RunAnywhere.storage.info()` etc. */
  storage: StorageCapability,

  /** C++-owned download workflow — plan/start/cancel/resume/progress. */
  downloads: DownloadsCapability,

  /** C++ SDKEvent proto stream — subscribe/publish/poll/failure. */
  sdkEvents: SDKEventsCapability,

  /** C++ model registry proto bridge — list/query/listDownloaded/get/mutate. */
  modelRegistry: ModelRegistryCapability,

  /** C++ model lifecycle proto bridge — load/unload/current/snapshot. */
  modelLifecycle: ModelLifecycleCapability,

  /** Plugin/extension management — `RunAnywhere.pluginLoader.register(ext)` etc. */
  pluginLoader: PluginLoaderCapability,

  /** VAD namespace — `RunAnywhere.vad.detect(audio)` etc. */
  vad: VADCapability,

  /** Text generation — `RunAnywhere.textGeneration.generate(options)` etc. */
  textGeneration: TextGenerationCapability,

  /** Structured output — `RunAnywhere.structuredOutput.generate(prompt, schema)` */
  structuredOutput: StructuredOutputCapability,

  /** Tool calling — `RunAnywhere.toolCalling.generate(prompt, tools)` */
  toolCalling: ToolCallingCapability,

  /** Speech-to-text — `RunAnywhere.stt.transcribe(audio)` */
  stt: STTCapability,

  /** Text-to-speech — `RunAnywhere.tts.synthesize(text)` */
  tts: TTSCapability,

  /** Vision-language models — `RunAnywhere.visionLanguage.generate(options)` */
  visionLanguage: VisionLanguageCapability,

  /** VLM model catalog — `RunAnywhere.vlmModels.list()` */
  vlmModels: VLMModelsCapability,

  /** Image diffusion — `RunAnywhere.diffusion.generate(options)` */
  diffusion: DiffusionCapability,

  /** Model lifecycle — `RunAnywhere.modelManagement.list()` / `.download()` etc. */
  modelManagement: ModelManagementCapability,

  /** Role→model mappings — `RunAnywhere.modelAssignments.set(role, modelId)` */
  modelAssignments: ModelAssignmentsCapability,

  /** Registered backend frameworks — `RunAnywhere.frameworks.list()` */
  frameworks: FrameworksCapability,

  /** Logging control — `RunAnywhere.logging.setLevel(LogLevel.Debug)` */
  logging: LoggingCapability,

  /** LoRA adapter management — `RunAnywhere.lora.load(config)` etc. */
  lora: LoRACapability,

  /** RAG retrieval pipeline — `RunAnywhere.rag.query(...)` etc. */
  rag: RAGExt.RAG,

  /** Hardware profile — `RunAnywhere.hardware.getProfile()` etc. */
  hardware: HardwareCapability,

  // =========================================================================
  // Canonical flat verbs (§1 / §3 / §5 / §6 of CANONICAL_API.md)
  // =========================================================================

  /**
   * Cancel any in-flight LLM generation (§1 / §3). Calls `iterator.return()`
   * on the active stream if one exists; otherwise a no-op. Symmetric with
   * Swift / Kotlin / RN / Flutter `RunAnywhere.cancelGeneration()`.
   */
  cancelGeneration(): void {
    const llm = ExtensionPoint.getProvider('llm') as {
      cancelGeneration?: () => void;
    } | undefined;
    if (typeof llm?.cancelGeneration === 'function') {
      llm.cancelGeneration();
    }
  },

  /**
   * Stop any in-progress TTS synthesis (§5). Symmetric with
   * Swift `RunAnywhere.stopSynthesis()`.
   */
  stopSynthesis(): void {
    Convenience.stopSpeaking();
  },

  // =========================================================================
  // Shutdown
  // =========================================================================

  shutdown(): void {
    logger.info('Shutting down RunAnywhere Web SDK...');

    // Unload all models before tearing down extensions
    ModelManager.unloadAll().catch(() => { /* ignore during shutdown */ });

    // Clean up all registered extensions and backends
    ExtensionRegistry.cleanupAll();
    ExtensionPoint.cleanupAll();

    // Clear WASM adapter singletons so stale module refs don't linger.
    HTTPAdapter.clearDefaultModule();
    ModelRegistryAdapter.clearDefaultModule();
    ModelLifecycleAdapter.clearDefaultModule();
    DownloadAdapter.clearDefaultModule();
    SDKEventStreamAdapter.clearDefaultModule();
    StorageAdapter.clearDefaultHandles();

    // Reset state
    EventBus.reset();
    ExtensionRegistry.reset();
    ExtensionPoint.reset();

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
