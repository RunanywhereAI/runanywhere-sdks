import 'analytics_context.dart';
import 'analytics_event.dart';

/// Structured event data models for strongly typed analytics
///
/// Corresponds to iOS SDK's AnalyticsEventData.swift

// MARK: - Voice Event Data Models

/// Pipeline creation event data
class PipelineCreationData implements AnalyticsEventData {
  final int stageCount;
  final List<String> stages;

  const PipelineCreationData({
    required this.stageCount,
    required this.stages,
  });

  @override
  Map<String, dynamic> toMap() => {
        'stageCount': stageCount,
        'stages': stages,
      };
}

/// Pipeline started event data
class PipelineStartedData implements AnalyticsEventData {
  final int stageCount;
  final List<String> stages;
  final double startTimestamp;

  const PipelineStartedData({
    required this.stageCount,
    required this.stages,
    required this.startTimestamp,
  });

  @override
  Map<String, dynamic> toMap() => {
        'stageCount': stageCount,
        'stages': stages,
        'startTimestamp': startTimestamp,
      };
}

/// Pipeline completion event data
class PipelineCompletionData implements AnalyticsEventData {
  final int stageCount;
  final List<String> stages;
  final double totalTimeMs;

  const PipelineCompletionData({
    required this.stageCount,
    required this.stages,
    required this.totalTimeMs,
  });

  @override
  Map<String, dynamic> toMap() => {
        'stageCount': stageCount,
        'stages': stages,
        'totalTimeMs': totalTimeMs,
      };
}

/// Stage execution event data
class StageExecutionData implements AnalyticsEventData {
  final String stageName;
  final double durationMs;

  const StageExecutionData({
    required this.stageName,
    required this.durationMs,
  });

  @override
  Map<String, dynamic> toMap() => {
        'stageName': stageName,
        'durationMs': durationMs,
      };
}

/// Voice transcription event data
class VoiceTranscriptionData implements AnalyticsEventData {
  final double durationMs;
  final int wordCount;
  final double audioLengthMs;
  final double realTimeFactor;

  const VoiceTranscriptionData({
    required this.durationMs,
    required this.wordCount,
    required this.audioLengthMs,
    required this.realTimeFactor,
  });

  @override
  Map<String, dynamic> toMap() => {
        'durationMs': durationMs,
        'wordCount': wordCount,
        'audioLengthMs': audioLengthMs,
        'realTimeFactor': realTimeFactor,
      };
}

/// Transcription start event data
class TranscriptionStartData implements AnalyticsEventData {
  final double audioLengthMs;
  final double startTimestamp;

  const TranscriptionStartData({
    required this.audioLengthMs,
    required this.startTimestamp,
  });

  @override
  Map<String, dynamic> toMap() => {
        'audioLengthMs': audioLengthMs,
        'startTimestamp': startTimestamp,
      };
}

// MARK: - STT Event Data Models

/// STT transcription completion data
class STTTranscriptionData implements AnalyticsEventData {
  final int wordCount;
  final double confidence;
  final double durationMs;
  final double audioLengthMs;
  final double realTimeFactor;
  final String speakerId;

  const STTTranscriptionData({
    required this.wordCount,
    required this.confidence,
    required this.durationMs,
    required this.audioLengthMs,
    required this.realTimeFactor,
    this.speakerId = 'unknown',
  });

  @override
  Map<String, dynamic> toMap() => {
        'wordCount': wordCount,
        'confidence': confidence,
        'durationMs': durationMs,
        'audioLengthMs': audioLengthMs,
        'realTimeFactor': realTimeFactor,
        'speakerId': speakerId,
      };
}

/// Final transcript event data
class FinalTranscriptData implements AnalyticsEventData {
  final int textLength;
  final int wordCount;
  final double confidence;
  final String speakerId;
  final double timestamp;

  const FinalTranscriptData({
    required this.textLength,
    required this.wordCount,
    required this.confidence,
    this.speakerId = 'unknown',
    required this.timestamp,
  });

  @override
  Map<String, dynamic> toMap() => {
        'textLength': textLength,
        'wordCount': wordCount,
        'confidence': confidence,
        'speakerId': speakerId,
        'timestamp': timestamp,
      };
}

/// Partial transcript event data
class PartialTranscriptData implements AnalyticsEventData {
  final int textLength;
  final int wordCount;

  const PartialTranscriptData({
    required this.textLength,
    required this.wordCount,
  });

  @override
  Map<String, dynamic> toMap() => {
        'textLength': textLength,
        'wordCount': wordCount,
      };
}

