import 'package:uuid/uuid.dart';

import '../../infrastructure/events/event_category.dart';
import '../../infrastructure/events/event_destination.dart';

export '../../infrastructure/events/event_category.dart';
export '../../infrastructure/events/event_destination.dart';

/// Base protocol for all SDK events.
///
/// Mirrors iOS `SDKEvent` protocol from RunAnywhere SDK.
/// Every event in the SDK should extend this class. The [destination] property
/// tells the router where to send the event:
/// - [EventDestination.all] (default) → EventBus + Analytics
/// - [EventDestination.publicOnly] → EventBus only
/// - [EventDestination.analyticsOnly] → Analytics only
///
/// Usage:
/// ```dart
/// EventPublisher.shared.track(LLMEvent.generationCompleted(...));
/// ```
abstract class SDKEvent {
  /// Unique identifier for this event instance
  String get id;

  /// Event type string (used for analytics categorization)
  String get type;

  /// Category for filtering/routing
  EventCategory get category;

  /// When the event occurred
  DateTime get timestamp;

  /// Optional session ID for grouping related events
  String? get sessionId => null;

  /// Where to route this event
  EventDestination get destination => EventDestination.all;

  /// Event properties as key-value pairs (for analytics serialization)
  Map<String, String> get properties => {};
}

/// Mixin providing default implementations for SDKEvent fields.
/// Similar to Swift protocol extensions.
mixin SDKEventDefaults implements SDKEvent {
  static const _uuid = Uuid();

  @override
  String get id => _uuid.v4();

  @override
  DateTime get timestamp => DateTime.now();

  @override
  String? get sessionId => null;

  @override
  EventDestination get destination => EventDestination.all;

  @override
  Map<String, String> get properties => {};
}

// ============================================================================
// SDK Initialization Events
// ============================================================================

/// SDK initialization events
abstract class SDKInitializationEvent with SDKEventDefaults {
  @override
  EventCategory get category => EventCategory.sdk;
}

class SDKInitializationStarted extends SDKInitializationEvent {
  @override
  String get type => 'sdk.initialization.started';
}

class SDKInitializationCompleted extends SDKInitializationEvent {
  @override
  String get type => 'sdk.initialization.completed';
}

class SDKInitializationFailed extends SDKInitializationEvent {
  final Object error;

  SDKInitializationFailed(this.error);

  @override
  String get type => 'sdk.initialization.failed';

  @override
  Map<String, String> get properties => {'error': error.toString()};
}

// ============================================================================
// SDK Configuration Events
// ============================================================================

/// SDK configuration events
abstract class SDKConfigurationEvent with SDKEventDefaults {
  @override
  EventCategory get category => EventCategory.sdk;
}

// ============================================================================
// SDK Generation Events (LLM)
// ============================================================================

/// SDK generation events
abstract class SDKGenerationEvent with SDKEventDefaults {
  @override
  EventCategory get category => EventCategory.llm;

  static SDKGenerationStarted started({required String prompt}) {
    return SDKGenerationStarted(prompt: prompt);
  }

  static SDKGenerationCompleted completed({
    required String response,
    required int tokensUsed,
    required int latencyMs,
  }) {
    return SDKGenerationCompleted(
      response: response,
      tokensUsed: tokensUsed,
      latencyMs: latencyMs,
    );
  }

  static SDKGenerationFailed failed(Object error) {
    return SDKGenerationFailed(error);
  }

  static SDKGenerationCostCalculated costCalculated({
    required double amount,
    required double savedAmount,
  }) {
    return SDKGenerationCostCalculated(
      amount: amount,
      savedAmount: savedAmount,
    );
  }
}

class SDKGenerationStarted extends SDKGenerationEvent {
  final String prompt;

  SDKGenerationStarted({required this.prompt});

  @override
  String get type => 'llm.generation.started';

  @override
  Map<String, String> get properties => {'prompt_length': '${prompt.length}'};
}

class SDKGenerationCompleted extends SDKGenerationEvent {
  final String response;
  final int tokensUsed;
  final int latencyMs;

  SDKGenerationCompleted({
    required this.response,
    required this.tokensUsed,
    required this.latencyMs,
  });

