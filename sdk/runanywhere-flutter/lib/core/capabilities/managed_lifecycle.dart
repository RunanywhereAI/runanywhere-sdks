//
// managed_lifecycle.dart
// RunAnywhere SDK
//
// Unified lifecycle management with integrated event tracking.
// Mirrors iOS ManagedLifecycle.swift from RunAnywhere SDK.
//

import 'dart:async';

import '../../foundation/logging/sdk_logger.dart';
import '../../infrastructure/events/event_publisher.dart';
import '../../public/events/sdk_event.dart';
import '../protocols/component/component_configuration.dart';
import 'capability_protocols.dart';

// Re-export for convenience
export 'capability_protocols.dart';

/// Generic lifecycle manager that wraps resource loading with integrated event tracking.
///
/// This class manages the lifecycle of a service (LLM, STT, TTS, etc.) and automatically
/// tracks lifecycle events via [EventPublisher], which routes them to both the public
/// EventBus and Analytics.
///
/// Mirrors iOS `ManagedLifecycle<ServiceType>` from Core/Capabilities/ManagedLifecycle.swift
///
/// Usage:
/// ```dart
/// final lifecycle = ManagedLifecycle<LLMService>.forLLM(
///   loadResource: (id, config) async => await createLLMService(id, config),
///   unloadResource: (service) async => await service.cleanup(),
/// );
///
/// final service = await lifecycle.load('llama-3.2-1b');
/// // ... use service ...
/// await lifecycle.unload();
/// ```
class ManagedLifecycle<ServiceType> {
  // MARK: - Dependencies

  final SDKLogger _logger;
  final CapabilityResourceType _resourceType;
  final Future<ServiceType> Function(
      String resourceId, ComponentConfiguration? config) _loadResource;
  final Future<void> Function(ServiceType service) _unloadResource;

  // MARK: - State

  ServiceType? _service;
  String? _loadedResourceId;
  Completer<ServiceType>? _inflightLoad;
  ComponentConfiguration? _configuration;

  // MARK: - Metrics

  int _loadCount = 0;
  double _totalLoadTime = 0;
  final DateTime _startTime = DateTime.now();

  // MARK: - Initialization

  /// Create a ManagedLifecycle instance.
  ///
  /// - [resourceType]: Type of resource being managed (for event creation)
  /// - [loggerCategory]: Category for logging
  /// - [loadResource]: Closure to load a resource by ID
  /// - [unloadResource]: Closure to unload/cleanup a resource
  ManagedLifecycle({
    required CapabilityResourceType resourceType,
    required String loggerCategory,
    required Future<ServiceType> Function(
            String resourceId, ComponentConfiguration? config)
        loadResource,
    required Future<void> Function(ServiceType service) unloadResource,
  })  : _resourceType = resourceType,
        _logger = SDKLogger(category: loggerCategory),
        _loadResource = loadResource,
        _unloadResource = unloadResource;

  // MARK: - State Properties

  /// Whether a resource is currently loaded
  bool get isLoaded => _service != null;

  /// The currently loaded resource ID
  String? get currentResourceId => _loadedResourceId;

  /// The currently loaded service
  ServiceType? get currentService => _service;

  /// Current loading state
  CapabilityLoadingState get state {
    if (_loadedResourceId != null) {
      return CapabilityLoaded(resourceId: _loadedResourceId!);
    }
    if (_inflightLoad != null) {
      return const CapabilityLoading(resourceId: '');
    }
    return const CapabilityIdle();
  }

  // MARK: - Configuration

  /// Set configuration for loading
  void configure(ComponentConfiguration? config) {
    _configuration = config;
  }

  // MARK: - Lifecycle Operations