/// Speaker detection event data
class SpeakerDetectionData implements AnalyticsEventData {
  final String speakerId;
  final double confidence;
  final double timestamp;

  const SpeakerDetectionData({
    required this.speakerId,
    required this.confidence,
    required this.timestamp,
  });

  @override
  Map<String, dynamic> toMap() => {
        'speakerId': speakerId,
        'confidence': confidence,
        'timestamp': timestamp,
      };
}

/// Speaker change event data
class SpeakerChangeData implements AnalyticsEventData {
  final String fromSpeaker;
  final String toSpeaker;
  final double timestamp;

  SpeakerChangeData({
    String? fromSpeaker,
    required this.toSpeaker,
    required this.timestamp,
  }) : fromSpeaker = fromSpeaker ?? 'none';

  @override
  Map<String, dynamic> toMap() => {
        'fromSpeaker': fromSpeaker,
        'toSpeaker': toSpeaker,
        'timestamp': timestamp,
      };
}

/// Language detection event data
class LanguageDetectionData implements AnalyticsEventData {
  final String language;
  final double confidence;

  const LanguageDetectionData({
    required this.language,
    required this.confidence,
  });

  @override
  Map<String, dynamic> toMap() => {
        'language': language,
        'confidence': confidence,
      };
}

// MARK: - Generation Event Data Models

/// Generation start event data
class GenerationStartData implements AnalyticsEventData {
  final String generationId;
  final String modelId;
  final String executionTarget;
  final int promptTokens;
  final int maxTokens;

  const GenerationStartData({
    required this.generationId,
    required this.modelId,
    required this.executionTarget,
    required this.promptTokens,
    required this.maxTokens,
  });

  @override
  Map<String, dynamic> toMap() => {
        'generationId': generationId,
        'modelId': modelId,
        'executionTarget': executionTarget,
        'promptTokens': promptTokens,
        'maxTokens': maxTokens,
      };
}

/// Generation completion event data
class GenerationCompletionData implements AnalyticsEventData {
  final String generationId;
  final String modelId;
  final String executionTarget;
  final int inputTokens;
  final int outputTokens;
  final double totalTimeMs;
  final double timeToFirstTokenMs;
  final double tokensPerSecond;

  const GenerationCompletionData({
    required this.generationId,
    required this.modelId,
    required this.executionTarget,
    required this.inputTokens,
    required this.outputTokens,
    required this.totalTimeMs,
    required this.timeToFirstTokenMs,
    required this.tokensPerSecond,
  });

  @override
  Map<String, dynamic> toMap() => {
        'generationId': generationId,
        'modelId': modelId,
        'executionTarget': executionTarget,
        'inputTokens': inputTokens,
        'outputTokens': outputTokens,
        'totalTimeMs': totalTimeMs,
        'timeToFirstTokenMs': timeToFirstTokenMs,
        'tokensPerSecond': tokensPerSecond,
      };
}

/// Streaming update event data
class StreamingUpdateData implements AnalyticsEventData {
  final String generationId;
  final int tokensGenerated;

  const StreamingUpdateData({
    required this.generationId,
    required this.tokensGenerated,
  });

  @override
  Map<String, dynamic> toMap() => {
        'generationId': generationId,
        'tokensGenerated': tokensGenerated,
      };
}

/// First token event data
class FirstTokenData implements AnalyticsEventData {
  final String generationId;
  final double timeToFirstTokenMs;

  const FirstTokenData({
    required this.generationId,
    required this.timeToFirstTokenMs,
  });

  @override
  Map<String, dynamic> toMap() => {
        'generationId': generationId,
        'timeToFirstTokenMs': timeToFirstTokenMs,
      };
}

/// Model loading event data
class ModelLoadingData implements AnalyticsEventData {
  final String modelId;
  final double loadTimeMs;
  final bool success;
  final String? errorCode;

  const ModelLoadingData({
    required this.modelId,
    required this.loadTimeMs,
    required this.success,
    this.errorCode,
  });

  @override
  Map<String, dynamic> toMap() => {
        'modelId': modelId,
        'loadTimeMs': loadTimeMs,
        'success': success,
        if (errorCode != null) 'errorCode': errorCode,
      };
}

/// Model unloading event data
class ModelUnloadingData implements AnalyticsEventData {
  final String modelId;
  final double timestamp;

  ModelUnloadingData({
    required this.modelId,
  }) : timestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;

  @override
  Map<String, dynamic> toMap() => {
        'modelId': modelId,
        'timestamp': timestamp,
      };
}

