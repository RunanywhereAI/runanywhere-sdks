/**
 * Initialization Phase
 *
 * Represents the two-phase initialization pattern matching iOS SDK.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift
 *
 * Phase 1 (Core): Synchronous, fast (~1-5ms)
 *   - Validate configuration
 *   - Setup logging
 *   - Store parameters
 *   - No network calls
 *
 * Phase 2 (Services): Asynchronous (~100-500ms)
 *   - Initialize network services
 *   - Setup authentication
 *   - Load models
 *   - Register device
 */

/**
 * The current initialization phase of the SDK
 */
export enum InitializationPhase {
  /**
   * SDK has not been initialized
   */
  NotInitialized = 'notInitialized',

  /**
   * Phase 1 complete: Core initialized (sync)
   * - Configuration validated
   * - Logging setup
   * - Parameters stored
   * - SDK is usable for basic operations
   */
  CoreInitialized = 'coreInitialized',

  /**
   * Phase 2 in progress: Services initializing (async)
   * - Network services starting
   * - Authentication in progress
   * - Models loading
   */
  ServicesInitializing = 'servicesInitializing',

  /**
   * Phase 2 complete: All services ready
   * - Network ready
   * - Authenticated (if required)
   * - Models loaded
   * - Device registered
   */
  FullyInitialized = 'fullyInitialized',

  /**
   * Initialization failed
   */
  Failed = 'failed',
}

/**
 * Check if a phase indicates the SDK is usable
 */
export function isSDKUsable(phase: InitializationPhase): boolean {
  return (
    phase === InitializationPhase.CoreInitialized ||
    phase === InitializationPhase.ServicesInitializing ||
    phase === InitializationPhase.FullyInitialized
  );
}

/**
 * Check if a phase indicates services are ready
 */
export function areServicesReady(phase: InitializationPhase): boolean {
  return phase === InitializationPhase.FullyInitialized;
}

/**
 * Check if initialization is in progress
 */
export function isInitializing(phase: InitializationPhase): boolean {
  return phase === InitializationPhase.ServicesInitializing;
}
