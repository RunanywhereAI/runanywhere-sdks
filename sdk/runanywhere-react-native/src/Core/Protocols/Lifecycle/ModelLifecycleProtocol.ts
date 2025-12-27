/**
 * ModelLifecycleProtocol.ts
 *
 * Protocol for managing model lifecycle states
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Protocols/Lifecycle/ModelLifecycleProtocol.swift
 */

/**
 * Represents the various states in a model's lifecycle
 */
export enum ModelLifecycleState {
  Uninitialized = 'uninitialized',
  Discovered = 'discovered',
  Downloading = 'downloading',
  Downloaded = 'downloaded',
  Extracting = 'extracting',
  Extracted = 'extracted',
  Validating = 'validating',
  Validated = 'validated',
  Initializing = 'initializing',
  Initialized = 'initialized',
  Loading = 'loading',
  Loaded = 'loaded',
  Ready = 'ready',
  Executing = 'executing',
  Error = 'error',
  Cleanup = 'cleanup',
}

/**
 * Whether the model is currently processing an operation
 */
export function isModelLifecycleProcessing(state: ModelLifecycleState): boolean {
  return (
    state === ModelLifecycleState.Downloading ||
    state === ModelLifecycleState.Extracting ||
    state === ModelLifecycleState.Validating ||
    state === ModelLifecycleState.Initializing ||
    state === ModelLifecycleState.Loading ||
    state === ModelLifecycleState.Executing
  );
}

/**
 * Observer protocol for model lifecycle changes
 */
export interface ModelLifecycleObserver {
  /**
   * Called when the model transitions to a new state
   * @param oldState - Previous state
   * @param newState - New state
   */
  modelDidTransition(from: ModelLifecycleState, to: ModelLifecycleState): void;

  /**
   * Called when an error occurs during state transition
   * @param error - The error that occurred
   * @param state - The state where the error occurred
   */
  modelDidEncounterError(error: Error, inState: ModelLifecycleState): void;
}

/**
 * Protocol for managing model lifecycle states
 */
export interface ModelLifecycleManager {
  /**
   * Current state of the model
   */
  readonly currentState: ModelLifecycleState;

  /**
   * Transition to a new state
   * @param state - The target state
   * @throws Error if the transition is invalid
   */
  transitionTo(state: ModelLifecycleState): Promise<void>;

  /**
   * Add an observer for state changes
   * @param observer - The observer to add
   */
  addObserver(observer: ModelLifecycleObserver): void;

  /**
   * Remove an observer
   * @param observer - The observer to remove
   */
  removeObserver(observer: ModelLifecycleObserver): void;

  /**
   * Check if a transition is valid
   * @param from - Source state
   * @param to - Target state
   * @returns Whether the transition is valid
   */
  isValidTransition(from: ModelLifecycleState, to: ModelLifecycleState): boolean;
}

/**
 * Errors related to model lifecycle
 */
export class ModelLifecycleError extends Error {
  constructor(
    message: string,
    public readonly fromState?: ModelLifecycleState,
    public readonly toState?: ModelLifecycleState,
    public readonly reason?: string
  ) {
    super(message);
    this.name = 'ModelLifecycleError';
  }

  static invalidTransition(
    from: ModelLifecycleState,
    to: ModelLifecycleState
  ): ModelLifecycleError {
    return new ModelLifecycleError(
      `Invalid transition from ${from} to ${to}`,
      from,
      to
    );
  }

  static statePrerequisiteNotMet(reason: string): ModelLifecycleError {
    return new ModelLifecycleError(`State prerequisite not met: ${reason}`, undefined, undefined, reason);
  }

  static transitionFailed(error: Error): ModelLifecycleError {
    return new ModelLifecycleError(
      `Transition failed: ${error.message}`,
      undefined,
      undefined,
      error.message
    );
  }

  static invalidState(reason: string): ModelLifecycleError {
    return new ModelLifecycleError(`Invalid state: ${reason}`, undefined, undefined, reason);
  }
}
