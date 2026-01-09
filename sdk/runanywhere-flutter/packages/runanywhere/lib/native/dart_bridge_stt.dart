// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/native_backend.dart';

/// STT bridge for C++ speech-to-text operations.
/// Matches Swift's `CppBridge+STT.swift`.
class DartBridgeSTT {
  DartBridgeSTT._();

  static final _logger = SDKLogger('DartBridge.STT');
  static final DartBridgeSTT instance = DartBridgeSTT._();

  NativeBackend? _backend;

  /// Set the native backend for STT operations
  void setBackend(NativeBackend backend) {
    _backend = backend;
  }

  /// Load an STT model
  Future<bool> loadModel({
    required String modelPath,
    String? modelType,
    Map<String, dynamic>? config,
  }) async {
    final backend = _backend;
    if (backend == null) {
      _logger.warning('No backend set for STT operations');
      return false;
    }

    try {
      backend.loadSttModel(
        modelPath,
        modelType: modelType ?? 'whisper',
        config: config,
      );
      return true;
    } catch (e) {
      _logger
          .error('Failed to load STT model', metadata: {'error': e.toString()});
      return false;
    }
  }

  /// Check if STT model is loaded
  bool isModelLoaded() {
    return _backend?.isSttModelLoaded ?? false;
  }

  /// Unload the current STT model
  Future<bool> unloadModel() async {
    final backend = _backend;
    if (backend == null) return true;

    try {
      backend.unloadSttModel();
      return true;
    } catch (e) {
      _logger.error('Failed to unload STT model',
          metadata: {'error': e.toString()});
      return false;
    }
  }

  /// Transcribe audio (non-streaming)
  Future<STTTranscriptionResult?> transcribe({
    required Float32List samples,
    int sampleRate = 16000,
    String? language,
  }) async {
    final backend = _backend;
    if (backend == null) {
      _logger.warning('No backend set for STT transcription');
      return null;
    }

    try {
      final result = backend.transcribe(
        samples,
        sampleRate: sampleRate,
        language: language,
      );

      return STTTranscriptionResult(
        text: result['text'] as String? ?? '',
        language: result['language'] as String? ?? language ?? 'en',
        confidence: (result['confidence'] as num?)?.toDouble() ?? 1.0,
        durationMs: result['duration_ms'] as int? ?? 0,
      );
    } catch (e) {
      _logger.error('Transcription failed', metadata: {'error': e.toString()});
      return null;
    }
  }

  /// Check if streaming is supported
  bool supportsStreaming() {
    return _backend?.sttSupportsStreaming ?? false;
  }

  /// Cancel ongoing transcription.
  ///
  /// STT cancellation signals the native backend to stop processing.
  /// Note: The effect depends on the backend's implementation.
  void cancel() {
    _logger.debug('STT cancel requested');
    // Native STT typically processes in one shot, so cancel is a no-op
    // For streaming STT, the stream would be closed instead
  }
}

/// Result of STT transcription
class STTTranscriptionResult {
  final String text;
  final String language;
  final double confidence;
  final int durationMs;

  STTTranscriptionResult({
    required this.text,
    required this.language,
    required this.confidence,
    required this.durationMs,
  });
}
