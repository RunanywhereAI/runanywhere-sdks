import '../../core/types/sdk_component.dart';
import '../../core/types/component_state.dart';
import 'sdk_event.dart';

/// Component initialization events
abstract class ComponentInitializationEvent with SDKEventDefaults {
  @override
  EventCategory get category => EventCategory.sdk;

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

class ComponentChecking extends ComponentInitializationEvent {
  final SDKComponent component;
  final String? modelId;

  ComponentChecking({required this.component, this.modelId});

  @override
  String get type => 'component.checking';
}

class ComponentInitializing extends ComponentInitializationEvent {
  final SDKComponent component;
  final String? modelId;

  ComponentInitializing({required this.component, this.modelId});

  @override
  String get type => 'component.initializing';
}

class ComponentReady extends ComponentInitializationEvent {
  final SDKComponent component;
  final String? modelId;

  ComponentReady({required this.component, this.modelId});

  @override
  String get type => 'component.ready';
}

class ComponentFailed extends ComponentInitializationEvent {
  final SDKComponent component;
  final Object error;

  ComponentFailed({required this.component, required this.error});

  @override
  String get type => 'component.failed';

  @override
  Map<String, String> get properties => {'error': error.toString()};
}

class ComponentStateChanged extends ComponentInitializationEvent {
  final SDKComponent component;
  final ComponentState oldState;
  final ComponentState newState;

  ComponentStateChanged({
    required this.component,
    required this.oldState,
    required this.newState,
  });

  @override
  String get type => 'component.state_changed';

  @override
  Map<String, String> get properties => {
        'old_state': oldState.name,
        'new_state': newState.name,
      };
}

// Download event classes - matching iOS SDK patterns

class ComponentDownloadRequired extends ComponentInitializationEvent {
  final SDKComponent component;
  final String modelId;
  final int sizeBytes;

  ComponentDownloadRequired({
    required this.component,
    required this.modelId,
    required this.sizeBytes,
  });

  @override
  String get type => 'component.download.required';

  @override
  Map<String, String> get properties => {
        'model_id': modelId,
        'size_bytes': sizeBytes.toString(),
      };
}

class ComponentDownloadStarted extends ComponentInitializationEvent {
  final SDKComponent component;
  final String modelId;

  ComponentDownloadStarted({required this.component, required this.modelId});

  @override
  String get type => 'component.download.started';

  @override
  Map<String, String> get properties => {'model_id': modelId};
}

class ComponentDownloadProgress extends ComponentInitializationEvent {
  final SDKComponent component;
  final String modelId;
  final double progress;

  ComponentDownloadProgress({
    required this.component,
    required this.modelId,
    required this.progress,
  });

  @override
  String get type => 'component.download.progress';

  @override
  Map<String, String> get properties => {
        'model_id': modelId,
        'progress': progress.toStringAsFixed(2),
      };
}

class ComponentDownloadCompleted extends ComponentInitializationEvent {
  final SDKComponent component;
  final String modelId;

  ComponentDownloadCompleted({required this.component, required this.modelId});

  @override
  String get type => 'component.download.completed';

  @override
  Map<String, String> get properties => {'model_id': modelId};
}
