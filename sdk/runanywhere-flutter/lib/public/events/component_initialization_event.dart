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

  // Download events - matching iOS SDK patterns
  static ComponentInitializationEvent componentDownloadRequired({
    required SDKComponent component,
    required String modelId,
    required int sizeBytes,
  }) {
    return ComponentDownloadRequired(
      component: component,
      modelId: modelId,
      sizeBytes: sizeBytes,
    );
  }

  static ComponentInitializationEvent componentDownloadStarted({
    required SDKComponent component,
    required String modelId,
  }) {
    return ComponentDownloadStarted(component: component, modelId: modelId);
  }

  static ComponentInitializationEvent componentDownloadProgress({
    required SDKComponent component,
    required String modelId,
    required double progress,
  }) {
    return ComponentDownloadProgress(
      component: component,
      modelId: modelId,
      progress: progress,
    );
  }

  static ComponentInitializationEvent componentDownloadCompleted({
    required SDKComponent component,
    required String modelId,
  }) {
    return ComponentDownloadCompleted(component: component, modelId: modelId);
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

// Download event classes - matching iOS SDK patterns

class ComponentDownloadRequired implements ComponentInitializationEvent {
  final SDKComponent component;
  final String modelId;
  final int sizeBytes;
  @override
  final DateTime timestamp = DateTime.now();

  ComponentDownloadRequired({
    required this.component,
    required this.modelId,
    required this.sizeBytes,
  });
}

class ComponentDownloadStarted implements ComponentInitializationEvent {
  final SDKComponent component;
  final String modelId;
  @override
  final DateTime timestamp = DateTime.now();

  ComponentDownloadStarted({required this.component, required this.modelId});
}

class ComponentDownloadProgress implements ComponentInitializationEvent {
  final SDKComponent component;
  final String modelId;
  final double progress;
  @override
  final DateTime timestamp = DateTime.now();

  ComponentDownloadProgress({
    required this.component,
    required this.modelId,
    required this.progress,
  });
}

class ComponentDownloadCompleted implements ComponentInitializationEvent {
  final SDKComponent component;
  final String modelId;
  @override
  final DateTime timestamp = DateTime.now();

  ComponentDownloadCompleted({required this.component, required this.modelId});
}
