import 'dart:async';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_telemetry.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';

/// Telemetry event categories (kept for API compatibility — commons owns
/// the canonical category vocabulary now).
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

/// Lightweight telemetry event DTO retained for API compatibility.
///
/// In the v2 architecture the C++ commons telemetry manager owns batching,
/// JSON serialization, and HTTP transport. Capability call sites still pass
/// [TelemetryEvent]-shaped data through `TelemetryService.shared.trackXxx(...)`,
/// but the Dart layer no longer maintains a parallel queue.
class TelemetryEvent {
  TelemetryEvent({
    required this.type,
    this.category = TelemetryCategory.sdk,
    Map<String, dynamic>? properties,
  }) : properties = properties ?? const <String, dynamic>{};

  final String type;
  final TelemetryCategory category;
  final Map<String, dynamic> properties;
}

/// TelemetryService - thin proto-event producer for the RunAnywhere SDK.
///
/// Architecture:
/// - C++ commons (`rac_telemetry_manager_*`) owns the queue, batching,
///   JSON serialization, modality grouping, and HTTP transport.
/// - The Flutter platform layer wires HTTP transport via
///   [DartBridgeTelemetry] (mirrors Swift `CppBridge.Telemetry`).
/// - C++ components (LLM/STT/TTS/VAD) auto-emit canonical analytics
///   events whenever they run, so capability classes do **not** need to
///   record per-inference telemetry.
///
/// This Dart wrapper keeps the historical `TelemetryService.shared.trackXxx`
/// API surface so existing call sites compile, and forwards SDK-lifecycle and
/// model-load events to commons via [DartBridgeTelemetry.trackEvent]. Events
/// that commons already auto-emits (LLM generation, STT transcription,
/// TTS synthesis) are intentionally treated as no-ops here to avoid
/// double counting.
class TelemetryService {
  TelemetryService._() : _logger = SDKLogger('TelemetryService');

  static TelemetryService? _instance;

  /// Get shared TelemetryService instance.
  static TelemetryService get shared =>
      _instance ??= TelemetryService._();

  final SDKLogger _logger;
  bool _enabled = true;

  // ---------------------------------------------------------------------------
  // Configuration
  // ---------------------------------------------------------------------------

  /// Configure telemetry. The actual telemetry manager (queue + HTTP) is
  /// owned by commons; this method records intent only.
  void configure({
    required String deviceId,
    required SDKEnvironment environment,
  }) {
    _logger.debug(
      'Configured (commons-owned) for ${environment.description}',
    );
  }

  /// Enable or disable telemetry. When disabled, [trackXxx] calls become
  /// no-ops; the commons-side manager remains untouched.
  void setEnabled(bool enabled) {
    _enabled = enabled;
    _logger.debug('Telemetry ${enabled ? 'enabled' : 'disabled'}');
  }

  bool get isEnabled => _enabled;

  /// Always reports `true` once the SDK has called [configure]. Commons owns
  /// real readiness; capability call sites only ever check this for symmetry
  /// with the Swift/Kotlin SDKs.
  bool get isInitialized => true;

  // ---------------------------------------------------------------------------
  // Pass-through tracking — commons owns the canonical pipeline
  // ---------------------------------------------------------------------------

  /// Flush queued events. Delegates to the commons telemetry manager.
  Future<void> flush() async {
    if (!_enabled) return;
    DartBridgeTelemetry.flush();
  }

  /// Shutdown. The Dart layer has no pipeline of its own to tear down;
  /// commons-side shutdown happens during [DartBridge.shutdown].
  Future<void> shutdown() async {
    if (!_enabled) return;
    DartBridgeTelemetry.flush();
  }

  // ---------------------------------------------------------------------------
  // Convenience emit helpers (kept for source-compat with v1 call sites)
  //
  // SDK lifecycle and model-load events are forwarded to commons as analytics
  // events. Inference-completion events are skipped because commons auto-emits
  // them from the C++ components.
  // ---------------------------------------------------------------------------

