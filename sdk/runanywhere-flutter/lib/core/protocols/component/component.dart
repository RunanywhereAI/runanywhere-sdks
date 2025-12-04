import 'dart:async';

import '../../types/component_state.dart';
import '../../types/sdk_component.dart';
import 'component_configuration.dart';

/// Base protocol that all SDK components must implement
abstract class Component {
  /// Unique identifier for this component type
  static SDKComponent get componentType {
    throw UnimplementedError('componentType must be overridden');
  }

  /// Current state of the component
  ComponentState get state;

  /// Configuration parameters for this component.
  /// Returns null if component has no parameters.
  ComponentInitParameters? get parameters;

  /// Initialize the component
  Future<void> initialize();

  /// Clean up and release resources
  Future<void> cleanup();

  /// Check if component is ready for use
  bool get isReady;

  /// Handle state transitions
  Future<void> transitionTo(ComponentState newState);
}

/// Protocol for components that need lifecycle management
abstract class LifecycleManaged extends Component {
  /// Called before initialization
  Future<void> willInitialize();

  /// Called after successful initialization
  Future<void> didInitialize();

  /// Called before cleanup
  Future<void> willCleanup();

  /// Called after cleanup
  Future<void> didCleanup();

  /// Handle memory pressure
  Future<void> handleMemoryPressure();
}

/// Protocol for components that require model loading
abstract class ModelBasedComponent extends Component {
  /// Model identifier
  String? get modelId;

  /// Check if model is loaded
  bool get isModelLoaded;

  /// Load the model
  Future<void> loadModel(String modelId);

  /// Unload the model
  Future<void> unloadModel();

  /// Get model memory usage
  Future<int> getModelMemoryUsage();
}

/// Protocol for components that provide services
abstract class ServiceComponent<T> extends Component {
  /// Get the underlying service instance
  T? getService();

  /// Create service instance
  Future<T> createService();
}

/// Protocol for components that can be part of a pipeline
abstract class PipelineComponent<Input, Output> extends Component {
  /// Process input and return output
  Future<Output> process(Input input);

  /// Check if this component can connect to another
  bool canConnectTo(Component component);
}

/// Result of component initialization for observability
class ComponentInitResult {
  final SDKComponent component;
  final bool success;
  final Duration duration;
  final String? adapter;
  final String? error;
  final Map<String, String> metadata;

  ComponentInitResult({
    required this.component,
    required this.success,
    required this.duration,
    this.adapter,
    this.error,
    Map<String, String>? metadata,
  }) : metadata = metadata ?? {};
}