  @override
  String get type => 'llm.generation.completed';

  @override
  Map<String, String> get properties => {
        'response_length': '${response.length}',
        'tokens_used': '$tokensUsed',
        'latency_ms': '$latencyMs',
      };
}

class SDKGenerationFailed extends SDKGenerationEvent {
  final Object error;

  SDKGenerationFailed(this.error);

  @override
  String get type => 'llm.generation.failed';

  @override
  Map<String, String> get properties => {'error': error.toString()};
}

class SDKGenerationCostCalculated extends SDKGenerationEvent {
  final double amount;
  final double savedAmount;

  SDKGenerationCostCalculated({
    required this.amount,
    required this.savedAmount,
  });

  @override
  String get type => 'llm.generation.cost_calculated';

  @override
  Map<String, String> get properties => {
        'amount': amount.toStringAsFixed(6),
        'saved_amount': savedAmount.toStringAsFixed(6),
      };
}

// ============================================================================
// SDK Model Events
// ============================================================================

/// SDK model events
abstract class SDKModelEvent with SDKEventDefaults {
  @override
  EventCategory get category => EventCategory.model;

  static SDKModelLoadStarted loadStarted({required String modelId}) {
    return SDKModelLoadStarted(modelId: modelId);
  }

  static SDKModelLoadCompleted loadCompleted({required String modelId}) {
    return SDKModelLoadCompleted(modelId: modelId);
  }

  static SDKModelLoadFailed loadFailed({
    required String modelId,
    required Object error,
  }) {
    return SDKModelLoadFailed(modelId: modelId, error: error);
  }

  static SDKModelUnloadStarted unloadStarted({required String modelId}) {
    return SDKModelUnloadStarted(modelId: modelId);
  }

  static SDKModelUnloadCompleted unloadCompleted({required String modelId}) {
    return SDKModelUnloadCompleted(modelId: modelId);
  }

  static SDKModelDeleted deleted({required String modelId}) {
    return SDKModelDeleted(modelId: modelId);
  }
}

class SDKModelLoadStarted extends SDKModelEvent {
  final String modelId;

  SDKModelLoadStarted({required this.modelId});

  @override
  String get type => 'model.load.started';

  @override
  Map<String, String> get properties => {'model_id': modelId};
}

class SDKModelLoadCompleted extends SDKModelEvent {
  final String modelId;

  SDKModelLoadCompleted({required this.modelId});

  @override
  String get type => 'model.load.completed';

  @override
  Map<String, String> get properties => {'model_id': modelId};
}

class SDKModelLoadFailed extends SDKModelEvent {
  final String modelId;
  final Object error;

  SDKModelLoadFailed({required this.modelId, required this.error});

  @override
  String get type => 'model.load.failed';

  @override
  Map<String, String> get properties => {
        'model_id': modelId,
        'error': error.toString(),
      };
}

class SDKModelUnloadStarted extends SDKModelEvent {
  final String modelId;

  SDKModelUnloadStarted({required this.modelId});

  @override
  String get type => 'model.unload.started';

  @override
  Map<String, String> get properties => {'model_id': modelId};
}

class SDKModelUnloadCompleted extends SDKModelEvent {
  final String modelId;

  SDKModelUnloadCompleted({required this.modelId});

  @override
  String get type => 'model.unload.completed';

  @override
  Map<String, String> get properties => {'model_id': modelId};
}

class SDKModelDeleted extends SDKModelEvent {
  final String modelId;

  SDKModelDeleted({required this.modelId});

  @override
  String get type => 'model.deleted';

  @override
  Map<String, String> get properties => {'model_id': modelId};
}

// ============================================================================
// SDK Voice Events
// ============================================================================

/// SDK voice events
abstract class SDKVoiceEvent with SDKEventDefaults {
  @override
  EventCategory get category => EventCategory.voice;

  static SDKVoiceListeningStarted listeningStarted() {
    return SDKVoiceListeningStarted();
  }

  static SDKVoiceListeningEnded listeningEnded() {
    return SDKVoiceListeningEnded();
  }

  static SDKVoiceSpeechDetected speechDetected() {
    return SDKVoiceSpeechDetected();
  }

