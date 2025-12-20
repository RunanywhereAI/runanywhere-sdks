/**
 * CapabilityProtocols.ts
 *
 * Base protocols and types for capability abstraction.
 * Matches iOS: Core/Capabilities/CapabilityProtocols.swift
 */

// ============================================================================
// Capability Loading State
// ============================================================================

/**
 * Represents the loading state of a capability.
 * Simple state machine: idle -> loading -> loaded OR failed
 */
export type CapabilityLoadingState =
  | { type: 'idle' }
  | { type: 'loading'; resourceId: string }
  | { type: 'loaded'; resourceId: string }
  | { type: 'failed'; error: Error };

/**
 * Create an idle state
 */
export function idleState(): CapabilityLoadingState {
  return { type: 'idle' };
}

/**
 * Create a loading state
 */
export function loadingState(resourceId: string): CapabilityLoadingState {
  return { type: 'loading', resourceId };
}

/**
 * Create a loaded state
 */
export function loadedState(resourceId: string): CapabilityLoadingState {
  return { type: 'loaded', resourceId };
}

/**
 * Create a failed state
 */
export function failedState(error: Error): CapabilityLoadingState {
  return { type: 'failed', error };
}

/**
 * Check if state is idle
 */
export function isIdle(state: CapabilityLoadingState): boolean {
  return state.type === 'idle';
}

/**
 * Check if state is loading
 */
export function isLoading(state: CapabilityLoadingState): boolean {
  return state.type === 'loading';
}

/**
 * Check if state is loaded
 */
export function isLoaded(state: CapabilityLoadingState): boolean {
  return state.type === 'loaded';
}

/**
 * Check if state is failed
 */
export function isFailed(state: CapabilityLoadingState): boolean {
  return state.type === 'failed';
}

/**
 * Get resource ID from state (if available)
 */
export function getResourceId(state: CapabilityLoadingState): string | null {
  if (state.type === 'loading' || state.type === 'loaded') {
    return state.resourceId;
  }
  return null;
}

// ============================================================================
// Capability Operation Result
// ============================================================================

/**
 * Result of a capability operation with timing metadata
 */
export interface CapabilityOperationResult<T> {
  readonly value: T;
  readonly processingTimeMs: number;
  readonly resourceId: string | null;
}

/**
 * Create a capability operation result
 */
export function createOperationResult<T>(
  value: T,
  processingTimeMs: number,
  resourceId?: string | null
): CapabilityOperationResult<T> {
  return {
    value,
    processingTimeMs,
    resourceId: resourceId ?? null,
  };
}

// ============================================================================
// Component Configuration Protocol
// ============================================================================

/**
 * Base interface for component configuration.
 * Matches iOS ComponentConfiguration protocol.
 */
export interface ComponentConfiguration {
  /**
   * Validate the configuration
   * @throws Error if configuration is invalid
   */
  validate?(): void;
}

// ============================================================================
// Capability Protocols
// ============================================================================

/**
 * Base protocol for all capabilities.
 * Matches iOS Capability protocol.
 */
export interface Capability<TConfiguration extends ComponentConfiguration = ComponentConfiguration> {
  /**
   * Configure the capability
   */
  configure(config: TConfiguration): void;

  /**
   * Cleanup resources
   */
  cleanup(): Promise<void>;
}

/**
 * Protocol for capabilities that load models/resources.
 * Matches iOS ModelLoadableCapability protocol.
 */
export interface ModelLoadableCapability<
  TService,
  TConfiguration extends ComponentConfiguration = ComponentConfiguration,
> extends Capability<TConfiguration> {
  /**
   * Whether a model is currently loaded
   */
  readonly isModelLoaded: boolean;

  /**
   * The currently loaded model/resource ID
   */
  readonly currentModelId: string | null;

  /**
   * Load a model by ID
   * @param modelId - The model identifier
   */
  loadModel(modelId: string): Promise<void>;

  /**
   * Unload the currently loaded model
   */
  unload(): Promise<void>;
}

