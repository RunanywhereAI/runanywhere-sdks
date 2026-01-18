import 'dart:async';
import 'dart:convert';

import 'package:runanywhere/data/network/http_service.dart';
import 'package:runanywhere/foundation/configuration/sdk_constants.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';
import 'package:uuid/uuid.dart';

/// Telemetry event categories (matches C++/Swift/React Native categories)
enum TelemetryCategory {
  sdk,
  model,
  llm,
  stt,
  tts,
  vad,
  voiceAgent,
  error,
}

extension TelemetryCategoryExtension on TelemetryCategory {
  String get value {
    switch (this) {
      case TelemetryCategory.sdk:
        return 'sdk';
      case TelemetryCategory.model:
        return 'model';
      case TelemetryCategory.llm:
        return 'llm';
      case TelemetryCategory.stt:
        return 'stt';
      case TelemetryCategory.tts:
        return 'tts';
      case TelemetryCategory.vad:
        return 'vad';
      case TelemetryCategory.voiceAgent:
        return 'voice_agent';
      case TelemetryCategory.error:
        return 'error';
    }
  }
}

/// Telemetry event model
class TelemetryEvent {
  final String id;
  final String type;
  final TelemetryCategory category;
  final Map<String, dynamic> properties;
  final DateTime timestamp;
  final DateTime createdAt;

  TelemetryEvent({
    String? id,
    required this.type,
    required this.category,
    Map<String, dynamic>? properties,
    DateTime? timestamp,
  })  : id = id ?? _generateEventId(),
        properties = properties ?? {},
        timestamp = timestamp ?? DateTime.now(),
        createdAt = DateTime.now();

  /// Generate a proper UUID v4 string for event IDs.
  /// Backend requires UUID format (xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx).
  /// Uses the uuid package for proper RFC 4122 compliance.
  static String _generateEventId() {
    return const Uuid().v4();
  }

  /// Convert to JSON for Supabase (development)
  /// Uses column names expected by Supabase telemetry_events table
  /// Schema matches C++ telemetry_json.cpp rac_telemetry_manager_payload_to_json()
  ///
  /// Only includes non-null values to match C++ behavior (add_string skips null).
  /// Events are sent one at a time, so each can have different keys.
  Map<String, dynamic> toSupabaseJson({
    required String deviceId,
    required String sdkVersion,
    required String platform,
  }) {
    final json = <String, dynamic>{
      // Required fields (Supabase-specific key names)
      'sdk_event_id': id,
      'event_type': type,
      'event_timestamp': timestamp.toUtc().toIso8601String(),
      'created_at': createdAt.toUtc().toIso8601String(),
      // Development-only fields
      'modality': category.value,
      'device_id': deviceId,
      // Device info
      'platform': platform,
      'sdk_version': sdkVersion,
    };

    // Helper to add non-null values only (matches C++ add_string/add_int behavior)
    void addIfNotNull(String supabaseKey, dynamic value) {
      if (value != null) {
        json[supabaseKey] = value;
      }
    }

    // Helper to get value from properties with fallback key
    dynamic getValue(String key, [String? fallbackKey]) {
      return properties[key] ?? (fallbackKey != null ? properties[fallbackKey] : null);
    }

    // Session tracking
    addIfNotNull('session_id', getValue('session_id'));

    // Model info
    addIfNotNull('model_id', getValue('model_id'));
    addIfNotNull('model_name', getValue('model_name'));
    addIfNotNull('framework', getValue('framework'));

    // Common metrics
    addIfNotNull(
        'processing_time_ms',
        getValue('processing_time_ms') ??
            getValue('load_time_ms') ??
            getValue('latency_ms') ??
            getValue('download_time_ms'));
    addIfNotNull('success', getValue('success'));
    addIfNotNull('error_message', getValue('error_message'));
    addIfNotNull('error_code', getValue('error_code'));

    // LLM fields
    addIfNotNull('input_tokens', getValue('input_tokens', 'prompt_tokens'));
    addIfNotNull('output_tokens', getValue('output_tokens', 'completion_tokens'));
    addIfNotNull('total_tokens', getValue('total_tokens'));
    addIfNotNull('tokens_per_second', getValue('tokens_per_second'));
    addIfNotNull('time_to_first_token_ms', getValue('time_to_first_token_ms'));
    addIfNotNull('generation_time_ms', getValue('generation_time_ms'));
    addIfNotNull('context_length', getValue('context_length'));
    addIfNotNull('temperature', getValue('temperature'));
    addIfNotNull('max_tokens', getValue('max_tokens'));
    addIfNotNull('is_streaming', getValue('is_streaming'));

    // STT fields
    addIfNotNull('audio_duration_ms', getValue('audio_duration_ms'));
    addIfNotNull('real_time_factor', getValue('real_time_factor'));
    addIfNotNull('word_count', getValue('word_count'));
    addIfNotNull('confidence', getValue('confidence'));
    addIfNotNull('language', getValue('language'));

    // TTS fields
    addIfNotNull('character_count', getValue('character_count', 'text_length'));
    addIfNotNull('voice', getValue('voice', 'voice_id'));
    addIfNotNull('sample_rate', getValue('sample_rate'));
    addIfNotNull('characters_per_second', getValue('characters_per_second'));
    // TTS uses output_duration_ms in Supabase (same as audio_duration_ms)
    addIfNotNull('output_duration_ms', getValue('audio_duration_ms'));
    addIfNotNull('audio_size_bytes', getValue('audio_size_bytes'));

    return json;
  }