  static SDKVoiceTranscriptionStarted transcriptionStarted() {
    return SDKVoiceTranscriptionStarted();
  }

  static SDKVoiceTranscriptionPartial transcriptionPartial(
      {required String text}) {
    return SDKVoiceTranscriptionPartial(text: text);
  }

  static SDKVoiceTranscriptionFinal transcriptionFinal({required String text}) {
    return SDKVoiceTranscriptionFinal(text: text);
  }

  static SDKVoiceResponseGenerated responseGenerated({required String text}) {
    return SDKVoiceResponseGenerated(text: text);
  }

  static SDKVoiceSynthesisStarted synthesisStarted() {
    return SDKVoiceSynthesisStarted();
  }

  static SDKVoiceAudioGenerated audioGenerated({required dynamic data}) {
    return SDKVoiceAudioGenerated(data: data);
  }

  static SDKVoiceSynthesisCompleted synthesisCompleted() {
    return SDKVoiceSynthesisCompleted();
  }

  static SDKVoicePipelineError pipelineError(Object error) {
    return SDKVoicePipelineError(error: error);
  }

  static SDKVoicePipelineStarted pipelineStarted() {
    return SDKVoicePipelineStarted();
  }

  static SDKVoicePipelineCompleted pipelineCompleted() {
    return SDKVoicePipelineCompleted();
  }

  static SDKVoiceVADStarted vadStarted() {
    return SDKVoiceVADStarted();
  }

  static SDKVoiceVADDetected vadDetected() {
    return SDKVoiceVADDetected();
  }

  static SDKVoiceVADEnded vadEnded() {
    return SDKVoiceVADEnded();
  }

  static SDKVoiceSTTProcessing sttProcessing() {
    return SDKVoiceSTTProcessing();
  }

  static SDKVoiceLLMProcessing llmProcessing() {
    return SDKVoiceLLMProcessing();
  }

  static SDKVoiceTTSProcessing ttsProcessing() {
    return SDKVoiceTTSProcessing();
  }
}

class SDKVoiceListeningStarted extends SDKVoiceEvent {
  @override
  String get type => 'voice.listening.started';
}

class SDKVoiceListeningEnded extends SDKVoiceEvent {
  @override
  String get type => 'voice.listening.ended';
}

class SDKVoiceSpeechDetected extends SDKVoiceEvent {
  @override
  String get type => 'voice.speech.detected';
}

class SDKVoiceTranscriptionStarted extends SDKVoiceEvent {
  @override
  String get type => 'voice.transcription.started';

  @override
  EventCategory get category => EventCategory.stt;
}

class SDKVoiceTranscriptionPartial extends SDKVoiceEvent {
  final String text;

  SDKVoiceTranscriptionPartial({required this.text});

  @override
  String get type => 'voice.transcription.partial';

  @override
  EventCategory get category => EventCategory.stt;

  @override
  Map<String, String> get properties => {'text': text};
}

class SDKVoiceTranscriptionFinal extends SDKVoiceEvent {
  final String text;

  SDKVoiceTranscriptionFinal({required this.text});

  @override
  String get type => 'voice.transcription.final';

  @override
  EventCategory get category => EventCategory.stt;

  @override
  Map<String, String> get properties => {'text': text};
}

class SDKVoiceResponseGenerated extends SDKVoiceEvent {
  final String text;

  SDKVoiceResponseGenerated({required this.text});

  @override
  String get type => 'voice.response.generated';

  @override
  Map<String, String> get properties => {'text_length': '${text.length}'};
}

class SDKVoiceSynthesisStarted extends SDKVoiceEvent {
  @override
  String get type => 'voice.synthesis.started';

  @override
  EventCategory get category => EventCategory.tts;
}

class SDKVoiceAudioGenerated extends SDKVoiceEvent {
  final dynamic data;

  SDKVoiceAudioGenerated({required this.data});

  @override
  String get type => 'voice.audio.generated';

  @override
  EventCategory get category => EventCategory.tts;
}

class SDKVoiceSynthesisCompleted extends SDKVoiceEvent {
  @override
  String get type => 'voice.synthesis.completed';

  @override
  EventCategory get category => EventCategory.tts;
}

