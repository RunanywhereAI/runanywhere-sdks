/**
 * Initialization State
 *
 * Tracks the complete initialization state of the SDK.
 * Matches iOS SDK state tracking pattern.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift
 */

import { InitializationPhase } from './InitializationPhase';
import type { SDKEnvironment } from '@runanywhere/proto-ts/model_types';
import type { SDKInitOptions } from '../../types/models';

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
   * Equivalent to iOS: isInitialized. RN reaches this through an async bridge.
   */
  isCoreInitialized: boolean;

  /**
   * Whether Phase 2 (services) initialization is complete
   * Equivalent to iOS: hasCompletedServicesInit
   */
  hasCompletedServicesInit: boolean;

  /**
   * Whether HTTP/auth setup succeeded. Tracked separately from
   * `hasCompletedServicesInit` so an offline Phase 2 (services done, HTTP
   * not configured) can be recovered by retrying only the auth round-trip
   * on the next public API call.
   * Equivalent to iOS: hasCompletedHTTPSetup
   * (RunAnywhere.swift `hasCompletedHTTPSetup` + `ensureServicesReady`)
   */
  hasCompletedHTTPSetup: boolean;

  /**
   * Whether HTTP setup is applicable at all for this configuration. When
   * commons reports `http_applicable=false` (dev mode / no usable external
   * config), public API calls must NOT keep retrying HTTP setup.
   * Equivalent to iOS: httpSetupApplicable (RunAnywhere.swift `SDKState`,
   * sourced from `RASdkInitResult.http_applicable`).
   */
  httpSetupApplicable: boolean;

  /**
   * Current SDK environment
   */
  environment: SDKEnvironment | null;

  /**
   * Stored initialization parameters
   */
  initParams: SDKInitOptions | null;

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
    hasCompletedHTTPSetup: false,
    httpSetupApplicable: true,
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
  params: SDKInitOptions,
  backendType: string | null
): InitializationState {
  return {
    ...state,
    phase: InitializationPhase.CoreInitialized,
    isCoreInitialized: true,
    environment: params.environment ?? null,
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
 * Update state to Phase 2 complete.
 *
 * `httpConfigured` mirrors Swift's `hasCompletedHTTPSetup` and reflects the
 * `http_configured` field on the Phase 2 result envelope. Phase 2 is allowed
 * to "complete" in offline mode (`hasCompletedServicesInit=true`,
 * `hasCompletedHTTPSetup=false`); the next public API call is expected to
 * call `markHTTPSetupResult` once `rac_sdk_retry_http_proto` succeeds.
 *
 * `httpApplicable` mirrors Swift's `httpSetupApplicable` and reflects the
 * `http_applicable` field on the same envelope; `false` stops further retries.
 */
export function markServicesInitialized(
  state: InitializationState,
  httpConfigured: boolean = false,
  httpApplicable: boolean = true
): InitializationState {
  return {
    ...state,
    phase: InitializationPhase.FullyInitialized,
    hasCompletedServicesInit: true,
    hasCompletedHTTPSetup: httpConfigured,
    httpSetupApplicable: httpApplicable,
    servicesInitTimestamp: Date.now(),
  };
}

/**
 * Record the outcome of an HTTP/auth setup retry (offline init recovery
 * path). Mirrors Swift `RunAnywhere.swift` `retryHTTPSetup()`, which updates
 * both `hasCompletedHTTPSetup` and `httpSetupApplicable` from the retry
 * proto result.
 */
export function markHTTPSetupResult(
  state: InitializationState,
  httpConfigured: boolean,
  httpApplicable: boolean = true
): InitializationState {
  return {
    ...state,
    hasCompletedHTTPSetup: httpConfigured || state.hasCompletedHTTPSetup,
    httpSetupApplicable: httpApplicable,
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
