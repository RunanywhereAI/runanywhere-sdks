/**
 * RunAnywhere Web SDK - Main Entry Point
 *
 * The public API for the RunAnywhere Web SDK.
 * Mirrors the pattern across all SDKs:
 *   - RunAnywhere.swift (iOS) - enum with static methods
 *   - RunAnywhere.kt (Kotlin) - object/class
 *   - RunAnywhere.ts (React Native) - object literal
 *   - RunAnywhere.dart (Flutter) - class
 *
 * All operations flow through the WASM bridge to RACommons C++.
 *
 * Usage:
 *   import { RunAnywhere } from '@runanywhere/web';
 *
 *   await RunAnywhere.initialize({ environment: 'development' });
 *   const result = await RunAnywhere.generate('Hello!', { maxTokens: 100 });
 */

import { SDKEnvironment, SDKEventType, ModelCategory, AccelerationPreference } from '../types/enums';
import type { SDKInitOptions } from '../types/models';
import { SDKError, SDKErrorCode } from '../Foundation/ErrorTypes';
import { EventBus } from '../Foundation/EventBus';
import { SDKLogger, LogLevel } from '../Foundation/SDKLogger';
import { WASMBridge } from '../Foundation/WASMBridge';
import type { AccelerationMode } from '../Foundation/WASMBridge';
import { SherpaONNXBridge } from '../Foundation/SherpaONNXBridge';
import { PlatformAdapter } from '../Foundation/PlatformAdapter';
import { loadOffsets } from '../Foundation/StructOffsets';
import { Offsets } from '../Foundation/StructOffsets';
import { ModelManager } from '../Infrastructure/ModelManager';
import type { CompactModelDef, ManagedModel, VLMLoader } from '../Infrastructure/ModelManager';
import { ExtensionRegistry } from '../Infrastructure/ExtensionRegistry';

// Extension imports for registration and shutdown cleanup
import { TextGeneration } from './Extensions/RunAnywhere+TextGeneration';
import { VLM } from './Extensions/RunAnywhere+VLM';
import { STT } from './Extensions/RunAnywhere+STT';
import { TTS } from './Extensions/RunAnywhere+TTS';
import { VAD } from './Extensions/RunAnywhere+VAD';
import { Embeddings } from './Extensions/RunAnywhere+Embeddings';
import { Diffusion } from './Extensions/RunAnywhere+Diffusion';
import { ToolCalling } from './Extensions/RunAnywhere+ToolCalling';

const logger = new SDKLogger('RunAnywhere');

// ---------------------------------------------------------------------------
// Internal State
// ---------------------------------------------------------------------------

let _isInitialized = false;
let _hasCompletedServicesInit = false;
let _platformAdapter: PlatformAdapter | null = null;
let _initOptions: SDKInitOptions | null = null;
/** Guard against concurrent initialize() calls */
let _initializingPromise: Promise<void> | null = null;

// ---------------------------------------------------------------------------
// RunAnywhere Public API
// ---------------------------------------------------------------------------