// MARK: - Monitoring Event Data Models

/// Resource usage event data
class ResourceUsageData implements AnalyticsEventData {
  final double memoryUsageMB;
  final double cpuUsagePercent;
  final double? diskUsageMB;
  final double? batteryLevel;

  const ResourceUsageData({
    required this.memoryUsageMB,
    required this.cpuUsagePercent,
    this.diskUsageMB,
    this.batteryLevel,
  });

  @override
  Map<String, dynamic> toMap() => {
        'memoryUsageMB': memoryUsageMB,
        'cpuUsagePercent': cpuUsagePercent,
        if (diskUsageMB != null) 'diskUsageMB': diskUsageMB,
        if (batteryLevel != null) 'batteryLevel': batteryLevel,
      };
}

/// Performance metrics event data
class PerformanceMetricsEventData implements AnalyticsEventData {
  final String operationName;
  final double durationMs;
  final bool success;
  final String? errorCode;

  const PerformanceMetricsEventData({
    required this.operationName,
    required this.durationMs,
    required this.success,
    this.errorCode,
  });

  @override
  Map<String, dynamic> toMap() => {
        'operationName': operationName,
        'durationMs': durationMs,
        'success': success,
        if (errorCode != null) 'errorCode': errorCode,
      };
}

/// CPU threshold event data
class CPUThresholdData implements AnalyticsEventData {
  final double cpuUsage;
  final double threshold;
  final double timestamp;

  CPUThresholdData({
    required this.cpuUsage,
    required this.threshold,
  }) : timestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;

  @override
  Map<String, dynamic> toMap() => {
        'cpuUsage': cpuUsage,
        'threshold': threshold,
        'timestamp': timestamp,
      };
}

/// Disk space warning event data
class DiskSpaceWarningData implements AnalyticsEventData {
  final int availableSpaceMB;
  final int requiredSpaceMB;
  final double timestamp;

  DiskSpaceWarningData({
    required this.availableSpaceMB,
    required this.requiredSpaceMB,
  }) : timestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;

  @override
  Map<String, dynamic> toMap() => {
        'availableSpaceMB': availableSpaceMB,
        'requiredSpaceMB': requiredSpaceMB,
        'timestamp': timestamp,
      };
}

/// Network latency event data
class NetworkLatencyData implements AnalyticsEventData {
  final String endpoint;
  final double latencyMs;
  final double timestamp;

  NetworkLatencyData({
    required this.endpoint,
    required this.latencyMs,
  }) : timestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;

  @override
  Map<String, dynamic> toMap() => {
        'endpoint': endpoint,
        'latencyMs': latencyMs,
        'timestamp': timestamp,
      };
}

/// Memory warning event data
class MemoryWarningData implements AnalyticsEventData {
  final String warningLevel;
  final int availableMemoryMB;
  final double timestamp;

  MemoryWarningData({
    required this.warningLevel,
    required this.availableMemoryMB,
  }) : timestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;

  @override
  Map<String, dynamic> toMap() => {
        'warningLevel': warningLevel,
        'availableMemoryMB': availableMemoryMB,
        'timestamp': timestamp,
      };
}

/// Session started event data
class SessionStartedData implements AnalyticsEventData {
  final String modelId;
  final String sessionType;
  final double timestamp;

  SessionStartedData({
    required this.modelId,
    required this.sessionType,
  }) : timestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;

  @override
  Map<String, dynamic> toMap() => {
        'modelId': modelId,
        'sessionType': sessionType,
        'timestamp': timestamp,
      };
}

/// Session ended event data
class SessionEndedData implements AnalyticsEventData {
  final String sessionId;
  final double duration;
  final double timestamp;

  SessionEndedData({
    required this.sessionId,
    required this.duration,
  }) : timestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;

  @override
  Map<String, dynamic> toMap() => {
        'sessionId': sessionId,
        'duration': duration,
        'timestamp': timestamp,
      };
}

// MARK: - Generic Error Data

/// Generic error event data
class ErrorEventData implements AnalyticsEventData {
  final String error;
  final String context;
  final String? errorCode;
  final double timestamp;

  ErrorEventData({
    required this.error,
    required AnalyticsContext analyticsContext,
    this.errorCode,
  })  : context = analyticsContext.rawValue,
        timestamp = DateTime.now().millisecondsSinceEpoch / 1000.0;

  @override
  Map<String, dynamic> toMap() => {
        'error': error,
        'context': context,
        if (errorCode != null) 'errorCode': errorCode,
        'timestamp': timestamp,
      };
}
