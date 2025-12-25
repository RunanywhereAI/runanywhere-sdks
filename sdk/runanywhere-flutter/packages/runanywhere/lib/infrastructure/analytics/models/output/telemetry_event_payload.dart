//
//  telemetry_event_payload.dart
//  RunAnywhere SDK
//
//  Typed telemetry payload for backend API transmission.
//  Matches iOS TelemetryEventPayload.swift exactly.
//  NO properties dictionary - all fields are strongly typed.
//

import 'package:runanywhere/infrastructure/analytics/models/domain/telemetry_data.dart';

/// Typed telemetry event payload for API transmission.
/// Maps to backend SDKTelemetryEvent schema with strongly typed fields.
class TelemetryEventPayload {
  // MARK: - Required Fields

  final String id;
  final String eventType;
  final DateTime timestamp;
  final DateTime createdAt;

  // MARK: - Session Tracking

  final String? sessionId;

  // MARK: - Model Info

  final String? modelId;
  final String? modelName;
  final String? framework;

  // MARK: - Device Info

  final String? device;
  final String? osVersion;
  final String? platform;
  final String? sdkVersion;

  // MARK: - Common Performance Metrics

  final double? processingTimeMs;
  final bool? success;
  final String? errorMessage;
  final String? errorCode;

  // MARK: - LLM-specific Fields

  final int? inputTokens;
  final int? outputTokens;
  final int? totalTokens;
  final double? tokensPerSecond;
  final double? timeToFirstTokenMs;
  final double? promptEvalTimeMs;
  final double? generationTimeMs;
  final int? contextLength;
  final double? temperature;
  final int? maxTokens;

  // MARK: - STT-specific Fields

  final double? audioDurationMs;
  final double? realTimeFactor;
  final int? wordCount;
  final double? confidence;
  final String? language;
  final bool? isStreaming;
  final int? segmentIndex;

  // MARK: - TTS-specific Fields

  final int? characterCount;
  final double? charactersPerSecond;
  final int? audioSizeBytes;
  final int? sampleRate;
  final String? voice;
  final double? outputDurationMs;

  // MARK: - Initializer

  TelemetryEventPayload({
    required this.id,
    required this.eventType,
    required this.timestamp,
    required this.createdAt,
    this.sessionId,
    this.modelId,
    this.modelName,
    this.framework,
    this.device,
    this.osVersion,
    this.platform,
    this.sdkVersion,
    this.processingTimeMs,
    this.success,
    this.errorMessage,
    this.errorCode,
    this.inputTokens,
    this.outputTokens,
    this.totalTokens,
    this.tokensPerSecond,
    this.timeToFirstTokenMs,
    this.promptEvalTimeMs,
    this.generationTimeMs,
    this.contextLength,
    this.temperature,
    this.maxTokens,
    this.audioDurationMs,
    this.realTimeFactor,
    this.wordCount,
    this.confidence,
    this.language,
    this.isStreaming,
    this.segmentIndex,
    this.characterCount,
    this.charactersPerSecond,
    this.audioSizeBytes,
    this.sampleRate,
    this.voice,
    this.outputDurationMs,
  });

  // MARK: - Conversion from TelemetryData