  /// Load a resource with automatic event tracking.
  ///
  /// - [resourceId]: The resource identifier to load
  /// - Returns: The loaded service
  /// - Throws: [LoadFailedError] if loading fails
  Future<ServiceType> load(String resourceId) async {
    final startTime = DateTime.now();
    _logger.info('Loading ${_resourceType.displayName}: $resourceId');

    // Check if already loaded with same ID
    if (_loadedResourceId == resourceId && _service != null) {
      _logger.info('Resource already loaded: $resourceId');
      return _service!;
    }

    // Wait for existing load to complete
    if (_inflightLoad != null) {
      _logger.info('Load in progress, waiting...');
      try {
        final result = await _inflightLoad!.future;
        if (_loadedResourceId == resourceId) {
          return result;
        }
      } catch (_) {
        // Previous load failed, continue with new load
      }
    }

    // Unload current if different
    if (_service != null && _loadedResourceId != resourceId) {
      _logger.info('Unloading current resource before loading new one');
      await _unloadResource(_service as ServiceType);
      _service = null;
      _loadedResourceId = null;
    }

    // Track load started
    _trackEvent(_LifecycleEventType.loadStarted, resourceId);

    // Create load completer
    final completer = Completer<ServiceType>();
    _inflightLoad = completer;

    try {
      final service = await _loadResource(resourceId, _configuration);
      final loadTimeMs =
          DateTime.now().difference(startTime).inMilliseconds.toDouble();

      _service = service;
      _loadedResourceId = resourceId;
      _inflightLoad = null;

      // Update metrics
      _loadCount += 1;
      _totalLoadTime += loadTimeMs;

      // Track load completed
      _trackEvent(_LifecycleEventType.loadCompleted, resourceId,
          durationMs: loadTimeMs);

      _logger.info(
          'Loaded ${_resourceType.displayName}: $resourceId in ${loadTimeMs.toInt()}ms');
      completer.complete(service);
      return service;
    } catch (error) {
      final loadTimeMs =
          DateTime.now().difference(startTime).inMilliseconds.toDouble();
      _inflightLoad = null;

      // Track load failed
      _trackEvent(_LifecycleEventType.loadFailed, resourceId,
          durationMs: loadTimeMs, error: error);

      _logger.error('Failed to load ${_resourceType.displayName}: $error');
      completer.completeError(error);
      throw LoadFailedError(resourceId, error);
    }
  }

  /// Unload the currently loaded resource.
  Future<void> unload() async {
    if (_service == null) return;

    final resourceId = _loadedResourceId ?? 'unknown';
    _logger.info('Unloading ${_resourceType.displayName}: $resourceId');

    await _unloadResource(_service as ServiceType);
    _service = null;
    _loadedResourceId = null;

    // Track unload event
    _trackEvent(_LifecycleEventType.unloaded, resourceId);
    _logger.info('Unloaded ${_resourceType.displayName}: $resourceId');
  }

  /// Reset all state, cancelling any in-flight loads.
  Future<void> reset() async {
    if (_loadedResourceId != null) {
      _trackEvent(_LifecycleEventType.unloaded, _loadedResourceId!);
    }

    _inflightLoad = null;

    if (_service != null) {
      await _unloadResource(_service as ServiceType);
    }

    _service = null;
    _loadedResourceId = null;
    _configuration = null;
  }

  /// Get service or throw if not loaded.
  ServiceType requireService() {
    if (_service == null) {
      throw const ResourceNotLoadedError('resource');
    }
    return _service!;
  }

  /// Track an operation error.
  void trackOperationError(Object error, String operation) {
    EventPublisher.shared.track(SDKErrorEvent(
      operation: operation,
      error: error,
    ));
  }

  /// Get current resource ID with fallback.
  String resourceIdOrUnknown() {
    return _loadedResourceId ?? 'unknown';
  }

  // MARK: - Metrics

  /// Get lifecycle metrics
  ModelLifecycleMetrics getLifecycleMetrics() {
    return ModelLifecycleMetrics(
      totalEvents: _loadCount,
      startTime: _startTime,
      lastEventTime: null,
      totalLoads: _loadCount,
      successfulLoads: _loadCount,
      failedLoads: 0,
      averageLoadTimeMs: _loadCount > 0 ? _totalLoadTime / _loadCount : 0,
      totalUnloads: 0,
      totalDownloads: 0,
      successfulDownloads: 0,
      failedDownloads: 0,
      totalBytesDownloaded: 0,
    );
  }

  // MARK: - Private Event Tracking

  void _trackEvent(
    _LifecycleEventType type,
    String resourceId, {
    double? durationMs,
    Object? error,
  }) {
    final event = _createEvent(type, resourceId, durationMs, error);
    EventPublisher.shared.track(event);
  }

  SDKEvent _createEvent(
    _LifecycleEventType type,
    String resourceId,
    double? durationMs,
    Object? error,
  ) {
    switch (_resourceType) {
      case CapabilityResourceType.llmModel:
        return _createLLMEvent(type, resourceId, durationMs, error);
      case CapabilityResourceType.sttModel:
        return _createSTTEvent(type, resourceId, durationMs, error);
      case CapabilityResourceType.ttsVoice:
        return _createTTSEvent(type, resourceId, durationMs, error);
      case CapabilityResourceType.vadModel:
      case CapabilityResourceType.diarizationModel:
        return _createModelEvent(type, resourceId, durationMs, error);
    }
  }

