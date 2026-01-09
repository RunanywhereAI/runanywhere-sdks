import 'dart:async';

import 'package:runanywhere/core/module_registry.dart';
import 'package:runanywhere/native/native_backend.dart';

/// Provider for ONNX-based TTS service.
///
/// This is the Flutter equivalent of Swift's `ONNXTTSServiceProvider`.
class OnnxTTSServiceProvider implements TTSServiceProvider {
  final NativeBackend _backend;

  /// Create a new ONNX TTS provider.
  OnnxTTSServiceProvider(this._backend);

  @override
  String get name => 'ONNX Runtime';

  @override
  String get version => '1.23.2';

  @override
  bool canHandle({String? modelId}) {
    if (modelId == null) return true;

    final lower = modelId.toLowerCase();

    // Handle ONNX models
    if (lower.endsWith('.onnx') || lower.contains('onnx')) {
      return true;
    }

    // Handle VITS models (ONNX-based TTS)
    if (lower.contains('vits')) {
      return true;
    }

    // Handle Piper TTS models (ONNX-based)
    if (lower.contains('piper')) {
      return true;
    }

    // Handle Sherpa TTS models
    if (lower.contains('sherpa') && lower.contains('tts')) {
      return true;
    }

    return false;
  }

  @override
  Future<TTSService> createTTSService(dynamic configuration) async {
    // Create wrapper service that conforms to TTSService interface
    final service = _OnnxTTSServiceWrapper(_backend);

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

/// Wrapper around NativeBackend to provide TTSService interface
class _OnnxTTSServiceWrapper implements TTSService {
  final NativeBackend _backend;
  bool _isInitialized = false;

  _OnnxTTSServiceWrapper(this._backend);

  @override
  Future<void> initialize({String? modelPath}) async {
    if (modelPath != null && modelPath.isNotEmpty) {
      _backend.loadTtsModel(modelPath, modelType: 'vits');
    }
    _isInitialized = true;
  }

  @override
  Future<TTSOutput> synthesize(TTSInput input) async {
    final result = _backend.synthesize(
      input.text,
      voiceId: input.voiceId,
      speed: input.rate,
      pitch: input.pitch,
    );

    final samples = result['samples'] as List;
    final sampleRate = result['sampleRate'] as int? ?? 22050;

    // Convert samples to bytes if needed
    final List<int> audioData;
    if (samples is List<int>) {
      audioData = samples;
    } else {
      audioData = <int>[];
    }

    return TTSOutput(
      audioData: audioData,
      format: 'pcm',
      sampleRate: sampleRate,
    );
  }

  @override
  bool get isReady => _isInitialized && _backend.isTtsModelLoaded;

  @override
  Future<void> cleanup() async {
    if (_backend.isTtsModelLoaded) {
      _backend.unloadTtsModel();
    }
    _isInitialized = false;
  }
}
