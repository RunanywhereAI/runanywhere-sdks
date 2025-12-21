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
