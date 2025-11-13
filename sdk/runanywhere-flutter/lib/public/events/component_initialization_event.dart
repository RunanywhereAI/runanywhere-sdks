import '../../core/types/sdk_component.dart';
import '../../core/types/component_state.dart';
import 'sdk_event.dart';

/// Component initialization events
abstract class ComponentInitializationEvent implements SDKEvent {
  static ComponentInitializationEvent componentChecking({
    required SDKComponent component,
    String? modelId,
  }) {
    return ComponentChecking(component: component, modelId: modelId);
  }

  static ComponentInitializationEvent componentInitializing({
    required SDKComponent component,
    String? modelId,
  }) {
    return ComponentInitializing(component: component, modelId: modelId);
  }

  static ComponentInitializationEvent componentReady({
    required SDKComponent component,
    String? modelId,
  }) {
    return ComponentReady(component: component, modelId: modelId);
  }

  static ComponentInitializationEvent componentFailed({
    required SDKComponent component,
    required Object error,
  }) {
    return ComponentFailed(component: component, error: error);
  }

  static ComponentInitializationEvent componentStateChanged({
    required SDKComponent component,
    required ComponentState oldState,
    required ComponentState newState,
  }) {
    return ComponentStateChanged(
      component: component,
      oldState: oldState,
      newState: newState,
    );
  }
}

class ComponentChecking implements ComponentInitializationEvent {
  final SDKComponent component;
  final String? modelId;
  @override
  final DateTime timestamp = DateTime.now();

  ComponentChecking({required this.component, this.modelId});
}

class ComponentInitializing implements ComponentInitializationEvent {
  final SDKComponent component;
  final String? modelId;
  @override
  final DateTime timestamp = DateTime.now();

  ComponentInitializing({required this.component, this.modelId});
}

class ComponentReady implements ComponentInitializationEvent {
  final SDKComponent component;
  final String? modelId;
  @override
  final DateTime timestamp = DateTime.now();

  ComponentReady({required this.component, this.modelId});
}

class ComponentFailed implements ComponentInitializationEvent {
  final SDKComponent component;
  final Object error;
  @override
  final DateTime timestamp = DateTime.now();

  ComponentFailed({required this.component, required this.error});
}

class ComponentStateChanged implements ComponentInitializationEvent {
  final SDKComponent component;
  final ComponentState oldState;
  final ComponentState newState;
  @override
  final DateTime timestamp = DateTime.now();

  ComponentStateChanged({
    required this.component,
    required this.oldState,
    required this.newState,
  });
}