  /// Convert to JSON for Production (Railway)
  /// Matches C++ telemetry_json.cpp rac_telemetry_manager_payload_to_json()
  ///
  /// Key differences from development:
  /// - Uses "id" (not "sdk_event_id")
  /// - Uses "timestamp" (not "event_timestamp")
  /// - Does NOT include modality or device_id at event level (they're at batch level)
  /// - All fields flattened (no 'properties' nesting)
  /// - No 'category' field (extra='forbid')
  Map<String, dynamic> toProductionJson() {
    final json = <String, dynamic>{
      // Required fields - match C++ exactly
      'id': id, // UUID format
      'timestamp': timestamp.toUtc().toIso8601String(),
      'event_type': type,
      'created_at': createdAt.toUtc().toIso8601String(),
      // NOTE: modality and device_id are at BATCH level in production, not here
    };

    // Helper to add non-null/non-zero values only (matches C++ add_string/add_int behavior)
    void addIfNotNull(String key, dynamic value) {
      if (value == null) return;
      // Skip zero values for integers (matches C++ add_int behavior)
      // But keep zero for doubles (confidence, real_time_factor, etc. can be 0.0)
      if (value is int && value == 0) return;
      json[key] = value;
    }

    // Helper to always add a value, even if zero (for fields that must be present)
    void addAlways(String key, dynamic value) {
      if (value != null) {
        json[key] = value;
      }
    }

    // Helper to get value from properties
    dynamic getValue(String key, [String? fallbackKey]) {
      return properties[key] ??
          (fallbackKey != null ? properties[fallbackKey] : null);
    }

    // Session tracking
    addIfNotNull('session_id', getValue('session_id'));

    // Model info
    addIfNotNull('model_id', getValue('model_id'));
    addIfNotNull('model_name', getValue('model_name'));
    addIfNotNull('framework', getValue('framework'));

    // Device info (included at event level in production per C++ telemetry_json.cpp:218-221)
    addIfNotNull('device', getValue('device'));
    addIfNotNull('os_version', getValue('os_version'));
    addIfNotNull('platform', getValue('platform'));
    addIfNotNull('sdk_version', getValue('sdk_version'));

    // Common metrics
    addIfNotNull(
        'processing_time_ms',
        getValue('processing_time_ms') ??
            getValue('load_time_ms') ??
            getValue('latency_ms') ??
            getValue('download_time_ms'));
    addIfNotNull('success', getValue('success'));
    addIfNotNull('error_message', getValue('error_message'));
    addIfNotNull('error_code', getValue('error_code'));

    // LLM fields (match C++ telemetry_json.cpp:229-239)
    addIfNotNull('input_tokens', getValue('input_tokens', 'prompt_tokens'));
    addIfNotNull('output_tokens', getValue('output_tokens', 'completion_tokens'));
    addIfNotNull('total_tokens', getValue('total_tokens'));
    addIfNotNull('tokens_per_second', getValue('tokens_per_second'));
    addIfNotNull('time_to_first_token_ms', getValue('time_to_first_token_ms'));
    addIfNotNull('prompt_eval_time_ms', getValue('prompt_eval_time_ms'));
    addIfNotNull('generation_time_ms', getValue('generation_time_ms'));
    addIfNotNull('context_length', getValue('context_length'));
    addIfNotNull('temperature', getValue('temperature'));
    addIfNotNull('max_tokens', getValue('max_tokens'));

    // STT fields (match C++ telemetry_json.cpp:242-248)
    addIfNotNull('audio_duration_ms', getValue('audio_duration_ms'));
    addIfNotNull('real_time_factor', getValue('real_time_factor'));
    addIfNotNull('word_count', getValue('word_count'));
    addIfNotNull('confidence', getValue('confidence'));
    addIfNotNull('language', getValue('language'));
    addIfNotNull('is_streaming', getValue('is_streaming'));
    addIfNotNull('segment_index', getValue('segment_index'));

    // TTS fields (match C++ telemetry_json.cpp:251-256)
    addIfNotNull('character_count', getValue('character_count', 'text_length'));
    addIfNotNull('characters_per_second', getValue('characters_per_second'));
    addIfNotNull('audio_size_bytes', getValue('audio_size_bytes'));
    addIfNotNull('sample_rate', getValue('sample_rate'));
    addIfNotNull('voice', getValue('voice', 'voice_id'));
    // TTS stores audio_duration_ms but backend expects output_duration_ms
    addIfNotNull('output_duration_ms', getValue('output_duration_ms', 'audio_duration_ms'));

    // Model lifecycle (match C++ telemetry_json.cpp:259-260)
    addIfNotNull('model_size_bytes', getValue('model_size_bytes'));
    addIfNotNull('archive_type', getValue('archive_type'));

    // VAD (match C++ telemetry_json.cpp:263)
    addIfNotNull('speech_duration_ms', getValue('speech_duration_ms'));

    // SDK lifecycle (match C++ telemetry_json.cpp:266)
    addIfNotNull('count', getValue('count'));

    // Storage (match C++ telemetry_json.cpp:269)
    addIfNotNull('freed_bytes', getValue('freed_bytes'));

    // Network (match C++ telemetry_json.cpp:272)
    addIfNotNull('is_online', getValue('is_online'));

    return json;
  }
}

