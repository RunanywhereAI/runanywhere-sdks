// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/native_backend.dart';

/// TTS bridge for C++ text-to-speech operations.
/// Matches Swift's `CppBridge+TTS.swift`.
class DartBridgeTTS {
  DartBridgeTTS._();

  static final _logger = SDKLogger('DartBridge.TTS');
  static final DartBridgeTTS instance = DartBridgeTTS._();

  NativeBackend? _backend;

  /// Set the native backend for TTS operations
  void setBackend(NativeBackend backend) {
    _backend = backend;
  }

  /// Load a TTS model
  Future<bool> loadModel({
    required String modelPath,
    String? modelType,
    Map<String, dynamic>? config,
  }) async {
    final backend = _backend;
    if (backend == null) {
      _logger.warning('No backend set for TTS operations');
      return false;
    }

    try {
      backend.loadTtsModel(
        modelPath,
        modelType: modelType ?? 'piper',
        config: config,
      );
      return true;
    } catch (e) {
      _logger
          .error('Failed to load TTS model', metadata: {'error': e.toString()});
      return false;
    }
  }

  /// Check if TTS model is loaded
  bool isModelLoaded() {
    return _backend?.isTtsModelLoaded ?? false;
  }

  /// Unload the current TTS model
  Future<bool> unloadModel() async {
    final backend = _backend;
    if (backend == null) return true;

    try {
      backend.unloadTtsModel();
      return true;
    } catch (e) {
      _logger.error('Failed to unload TTS model',
          metadata: {'error': e.toString()});
      return false;
    }
  }

  /// Synthesize text to audio
  Future<TTSSynthesisResult?> synthesize({
    required String text,
    String? voiceId,
    double speed = 1.0,
    double pitch = 0.0,
  }) async {
    final backend = _backend;
    if (backend == null) {
      _logger.warning('No backend set for TTS synthesis');
      return null;
    }

    try {
      final result = backend.synthesize(
        text,
        voiceId: voiceId,
        speed: speed,
        pitch: pitch,
      );

      final samples = result['samples'] as Float32List?;
      final sampleRate = result['sampleRate'] as int? ?? 22050;

      if (samples == null || samples.isEmpty) return null;

      return TTSSynthesisResult(
        audioSamples: samples,
        sampleRate: sampleRate,
      );
    } catch (e) {
      _logger.error('Synthesis failed', metadata: {'error': e.toString()});
      return null;
    }
  }

  /// Check if streaming is supported
  /// Note: TTS streaming is not yet implemented in NativeBackend.
  bool supportsStreaming() {
    return false;
  }

  /// Get available voices
  Future<List<TTSVoice>> getVoices() async {
    final backend = _backend;
    if (backend == null) return [];

    try {
      final voiceIds = backend.getTtsVoices();
      return voiceIds
          .map((id) => TTSVoice(
                id: id,
                name: id,
                language: 'en',
              ))
          .toList();
    } catch (e) {
      _logger.warning('Failed to get voices: $e');
      return [];
    }
  }

  /// Cancel ongoing synthesis
  /// Note: TTS cancel is not yet implemented in NativeBackend.
  void cancel() {
    _logger.debug('TTS cancel called (not yet implemented)');
  }
}

/// Result of TTS synthesis
class TTSSynthesisResult {
  final Float32List audioSamples;
  final int sampleRate;

  TTSSynthesisResult({
    required this.audioSamples,
    required this.sampleRate,
  });

  /// Duration in seconds
  double get duration => audioSamples.length / sampleRate;
}

/// TTS voice information
class TTSVoice {
  final String id;
  final String name;
  final String language;
  final String? gender;

  TTSVoice({
    required this.id,
    required this.name,
    required this.language,
    this.gender,
  });
}
