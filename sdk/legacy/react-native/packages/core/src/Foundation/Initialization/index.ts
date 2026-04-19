/**
 * Initialization Module
 *
 * Types and utilities for SDK two-phase initialization.
 * Matches iOS SDK pattern.
 */

export {
  InitializationPhase,
  isSDKUsable,
  areServicesReady,
  isInitializing,
} from './InitializationPhase';

// Type exports
export type { SDKInitParams, InitializationState } from './InitializationState';

// Value exports
export {
  createInitialState,
  markCoreInitialized,
  markServicesInitializing,
  markServicesInitialized,
  markInitializationFailed,
  resetState,
} from './InitializationState';
