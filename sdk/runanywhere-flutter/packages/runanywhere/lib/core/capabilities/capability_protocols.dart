//
// capability_protocols.dart
// RunAnywhere SDK
//
// Base protocols and types for capability abstraction.
// Mirrors iOS CapabilityProtocols.swift from RunAnywhere SDK.
//

/// Represents the loading state of a capability.
///
/// Uses Dart sealed classes to mirror iOS enum with associated values.
/// Matches iOS `CapabilityLoadingState` from Core/Capabilities/CapabilityProtocols.swift
sealed class CapabilityLoadingState {
  const CapabilityLoadingState();

  /// Whether this state represents a loaded resource
  bool get isLoaded => this is CapabilityLoaded;

  /// Whether this state represents a loading in progress
  bool get isLoading => this is CapabilityLoading;

  /// Whether this state represents an idle state
  bool get isIdle => this is CapabilityIdle;

  /// Whether this state represents a failed state
  bool get isFailed => this is CapabilityFailed;
}

/// Idle state - no resource loaded
class CapabilityIdle extends CapabilityLoadingState {
  const CapabilityIdle();

  @override
  bool operator ==(Object other) => other is CapabilityIdle;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'CapabilityLoadingState.idle';
}

/// Loading state - resource is being loaded
class CapabilityLoading extends CapabilityLoadingState {
  /// The ID of the resource being loaded
  final String resourceId;

  const CapabilityLoading({required this.resourceId});

  @override
  bool operator ==(Object other) =>
      other is CapabilityLoading && other.resourceId == resourceId;

  @override
  int get hashCode => Object.hash(runtimeType, resourceId);

  @override
  String toString() =>
      'CapabilityLoadingState.loading(resourceId: $resourceId)';
}

/// Loaded state - resource is ready to use
class CapabilityLoaded extends CapabilityLoadingState {
  /// The ID of the loaded resource
  final String resourceId;

  const CapabilityLoaded({required this.resourceId});

  @override
  bool operator ==(Object other) =>
      other is CapabilityLoaded && other.resourceId == resourceId;

  @override
  int get hashCode => Object.hash(runtimeType, resourceId);

  @override
  String toString() => 'CapabilityLoadingState.loaded(resourceId: $resourceId)';
}

/// Failed state - resource loading failed
class CapabilityFailed extends CapabilityLoadingState {
  /// The error that caused the failure
  final Object error;

  const CapabilityFailed({required this.error});

  @override
  bool operator ==(Object other) => other is CapabilityFailed;

  @override
  int get hashCode => runtimeType.hashCode;

  @override
  String toString() => 'CapabilityLoadingState.failed(error: $error)';
}

/// Type of resource managed by a capability.
///
/// Matches iOS `CapabilityResourceType` from Core/Capabilities/ManagedLifecycle.swift
enum CapabilityResourceType {
  /// Large language model
  llmModel('llm_model', 'LLM Model'),

  /// Speech-to-text model
  sttModel('stt_model', 'STT Model'),

  /// Text-to-speech voice
  ttsVoice('tts_voice', 'TTS Voice'),

  /// Voice activity detection model
  vadModel('vad_model', 'VAD Model'),

  /// Speaker diarization model
  diarizationModel('diarization_model', 'Diarization Model');

  /// Raw string value for serialization
  final String rawValue;

  /// Human-readable display name
  final String displayName;

  const CapabilityResourceType(this.rawValue, this.displayName);
}

/// Result of a capability operation with timing metadata.
///
/// Matches iOS `CapabilityOperationResult` from Core/Capabilities/CapabilityProtocols.swift
class CapabilityOperationResult<T> {
  /// The operation result value
  final T value;

  /// Processing time in milliseconds
  final double processingTimeMs;

  /// Optional resource ID associated with the operation
  final String? resourceId;

  const CapabilityOperationResult({
    required this.value,
    required this.processingTimeMs,
    this.resourceId,
  });
}

/// Helper for tracking capability operation metrics.
///
/// Matches iOS `CapabilityMetrics` from Core/Capabilities/CapabilityProtocols.swift
class CapabilityMetrics {
  /// When the operation started
  final DateTime startTime;

  /// Resource ID being operated on
  final String resourceId;

  CapabilityMetrics({required this.resourceId}) : startTime = DateTime.now();

  /// Get elapsed time in milliseconds
  double get elapsedMs =>
      DateTime.now().difference(startTime).inMicroseconds / 1000.0;

  /// Create a result with the current metrics
  CapabilityOperationResult<T> result<T>(T value) {
    return CapabilityOperationResult<T>(
      value: value,
      processingTimeMs: elapsedMs,
      resourceId: resourceId,
    );
  }
}

/// Common errors for capability operations.
///
/// Matches iOS `CapabilityError` from Core/Capabilities/CapabilityProtocols.swift
sealed class CapabilityError implements Exception {
  const CapabilityError();

  /// Get human-readable error description
  String get message;

  @override
  String toString() => message;
}

/// Capability is not initialized
class CapabilityNotInitializedError extends CapabilityError {
  final String capability;

  const CapabilityNotInitializedError(this.capability);

  @override
  String get message => '$capability is not initialized';
}

/// Resource is not loaded
class ResourceNotLoadedError extends CapabilityError {
  final String resource;

  const ResourceNotLoadedError(this.resource);

  @override
  String get message => 'No $resource is loaded. Call load first.';
}

/// Resource loading failed
class LoadFailedError extends CapabilityError {
  final String resource;
  final Object? underlyingError;

  const LoadFailedError(this.resource, [this.underlyingError]);

  @override
  String get message =>
      'Failed to load $resource: ${underlyingError ?? "Unknown error"}';
}

/// Operation failed
class OperationFailedError extends CapabilityError {
  final String operation;
  final Object? underlyingError;

  const OperationFailedError(this.operation, [this.underlyingError]);

  @override
  String get message =>
      '$operation failed: ${underlyingError ?? "Unknown error"}';
}

/// Provider not found
class ProviderNotFoundError extends CapabilityError {
  final String provider;

  const ProviderNotFoundError(this.provider);

  @override
  String get message =>
      'No $provider provider registered. Please register a provider first.';
}

/// Composite component failed
class CompositeComponentFailedError extends CapabilityError {
  final String component;
  final Object? underlyingError;

  const CompositeComponentFailedError(this.component, [this.underlyingError]);

  @override
  String get message =>
      '$component component failed: ${underlyingError ?? "Unknown error"}';
}

/// Lifecycle metrics for tracking load/unload operations.
///
/// Matches iOS `ModelLifecycleMetrics` concept.
class ModelLifecycleMetrics {
  final int totalEvents;
  final DateTime startTime;
  final DateTime? lastEventTime;
  final int totalLoads;
  final int successfulLoads;
  final int failedLoads;
  final double averageLoadTimeMs;
  final int totalUnloads;
  final int totalDownloads;
  final int successfulDownloads;
  final int failedDownloads;
  final int totalBytesDownloaded;

  const ModelLifecycleMetrics({
    required this.totalEvents,
    required this.startTime,
    this.lastEventTime,
    this.totalLoads = 0,
    this.successfulLoads = 0,
    this.failedLoads = 0,
    this.averageLoadTimeMs = 0,
    this.totalUnloads = 0,
    this.totalDownloads = 0,
    this.successfulDownloads = 0,
    this.failedDownloads = 0,
    this.totalBytesDownloaded = 0,
  });
}
