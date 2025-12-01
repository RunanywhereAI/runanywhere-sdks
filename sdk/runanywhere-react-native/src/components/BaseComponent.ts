/**
 * BaseComponent.ts
 *
 * Abstract base class for all SDK components in the React Native SDK.
 * Provides lifecycle management, state tracking, and event emission.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Components/BaseComponent.swift
 */

import { EventBus, type EventBusImpl } from '../Public/Events';
import { SDKError, SDKErrorCode } from '../Public/Errors/SDKError';
import { ComponentState, SDKComponent } from '../types/enums';
import type { ComponentInitializationEvent } from '../types/events';

// ============================================================================
// Component Protocols (TypeScript Interfaces)
// ============================================================================

/**
 * Base protocol for component inputs
 * Reference: ComponentInput protocol in BaseComponent.swift
 */
export interface ComponentInput {
  validate(): void;
}

/**
 * Base protocol for component outputs
 * Reference: ComponentOutput protocol in BaseComponent.swift
 */
export interface ComponentOutput {
  timestamp: Date;
}

/**
 * Base protocol for component configurations
 * Reference: ComponentConfiguration protocol in BaseComponent.swift
 */
export interface ComponentConfiguration {
  validate(): void;
}

/**
 * Base protocol for component initialization parameters
 * Reference: ComponentInitParameters protocol in Component.swift
 */
export interface ComponentInitParameters {
  componentType: SDKComponent;
  modelId?: string;
  validate(): void;
}

/**
 * Service wrapper protocol for protocol types
 * Reference: ServiceWrapper protocol in BaseComponent.swift
 */
export interface ServiceWrapper<T> {
  wrappedService: T | null;
}

/**
 * Core component interface
 * Reference: Component protocol in Component.swift
 */
export interface Component {
  /** Component type identifier */
  readonly componentType: SDKComponent;

  /** Current state of the component */
  readonly state: ComponentState;

  /** Configuration parameters */
  readonly parameters: ComponentInitParameters;

  /** Initialize the component */
  initialize(parameters?: ComponentInitParameters): Promise<void>;

  /** Clean up and release resources */
  cleanup(): Promise<void>;

  /** Check if component is ready for use */
  readonly isReady: boolean;

  /** Handle state transitions */
  transitionTo(state: ComponentState): Promise<void>;
}

/**
 * Protocol for components that provide services
 * Reference: ServiceComponent protocol in Component.swift
 */
export interface ServiceComponent<TService> extends Component {
  /** Get the underlying service instance */
  getService(): TService | null;
}

// ============================================================================
// Base Component Implementation
// ============================================================================

/**
 * Abstract base component for all SDK components
 *
 * Provides:
 * - Lifecycle management (notInitialized -> initializing -> ready -> error)
 * - State tracking and validation
 * - Event emission for state changes
 * - Service creation and cleanup patterns
 *
 * Reference: BaseComponent<TService> in BaseComponent.swift
 *
 * @template TService - The service type this component manages
 *
 * @example
 * ```typescript
 * class MyComponent extends BaseComponent<MyService> {
 *   static override componentType = SDKComponent.LLM;
 *
 *   protected async createService(): Promise<MyService> {
 *     return new MyService(this.configuration);
 *   }
 *
 *   protected async performCleanup(): Promise<void> {
 *     await this.service?.cleanup();
 *   }
 * }
 * ```
 */
export abstract class BaseComponent<TService> implements ServiceComponent<TService> {
  // ============================================================================
  // Static Properties
  // ============================================================================

  /**
   * Component type identifier (must be overridden in subclass)
   * Reference: componentType in BaseComponent.swift
   */
  static componentType: SDKComponent = SDKComponent.LLM; // Default, override in subclass

  // ============================================================================
  // Instance Properties
  // ============================================================================

  /**
   * Current component state
   * Reference: state in BaseComponent.swift
   */
  protected _state: ComponentState = ComponentState.NotInitialized;

  /**
   * The service that performs the actual work
   * Reference: service in BaseComponent.swift
   */
  protected service: TService | null = null;

  /**
   * Component configuration
   * Reference: configuration in BaseComponent.swift
   */
  protected readonly configuration: ComponentConfiguration;

  /**
   * Event bus for publishing events
   * Reference: eventBus in BaseComponent.swift
   */
  protected readonly eventBus: EventBusImpl = EventBus.getInstance();

  /**
   * Current processing stage
   * Reference: currentStage in BaseComponent.swift
   */
  protected currentStage: string | null = null;

  // ============================================================================
  // Constructor
  // ============================================================================

  /**
   * Create a new base component
   *
   * @param configuration - Component-specific configuration
   */
  constructor(configuration: ComponentConfiguration) {
    this.configuration = configuration;
  }

  // ============================================================================
  // Component Protocol Implementation
  // ============================================================================

  /**
   * Get component type
   * Reference: componentType in Component protocol
   */
  get componentType(): SDKComponent {
    return (this.constructor as typeof BaseComponent).componentType;
  }

  /**
   * Get current state
   * Reference: state in Component protocol
   */
  get state(): ComponentState {
    return this._state;
  }

  /**
   * Get initialization parameters
   * Reference: parameters in Component protocol
   */
  get parameters(): ComponentInitParameters {
    // Bridge configuration to parameters if it implements the interface
    if (this.isComponentInitParameters(this.configuration)) {
      return this.configuration;
    }
    // Return empty parameters
    return {
      componentType: this.componentType,
      modelId: undefined,
      validate: () => {},
    };
  }

