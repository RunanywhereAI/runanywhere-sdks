/// Base protocol for all SDK events
abstract class SDKEvent {
  /// Timestamp when the event occurred
  DateTime get timestamp => DateTime.now();
}

/// SDK initialization events
abstract class SDKInitializationEvent implements SDKEvent {}

class SDKInitializationStarted implements SDKInitializationEvent {
  @override
  final DateTime timestamp = DateTime.now();
}

class SDKInitializationCompleted implements SDKInitializationEvent {
  @override
  final DateTime timestamp = DateTime.now();
}

class SDKInitializationFailed implements SDKInitializationEvent {
  final Object error;
  @override
  final DateTime timestamp = DateTime.now();

  SDKInitializationFailed(this.error);
}

/// SDK configuration events
abstract class SDKConfigurationEvent implements SDKEvent {}

/// SDK generation events
abstract class SDKGenerationEvent implements SDKEvent {
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

class SDKGenerationStarted implements SDKGenerationEvent {
  final String prompt;
  @override
  final DateTime timestamp = DateTime.now();

  SDKGenerationStarted({required this.prompt});
}

class SDKGenerationCompleted implements SDKGenerationEvent {
  final String response;
  final int tokensUsed;
  final int latencyMs;
  @override
  final DateTime timestamp = DateTime.now();

  SDKGenerationCompleted({
    required this.response,
    required this.tokensUsed,
    required this.latencyMs,
  });
}

class SDKGenerationFailed implements SDKGenerationEvent {
  final Object error;
  @override
  final DateTime timestamp = DateTime.now();

  SDKGenerationFailed(this.error);
}

class SDKGenerationCostCalculated implements SDKGenerationEvent {
  final double amount;
  final double savedAmount;
  @override
  final DateTime timestamp = DateTime.now();

  SDKGenerationCostCalculated({
    required this.amount,
    required this.savedAmount,
  });
}

/// SDK model events
abstract class SDKModelEvent implements SDKEvent {
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
}

class SDKModelLoadStarted implements SDKModelEvent {
  final String modelId;
  @override
  final DateTime timestamp = DateTime.now();

  SDKModelLoadStarted({required this.modelId});
}

class SDKModelLoadCompleted implements SDKModelEvent {
  final String modelId;
  @override
  final DateTime timestamp = DateTime.now();

  SDKModelLoadCompleted({required this.modelId});
}

class SDKModelLoadFailed implements SDKModelEvent {
  final String modelId;
  final Object error;
  @override
  final DateTime timestamp = DateTime.now();

  SDKModelLoadFailed({required this.modelId, required this.error});
}

class SDKModelUnloadStarted implements SDKModelEvent {
  final String modelId;
  @override
  final DateTime timestamp = DateTime.now();

  SDKModelUnloadStarted({required this.modelId});
}

class SDKModelUnloadCompleted implements SDKModelEvent {
  final String modelId;
  @override
  final DateTime timestamp = DateTime.now();

  SDKModelUnloadCompleted({required this.modelId});
}

/// SDK voice events
abstract class SDKVoiceEvent implements SDKEvent {
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

class SDKVoiceListeningStarted implements SDKVoiceEvent {
  @override
  final DateTime timestamp = DateTime.now();
}

class SDKVoiceListeningEnded implements SDKVoiceEvent {
  @override
  final DateTime timestamp = DateTime.now();
}

class SDKVoiceSpeechDetected implements SDKVoiceEvent {
  @override
  final DateTime timestamp = DateTime.now();
}

class SDKVoiceTranscriptionStarted implements SDKVoiceEvent {
  @override
  final DateTime timestamp = DateTime.now();
}

class SDKVoiceTranscriptionPartial implements SDKVoiceEvent {
  final String text;
  @override
  final DateTime timestamp = DateTime.now();

  SDKVoiceTranscriptionPartial({required this.text});
}

class SDKVoiceTranscriptionFinal implements SDKVoiceEvent {
  final String text;
  @override
  final DateTime timestamp = DateTime.now();

  SDKVoiceTranscriptionFinal({required this.text});
}

class SDKVoiceResponseGenerated implements SDKVoiceEvent {
  final String text;
  @override
  final DateTime timestamp = DateTime.now();

  SDKVoiceResponseGenerated({required this.text});
}

class SDKVoiceSynthesisStarted implements SDKVoiceEvent {
  @override
  final DateTime timestamp = DateTime.now();
}

class SDKVoiceAudioGenerated implements SDKVoiceEvent {
  final dynamic data;
  @override
  final DateTime timestamp = DateTime.now();

  SDKVoiceAudioGenerated({required this.data});
}

class SDKVoiceSynthesisCompleted implements SDKVoiceEvent {
  @override
  final DateTime timestamp = DateTime.now();
}

class SDKVoicePipelineError implements SDKVoiceEvent {
  final Object error;
  @override
  final DateTime timestamp = DateTime.now();

  SDKVoicePipelineError({required this.error});
}

class SDKVoicePipelineStarted implements SDKVoiceEvent {
  @override
  final DateTime timestamp = DateTime.now();
}

class SDKVoicePipelineCompleted implements SDKVoiceEvent {
  @override
  final DateTime timestamp = DateTime.now();
}

class SDKVoiceVADStarted implements SDKVoiceEvent {
  @override
  final DateTime timestamp = DateTime.now();
}

class SDKVoiceVADDetected implements SDKVoiceEvent {
  @override
  final DateTime timestamp = DateTime.now();
}

class SDKVoiceVADEnded implements SDKVoiceEvent {
  @override
  final DateTime timestamp = DateTime.now();
}

class SDKVoiceSTTProcessing implements SDKVoiceEvent {
  @override
  final DateTime timestamp = DateTime.now();
}

class SDKVoiceLLMProcessing implements SDKVoiceEvent {
  @override
  final DateTime timestamp = DateTime.now();
}

class SDKVoiceTTSProcessing implements SDKVoiceEvent {
  @override
  final DateTime timestamp = DateTime.now();
}

/// SDK performance events
abstract class SDKPerformanceEvent implements SDKEvent {}

/// SDK network events
abstract class SDKNetworkEvent implements SDKEvent {}

/// SDK storage events
abstract class SDKStorageEvent implements SDKEvent {}

/// SDK framework events
abstract class SDKFrameworkEvent implements SDKEvent {}
