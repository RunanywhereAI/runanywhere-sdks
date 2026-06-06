/**
 * Initialization Module
 *
 * Types and utilities for SDK two-phase initialization.
 * Mirrors the Swift SDK pattern.
 */

export { InitializationPhase } from './InitializationPhase';
export type { InitializationState } from './InitializationState';
export {
  createInitialState,
  markCoreInitialized,
  markServicesInitializing,
  markServicesInitialized,
  markInitializationFailed,
  resetState,
} from './InitializationState';
