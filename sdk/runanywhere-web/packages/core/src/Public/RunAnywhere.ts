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

import { SDKEnvironment } from '../types/enums';
import type { SDKInitOptions } from '../types/models';
import { SDKError, SDKErrorCode } from '../Foundation/ErrorTypes';
import { EventBus } from '../Foundation/EventBus';
import { SDKLogger, LogLevel } from '../Foundation/SDKLogger';
import { WASMBridge } from '../Foundation/WASMBridge';
import { PlatformAdapter } from '../Foundation/PlatformAdapter';

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

    // Phase 1: Load WASM module
    const bridge = WASMBridge.shared;
    await bridge.load(wasmUrl);

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

    // Set log level field (first field in rac_config_t after platform_adapter pointer)
    // rac_config_t layout: { rac_platform_adapter_t* adapter, rac_log_level_t log_level, const char* log_tag }
    // Note: platform adapter is already set via rac_set_platform_adapter()
    const logLevel = options.debug ? 1 : 2; // DEBUG=1, INFO=2
    m.setValue(configPtr + 4, logLevel, 'i32'); // log_level (offset 4 after pointer)

    const result = m._rac_init(configPtr);
    m._free(configPtr);

    if (result !== 0) {
      const errMsg = bridge.getErrorMessage(result);
      throw new SDKError(SDKErrorCode.InitializationFailed, `rac_init failed: ${errMsg}`);
    }

    _isInitialized = true;
    _hasCompletedServicesInit = true;

    logger.info('RunAnywhere Web SDK initialized successfully');
    EventBus.shared.emit('sdk.initialized', 'initialization' as never, { environment: env });
  },

  // =========================================================================
  // Shutdown
  // =========================================================================

  /**
   * Shutdown the SDK and release all resources.
   */
  shutdown(): void {
    logger.info('Shutting down RunAnywhere Web SDK...');

    if (_platformAdapter) {
      _platformAdapter.cleanup();
      _platformAdapter = null;
    }

    WASMBridge.shared.shutdown();
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
