/**
 * RunAnywhere Web SDK - Main Entry Point
 *
 * The public API for the RunAnywhere Web SDK.
 * Mirrors the pattern across all SDKs:
 *   - RunAnywhere.swift (iOS) - enum with static methods
 *   - RunAnywhere.kt (Kotlin) - object/class
 *   - RunAnywhere.ts (React Native) - object literal
 *
 * All operations flow through the WASM bridge to RACommons C++.
 * Backend packages (@runanywhere/web-llamacpp, @runanywhere/web-onnx)
 * register themselves via the ExtensionPoint API.
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

import { SDKEnvironment, SDKEventType, ModelCategory, AccelerationPreference } from '../types/enums';
import type { SDKInitOptions } from '../types/models';
import { SDKError, SDKErrorCode } from '../Foundation/ErrorTypes';
import { EventBus } from '../Foundation/EventBus';
import { SDKLogger, LogLevel } from '../Foundation/SDKLogger';
import { WASMBridge } from '../Foundation/WASMBridge';
import type { AccelerationMode } from '../Foundation/WASMBridge';
import { PlatformAdapter } from '../Foundation/PlatformAdapter';
import { loadOffsets } from '../Foundation/StructOffsets';
import { Offsets } from '../Foundation/StructOffsets';
import { ModelManager } from '../Infrastructure/ModelManager';
import type { CompactModelDef, ManagedModel, VLMLoader } from '../Infrastructure/ModelManager';
import { ExtensionRegistry } from '../Infrastructure/ExtensionRegistry';
import { ExtensionPoint } from '../Infrastructure/ExtensionPoint';
import { LocalFileStorage } from '../Infrastructure/LocalFileStorage';

const logger = new SDKLogger('RunAnywhere');

// ---------------------------------------------------------------------------
// Internal State
// ---------------------------------------------------------------------------

let _isInitialized = false;
let _hasCompletedServicesInit = false;
let _platformAdapter: PlatformAdapter | null = null;
let _initOptions: SDKInitOptions | null = null;
let _initializingPromise: Promise<void> | null = null;
let _localFileStorage: LocalFileStorage | null = null;

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

  get areServicesReady(): boolean {
    return _hasCompletedServicesInit;
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

  get isWASMLoaded(): boolean {
    return WASMBridge.shared.isLoaded;
  },

  get accelerationMode(): AccelerationMode {
    return WASMBridge.shared.accelerationMode;
  },

  // =========================================================================
  // Initialization
  // =========================================================================

  /**
   * Initialize the RunAnywhere SDK.
   *
   * This performs:
   *   1. Load RACommons WASM module
   *   2. Register JS platform adapter callbacks
   *   3. Call rac_init() (same C function as iOS/Android)
   *   4. Mark SDK as initialized
   *
   * After initialization, register backend packages:
   *   await LlamaCPP.register();  // @runanywhere/web-llamacpp
   *   await ONNX.register();      // @runanywhere/web-onnx
   */
  async initialize(options: SDKInitOptions = {}, wasmUrl?: string): Promise<void> {
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

        // Phase 1: Load WASM module
        const bridge = WASMBridge.shared;
        const acceleration = options.acceleration ?? AccelerationPreference.Auto;
        await bridge.load(wasmUrl, options.webgpuWasmUrl, acceleration);

        logger.info(`Hardware acceleration: ${bridge.accelerationMode}`);

        EventBus.shared.emit('sdk.accelerationMode', SDKEventType.Device, {
          mode: bridge.accelerationMode,
        });

        // Phase 2: Load core struct offsets
        loadOffsets(bridge.module);

        // Phase 3: Register platform adapter
        _platformAdapter = new PlatformAdapter();
        _platformAdapter.register();

        // Phase 4: Initialize RACommons core
        const m = bridge.module;

        const configSize = m._rac_wasm_sizeof_config();
        const configPtr = m._malloc(configSize);

        for (let i = 0; i < configSize; i++) {
          m.setValue(configPtr + i, 0, 'i8');
        }

        m.setValue(configPtr, _platformAdapter.getAdapterPtr(), '*');
        const logLevel = options.debug ? 1 : 2;
        m.setValue(configPtr + Offsets.config.logLevel, logLevel, 'i32');

        const result = await bridge.callFunction<number | Promise<number>>(
          'rac_init', 'number', ['number'], [configPtr], { async: true },
        ) as number;
        m._free(configPtr);

        if (result !== 0) {
          const errMsg = bridge.getErrorMessage(result);
          throw new SDKError(SDKErrorCode.InitializationFailed, `rac_init failed: ${errMsg}`);
        }

        // Phase 5: SDK ready — backend packages register themselves
        // via LlamaCPP.register() / ONNX.register() after this returns.

        _isInitialized = true;
        _hasCompletedServicesInit = true;

        logger.info('RunAnywhere Web SDK initialized successfully');
        EventBus.shared.emit('sdk.initialized', SDKEventType.Initialization, {
          environment: env,
          accelerationMode: bridge.accelerationMode,
        });
      } finally {
        _initializingPromise = null;
      }
    })();

    return _initializingPromise;
  },

  // =========================================================================
  // Model Management
  // =========================================================================

  registerModels(models: CompactModelDef[]): void {
    ModelManager.registerModels(models);
  },

  setVLMLoader(loader: VLMLoader): void {
    ModelManager.setVLMLoader(loader);
  },

  async downloadModel(modelId: string): Promise<void> {
    return ModelManager.downloadModel(modelId);
  },

  async loadModel(modelId: string): Promise<boolean> {
    return ModelManager.loadModel(modelId);
  },

  availableModels(): ManagedModel[] {
    return ModelManager.getModels();
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

  // =========================================================================
  // Model Import (file picker / drag-and-drop)
  // =========================================================================

  /**
   * Open a file picker to import a model file.
   *
   * Progressive enhancement:
   * - Chrome/Edge: Uses showOpenFilePicker() (modern File System Access API)
   * - Safari/Firefox/mobile: Falls back to hidden <input type="file">
   *
   * Works on ALL browsers and platforms (desktop + mobile).
   *
   * @param options.modelId - Optional: associate with an existing registered model
   * @param options.accept - File extensions to accept (default: .gguf, .onnx, .bin)
   * @returns The model ID, or null if the user cancelled
   */
  async importModelFromPicker(options?: { modelId?: string; accept?: string[] }): Promise<string | null> {
    const acceptExts = options?.accept ?? ['.gguf', '.onnx', '.bin'];

    // Try modern File System Access API (Chrome/Edge desktop + Android 144+)
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    if ('showOpenFilePicker' in window) {
      try {
        // eslint-disable-next-line @typescript-eslint/no-explicit-any
        const [handle] = await (window as any).showOpenFilePicker({
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
        // Fall through to <input> fallback
        logger.debug('showOpenFilePicker failed, using input fallback');
      }
    }

    // Fallback: hidden <input type="file"> (Safari, Firefox, iOS, all mobile)
    return new Promise<string | null>((resolve) => {
      const input = document.createElement('input');
      input.type = 'file';
      input.accept = acceptExts.join(',');
      input.style.display = 'none';

      input.onchange = async () => {
        const file = input.files?.[0];
        document.body.removeChild(input);
        if (!file) { resolve(null); return; }
        try {
          const id = await this.importModelFromFile(file, options);
          resolve(id);
        } catch (err) {
          logger.error(`Import failed: ${err instanceof Error ? err.message : String(err)}`);
          resolve(null);
        }
      };

      // Handle cancel (input doesn't fire change on cancel in all browsers)
      input.addEventListener('cancel', () => {
        document.body.removeChild(input);
        resolve(null);
      });

      document.body.appendChild(input);
      input.click();
    });
  },

  /**
   * Import a model from a File object.
   *
   * Use this for drag-and-drop, programmatic imports, or any case where
   * you already have a File/Blob reference.
   *
   * Works on ALL browsers and platforms.
   *
   * @param file - The File object to import
   * @param options.modelId - Optional: associate with an existing registered model
   * @returns The model ID (existing or auto-generated from filename)
   */
  async importModelFromFile(file: File, options?: { modelId?: string }): Promise<string> {
    logger.info(`Importing model from file: ${file.name} (${(file.size / 1024 / 1024).toFixed(1)} MB)`);
    return ModelManager.importModel(file, options?.modelId);
  },

  // =========================================================================
  // Local File Storage (persistent model storage)
  // =========================================================================

  /** Whether the File System Access API is available in this browser. */
  get isLocalStorageSupported(): boolean {
    return LocalFileStorage.isSupported;
  },

  /** Whether a local storage directory is currently configured and authorized. */
  get isLocalStorageReady(): boolean {
    return _localFileStorage?.isReady ?? false;
  },

  /** Whether a directory handle exists in IndexedDB (may need re-authorization). */
  get hasLocalStorageHandle(): boolean {
    return _localFileStorage?.hasStoredHandle ?? false;
  },

  /** The name of the currently configured local storage directory (for UI display). */
  get localStorageDirectoryName(): string | null {
    return _localFileStorage?.directoryName ?? null;
  },

  /**
   * Prompt the user to choose a local directory for model storage.
   * Opens the OS folder picker dialog.
   * Must be called from a user gesture (button click).
   *
   * @returns true if a directory was selected
   */
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

  /**
   * Attempt to restore a previously chosen local storage directory.
   * Call on app startup — if permission is still granted (Chrome 122+),
   * models will be loaded from the local filesystem automatically.
   *
   * @returns true if directory was restored and permission is granted
   */
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

  /**
   * Request re-authorization for a previously chosen directory.
   * Must be called from a user gesture (button click).
   * Use when `hasLocalStorageHandle` is true but `isLocalStorageReady` is false.
   *
   * @returns true if permission was granted
   */
  async requestLocalStorageAccess(): Promise<boolean> {
    if (!_localFileStorage) return false;

    const success = await _localFileStorage.requestAccess();
    if (success) {
      ModelManager.setLocalFileStorage(_localFileStorage);
    }
    return success;
  },

  // =========================================================================
  // Shutdown
  // =========================================================================

  shutdown(): void {
    logger.info('Shutting down RunAnywhere Web SDK...');

    // 1. Clean up all registered extensions (reverse dependency order)
    ExtensionRegistry.cleanupAll();

    // 2. Clean up all registered backends (includes sherpa-onnx shutdown)
    ExtensionPoint.cleanupAll();

    // 3. Platform adapter
    if (_platformAdapter) {
      try { _platformAdapter.cleanup(); } catch { /* ignore */ }
      _platformAdapter = null;
    }

    // 4. RACommons WASM bridge
    try { WASMBridge.shared.shutdown(); } catch { /* ignore */ }

    // 5. Reset state
    EventBus.reset();
    ExtensionRegistry.reset();
    ExtensionPoint.reset();

    _isInitialized = false;
    _hasCompletedServicesInit = false;
    _initOptions = null;
    _initializingPromise = null;
    _localFileStorage = null;

    logger.info('RunAnywhere Web SDK shut down');
  },

  // =========================================================================
  // Reset (testing)
  // =========================================================================

  reset(): void {
    RunAnywhere.shutdown();
  },
};