/// TelemetryService - Event tracking for RunAnywhere SDK
///
/// This service provides telemetry tracking for the Flutter SDK,
/// aligned with Swift/Kotlin/React Native SDKs.
///
/// ARCHITECTURE:
/// - C++ telemetry manager handles core event logic (batching, JSON building, routing)
/// - Platform SDK provides HTTP transport via HTTPService
/// - Events are automatically tracked by C++ when using LLM/STT/TTS/VAD capabilities
///
/// This Dart service provides:
/// - A wrapper to send telemetry events via HTTPService
/// - Convenience methods that match the Swift/Kotlin/React Native API
/// - SDK-level events that Dart code can emit
///
/// Usage:
/// ```dart
/// // Configure (called during SDK init)
/// TelemetryService.shared.configure(
///   deviceId: 'device-123',
///   environment: SDKEnvironment.production,
/// );
///
/// // Track events
/// TelemetryService.shared.trackSDKInit(
///   environment: 'production',
///   success: true,
/// );
///
/// // Flush pending events
/// await TelemetryService.shared.flush();
/// ```
class TelemetryService {
  // ============================================================================
  // Singleton
  // ============================================================================

  static TelemetryService? _instance;

  /// Get shared TelemetryService instance
  static TelemetryService get shared {
    _instance ??= TelemetryService._();
    return _instance!;
  }

  // ============================================================================
  // State
  // ============================================================================

  bool _enabled = true;
  String? _deviceId;
  SDKEnvironment _environment = SDKEnvironment.production;
  final List<TelemetryEvent> _eventQueue = [];
  Timer? _flushTimer;
  bool _isFlushInProgress = false;

  final SDKLogger _logger;

  // ============================================================================
  // Configuration
  // ============================================================================

  /// Batch size before auto-flush
  static const int _batchSize = 10;

  /// Flush interval in seconds
  static const int _flushIntervalSeconds = 30;

  // ============================================================================
  // Initialization
  // ============================================================================

  TelemetryService._() : _logger = SDKLogger('TelemetryService');

  /// Configure telemetry service
  ///
  /// [deviceId] - Unique device identifier
  /// [environment] - SDK environment (development, staging, production)
  void configure({
    required String deviceId,
    required SDKEnvironment environment,
  }) {
    _deviceId = deviceId;
    _environment = environment;

    // Start periodic flush timer
    _startFlushTimer();

    _logger.debug('Configured for ${environment.description}');
  }

