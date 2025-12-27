/**
 * BaseComponent.ts
 *
 * Simplified base component for all SDK components
 * Provides lifecycle management, state tracking, and event emission.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Components/BaseComponent.swift
 */

import { ComponentState } from '../Models/Common/ComponentState';
import { SDKComponent } from '../Models/Common/SDKComponent';
import type { ComponentInitParameters } from '../Models/Common/ComponentInitParameters';
import { EmptyComponentParameters } from '../Models/Common/ComponentInitParameters';
import { ServiceContainer } from '../../Foundation/DependencyInjection/ServiceContainer';
// EventBus and SDKError will be moved to Public/ later - using relative paths for now
import { EventBus } from '../../Public/Events/EventBus';
import { SDKError, SDKErrorCode } from '../../Public/Errors/SDKError';
import type { ComponentInitializationEvent } from '../../types/events';

// ============================================================================
// Component Protocols (TypeScript Interfaces)
// ============================================================================

/**
 * Base protocol for component inputs
 * Reference: ComponentInput protocol in BaseComponent.swift
 */
export interface ComponentInput {
  /** Validate the input */
  validate(): void;
  /** Optional timestamp for the input */
  timestamp?: Date;
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
 * Service wrapper protocol that allows protocol types to be used with BaseComponent
 * Reference: ServiceWrapper protocol in BaseComponent.swift
 */
export interface ServiceWrapper<T> {
  wrappedService: T | null;
}

/**
 * Generic service wrapper for any protocol
 */
export class AnyServiceWrapper<T> implements ServiceWrapper<T> {
  public wrappedService: T | null = null;

  constructor(service: T | null = null) {
    this.wrappedService = service;
  }
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
 * Simplified base component for all SDK components
 *
 * Provides:
 * - Lifecycle management (notInitialized -> initializing -> ready -> failed)
 * - State tracking and validation
 * - Event emission for state changes
 * - Service creation and cleanup patterns
 *
 * Reference: BaseComponent<TService> in BaseComponent.swift
 *
 * @template TService - The service type this component manages
 */
export abstract class BaseComponent<
  TService,
> implements ServiceComponent<TService> {
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
   * Current state (protected) - required by Component protocol
   * Reference: state in BaseComponent.swift
   */
  protected _state: ComponentState = ComponentState.NotInitialized;

  /**
   * The service that performs the actual work
   * Reference: service in BaseComponent.swift
   */
  protected service: TService | null = null;

  /**
   * Configuration (immutable)
   * Reference: configuration in BaseComponent.swift
   */
  public readonly configuration: ComponentConfiguration;

  /**
   * Parameters for Component protocol (bridge to configuration)
   * Reference: parameters in BaseComponent.swift
   */
  public get parameters(): ComponentInitParameters {
    // Bridge configuration to parameters if it conforms
    if (this.isComponentInitParameters(this.configuration)) {
      return this.configuration;
    }
    // Return empty parameters
    return new EmptyComponentParameters(this.componentType);
  }

  /**
   * Service container for dependency injection
   * Reference: serviceContainer in BaseComponent.swift
   */
  public serviceContainer?: ServiceContainer;

  /**
   * Event bus for publishing events
   * Reference: eventBus in BaseComponent.swift
   */
  public readonly eventBus = EventBus.getInstance();

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
   * @param serviceContainer - Optional service container for dependency injection
   */
  constructor(
    configuration: ComponentConfiguration,
    serviceContainer?: ServiceContainer
  ) {
    this.configuration = configuration;
    this.serviceContainer = serviceContainer ?? ServiceContainer.shared;
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
   * Reference: initialize(with:) in BaseComponent.swift
   *
   * @param _parameters - Optional initialization parameters (uses configuration if not provided)
   * @throws {SDKError} If initialization fails or component is in invalid state
   */
  async initialize(_parameters?: ComponentInitParameters): Promise<void> {
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
        modelId: undefined,
      } as ComponentInitializationEvent);

      this.configuration.validate();

      // Stage: Service Creation
      this.currentStage = 'service_creation';
      this.eventBus.emitComponentInitialization({
        type: 'componentInitializing',
        component: this.componentType,
        modelId: undefined,
      } as ComponentInitializationEvent);

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
        modelId: undefined,
      } as ComponentInitializationEvent);
    } catch (error) {
      this.updateState(ComponentState.Failed);
      this.eventBus.emitComponentInitialization({
        type: 'componentFailed',
        component: this.componentType,
        error: error instanceof Error ? error.message : String(error),
      } as ComponentInitializationEvent);
      throw error;
    }
  }

  /**
   * Create the service (override in subclass)
   * Reference: createService() in BaseComponent.swift
   *
   * @returns The created service instance
   * @throws {SDKError} If service creation fails
   */
  protected abstract createService(): Promise<TService>;

  /**
   * Initialize the service (override if needed)
   * Reference: initializeService() in BaseComponent.swift
   *
   * @throws {SDKError} If service initialization fails
   */
  protected async initializeService(): Promise<void> {
    // Default: no-op
    // Override in subclass if service needs initialization
  }

  /**
   * Cleanup
   * Reference: cleanup() in BaseComponent.swift
   *
   * @throws {SDKError} If cleanup fails
   */
  async cleanup(): Promise<void> {
    if (this._state === ComponentState.NotInitialized) {
      return;
    }

    this._state = ComponentState.NotInitialized;

    // Allow subclass to perform cleanup
    await this.performCleanup();

    // Clear service reference
    this.service = null;

    this._state = ComponentState.NotInitialized;
  }

  /**
   * Perform cleanup (override in subclass if needed)
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
   * Reference: updateState() in BaseComponent.swift
   *
   * @param newState - The new state to transition to
   */
  private updateState(newState: ComponentState): void {
    const oldState = this._state;
    this._state = newState;
    this.eventBus.emitComponentInitialization({
      type: 'componentStateChanged',
      component: this.componentType,
      oldState: String(oldState),
      newState: String(newState),
    } as ComponentInitializationEvent);
  }

  /**
   * Handle state transitions
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
      typeof (config as ComponentInitParameters).componentType === 'string'
    );
  }
}