  SDKEvent _createLLMEvent(
    _LifecycleEventType type,
    String resourceId,
    double? durationMs,
    Object? error,
  ) {
    switch (type) {
      case _LifecycleEventType.loadStarted:
        return LLMModelLoadStarted(modelId: resourceId);
      case _LifecycleEventType.loadCompleted:
        return LLMModelLoadCompleted(
            modelId: resourceId, durationMs: durationMs ?? 0);
      case _LifecycleEventType.loadFailed:
        return LLMModelLoadFailed(
            modelId: resourceId, error: error ?? 'Unknown error');
      case _LifecycleEventType.unloaded:
        return LLMModelUnloaded(modelId: resourceId);
    }
  }

  SDKEvent _createSTTEvent(
    _LifecycleEventType type,
    String resourceId,
    double? durationMs,
    Object? error,
  ) {
    switch (type) {
      case _LifecycleEventType.loadStarted:
        return STTModelLoadStarted(modelId: resourceId);
      case _LifecycleEventType.loadCompleted:
        return STTModelLoadCompleted(
            modelId: resourceId, durationMs: durationMs ?? 0);
      case _LifecycleEventType.loadFailed:
        return STTModelLoadFailed(
            modelId: resourceId, error: error ?? 'Unknown error');
      case _LifecycleEventType.unloaded:
        return STTModelUnloaded(modelId: resourceId);
    }
  }

  SDKEvent _createTTSEvent(
    _LifecycleEventType type,
    String resourceId,
    double? durationMs,
    Object? error,
  ) {
    switch (type) {
      case _LifecycleEventType.loadStarted:
        return TTSModelLoadStarted(voiceId: resourceId);
      case _LifecycleEventType.loadCompleted:
        return TTSModelLoadCompleted(
            voiceId: resourceId, durationMs: durationMs ?? 0);
      case _LifecycleEventType.loadFailed:
        return TTSModelLoadFailed(
            voiceId: resourceId, error: error ?? 'Unknown error');
      case _LifecycleEventType.unloaded:
        return TTSModelUnloaded(voiceId: resourceId);
    }
  }

  SDKEvent _createModelEvent(
    _LifecycleEventType type,
    String resourceId,
    double? durationMs,
    Object? error,
  ) {
    // Use generic model events for VAD and diarization
    switch (type) {
      case _LifecycleEventType.loadStarted:
        return SDKModelLoadStarted(modelId: resourceId);
      case _LifecycleEventType.loadCompleted:
        return SDKModelLoadCompleted(modelId: resourceId);
      case _LifecycleEventType.loadFailed:
        return SDKModelLoadFailed(
            modelId: resourceId, error: error ?? 'Unknown error');
      case _LifecycleEventType.unloaded:
        return SDKModelUnloadCompleted(modelId: resourceId);
    }
  }
}

/// Private enum for lifecycle event types
enum _LifecycleEventType {
  loadStarted,
  loadCompleted,
  loadFailed,
  unloaded,
}

// ============================================================================
// Lifecycle Event Classes
// ============================================================================

/// LLM model load started event
class LLMModelLoadStarted extends SDKModelEvent {
  final String modelId;

  LLMModelLoadStarted({required this.modelId});

  @override
  String get type => 'llm.model.load.started';

  @override
  EventCategory get category => EventCategory.llm;

  @override
  Map<String, String> get properties => {'model_id': modelId};
}

/// LLM model load completed event
class LLMModelLoadCompleted extends SDKModelEvent {
  final String modelId;
  final double durationMs;

  LLMModelLoadCompleted({required this.modelId, required this.durationMs});

  @override
  String get type => 'llm.model.load.completed';

  @override
  EventCategory get category => EventCategory.llm;

  @override
  Map<String, String> get properties => {
        'model_id': modelId,
        'duration_ms': durationMs.toStringAsFixed(0),
      };
}

/// LLM model load failed event
class LLMModelLoadFailed extends SDKModelEvent {
  final String modelId;
  final Object error;

  LLMModelLoadFailed({required this.modelId, required this.error});

