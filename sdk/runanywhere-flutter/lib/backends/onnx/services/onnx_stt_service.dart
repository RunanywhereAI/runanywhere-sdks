import 'dart:async';
import 'dart:typed_data';

import '../../../core/module_registry.dart';
import '../../../native/native_backend.dart';

/// ONNX-based Speech-to-Text service.
///
/// This is the Flutter equivalent of Swift's `ONNXSTTService`.
/// It uses the native runanywhere-core library for transcription.
///
/// ## Usage
///
/// ```dart
/// final backend = NativeBackend();
/// backend.create('onnx');
///
/// final stt = OnnxSTTService(backend);
/// await stt.initialize(modelPath: '/path/to/model');
///
/// final result = await stt.transcribe(
///   audioData: audioBytes,
///   options: STTOptions(language: 'en'),
/// );
/// print(result.transcript);
/// ```
class OnnxSTTService implements STTService {
  final NativeBackend _backend;
  String? _modelPath;
  bool _isInitialized = false;

  /// Create a new ONNX STT service.
  OnnxSTTService(this._backend);

  @override
  Future<void> initialize({String? modelPath}) async {
    _modelPath = modelPath;

    if (modelPath != null) {
      final modelType = _detectModelType(modelPath);
      _backend.loadSttModel(
        modelPath,
        modelType: modelType,
        config: {'language': 'en'},
      );
    }

    _isInitialized = true;
  }

  @override
  bool get isReady => _isInitialized && _backend.isSttModelLoaded;

  @override
  String? get currentModel => _modelPath;

  @override
  bool get supportsStreaming => _backend.sttSupportsStreaming;

  @override
  Future<STTTranscriptionResult> transcribe({
    required List<int> audioData,
    required STTOptions options,
  }) async {
    // Convert PCM16 to Float32
    final samples = _convertToFloat32(audioData);

    final result = _backend.transcribe(
      samples,
      sampleRate: options.sampleRate,
      language: options.language,
    );

    return STTTranscriptionResult(
      transcript: result['text'] as String? ?? '',
      confidence: (result['confidence'] as num?)?.toDouble() ?? 1.0,
      language: result['language'] as String?,
      timestamps: _parseTimestamps(result['timestamps']),
      alternatives: null,
    );
  }

  @override
  Future<void> cleanup() async {
    if (_backend.isSttModelLoaded) {
      _backend.unloadSttModel();
    }
    _isInitialized = false;
  }

  // ============================================================================
  // Streaming Methods
  // ============================================================================

  /// Create a streaming session.
  Object createStream({Map<String, dynamic>? config}) {
    return _backend.createSttStream(config: config);
  }

  /// Feed audio to a streaming session.
  void feedAudio(Object stream, Float32List samples, {int sampleRate = 16000}) {
    _backend.feedSttAudio(stream as dynamic, samples, sampleRate: sampleRate);
  }

  /// Check if decoder is ready.
  bool isStreamReady(Object stream) {
    return _backend.isSttReady(stream as dynamic);
  }

  /// Decode and get current result.
  Map<String, dynamic>? decodeStream(Object stream) {
    return _backend.decodeStt(stream as dynamic);
  }

  /// Check for end-of-speech.
  bool isEndpoint(Object stream) {
    return _backend.isSttEndpoint(stream as dynamic);
  }

  /// Signal end of audio input.
  void inputFinished(Object stream) {
    _backend.sttInputFinished(stream as dynamic);
  }

  /// Reset stream for new utterance.
  void resetStream(Object stream) {
    _backend.resetSttStream(stream as dynamic);
  }

  /// Destroy streaming session.
  void destroyStream(Object stream) {
    _backend.destroySttStream(stream as dynamic);
  }

  /// Cancel ongoing transcription.
  void cancel() {
    _backend.cancelStt();
  }

  // ============================================================================
  // Private Helpers
  // ============================================================================

  String _detectModelType(String path) {
    final lowerPath = path.toLowerCase();
    if (lowerPath.contains('zipformer') || lowerPath.contains('sherpa')) {
      return 'zipformer';
    }
    if (lowerPath.contains('paraformer')) {
      return 'paraformer';
    }
    return 'whisper';
  }

  Float32List _convertToFloat32(List<int> audioData) {
    // Assume input is PCM16 (2 bytes per sample)
    final float32 = Float32List(audioData.length ~/ 2);
    for (var i = 0; i < float32.length; i++) {
      final sample = audioData[i * 2] | (audioData[i * 2 + 1] << 8);
      final signedSample = sample > 32767 ? sample - 65536 : sample;
      float32[i] = signedSample / 32768.0;
    }
    return float32;
  }

  List<TimestampInfo>? _parseTimestamps(dynamic timestamps) {
    if (timestamps == null) return null;
    if (timestamps is! List) return null;

    return timestamps.map((t) {
      if (t is Map) {
        return TimestampInfo(
          word: t['word'] as String? ?? '',
          startTime: (t['start'] as num?)?.toDouble() ?? 0.0,
          endTime: (t['end'] as num?)?.toDouble() ?? 0.0,
        );
      }
      return TimestampInfo(word: '', startTime: 0, endTime: 0);
    }).toList();
  }
}