  /// Enable or disable telemetry
  void setEnabled(bool enabled) {
    _enabled = enabled;
    _logger.debug('Telemetry ${enabled ? 'enabled' : 'disabled'}');

    if (!enabled) {
      _stopFlushTimer();
      _eventQueue.clear();
    } else {
      _startFlushTimer();
    }
  }

  /// Check if telemetry is enabled
  bool get isEnabled => _enabled;

  /// Check if telemetry is initialized (configured with device ID)
  bool get isInitialized => _deviceId != null;

  // ============================================================================
  // Core Telemetry Operations
  // ============================================================================

  /// Track a generic event
  ///
  /// [type] - Event type identifier
  /// [category] - Event category for grouping
  /// [properties] - Additional event properties
  void track(
    String type, {
    TelemetryCategory category = TelemetryCategory.sdk,
    Map<String, dynamic>? properties,
  }) {
    if (!_enabled) return;

    final event = TelemetryEvent(
      type: type,
      category: category,
      properties: _enrichProperties(properties),
    );

    _eventQueue.add(event);
    _logger.debug('Event tracked: $type');

    // Auto-flush if batch size reached
    if (_eventQueue.length >= _batchSize) {
      unawaited(flush());
    }
  }

  /// Flush pending telemetry events
  ///
  /// Sends all queued events to the backend immediately.
  /// Call this on app background/exit to ensure events are sent.
  Future<void> flush() async {
    if (!_enabled || _eventQueue.isEmpty || _isFlushInProgress) {
      return;
    }

    _isFlushInProgress = true;

    try {
      // Take current batch
      final batch = List<TelemetryEvent>.from(_eventQueue);
      _eventQueue.clear();

      // Get telemetry endpoint based on environment
      final endpoint = _getTelemetryEndpoint();

      if (_environment == SDKEnvironment.development) {
        // Supabase: Send events ONE AT A TIME to avoid "All object keys must match" error
        // Each event can have different keys based on its properties
        int successCount = 0;
        for (final event in batch) {
          try {
            final payload = event.toSupabaseJson(
              deviceId: _deviceId ?? 'unknown',
              sdkVersion: SDKConstants.version,
              platform: SDKConstants.platform,
            );

            // Debug: Log the payload being sent
            _logger.debug('Sending telemetry event: ${event.type}');
            _logger.debug('Payload: $payload');

            final response = await HTTPService.shared.post<dynamic>(
              endpoint,
              payload,
              requiresAuth: false,
            );

            // Debug: Log the response
            _logger.debug('Response for ${event.type}: $response');

            successCount++;
          } catch (e) {
            _logger.error('Failed to send event ${event.type}: $e');
          }
        }
        _logger.debug('Flushed $successCount/${batch.length} events');
      } else {
        // Production/Staging: Group events by modality and send separate batches
        // This matches the C++ telemetry manager which groups by modality
        // V2 modalities: llm, stt, tts, model (get modality field at batch level)
        // V1 modality: system/null (SDK lifecycle, storage, device, network events)
        final v2Modalities = {'llm', 'stt', 'tts', 'model'};
        final Map<String?, List<TelemetryEvent>> byModality = {};

        // Group events by modality
        for (final event in batch) {
          final modality = event.category.value;
          // V2 modalities get their modality name, V1 events get null
          final key = v2Modalities.contains(modality) ? modality : null;
          byModality.putIfAbsent(key, () => []).add(event);
        }

        // Send batches by modality (matching C++ telemetry_manager.cpp)
        int successCount = 0;
        for (final entry in byModality.entries) {
          final modality = entry.key;
          final modalityEvents = entry.value;

          final payload = <String, dynamic>{
            'events': modalityEvents.map((e) => e.toProductionJson()).toList(),
            'device_id': _deviceId,
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          };

          // Include modality at batch level for V2 events
          if (modality != null) {
            payload['modality'] = modality;
          }

          try {
            await HTTPService.shared.post<dynamic>(
              endpoint,
              payload,
              requiresAuth: true,
            );
            successCount += modalityEvents.length;
            _logger.debug(
                'Flushed ${modalityEvents.length} ${modality ?? "system"} events');
          } catch (e) {
            _logger.error(
                'Failed to flush ${modality ?? "system"} events: $e');
          }
        }
        _logger.debug('Flushed $successCount/${batch.length} events total');
      }
    } catch (e) {
      _logger.error('Failed to flush telemetry: $e');
      // Events are already removed from queue, so they're lost on failure
      // This is acceptable for telemetry to avoid memory buildup
    } finally {
      _isFlushInProgress = false;
    }
  }

