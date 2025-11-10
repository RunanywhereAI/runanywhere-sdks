/// Base class for all SDK events
/// Similar to Swift SDK's SDKEvent
abstract class SDKEvent {
  final DateTime timestamp;

  SDKEvent() : timestamp = DateTime.now();
}

/// SDK Initialization Events
class SDKInitializationEvent extends SDKEvent {
  final String? prompt;
  final String? response;
  final int? tokensUsed;
  final int? latencyMs;
  final double? amount;
  final double? savedAmount;
  final String? modelId;
  final Error? error;

  SDKInitializationEvent.started()
      : prompt = null,
        response = null,
        tokensUsed = null,
        latencyMs = null,
        amount = null,
        savedAmount = null,
        modelId = null,
        error = null;

  SDKInitializationEvent.completed()
      : prompt = null,
        response = null,
        tokensUsed = null,
        latencyMs = null,
        amount = null,
        savedAmount = null,
        modelId = null,
        error = null;

  SDKInitializationEvent.failed(Error? error)
      : error = error,
        prompt = null,
        response = null,
        tokensUsed = null,
        latencyMs = null,
        amount = null,
        savedAmount = null,
        modelId = null;
}

/// SDK Generation Events
class SDKGenerationEvent extends SDKEvent {
  final String? prompt;
  final String? response;
  final int? tokensUsed;
  final int? latencyMs;
  final double? amount;
  final double? savedAmount;
  final Error? error;

  SDKGenerationEvent.started({required this.prompt})
      : response = null,
        tokensUsed = null,
        latencyMs = null,
        amount = null,
        savedAmount = null,
        error = null;

  SDKGenerationEvent.completed({
    required this.response,
    required this.tokensUsed,
    required this.latencyMs,
  })  : prompt = null,
        amount = null,
        savedAmount = null,
        error = null;

  SDKGenerationEvent.costCalculated({
    required this.amount,
    required this.savedAmount,
  })  : prompt = null,
        response = null,
        tokensUsed = null,
        latencyMs = null,
        error = null;

  SDKGenerationEvent.failed(Error? error)
      : error = error,
        prompt = null,
        response = null,
        tokensUsed = null,
        latencyMs = null,
        amount = null,
        savedAmount = null;
}

/// SDK Voice Events
class SDKVoiceEvent extends SDKEvent {
  final String? text;
  final Error? error;

  SDKVoiceEvent.transcriptionStarted()
      : text = null,
        error = null;

  SDKVoiceEvent.transcriptionFinal({required this.text}) : error = null;

  SDKVoiceEvent.pipelineStarted()
      : text = null,
        error = null;

  SDKVoiceEvent.pipelineError(Error? error)
      : error = error,
        text = null;
}

/// SDK Model Events
class SDKModelEvent extends SDKEvent {
  final String? modelId;
  final Error? error;

  SDKModelEvent.loadStarted({required this.modelId}) : error = null;

  SDKModelEvent.loadCompleted({required this.modelId}) : error = null;

  SDKModelEvent.loadFailed({required this.modelId, required Error? error})
      : error = error;
}