export const RunAnywhere = {
  // =========================================================================
  // SDK State
  // =========================================================================

  /** Whether the SDK is initialized (Phase 1 complete) */
  get isInitialized(): boolean {
    return _isInitialized;
  },

  /** Whether services are fully ready (Phase 2 complete) */
  get areServicesReady(): boolean {
    return _hasCompletedServicesInit;
  },

  /** Current SDK version */
  get version(): string {
    return '0.1.0';
  },

  /** Current environment */
  get environment(): SDKEnvironment | null {
    return _initOptions?.environment ?? null;
  },

  /** Access to the event bus */
  get events(): EventBus {
    return EventBus.shared;
  },

  /** Whether the WASM module is loaded */
  get isWASMLoaded(): boolean {
    return WASMBridge.shared.isLoaded;
  },

  /** The active hardware acceleration mode ('webgpu' or 'cpu'). */
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
   * @param options - SDK initialization options
   * @param wasmUrl - Optional URL to the racommons.js glue file
   *
   * @example
   * ```typescript
   * // Development mode (default)
   * await RunAnywhere.initialize();
   *
   * // Production mode
   * await RunAnywhere.initialize({
   *   apiKey: 'your-key',
   *   baseURL: 'https://api.runanywhere.ai',
   *   environment: 'production',
   * });
   * ```
   */
  async initialize(options: SDKInitOptions = {}, wasmUrl?: string): Promise<void> {
    // Guard: already done
    if (_isInitialized) {
      logger.debug('Already initialized');
      return;
    }

    // Guard: another call is already in flight – wait for it instead of racing
    if (_initializingPromise) {
      logger.debug('Initialization already in progress, awaiting...');
      return _initializingPromise;
    }

    _initializingPromise = (async () => {
      try {
        const env = options.environment ?? SDKEnvironment.Development;
        _initOptions = { ...options, environment: env };

        // Configure logging
        if (options.debug) {
          SDKLogger.level = LogLevel.Debug;
        }

        logger.info(`Initializing RunAnywhere Web SDK (${env})...`);

        // Phase 1: Load WASM module (auto-detects WebGPU and loads correct variant)
        const bridge = WASMBridge.shared;
        const acceleration = options.acceleration ?? AccelerationPreference.Auto;
        await bridge.load(wasmUrl, options.webgpuWasmUrl, acceleration);

        logger.info(`Hardware acceleration: ${bridge.accelerationMode}`);

        // Emit acceleration mode event so app UIs can show a badge
        EventBus.shared.emit('sdk.accelerationMode', SDKEventType.Device, {
          mode: bridge.accelerationMode,
        });

        // Phase 1b: Load struct field offsets from the WASM module.
        // This must happen before any struct read/write in the SDK.
        loadOffsets(bridge.module);

        // Phase 2: Register platform adapter
        _platformAdapter = new PlatformAdapter();
        _platformAdapter.register();

        // Phase 3: Initialize RACommons core
        const m = bridge.module;

        // Create rac_config_t in WASM memory
        const configSize = m._rac_wasm_sizeof_config();
        const configPtr = m._malloc(configSize);

        // Zero-initialize
        for (let i = 0; i < configSize; i++) {
          m.setValue(configPtr + i, 0, 'i8');
        }

        // Set platform_adapter pointer (offset 0) -- always first field
        m.setValue(configPtr, _platformAdapter.getAdapterPtr(), '*');
        // Set log_level using compiler-provided offset
        const logLevel = options.debug ? 1 : 2; // DEBUG=1, INFO=2
        m.setValue(configPtr + Offsets.config.logLevel, logLevel, 'i32');

        // {async: true} lets JSPI suspend during WebGPU adapter/device init.
        const result = await bridge.callFunction<number | Promise<number>>(
          'rac_init', 'number', ['number'], [configPtr], { async: true },
        ) as number;
        m._free(configPtr);

        if (result !== 0) {
          const errMsg = bridge.getErrorMessage(result);
          throw new SDKError(SDKErrorCode.InitializationFailed, `rac_init failed: ${errMsg}`);
        }

        // Phase 4: Register available backends
        // The llama.cpp LLM backend must be registered before any LLM/VLM operations.
        // Check if the function exists (only present when built with --llamacpp).
        if (typeof (m as any)['_rac_backend_llamacpp_register'] === 'function') {
          const regResult = await bridge.callFunction<number | Promise<number>>(
            'rac_backend_llamacpp_register', 'number', [], [], { async: true },
          ) as number;
          if (regResult === 0) {
            logger.info('llama.cpp LLM backend registered');
          } else {
            logger.warning(`llama.cpp backend registration returned: ${regResult}`);
          }
        }

        // Phase 5: Register model loaders with ModelManager.
        // This keeps the dependency flow correct: Public -> Infrastructure.
        ModelManager.setLLMLoader(TextGeneration);
        ModelManager.setSTTLoader(STT);
        ModelManager.setTTSLoader(TTS);
        ModelManager.setVADLoader(VAD);

        // Phase 6: Register extensions with the lifecycle registry.
        // Order matters: low-level components first (cleaned up last).
        ExtensionRegistry.register(TextGeneration);
        ExtensionRegistry.register(STT);
        ExtensionRegistry.register(TTS);
        ExtensionRegistry.register(VAD);
        ExtensionRegistry.register(VLM);
        ExtensionRegistry.register(Embeddings);
        ExtensionRegistry.register(Diffusion);
        ExtensionRegistry.register(ToolCalling);

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
  // Model Management (mirrors iOS RunAnywhere.registerModel / loadModel / etc.)
  // =========================================================================

  /**
   * Register a catalog of models for download and loading.
   * @param models - Compact model definitions to register
   */
  registerModels(models: CompactModelDef[]): void {
    ModelManager.registerModels(models);
  },

  /**
   * Set the VLM (vision-language model) loader implementation.
   * The app provides an implementation (typically backed by a Web Worker).
   */
  setVLMLoader(loader: VLMLoader): void {
    ModelManager.setVLMLoader(loader);
  },

  /**
   * Download a model (and any companion files) to persistent OPFS storage.
   * @param modelId - The model ID to download
   */
  async downloadModel(modelId: string): Promise<void> {
    return ModelManager.downloadModel(modelId);
  },

  /**
   * Load a downloaded model into the inference engine.
   * @param modelId - The model ID to load
   * @returns true if loaded successfully
   */
  async loadModel(modelId: string): Promise<boolean> {
    return ModelManager.loadModel(modelId);
  },

  /**
   * Get all registered models with their current status.
   */
  availableModels(): ManagedModel[] {
    return ModelManager.getModels();
  },

  /**
   * Get the currently loaded model for a given category.
   * @param category - Optional model category filter
   */
  getLoadedModel(category?: ModelCategory): ManagedModel | null {
    return ModelManager.getLoadedModel(category);
  },

  /**
   * Unload ALL loaded models and free their resources.
   *
   * Useful when switching between features/tabs to ensure clean state
   * and reclaim memory. Called automatically by `loadModel()`, but can
   * also be called explicitly by the app.
   */
  async unloadAll(): Promise<void> {
    return ModelManager.unloadAll();
  },

  /**
   * Delete a downloaded model from OPFS storage.
   * @param modelId - The model ID to delete
   */
  async deleteModel(modelId: string): Promise<void> {
    return ModelManager.deleteModel(modelId);
  },

  // =========================================================================
  // Shutdown
  // =========================================================================

  /**
   * Shutdown the SDK and release all resources.
   *
   * Cleans up extensions in reverse dependency order so that
   * higher-level components (e.g. VoiceAgent pipeline) are torn
   * down before the lower-level ones they depend on.
   */
  shutdown(): void {
    logger.info('Shutting down RunAnywhere Web SDK...');

    // ------------------------------------------------------------------
    // 1. Clean up all registered extensions in reverse dependency order.
    //    Extensions were registered low-level first, so reverse cleanup
    //    tears down high-level orchestrations before their dependencies.
    // ------------------------------------------------------------------

    ExtensionRegistry.cleanupAll();

    // ------------------------------------------------------------------
    // 2. Shut down WASM bridges
    // ------------------------------------------------------------------

    // SherpaONNXBridge (STT/TTS/VAD WASM module)
    try { SherpaONNXBridge.shared.shutdown(); } catch { /* ignore during shutdown */ }

    // Platform adapter
    if (_platformAdapter) {
      try { _platformAdapter.cleanup(); } catch { /* ignore during shutdown */ }
      _platformAdapter = null;
    }

    // RACommons WASM bridge
    try { WASMBridge.shared.shutdown(); } catch { /* ignore during shutdown */ }

    // ------------------------------------------------------------------
    // 3. Reset SDK state
    // ------------------------------------------------------------------

    EventBus.reset();
    ExtensionRegistry.reset();

    _isInitialized = false;
    _hasCompletedServicesInit = false;
    _initOptions = null;
    _initializingPromise = null;

    logger.info('RunAnywhere Web SDK shut down');
  },

  // =========================================================================
  // Reset (testing)
  // =========================================================================

  /**
   * Reset SDK state (for testing purposes).
   */
  reset(): void {
    RunAnywhere.shutdown();
  },
};