  /// Shutdown telemetry service
  ///
  /// Flushes any pending events before stopping.
  Future<void> shutdown() async {
    _stopFlushTimer();

    try {
      await flush();
      _logger.debug('Telemetry shutdown complete');
    } catch (e) {
      _logger.error('Telemetry shutdown error: $e');
    }
  }

  // ============================================================================
  // Convenience Methods
  // ============================================================================

  /// Track SDK initialization
  void trackSDKInit({
    required String environment,
    required bool success,
  }) {
    track(
      'sdk_initialized',
      category: TelemetryCategory.sdk,
      properties: {
        'environment': environment,
        'success': success,
        'sdk_version': SDKConstants.version,
        'platform': SDKConstants.platform,
      },
    );
  }

  /// Track model loading
  void trackModelLoad({
    required String modelId,
    required String modelType,
    required bool success,
    int? loadTimeMs,
  }) {
    track(
      'model_loaded',
      category: TelemetryCategory.model,
      properties: {
        'model_id': modelId,
        'model_type': modelType,
        'success': success,
        if (loadTimeMs != null) 'load_time_ms': loadTimeMs,
      },
    );
  }

  /// Track model download
  void trackModelDownload({
    required String modelId,
    required bool success,
    int? downloadTimeMs,
    int? sizeBytes,
  }) {
    track(
      'model_downloaded',
      category: TelemetryCategory.model,
      properties: {
        'model_id': modelId,
        'success': success,
        if (downloadTimeMs != null) 'download_time_ms': downloadTimeMs,
        if (sizeBytes != null) 'size_bytes': sizeBytes,
      },
    );
  }

  /// Track text generation
  void trackGeneration({
    required String modelId,
    required int promptTokens,
    required int completionTokens,
    required int latencyMs,
    String? modelName,
    double? temperature,
    int? maxTokens,
    int? contextLength,
    double? tokensPerSecond,
    int? timeToFirstTokenMs,
    bool isStreaming = false,
  }) {
    final totalTokens = promptTokens + completionTokens;
    final calculatedTps = tokensPerSecond ?? 
        (latencyMs > 0 ? (completionTokens / latencyMs) * 1000 : 0.0);
    
    track(
      'generation_completed',
      category: TelemetryCategory.llm,
      properties: {
        'model_id': modelId,
        'model_name': modelName,
        'prompt_tokens': promptTokens,
        'completion_tokens': completionTokens,
        'total_tokens': totalTokens,
        'latency_ms': latencyMs,
        'generation_time_ms': latencyMs,
        'tokens_per_second': calculatedTps,
        'temperature': temperature,
        'max_tokens': maxTokens,
        'context_length': contextLength,
        'time_to_first_token_ms': timeToFirstTokenMs,
        'is_streaming': isStreaming,
      },
    );
  }

  /// Track transcription
  void trackTranscription({
    required String modelId,
    required int audioDurationMs,
    required int latencyMs,
    String? modelName,
    int? wordCount,
    double? confidence,
    String? language,
    bool isStreaming = false,
  }) {
    // Calculate real-time factor (RTF) - how fast transcription is vs audio length
    // RTF < 1 means faster than real-time
    final realTimeFactor = audioDurationMs > 0 
        ? latencyMs / audioDurationMs 
        : null;
    
    // Infer language from model ID if not provided (e.g., "whisper-tiny.en" → "en")
    String? detectedLanguage = language;
    if (detectedLanguage == null || detectedLanguage.isEmpty) {
      // Try to extract language from model ID (e.g., ".en", "-en", "_en")
      final langMatch = RegExp(r'[._-](en|zh|de|fr|es|ja|ko|ru|pt|it|nl|pl|ar|tr|sv|da|no|fi|cs|el|he|hu|id|ms|ro|th|uk|vi)$', caseSensitive: false).firstMatch(modelId);
      if (langMatch != null) {
        detectedLanguage = langMatch.group(1)?.toLowerCase();
      }
    }

    // Ensure confidence has a value - models that don't compute confidence return 0.0
    // Use 1.0 as default for successful transcriptions (high confidence)
    // If model returns 0.0 (no confidence computed), estimate based on word count
    double effectiveConfidence = confidence ?? 0.0;
    if (effectiveConfidence == 0.0 && wordCount != null && wordCount > 0) {
      // Model didn't compute confidence but we got words - estimate 0.9 confidence
      effectiveConfidence = 0.9;
    } else if (effectiveConfidence == 0.0) {
      // No words, low confidence
      effectiveConfidence = 0.0;
    }
    
    track(
      'transcription_completed',
      category: TelemetryCategory.stt,
      properties: {
        'model_id': modelId,
        'model_name': modelName,
        'audio_duration_ms': audioDurationMs,
        'latency_ms': latencyMs,
        'word_count': wordCount,
        'confidence': effectiveConfidence,
        'language': detectedLanguage,
        'real_time_factor': realTimeFactor,
        'is_streaming': isStreaming,
      },
    );
  }

