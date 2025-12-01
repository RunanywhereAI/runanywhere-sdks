/**
 * Component.ts
 *
 * Core component protocol and related protocols
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Protocols/Component/Component.swift
 */

import type { ComponentState } from '../../Models/Common/ComponentState';
import type { SDKComponent } from '../../Models/Common/SDKComponent';
import type { ComponentInitParameters } from '../../Models/Common/ComponentInitParameters';

// ============================================================================
// Core Component Protocol
// ============================================================================

/**
 * Base protocol that all SDK components must implement
 */
export interface Component {
  /**
   * Unique identifier for this component type
   */
  readonly componentType: SDKComponent;

  /**
   * Current state of the component
   */
  readonly state: ComponentState;

  /**
   * Configuration parameters for this component
   */
  readonly parameters: ComponentInitParameters;

  /**
   * Initialize the component with given parameters
   * @param parameters - Component-specific initialization parameters
   * @throws Error if initialization fails
   */
  initialize(parameters?: ComponentInitParameters): Promise<void>;

  /**
   * Clean up and release resources
   */
  cleanup(): Promise<void>;

  /**
   * Check if component is ready for use
   */
  readonly isReady: boolean;

  /**
   * Handle state transitions
   * @param state - Target state
   */
  transitionTo(state: ComponentState): Promise<void>;
}

// ============================================================================
// Lifecycle Management Protocol
// ============================================================================

/**
 * Protocol for components that need lifecycle management
 */
export interface LifecycleManaged extends Component {
  /**
   * Called before initialization
   */
  willInitialize(): Promise<void>;

  /**
   * Called after successful initialization
   */
  didInitialize(): Promise<void>;

  /**
   * Called before cleanup
   */
  willCleanup(): Promise<void>;

  /**
   * Called after cleanup
   */
  didCleanup(): Promise<void>;

  /**
   * Handle memory pressure
   */
  handleMemoryPressure(): Promise<void>;
}

// ============================================================================
// Model-Based Component
// ============================================================================

/**
 * Protocol for components that require model loading
 */
export interface ModelBasedComponent extends Component {
  /**
   * Model identifier
   */
  readonly modelId: string | null;

  /**
   * Check if model is loaded
   */
  readonly isModelLoaded: boolean;

  /**
   * Load the model
   * @param modelId - Model identifier to load
   */
  loadModel(modelId: string): Promise<void>;

  /**
   * Unload the model
   */
  unloadModel(): Promise<void>;

  /**
   * Get model memory usage
   * @returns Memory usage in bytes
   */
  getModelMemoryUsage(): Promise<number>;
}

// ============================================================================
// Service Component
// ============================================================================

/**
 * Protocol for components that provide services
 */
export interface ServiceComponent<TService> extends Component {
  /**
   * Get the underlying service instance
   * @returns The service instance or null if not initialized
   */
  getService(): TService | null;

  /**
   * Create service instance
   * @returns The created service instance
   */
  createService(): Promise<TService>;
}

// ============================================================================
// Pipeline Component
// ============================================================================

/**
 * Protocol for components that can be part of a pipeline
 */
export interface PipelineComponent<TInput, TOutput> extends Component {
  /**
   * Process input and return output
   * @param input - Input data
   * @returns Processed output
   */
  process(input: TInput): Promise<TOutput>;

  /**
   * Check if this component can connect to another
   * @param component - Component to check compatibility with
   * @returns Whether the components can be connected
   */
  canConnectTo(component: Component): boolean;
}

// ============================================================================
// Component Initialization Result
// ============================================================================

/**
 * Result of component initialization for observability
 */
export interface ComponentInitResult {
  /**
   * Component type
   */
  readonly component: SDKComponent;

  /**
   * Whether initialization was successful
   */
  success: boolean;

  /**
   * Duration of initialization in milliseconds
   */
  readonly duration: number;

  /**
   * Adapter used (if any)
   */
  readonly adapter: string | null;

  /**
   * Error message (if failed)
   */
  error: string | null;

  /**
   * Additional metadata
   */
  metadata: Record<string, string>;
}

/**
 * Create a successful component initialization result
 */
export function createComponentInitResult(
  component: SDKComponent,
  duration: number,
  adapter?: string | null,
  metadata?: Record<string, string>
): ComponentInitResult {
  return {
    component,
    success: true,
    duration,
    adapter: adapter ?? null,
    error: null,
    metadata: metadata ?? {},
  };
}

/**
 * Create a failed component initialization result
 */
export function createFailedComponentInitResult(
  component: SDKComponent,
  duration: number,
  error: string,
  metadata?: Record<string, string>
): ComponentInitResult {
  return {
    component,
    success: false,
    duration,
    adapter: null,
    error,
    metadata: metadata ?? {},
  };
}