  /**
   * Check if component is ready
   * Reference: isReady in Component protocol
   */
  get isReady(): boolean {
    return this._state === ComponentState.Ready;
  }

  // ============================================================================
  // Lifecycle Methods
  // ============================================================================

  /**
   * Initialize the component
   *
   * Follows the lifecycle:
   * 1. Validate configuration
   * 2. Create service
   * 3. Initialize service
   * 4. Transition to ready state
   *
   * Reference: initialize() in BaseComponent.swift
   *
   * @param parameters - Optional initialization parameters (uses configuration if not provided)
   * @throws {SDKError} If initialization fails or component is in invalid state
   */
  async initialize(parameters?: ComponentInitParameters): Promise<void> {
    // Check current state
    if (this._state !== ComponentState.NotInitialized) {
      if (this._state === ComponentState.Ready) {
        return; // Already initialized
      }
      throw new SDKError(
        SDKErrorCode.InvalidState,
        `Cannot initialize from state: ${this._state}`
      );
    }

    // Emit state change event
    this.updateState(ComponentState.Initializing);

    try {
      // Stage: Validation
      this.currentStage = 'validation';
      this.eventBus.emitComponentInitialization({
        type: 'componentChecking',
        component: this.componentType,
        modelId: parameters?.modelId,
      });
      this.configuration.validate();

      // Stage: Service Creation
      this.currentStage = 'service_creation';
      this.eventBus.emitComponentInitialization({
        type: 'componentInitializing',
        component: this.componentType,
        modelId: parameters?.modelId,
      });
      this.service = await this.createService();

      // Stage: Service Initialization
      this.currentStage = 'service_initialization';
      await this.initializeService();

      // Component ready
      this.currentStage = null;
      this.updateState(ComponentState.Ready);
      this.eventBus.emitComponentInitialization({
        type: 'componentReady',
        component: this.componentType,
        modelId: parameters?.modelId,
      });
    } catch (error) {
      this.updateState(ComponentState.Error);
      this.eventBus.emitComponentInitialization({
        type: 'componentFailed',
        component: this.componentType,
        error: error instanceof Error ? error.message : String(error),
      });
      throw error;
    }
  }

  /**
   * Create the service instance (must be overridden in subclass)
   *
   * Reference: createService() in BaseComponent.swift
   *
   * @returns The created service instance
   * @throws {SDKError} If service creation fails
   */
  protected abstract createService(): Promise<TService>;

  /**
   * Initialize the service (can be overridden if needed)
   *
   * Reference: initializeService() in BaseComponent.swift
   *
   * @throws {SDKError} If service initialization fails
   */
  protected async initializeService(): Promise<void> {
    // Default: no-op
    // Override in subclass if service needs initialization
  }

  /**
   * Clean up and release resources
   *
   * Reference: cleanup() in BaseComponent.swift
   *
   * @throws {SDKError} If cleanup fails
   */
  async cleanup(): Promise<void> {
    if (this._state === ComponentState.NotInitialized) {
      return; // Already cleaned up
    }

    this._state = ComponentState.CleaningUp;

    // Allow subclass to perform cleanup
    await this.performCleanup();

    // Clear service reference
    this.service = null;

    // Reset state
    this._state = ComponentState.NotInitialized;
  }

  /**
   * Perform cleanup (can be overridden in subclass)
   *
   * Reference: performCleanup() in BaseComponent.swift
   */
  protected async performCleanup(): Promise<void> {
    // Default: no-op
    // Override in subclass for custom cleanup
  }

  // ============================================================================
  // State Management
  // ============================================================================

  /**
   * Ensure component is ready for processing
   *
   * Reference: ensureReady() in BaseComponent.swift
   *
   * @throws {SDKError} If component is not ready
   */
  protected ensureReady(): void {
    if (this._state !== ComponentState.Ready) {
      throw new SDKError(
        SDKErrorCode.ComponentNotReady,
        `${this.componentType} is not ready. Current state: ${this._state}`
      );
    }
  }

  /**
   * Update state and emit event
   *
   * Reference: updateState() in BaseComponent.swift
   *
   * @param newState - The new state to transition to
   */
  protected updateState(newState: ComponentState): void {
    const oldState = this._state;
    this._state = newState;
    this.eventBus.emitComponentInitialization({
      type: 'componentStateChanged',
      component: this.componentType,
      oldState: oldState,
      newState: newState,
    });
  }

  /**
   * Handle state transitions
   *
   * Reference: transitionTo(state:) in Component protocol
   *
   * @param state - Target state
   */
  async transitionTo(state: ComponentState): Promise<void> {
    this.updateState(state);
  }

  // ============================================================================
  // Service Component Protocol
  // ============================================================================

  /**
   * Get the underlying service instance
   *
   * Reference: getService() in ServiceComponent protocol
   *
   * @returns The service instance or null if not initialized
   */
  getService(): TService | null {
    return this.service;
  }

  // ============================================================================
  // Helper Methods
  // ============================================================================

  /**
   * Type guard to check if configuration implements ComponentInitParameters
   */
  private isComponentInitParameters(
    config: ComponentConfiguration
  ): config is ComponentConfiguration & ComponentInitParameters {
    return (
      'componentType' in config &&
      'modelId' in config &&
      typeof (config as any).componentType === 'string'
    );
  }
}

