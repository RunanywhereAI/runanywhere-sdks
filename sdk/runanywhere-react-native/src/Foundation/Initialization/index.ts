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

export {
  SDKInitParams,
  InitializationState,
  createInitialState,
  markCoreInitialized,
  markServicesInitializing,
  markServicesInitialized,
  markInitializationFailed,
  resetState,
} from './InitializationState';