  /// Track speech synthesis
  void trackSynthesis({
    required String voiceId,
    required int textLength,
    required int audioDurationMs,
    required int latencyMs,
    String? modelName,
    int? sampleRate,
    int? audioSizeBytes,
  }) {
    // Calculate characters per second
    final charactersPerSecond = latencyMs > 0 
        ? (textLength / latencyMs) * 1000 
        : null;
    
    track(
      'synthesis_completed',
      category: TelemetryCategory.tts,
      properties: {
        'model_id': voiceId, // Use voice ID as model ID for TTS
        'voice_id': voiceId,
        'model_name': modelName,
        'text_length': textLength,
        'character_count': textLength, // Alias for backend compatibility
        'audio_duration_ms': audioDurationMs,
        'output_duration_ms': audioDurationMs, // Alias for TTS backend field
        'latency_ms': latencyMs,
        'sample_rate': sampleRate,
        'characters_per_second': charactersPerSecond,
        'audio_size_bytes': audioSizeBytes,
      },
    );
  }

  /// Track VAD event
  void trackVAD({
    required String eventType,
    Map<String, dynamic>? properties,
  }) {
    track(
      'vad_$eventType',
      category: TelemetryCategory.vad,
      properties: properties,
    );
  }

  /// Track voice agent turn
  void trackVoiceAgentTurn({
    required String transcription,
    required String response,
    required int totalLatencyMs,
    int? sttLatencyMs,
    int? llmLatencyMs,
    int? ttsLatencyMs,
  }) {
    track(
      'voice_turn_completed',
      category: TelemetryCategory.voiceAgent,
      properties: {
        'transcription_length': transcription.length,
        'response_length': response.length,
        'total_latency_ms': totalLatencyMs,
        if (sttLatencyMs != null) 'stt_latency_ms': sttLatencyMs,
        if (llmLatencyMs != null) 'llm_latency_ms': llmLatencyMs,
        if (ttsLatencyMs != null) 'tts_latency_ms': ttsLatencyMs,
      },
    );
  }

  /// Track error
  void trackError({
    required String errorCode,
    required String errorMessage,
    Map<String, dynamic>? context,
  }) {
    track(
      'error',
      category: TelemetryCategory.error,
      properties: {
        'error_code': errorCode,
        'error_message': errorMessage,
        if (context != null) ...context,
      },
    );
  }

  // ============================================================================
  // Private Methods
  // ============================================================================

  Map<String, dynamic> _enrichProperties(Map<String, dynamic>? properties) {
    return {
      'device_id': _deviceId,
      'sdk_version': SDKConstants.version,
      'platform': SDKConstants.platform,
      if (properties != null) ...properties,
    };
  }

  String _getTelemetryEndpoint() {
    switch (_environment) {
      case SDKEnvironment.development:
        return '/rest/v1/telemetry_events';
      case SDKEnvironment.staging:
      case SDKEnvironment.production:
        return '/api/v1/sdk/telemetry';
    }
  }

  void _startFlushTimer() {
    _stopFlushTimer();
    _flushTimer = Timer.periodic(
      const Duration(seconds: _flushIntervalSeconds),
      (_) => flush(),
    );
  }

  void _stopFlushTimer() {
    _flushTimer?.cancel();
    _flushTimer = null;
  }

  /// Reset for testing
  static void resetForTesting() {
    _instance?._stopFlushTimer();
    _instance = null;
  }
}
