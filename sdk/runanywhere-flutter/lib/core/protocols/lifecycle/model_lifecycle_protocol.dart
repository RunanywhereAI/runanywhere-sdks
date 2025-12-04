// Model lifecycle state and management protocols
// Matches iOS ModelLifecycleProtocol from Core/Protocols/Lifecycle/ModelLifecycleProtocol.swift

/// Represents the various states in a model's lifecycle
enum ModelLifecycleState {
  uninitialized('uninitialized'),
  discovered('discovered'),
  downloading('downloading'),
  downloaded('downloaded'),
  extracting('extracting'),
  extracted('extracted'),
  validating('validating'),
  validated('validated'),
  initializing('initializing'),
  initialized('initialized'),
  loading('loading'),
  loaded('loaded'),
  ready('ready'),
  executing('executing'),
  error('error'),
  cleanup('cleanup');

  final String rawValue;

  const ModelLifecycleState(this.rawValue);

  /// Whether the model is currently processing an operation
  bool get isProcessing {
    switch (this) {
      case ModelLifecycleState.downloading:
      case ModelLifecycleState.extracting:
      case ModelLifecycleState.validating:
      case ModelLifecycleState.initializing:
      case ModelLifecycleState.loading:
      case ModelLifecycleState.executing:
        return true;
      default:
        return false;
    }
  }
}

/// Observer protocol for model lifecycle changes
abstract class ModelLifecycleObserver {
  /// Called when the model transitions to a new state
  void modelDidTransition(
    ModelLifecycleState oldState,
    ModelLifecycleState newState,
  );

  /// Called when an error occurs during state transition
  void modelDidEncounterError(Object error, ModelLifecycleState state);
}

/// Protocol for managing model lifecycle states
abstract class ModelLifecycleManager {
  /// Current state of the model
  ModelLifecycleState get currentState;

  /// Transition to a new state
  Future<void> transitionTo(ModelLifecycleState state);

  /// Add an observer for state changes
  void addObserver(ModelLifecycleObserver observer);

  /// Remove an observer
  void removeObserver(ModelLifecycleObserver observer);

  /// Check if a transition is valid
  bool isValidTransition(ModelLifecycleState from, ModelLifecycleState to);
}

/// Errors related to model lifecycle
sealed class ModelLifecycleError implements Exception {
  String get message;
}

class InvalidTransitionError extends ModelLifecycleError {
  final ModelLifecycleState from;
  final ModelLifecycleState to;

  InvalidTransitionError(this.from, this.to);

  @override
  String get message =>
      'Invalid transition from ${from.rawValue} to ${to.rawValue}';

  @override
  String toString() => 'InvalidTransitionError: $message';
}

class StatePrerequisiteNotMetError extends ModelLifecycleError {
  final String reason;

  StatePrerequisiteNotMetError(this.reason);

  @override
  String get message => 'State prerequisite not met: $reason';

  @override
  String toString() => 'StatePrerequisiteNotMetError: $message';
}

class TransitionFailedError extends ModelLifecycleError {
  final Object cause;

  TransitionFailedError(this.cause);

  @override
  String get message => 'Transition failed: $cause';

  @override
  String toString() => 'TransitionFailedError: $message';
}

class InvalidStateError extends ModelLifecycleError {
  final String reason;

  InvalidStateError(this.reason);

  @override
  String get message => 'Invalid state: $reason';

  @override
  String toString() => 'InvalidStateError: $message';
}
