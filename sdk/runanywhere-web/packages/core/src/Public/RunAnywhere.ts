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

import { SDKEnvironment, SDKEventType, ModelCategory } from '../types/enums';
import type { SDKInitOptions } from '../types/models';
import { EventBus } from '../Foundation/EventBus';
import { SDKLogger, LogLevel } from '../Foundation/SDKLogger';
import { ModelManager } from '../Infrastructure/ModelManager';
import type { CompactModelDef, ManagedModel, VLMLoader } from '../Infrastructure/ModelManager';
import { ExtensionRegistry } from '../Infrastructure/ExtensionRegistry';
import { ExtensionPoint } from '../Infrastructure/ExtensionPoint';
import { LocalFileStorage } from '../Infrastructure/LocalFileStorage';

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

  get version(): string {
    return '0.1.0';
  },

  get environment(): SDKEnvironment | null {
    return _initOptions?.environment ?? null;
  },

  get events(): EventBus {
    return EventBus.shared;
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

        // Restore local file storage from previous session (non-blocking)
        try {
          await RunAnywhere.restoreLocalStorage();
        } catch (err) {
          logger.warning(`Failed to restore local storage: ${err instanceof Error ? err.message : String(err)}`);
        }

        _isInitialized = true;

        logger.info('RunAnywhere Web SDK initialized successfully');
        EventBus.shared.emit('sdk.initialized', SDKEventType.Initialization, {
          environment: env,
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
  // Shutdown
  // =========================================================================

  shutdown(): void {
    logger.info('Shutting down RunAnywhere Web SDK...');

    // Unload all models before tearing down extensions
    ModelManager.unloadAll().catch(() => { /* ignore during shutdown */ });

    // Clean up all registered extensions and backends
    ExtensionRegistry.cleanupAll();
    ExtensionPoint.cleanupAll();

    // Reset state
    EventBus.reset();
    ExtensionRegistry.reset();
    ExtensionPoint.reset();

    _isInitialized = false;
    _initOptions = null;
    _initializingPromise = null;
    _localFileStorage = null;

    logger.info('RunAnywhere Web SDK shut down');
  },

  reset(): void {
    RunAnywhere.shutdown();
  },
};
