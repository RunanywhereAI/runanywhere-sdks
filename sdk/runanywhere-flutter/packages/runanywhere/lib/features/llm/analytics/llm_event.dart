import 'package:runanywhere/public/events/sdk_event.dart';

/// All LLM-related events.
///
/// Usage:
/// ```dart
/// EventPublisher.shared.track(LLMGenerationCompletedEvent(...));
/// ```
///
/// Matches iOS `LLMEvent` enum from LLMEvent.swift
sealed class LLMEvent with SDKEventDefaults {
  const LLMEvent();

  @override
  EventCategory get category => EventCategory.llm;
}

// MARK: - Model Lifecycle Events

/// Model load started
class LLMModelLoadStartedEvent extends LLMEvent {
  final String modelId;
  final int modelSizeBytes;
  final String framework;

  const LLMModelLoadStartedEvent({
    required this.modelId,
    this.modelSizeBytes = 0,
    this.framework = 'unknown',
  });

  @override
  String get type => 'llm_model_load_started';

  @override
  Map<String, String> get properties {
    final props = <String, String>{
      'model_id': modelId,
      'framework': framework,
    };
    if (modelSizeBytes > 0) {
      props['model_size_bytes'] = modelSizeBytes.toString();
    }
    return props;
  }
}

/// Model load completed
class LLMModelLoadCompletedEvent extends LLMEvent {
  final String modelId;
  final double durationMs;
  final int modelSizeBytes;
  final String framework;

  const LLMModelLoadCompletedEvent({
    required this.modelId,
    required this.durationMs,
    this.modelSizeBytes = 0,
    this.framework = 'unknown',
  });

  @override
  String get type => 'llm_model_load_completed';

  @override
  Map<String, String> get properties {
    final props = <String, String>{
      'model_id': modelId,
      'duration_ms': durationMs.toStringAsFixed(1),
      'framework': framework,
    };
    if (modelSizeBytes > 0) {
      props['model_size_bytes'] = modelSizeBytes.toString();
    }
    return props;
  }
}

/// Model load failed
class LLMModelLoadFailedEvent extends LLMEvent {
  final String modelId;
  final String error;
  final String framework;

  const LLMModelLoadFailedEvent({
    required this.modelId,
    required this.error,
    this.framework = 'unknown',
  });

  @override
  String get type => 'llm_model_load_failed';

  @override
  Map<String, String> get properties => {
        'model_id': modelId,
        'error': error,
        'framework': framework,
      };
}

/// Model unloaded
class LLMModelUnloadedEvent extends LLMEvent {
  final String modelId;

  const LLMModelUnloadedEvent({required this.modelId});

  @override
  String get type => 'llm_model_unloaded';

  @override
  Map<String, String> get properties => {'model_id': modelId};
}

/// Model unload started
class LLMModelUnloadStartedEvent extends LLMEvent {
  final String modelId;

  const LLMModelUnloadStartedEvent({required this.modelId});

  @override
  String get type => 'llm_model_unload_started';

  @override
  Map<String, String> get properties => {'model_id': modelId};
}

// MARK: - Generation Events

/// Generation started
class LLMGenerationStartedEvent extends LLMEvent {
  final String generationId;
  final String modelId;
  final String? prompt;
  final bool isStreaming;
  final String framework;

  const LLMGenerationStartedEvent({
    required this.generationId,
    required this.modelId,
    this.prompt,
    this.isStreaming = false,
    this.framework = 'unknown',
  });

  @override
  String get type => 'llm_generation_started';

  @override
  Map<String, String> get properties {
    final props = <String, String>{
      'generation_id': generationId,
      'model_id': modelId,
      'is_streaming': isStreaming.toString(),
      'framework': framework,
    };
    if (prompt != null) {
      props['prompt_length'] = prompt!.length.toString();
    }
    return props;
  }
}

/// First token received (for latency tracking)
class LLMFirstTokenEvent extends LLMEvent {
  final String generationId;
  final double latencyMs;

  const LLMFirstTokenEvent({
    required this.generationId,
    required this.latencyMs,
  });

  @override
  String get type => 'llm_first_token';

  @override
  Map<String, String> get properties => {
        'generation_id': generationId,
        'latency_ms': latencyMs.toStringAsFixed(1),
      };
}

/// Streaming update (analytics only, too chatty for public API)
class LLMStreamingUpdateEvent extends LLMEvent {
  final String generationId;
  final int tokensGenerated;

  const LLMStreamingUpdateEvent({
    required this.generationId,
    required this.tokensGenerated,
  });

  @override
  String get type => 'llm_streaming_update';

  /// Streaming updates are too chatty for public API
  @override
  EventDestination get destination => EventDestination.analyticsOnly;

  @override
  Map<String, String> get properties => {
        'generation_id': generationId,
        'tokens_generated': tokensGenerated.toString(),
      };
}

/// Generation completed
class LLMGenerationCompletedEvent extends LLMEvent {
  final String generationId;
  final String modelId;
  final int inputTokens;
  final int outputTokens;
  final double durationMs;
  final double tokensPerSecond;
  final bool isStreaming;
  final double? timeToFirstTokenMs;
  final String framework;

  const LLMGenerationCompletedEvent({
    required this.generationId,
    required this.modelId,
    required this.inputTokens,
    required this.outputTokens,
    required this.durationMs,
    required this.tokensPerSecond,
    this.isStreaming = false,
    this.timeToFirstTokenMs,
    this.framework = 'unknown',
  });

  @override
  String get type => 'llm_generation_completed';

  @override
  Map<String, String> get properties {
    final props = <String, String>{
      'generation_id': generationId,
      'model_id': modelId,
      'input_tokens': inputTokens.toString(),
      'output_tokens': outputTokens.toString(),
      'duration_ms': durationMs.toStringAsFixed(1),
      'tokens_per_second': tokensPerSecond.toStringAsFixed(2),
      'is_streaming': isStreaming.toString(),
      'framework': framework,
    };
    if (timeToFirstTokenMs != null) {
      props['time_to_first_token_ms'] = timeToFirstTokenMs!.toStringAsFixed(1);
    }
    return props;
  }
}

/// Generation failed
class LLMGenerationFailedEvent extends LLMEvent {
  final String generationId;
  final String error;

  const LLMGenerationFailedEvent({
    required this.generationId,
    required this.error,
  });

  @override
  String get type => 'llm_generation_failed';

  @override
  Map<String, String> get properties => {
        'generation_id': generationId,
        'error': error,
      };
}
