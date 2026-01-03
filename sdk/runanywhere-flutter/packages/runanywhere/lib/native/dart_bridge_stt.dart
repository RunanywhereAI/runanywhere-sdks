// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:typed_data';

import '../foundation/logging/sdk_logger.dart';
import 'ffi_types.dart';
import 'native_backend.dart';

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
      _logger.error('Failed to load STT model', metadata: {'error': e.toString()});
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
      _logger.error('Failed to unload STT model', metadata: {'error': e.toString()});
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

  /// Create a streaming session
  RaStreamHandle? createStream({Map<String, dynamic>? config}) {
    final backend = _backend;
    if (backend == null) return null;

    try {
      return backend.createSttStream(config: config);
    } catch (e) {
      _logger.error('Failed to create STT stream', metadata: {'error': e.toString()});
      return null;
    }
  }

  /// Feed audio to streaming session
  void feedAudio(RaStreamHandle stream, Float32List samples, {int sampleRate = 16000}) {
    final backend = _backend;
    if (backend == null) return;

    backend.feedSttAudio(stream, samples, sampleRate: sampleRate);
  }

  /// Check if stream is ready for decoding
  bool isStreamReady(RaStreamHandle stream) {
    return _backend?.isSttReady(stream) ?? false;
  }

  /// Decode current stream buffer
  Map<String, dynamic>? decodeStream(RaStreamHandle stream) {
    return _backend?.decodeStt(stream);
  }

  /// Check if endpoint detected
  bool isEndpoint(RaStreamHandle stream) {
    return _backend?.isSttEndpoint(stream) ?? false;
  }

  /// Signal input finished
  void inputFinished(RaStreamHandle stream) {
    _backend?.sttInputFinished(stream);
  }

  /// Reset stream for reuse
  void resetStream(RaStreamHandle stream) {
    _backend?.resetSttStream(stream);
  }

  /// Destroy streaming session
  void destroyStream(RaStreamHandle stream) {
    _backend?.destroySttStream(stream);
  }

  /// Cancel ongoing transcription
  void cancel() {
    _backend?.cancelStt();
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