  @override
  String get type => 'llm.model.load.failed';

  @override
  EventCategory get category => EventCategory.llm;

  @override
  Map<String, String> get properties => {
        'model_id': modelId,
        'error': error.toString(),
      };
}

/// LLM model unloaded event
class LLMModelUnloaded extends SDKModelEvent {
  final String modelId;

  LLMModelUnloaded({required this.modelId});

  @override
  String get type => 'llm.model.unloaded';

  @override
  EventCategory get category => EventCategory.llm;

  @override
  Map<String, String> get properties => {'model_id': modelId};
}

// ============================================================================
// STT Lifecycle Events
// ============================================================================

/// STT model load started event
class STTModelLoadStarted extends SDKModelEvent {
  final String modelId;

  STTModelLoadStarted({required this.modelId});

  @override
  String get type => 'stt.model.load.started';

  @override
  EventCategory get category => EventCategory.stt;

  @override
  Map<String, String> get properties => {'model_id': modelId};
}

/// STT model load completed event
class STTModelLoadCompleted extends SDKModelEvent {
  final String modelId;
  final double durationMs;

  STTModelLoadCompleted({required this.modelId, required this.durationMs});

  @override
  String get type => 'stt.model.load.completed';

  @override
  EventCategory get category => EventCategory.stt;

  @override
  Map<String, String> get properties => {
        'model_id': modelId,
        'duration_ms': durationMs.toStringAsFixed(0),
      };
}

/// STT model load failed event
class STTModelLoadFailed extends SDKModelEvent {
  final String modelId;
  final Object error;

  STTModelLoadFailed({required this.modelId, required this.error});

  @override
  String get type => 'stt.model.load.failed';

  @override
  EventCategory get category => EventCategory.stt;

  @override
  Map<String, String> get properties => {
        'model_id': modelId,
        'error': error.toString(),
      };
}

/// STT model unloaded event
class STTModelUnloaded extends SDKModelEvent {
  final String modelId;

  STTModelUnloaded({required this.modelId});

  @override
  String get type => 'stt.model.unloaded';

  @override
  EventCategory get category => EventCategory.stt;

  @override
  Map<String, String> get properties => {'model_id': modelId};
}

// ============================================================================
// TTS Lifecycle Events
// ============================================================================

/// TTS model load started event
class TTSModelLoadStarted extends SDKModelEvent {
  final String voiceId;

  TTSModelLoadStarted({required this.voiceId});

  @override
  String get type => 'tts.model.load.started';

  @override
  EventCategory get category => EventCategory.tts;

  @override
  Map<String, String> get properties => {'voice_id': voiceId};
}

/// TTS model load completed event
class TTSModelLoadCompleted extends SDKModelEvent {
  final String voiceId;
  final double durationMs;

  TTSModelLoadCompleted({required this.voiceId, required this.durationMs});

  @override
  String get type => 'tts.model.load.completed';

  @override
  EventCategory get category => EventCategory.tts;

  @override
  Map<String, String> get properties => {
        'voice_id': voiceId,
        'duration_ms': durationMs.toStringAsFixed(0),
      };
}

/// TTS model load failed event
class TTSModelLoadFailed extends SDKModelEvent {
  final String voiceId;
  final Object error;

  TTSModelLoadFailed({required this.voiceId, required this.error});

  @override
  String get type => 'tts.model.load.failed';

  @override
  EventCategory get category => EventCategory.tts;

  @override
  Map<String, String> get properties => {
        'voice_id': voiceId,
        'error': error.toString(),
      };
}

/// TTS model unloaded event
class TTSModelUnloaded extends SDKModelEvent {
  final String voiceId;

  TTSModelUnloaded({required this.voiceId});

  @override
  String get type => 'tts.model.unloaded';

  @override
  EventCategory get category => EventCategory.tts;

  @override
  Map<String, String> get properties => {'voice_id': voiceId};
}

// ============================================================================
// Error Event
// ============================================================================

/// Generic SDK error event
class SDKErrorEvent with SDKEventDefaults {
  final String operation;
  final Object error;
  final int? code;

  SDKErrorEvent({
    required this.operation,
    required this.error,
    this.code,
  });

  @override
  String get type => 'sdk.error';

  @override
  EventCategory get category => EventCategory.error;

  @override
  Map<String, String> get properties => {
        'operation': operation,
        'error': error.toString(),
        if (code != null) 'code': code.toString(),
      };
}