/**
 * Protocol for capabilities that initialize a service without model loading.
 * (e.g., VAD, Speaker Diarization)
 * Matches iOS ServiceBasedCapability protocol.
 */
export interface ServiceBasedCapability<
  TService,
  TConfiguration extends ComponentConfiguration = ComponentConfiguration,
> extends Capability<TConfiguration> {
  /**
   * Whether the capability is ready to use
   */
  readonly isReady: boolean;

  /**
   * Initialize the capability with default configuration
   */
  initialize(): Promise<void>;

  /**
   * Initialize the capability with configuration
   */
  initializeWithConfig(config: TConfiguration): Promise<void>;
}

/**
 * Protocol for capabilities that compose multiple other capabilities.
 * (e.g., VoiceAgent which uses STT, LLM, TTS, VAD)
 * Matches iOS CompositeCapability protocol.
 */
export interface CompositeCapability {
  /**
   * Whether the composite capability is fully initialized
   */
  readonly isReady: boolean;

  /**
   * Clean up all composed resources
   */
  cleanup(): Promise<void>;
}

// ============================================================================
// Capability Metrics Helper
// ============================================================================

/**
 * Helper for tracking capability operation metrics
 */
export class CapabilityMetrics {
  public readonly startTime: number;
  public readonly resourceId: string;

  constructor(resourceId: string) {
    this.startTime = Date.now();
    this.resourceId = resourceId;
  }

  /**
   * Get elapsed time in milliseconds
   */
  get elapsedMs(): number {
    return Date.now() - this.startTime;
  }

  /**
   * Create a result with the current metrics
   */
  result<T>(value: T): CapabilityOperationResult<T> {
    return createOperationResult(value, this.elapsedMs, this.resourceId);
  }
}

// ============================================================================
// Capability Error
// ============================================================================

/**
 * Common errors for capability operations.
 * Matches iOS CapabilityError enum.
 */
export class CapabilityError extends Error {
  constructor(
    message: string,
    public readonly code: CapabilityErrorCode
  ) {
    super(message);
    this.name = 'CapabilityError';
  }

  static notInitialized(capability: string): CapabilityError {
    return new CapabilityError(`${capability} is not initialized`, CapabilityErrorCode.NotInitialized);
  }

  static resourceNotLoaded(resource: string): CapabilityError {
    return new CapabilityError(
      `No ${resource} is loaded. Call load first.`,
      CapabilityErrorCode.ResourceNotLoaded
    );
  }

  static loadFailed(resource: string, underlyingError?: Error): CapabilityError {
    const message = underlyingError
      ? `Failed to load ${resource}: ${underlyingError.message}`
      : `Failed to load ${resource}: Unknown error`;
    return new CapabilityError(message, CapabilityErrorCode.LoadFailed);
  }

  static operationFailed(operation: string, underlyingError?: Error): CapabilityError {
    const message = underlyingError
      ? `${operation} failed: ${underlyingError.message}`
      : `${operation} failed: Unknown error`;
    return new CapabilityError(message, CapabilityErrorCode.OperationFailed);
  }

  static providerNotFound(provider: string): CapabilityError {
    return new CapabilityError(
      `No ${provider} provider registered. Please register a provider first.`,
      CapabilityErrorCode.ProviderNotFound
    );
  }

  static compositeComponentFailed(component: string, underlyingError?: Error): CapabilityError {
    const message = underlyingError
      ? `${component} component failed: ${underlyingError.message}`
      : `${component} component failed: Unknown error`;
    return new CapabilityError(message, CapabilityErrorCode.CompositeComponentFailed);
  }
}

/**
 * Error codes for capability errors
 */
export enum CapabilityErrorCode {
  NotInitialized = 'not_initialized',
  ResourceNotLoaded = 'resource_not_loaded',
  LoadFailed = 'load_failed',
  OperationFailed = 'operation_failed',
  ProviderNotFound = 'provider_not_found',
  CompositeComponentFailed = 'composite_component_failed',
}