class SDKVoicePipelineError extends SDKVoiceEvent {
  final Object error;

  SDKVoicePipelineError({required this.error});

  @override
  String get type => 'voice.pipeline.error';

  @override
  EventCategory get category => EventCategory.error;

  @override
  Map<String, String> get properties => {'error': error.toString()};
}

class SDKVoicePipelineStarted extends SDKVoiceEvent {
  @override
  String get type => 'voice.pipeline.started';
}

class SDKVoicePipelineCompleted extends SDKVoiceEvent {
  @override
  String get type => 'voice.pipeline.completed';
}

class SDKVoiceVADStarted extends SDKVoiceEvent {
  @override
  String get type => 'voice.vad.started';
}

class SDKVoiceVADDetected extends SDKVoiceEvent {
  @override
  String get type => 'voice.vad.detected';
}

class SDKVoiceVADEnded extends SDKVoiceEvent {
  @override
  String get type => 'voice.vad.ended';
}

class SDKVoiceSTTProcessing extends SDKVoiceEvent {
  @override
  String get type => 'voice.stt.processing';

  @override
  EventCategory get category => EventCategory.stt;
}

class SDKVoiceLLMProcessing extends SDKVoiceEvent {
  @override
  String get type => 'voice.llm.processing';

  @override
  EventCategory get category => EventCategory.llm;
}

class SDKVoiceTTSProcessing extends SDKVoiceEvent {
  @override
  String get type => 'voice.tts.processing';

  @override
  EventCategory get category => EventCategory.tts;
}

// ============================================================================
// SDK Device Events
// ============================================================================

/// SDK device events.
///
/// Mirrors iOS `DeviceEvent` from RunAnywhere SDK.
abstract class SDKDeviceEvent with SDKEventDefaults {
  @override
  EventCategory get category => EventCategory.device;

  /// Factory method: device registered successfully
  static DeviceRegistered registered({required String deviceId}) {
    return DeviceRegistered(deviceId: deviceId);
  }

  /// Factory method: device registration failed
  static DeviceRegistrationFailed registrationFailed({required String error}) {
    return DeviceRegistrationFailed(error: error);
  }
}

class DeviceRegistered extends SDKDeviceEvent {
  final String deviceId;

  DeviceRegistered({required this.deviceId});

  @override
  String get type => 'device.registered';

  @override
  Map<String, String> get properties => {
        'device_id':
            deviceId.length > 8 ? '${deviceId.substring(0, 8)}...' : deviceId
      };
}

class DeviceRegistrationFailed extends SDKDeviceEvent {
  final String error;

  DeviceRegistrationFailed({required this.error});

  @override
  String get type => 'device.registration.failed';

  @override
  Map<String, String> get properties => {'error': error};
}

// ============================================================================
// SDK Performance Events
// ============================================================================

/// SDK performance events
abstract class SDKPerformanceEvent with SDKEventDefaults {
  @override
  EventCategory get category => EventCategory.sdk;
}

// ============================================================================
// SDK Network Events
// ============================================================================

/// SDK network events
abstract class SDKNetworkEvent with SDKEventDefaults {
  @override
  EventCategory get category => EventCategory.network;
}

// ============================================================================
// SDK Storage Events
// ============================================================================

/// SDK storage events
abstract class SDKStorageEvent with SDKEventDefaults {
  @override
  EventCategory get category => EventCategory.storage;

  /// Factory method: cache cleared
  static SDKStorageCacheCleared cacheCleared() {
    return SDKStorageCacheCleared();
  }

  /// Factory method: temp files cleaned
  static SDKStorageTempFilesCleaned tempFilesCleaned() {
    return SDKStorageTempFilesCleaned();
  }
}

class SDKStorageCacheCleared extends SDKStorageEvent {
  @override
  String get type => 'storage.cache.cleared';
}

class SDKStorageTempFilesCleaned extends SDKStorageEvent {
  @override
  String get type => 'storage.temp_files.cleaned';
}

// ============================================================================
// SDK Framework Events
// ============================================================================

/// SDK framework events
abstract class SDKFrameworkEvent with SDKEventDefaults {
  @override
  EventCategory get category => EventCategory.sdk;
}