  /// Convert from local TelemetryData (with properties dict) to typed payload for API
  factory TelemetryEventPayload.fromTelemetryData(TelemetryData telemetryData) {
    final props = telemetryData.properties;

    return TelemetryEventPayload(
      id: telemetryData.id,
      eventType: telemetryData.eventType,
      timestamp: telemetryData.timestamp,
      createdAt: telemetryData.createdAt,
      // Session
      sessionId: props['session_id'],
      // Model info
      modelId: props['model_id'],
      modelName: props['model_name'],
      framework: props['framework'],
      // Device info
      device: props['device'],
      osVersion: props['os_version'],
      platform: props['platform'],
      sdkVersion: props['sdk_version'],
      // Common metrics
      processingTimeMs:
          _parseDouble(props['processing_time_ms'] ?? props['total_time_ms']),
      success: _parseBool(props['success']),
      errorMessage: props['error_message'],
      errorCode: props['error_code'],
      // LLM
      inputTokens: _parseInt(props['input_tokens'] ?? props['prompt_tokens']),
      outputTokens: _parseInt(props['output_tokens']),
      totalTokens: _parseInt(props['total_tokens']),
      tokensPerSecond: _parseDouble(props['tokens_per_second']),
      timeToFirstTokenMs: _parseDouble(props['time_to_first_token_ms']),
      promptEvalTimeMs: _parseDouble(props['prompt_eval_time_ms']),
      generationTimeMs: _parseDouble(props['generation_time_ms']),
      contextLength: _parseInt(props['context_length']),
      temperature: _parseDouble(props['temperature']),
      maxTokens: _parseInt(props['max_tokens']),
      // STT
      audioDurationMs: _parseDouble(props['audio_duration_ms']),
      realTimeFactor: _parseDouble(props['real_time_factor']),
      wordCount: _parseInt(props['word_count']),
      confidence: _parseDouble(props['confidence']),
      language: props['language'],
      isStreaming: _parseBool(props['is_streaming']),
      segmentIndex: _parseInt(props['segment_index']),
      // TTS
      characterCount: _parseInt(props['character_count']),
      charactersPerSecond: _parseDouble(props['characters_per_second']),
      audioSizeBytes: _parseInt(props['audio_size_bytes']),
      sampleRate: _parseInt(props['sample_rate']),
      voice: props['voice'],
      outputDurationMs: _parseDouble(
          props['output_duration_ms'] ?? props['audio_duration_ms']),
    );
  }

  // MARK: - Private Helpers

  static double? _parseDouble(String? value) {
    if (value == null) return null;
    return double.tryParse(value);
  }

  static int? _parseInt(String? value) {
    if (value == null) return null;
    return int.tryParse(value);
  }

  static bool? _parseBool(String? value) {
    if (value == null) return null;
    final lower = value.toLowerCase();
    return lower == 'true' || value == '1';
  }

  // MARK: - JSON Serialization (snake_case for API)

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'event_type': eventType,
      'timestamp': timestamp.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      if (sessionId != null) 'session_id': sessionId,
      if (modelId != null) 'model_id': modelId,
      if (modelName != null) 'model_name': modelName,
      if (framework != null) 'framework': framework,
      if (device != null) 'device': device,
      if (osVersion != null) 'os_version': osVersion,
      if (platform != null) 'platform': platform,
      if (sdkVersion != null) 'sdk_version': sdkVersion,
      if (processingTimeMs != null) 'processing_time_ms': processingTimeMs,
      if (success != null) 'success': success,
      if (errorMessage != null) 'error_message': errorMessage,
      if (errorCode != null) 'error_code': errorCode,
      if (inputTokens != null) 'input_tokens': inputTokens,
      if (outputTokens != null) 'output_tokens': outputTokens,
      if (totalTokens != null) 'total_tokens': totalTokens,
      if (tokensPerSecond != null) 'tokens_per_second': tokensPerSecond,
      if (timeToFirstTokenMs != null)
        'time_to_first_token_ms': timeToFirstTokenMs,
      if (promptEvalTimeMs != null) 'prompt_eval_time_ms': promptEvalTimeMs,
      if (generationTimeMs != null) 'generation_time_ms': generationTimeMs,
      if (contextLength != null) 'context_length': contextLength,
      if (temperature != null) 'temperature': temperature,
      if (maxTokens != null) 'max_tokens': maxTokens,
      if (audioDurationMs != null) 'audio_duration_ms': audioDurationMs,
      if (realTimeFactor != null) 'real_time_factor': realTimeFactor,
      if (wordCount != null) 'word_count': wordCount,
      if (confidence != null) 'confidence': confidence,
      if (language != null) 'language': language,
      if (isStreaming != null) 'is_streaming': isStreaming,
      if (segmentIndex != null) 'segment_index': segmentIndex,
      if (characterCount != null) 'character_count': characterCount,
      if (charactersPerSecond != null)
        'characters_per_second': charactersPerSecond,
      if (audioSizeBytes != null) 'audio_size_bytes': audioSizeBytes,
      if (sampleRate != null) 'sample_rate': sampleRate,
      if (voice != null) 'voice': voice,
      if (outputDurationMs != null) 'output_duration_ms': outputDurationMs,
    };
  }
}
