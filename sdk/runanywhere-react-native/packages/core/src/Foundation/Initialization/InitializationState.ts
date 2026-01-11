/**
 * Initialization State
 *
 * Tracks the complete initialization state of the SDK.
 * Matches iOS SDK state tracking pattern.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift
 */

import { InitializationPhase } from './InitializationPhase';
import type { SDKEnvironment } from '../../types';

/**
 * Parameters passed to SDK initialization
 * Matches iOS SDKInitParams
 */
export interface SDKInitParams {
  /**
   * API key for backend authentication
   */
  apiKey?: string;

  /**
   * Base URL for API calls
   */
  baseURL?: string;

  /**
   * SDK environment (development, staging, production)
   */
  environment: SDKEnvironment;
}

/**
 * Complete initialization state of the SDK
 */
export interface InitializationState {
  /**
   * Current initialization phase
   */
  phase: InitializationPhase;

  /**
   * Whether Phase 1 (core) initialization is complete
   * Equivalent to iOS: isInitialized
   */
  isCoreInitialized: boolean;

  /**
   * Whether Phase 2 (services) initialization is complete
   * Equivalent to iOS: hasCompletedServicesInit
   */
  hasCompletedServicesInit: boolean;

  /**
   * Current SDK environment
   */
  environment: SDKEnvironment | null;

  /**
   * Stored initialization parameters
   */
  initParams: SDKInitParams | null;

  /**
   * Backend type in use (e.g., 'llamacpp', 'onnx')
   */
  backendType: string | null;

  /**
   * Error if initialization failed
   */
  error: Error | null;

  /**
   * Timestamp when Phase 1 completed
   */
  coreInitTimestamp: number | null;

  /**
   * Timestamp when Phase 2 completed
   */
  servicesInitTimestamp: number | null;
}

/**
 * Create initial (not initialized) state
 */
export function createInitialState(): InitializationState {
  return {
    phase: InitializationPhase.NotInitialized,
    isCoreInitialized: false,
    hasCompletedServicesInit: false,
    environment: null,
    initParams: null,
    backendType: null,
    error: null,
    coreInitTimestamp: null,
    servicesInitTimestamp: null,
  };
}

/**
 * Update state to Phase 1 complete
 */
export function markCoreInitialized(
  state: InitializationState,
  params: SDKInitParams,
  backendType: string | null
): InitializationState {
  return {
    ...state,
    phase: InitializationPhase.CoreInitialized,
    isCoreInitialized: true,
    environment: params.environment,
    initParams: params,
    backendType,
    coreInitTimestamp: Date.now(),
    error: null,
  };
}

/**
 * Update state to Phase 2 in progress
 */
export function markServicesInitializing(
  state: InitializationState
): InitializationState {
  return {
    ...state,
    phase: InitializationPhase.ServicesInitializing,
  };
}

/**
 * Update state to Phase 2 complete
 */
export function markServicesInitialized(
  state: InitializationState
): InitializationState {
  return {
    ...state,
    phase: InitializationPhase.FullyInitialized,
    hasCompletedServicesInit: true,
    servicesInitTimestamp: Date.now(),
  };
}

/**
 * Update state to failed
 */
export function markInitializationFailed(
  state: InitializationState,
  error: Error
): InitializationState {
  return {
    ...state,
    phase: InitializationPhase.Failed,
    error,
  };
}

/**
 * Reset state to initial
 */
export function resetState(): InitializationState {
  return createInitialState();
}