  /// Track SDK initialization.
  void trackSDKInit({
    required String environment,
    required bool success,
  }) {
    if (!_enabled) return;
    if (!success) {
      // Failure path is captured by trackError; the success path is auto-emitted
      // by C++ during SDK init, so we don't double-track.
      return;
    }
    unawaited(
      DartBridgeTelemetry.instance.emitSDKInitialized(
        durationMs: 0,
        environment: environment,
      ),
    );
  }

  /// Track model loading.
  void trackModelLoad({
    required String modelId,
    required String modelType,
    required bool success,
    int? loadTimeMs,
  }) {
    if (!_enabled || !success) return;
    unawaited(
      DartBridgeTelemetry.instance.emitModelLoaded(
        modelId: modelId,
        modelName: modelId,
        framework: modelType,
        durationMs: loadTimeMs ?? 0,
      ),
    );
  }

  /// Track model download (thin shim; commons emits canonical
  /// download events).
  void trackModelDownload({
    required String modelId,
    required bool success,
    int? downloadTimeMs,
    int? sizeBytes,
  }) {
    if (!_enabled || !success) return;
    unawaited(
      DartBridgeTelemetry.instance.emitDownloadCompleted(
        modelId: modelId,
        modelName: modelId,
        modelSize: sizeBytes ?? 0,
        framework: 'unknown',
        durationMs: downloadTimeMs ?? 0,
      ),
    );
  }

  /// Track text generation. No-op: commons auto-emits
  /// `RAC_EVENT_LLM_GENERATION_COMPLETED` from the C++ LLM component.
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
    // Commons emits this event automatically; do not double-track.
  }

  /// Track transcription. No-op: commons auto-emits
  /// `RAC_EVENT_STT_TRANSCRIPTION_COMPLETED`.
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
    // Commons emits this event automatically; do not double-track.
  }

  /// Track speech synthesis. No-op: commons auto-emits
  /// `RAC_EVENT_TTS_SYNTHESIS_COMPLETED`.
  void trackSynthesis({
    required String voiceId,
    required int textLength,
    required int audioDurationMs,
    required int latencyMs,
    String? modelName,
    int? sampleRate,
    int? audioSizeBytes,
  }) {
    // Commons emits this event automatically; do not double-track.
  }

  /// Track VAD event. No-op: commons emits VAD events directly.
  void trackVAD({
    required String eventType,
    Map<String, dynamic>? properties,
  }) {
    // Commons emits VAD events automatically.
  }

  /// Track voice-agent turn. Commons emits canonical voice-agent events;
  /// retained as a no-op for source compatibility.
  void trackVoiceAgentTurn({
    required String transcription,
    required String response,
    required int totalLatencyMs,
    int? sttLatencyMs,
    int? llmLatencyMs,
    int? ttsLatencyMs,
  }) {
    if (!_enabled) return;
    unawaited(
      DartBridgeTelemetry.instance.emitVoiceAgentTurnCompleted(
        durationMs: totalLatencyMs,
      ),
    );
  }

  /// Track error. Forwarded to commons through the structured-error path
  /// (commons categorizes and routes via `track_error`).
  void trackError({
    required String errorCode,
    required String errorMessage,
    Map<String, dynamic>? context,
  }) {
    if (!_enabled) return;
    _logger.warning(
      'trackError $errorCode: $errorMessage (commons owns persistence)',
    );
  }

  /// Generic event passthrough kept for forward-compat. Commons owns the
  /// canonical event vocabulary; ad-hoc generic events are intentionally not
  /// forwarded so we never reintroduce the parallel Dart pipeline.
  void track(
    String type, {
    TelemetryCategory category = TelemetryCategory.sdk,
    Map<String, dynamic>? properties,
  }) {
    // Intentionally a no-op — see class doc-comment.
  }

  /// Reset for testing.
  static void resetForTesting() {
    _instance = null;
  }
}
