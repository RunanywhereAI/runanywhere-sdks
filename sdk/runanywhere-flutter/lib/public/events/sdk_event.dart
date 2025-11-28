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

/// SDK voice events
abstract class SDKVoiceEvent implements SDKEvent {
  static SDKVoiceTranscriptionStarted transcriptionStarted() {
    return SDKVoiceTranscriptionStarted();
  }

  static SDKVoiceTranscriptionFinal transcriptionFinal({required String text}) {
    return SDKVoiceTranscriptionFinal(text: text);
  }

  static SDKVoicePipelineError pipelineError(Object error) {
    return SDKVoicePipelineError(error: error);
  }
}

class SDKVoiceTranscriptionStarted implements SDKVoiceEvent {
  @override
  final DateTime timestamp = DateTime.now();
}

class SDKVoiceTranscriptionFinal implements SDKVoiceEvent {
  final String text;
  @override
  final DateTime timestamp = DateTime.now();

  SDKVoiceTranscriptionFinal({required this.text});
}

class SDKVoicePipelineError implements SDKVoiceEvent {
  final Object error;
  @override
  final DateTime timestamp = DateTime.now();

  SDKVoicePipelineError({required this.error});
}

/// SDK performance events
abstract class SDKPerformanceEvent implements SDKEvent {}

/// SDK network events
abstract class SDKNetworkEvent implements SDKEvent {}

/// SDK storage events
abstract class SDKStorageEvent implements SDKEvent {}

/// SDK framework events
abstract class SDKFrameworkEvent implements SDKEvent {}

