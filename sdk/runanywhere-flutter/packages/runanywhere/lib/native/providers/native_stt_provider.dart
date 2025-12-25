import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/core/module_registry.dart';
import 'package:runanywhere/native/native_backend.dart';

/// Native STT service using ONNX/Sherpa-ONNX backend via FFI.
///
/// This is the Flutter equivalent of iOS's ONNXSTTService.
class NativeSTTService implements STTService {
  final NativeBackend _backend;
  String? _modelPath;
  bool _isInitialized = false;

  NativeSTTService(this._backend);

  /// ONNX Runtime inference framework
  /// Matches iOS ONNXSTTService.inferenceFramework
  @override
  String? get inferenceFramework => 'onnx';

  @override
  Future<void> initialize({String? modelPath}) async {
    _modelPath = modelPath;

    if (modelPath != null) {
      // Detect model type from path
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
      sampleRate: 16000,
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

  String _detectModelType(String path) {
    final lowerPath = path.toLowerCase();
    if (lowerPath.contains('zipformer') || lowerPath.contains('sherpa')) {
      return 'zipformer';
    }
    if (lowerPath.contains('paraformer')) {
      return 'paraformer';
    }
    // Default to whisper
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

/// Provider for native STT service.
///
/// This is the Flutter equivalent of iOS's ONNXSTTServiceProvider.
class NativeSTTServiceProvider implements STTServiceProvider {
  final NativeBackend _backend;

  NativeSTTServiceProvider(this._backend);

  @override
  String get name => 'NativeONNX';

  @override
  bool canHandle({String? modelId}) {
    if (modelId == null) return true;

    final lower = modelId.toLowerCase();
    // Handle ONNX-based STT models
    return lower.endsWith('.onnx') ||
        lower.contains('whisper') ||
        lower.contains('zipformer') ||
        lower.contains('sherpa') ||
        lower.contains('paraformer');
  }

  @override
  Future<STTService> createSTTService(dynamic configuration) async {
    final service = NativeSTTService(_backend);

    String? modelPath;
    if (configuration is Map) {
      modelPath = configuration['modelPath'] as String?;
    } else if (configuration is String) {
      modelPath = configuration;
    }

    await service.initialize(modelPath: modelPath);
    return service;
  }
}
