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
import { ModelManager } from '../Infrastructure/ModelManager';
import type { CompactModelDef, ManagedModel, VLMLoader } from '../Infrastructure/ModelManager';

// Extension imports for shutdown cleanup
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
    if (_isInitialized) {
      logger.debug('Already initialized');
      return;
    }

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

    // Phase 2: Register platform adapter
    _platformAdapter = new PlatformAdapter();
    _platformAdapter.register();

    // Phase 3: Initialize RACommons core
    const m = bridge.module;

    // Create rac_config_t in WASM memory
    // Layout: { rac_platform_adapter_t* platform_adapter, rac_log_level_t log_level, const char* log_tag }
    const configSize = m._rac_wasm_sizeof_config();
    const configPtr = m._malloc(configSize);

    // Zero-initialize
    for (let i = 0; i < configSize; i++) {
      m.setValue(configPtr + i, 0, 'i8');
    }

    // Set platform_adapter pointer (offset 0) -- rac_init checks this field
    m.setValue(configPtr, _platformAdapter.getAdapterPtr(), '*');
    // Set log_level (offset 4, after the pointer)
    const logLevel = options.debug ? 1 : 2; // DEBUG=1, INFO=2
    m.setValue(configPtr + 4, logLevel, 'i32');

    const result = m._rac_init(configPtr);
    m._free(configPtr);

    if (result !== 0) {
      const errMsg = bridge.getErrorMessage(result);
      throw new SDKError(SDKErrorCode.InitializationFailed, `rac_init failed: ${errMsg}`);
    }

    // Phase 4: Register available backends
    // The llama.cpp LLM backend must be registered before any LLM/VLM operations.
    // Check if the function exists (only present when built with --llamacpp).
    if (typeof (m as any)['_rac_backend_llamacpp_register'] === 'function') {
      const regResult = m.ccall('rac_backend_llamacpp_register', 'number', [], []) as number;
      if (regResult === 0) {
        logger.info('llama.cpp LLM backend registered');
      } else {
        logger.warning(`llama.cpp backend registration returned: ${regResult}`);
      }
    }

    _isInitialized = true;
    _hasCompletedServicesInit = true;

    logger.info('RunAnywhere Web SDK initialized successfully');
    EventBus.shared.emit('sdk.initialized', SDKEventType.Initialization, {
      environment: env,
      accelerationMode: bridge.accelerationMode,
    });
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
    // 1. Clean up extensions in reverse dependency order
    //    (high-level orchestrations first, then individual components)
    // ------------------------------------------------------------------

    // Diffusion / Embeddings — independent components
    try { Diffusion.cleanup(); } catch { /* ignore during shutdown */ }
    try { Embeddings.cleanup(); } catch { /* ignore during shutdown */ }

    // VLM — uses llama.cpp backend (independent of LLM component)
    try { VLM.cleanup(); } catch { /* ignore during shutdown */ }

    // ToolCalling — depends on TextGeneration, clear registry first
    try { ToolCalling.cleanup(); } catch { /* ignore during shutdown */ }

    // sherpa-onnx based components: VAD, TTS, STT
    try { VAD.cleanup(); } catch { /* ignore during shutdown */ }
    try { TTS.cleanup(); } catch { /* ignore during shutdown */ }
    try { STT.cleanup(); } catch { /* ignore during shutdown */ }

    // TextGeneration — base LLM component (RACommons WASM)
    try { TextGeneration.cleanup(); } catch { /* ignore during shutdown */ }

    // ------------------------------------------------------------------
    // 2. Shut down WASM bridges
    // ------------------------------------------------------------------

    // SherpaONNXBridge (STT/TTS/VAD WASM module)
    try { SherpaONNXBridge.shared.shutdown(); } catch { /* ignore during shutdown */ }

    // Platform adapter
    if (_platformAdapter) {
      _platformAdapter.cleanup();
      _platformAdapter = null;
    }

    // RACommons WASM bridge
    WASMBridge.shared.shutdown();

    // ------------------------------------------------------------------
    // 3. Reset SDK state
    // ------------------------------------------------------------------

    EventBus.reset();

    _isInitialized = false;
    _hasCompletedServicesInit = false;
    _initOptions = null;

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
