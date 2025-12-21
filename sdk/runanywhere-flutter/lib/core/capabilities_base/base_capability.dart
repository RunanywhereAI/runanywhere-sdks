import 'dart:async';

import 'package:runanywhere/core/protocols/component/component.dart';
import 'package:runanywhere/core/protocols/component/component_configuration.dart';
import 'package:runanywhere/core/types/component_state.dart';
import 'package:runanywhere/core/types/sdk_component.dart';
import 'package:runanywhere/foundation/dependency_injection/service_container.dart';
import 'package:runanywhere/public/events/component_initialization_event.dart';
import 'package:runanywhere/public/events/event_bus.dart';

/// Simplified base capability for all SDK capabilities
/// Matches iOS BaseCapability pattern from Features/
abstract class BaseCapability<T> implements Component {
  /// Current state
  ComponentState _state = ComponentState.notInitialized;

  @override
  ComponentState get state => _state;

  /// The service that performs the actual work
  T? _service;

  T? get service => _service;

  /// Configuration (immutable)
  final ComponentConfiguration configuration;

  /// Service container for dependency injection
  final ServiceContainer? serviceContainer;

  /// Event bus for publishing events
  final EventBus eventBus = EventBus.shared;

  /// Current processing stage
  String? currentStage;

  /// Initialize the capability
  BaseCapability({
    required this.configuration,
    this.serviceContainer,
  });

  @override
  Future<void> initialize() async {
    if (_state != ComponentState.notInitialized) {
      if (_state == ComponentState.ready) {
        return; // Already initialized
      }
      throw StateError('Cannot initialize from state: $_state');
    }

    // Emit state change event
    _updateState(ComponentState.initializing);

    try {
      // Stage: Validation
      currentStage = 'validation';
      eventBus.publish(ComponentInitializationEvent.componentChecking(
        component: componentType,
        modelId: null,
      ));
      configuration.validate();

      // Stage: Service Creation
      currentStage = 'service_creation';
      eventBus.publish(ComponentInitializationEvent.componentInitializing(
        component: componentType,
        modelId: null,
      ));
      _service = await createService();

      // Stage: Service Initialization
      currentStage = 'service_initialization';
      await initializeService();

      // Component ready
      currentStage = null;
      _updateState(ComponentState.ready);
      eventBus.publish(ComponentInitializationEvent.componentReady(
        component: componentType,
        modelId: null,
      ));
    } catch (e) {
      _updateState(ComponentState.failed);
      eventBus.publish(ComponentInitializationEvent.componentFailed(
        component: componentType,
        error: e,
      ));
      rethrow;
    }
  }

  /// Create the service (override in subclass)
  Future<T> createService();

  /// Initialize the service (override if needed)
  Future<void> initializeService() async {
    // Default: no-op
    // Override in subclass if service needs initialization
  }

  @override
  Future<void> cleanup() async {
    if (_state == ComponentState.notInitialized) {
      return;
    }

    _state = ComponentState.notInitialized;

    // Allow subclass to perform cleanup
    await performCleanup();

    // Clear service reference
    _service = null;

    _state = ComponentState.notInitialized;
  }

  /// Perform cleanup (override in subclass if needed)
  Future<void> performCleanup() async {
    // Default: no-op
    // Override in subclass for custom cleanup
  }

  @override
  bool get isReady => _state == ComponentState.ready;

  @override
  ComponentInitParameters? get parameters {
    // Default implementation returns null.
    // Subclasses should override if configuration implements ComponentInitParameters.
    final config = configuration;
    if (config is ComponentInitParameters) {
      return config as ComponentInitParameters;
    }
    return null;
  }

  /// Ensure capability is ready for processing
  void ensureReady() {
    if (_state != ComponentState.ready) {
      throw StateError(
        '${componentType.value} is not ready. Current state: $_state',
      );
    }
  }

  /// Update state and emit event
  void _updateState(ComponentState newState) {
    final oldState = _state;
    _state = newState;
    eventBus.publish(ComponentInitializationEvent.componentStateChanged(
      component: componentType,
      oldState: oldState,
      newState: newState,
    ));
  }

  @override
  Future<void> transitionTo(ComponentState newState) async {
    _updateState(newState);
  }

  /// Get component type (must be overridden in subclasses)
  SDKComponent get componentType;
}
