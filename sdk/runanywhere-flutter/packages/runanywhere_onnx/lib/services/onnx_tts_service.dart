import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/core/module_registry.dart';
import 'package:runanywhere/native/native_backend.dart';

/// ONNX-based Text-to-Speech service.
///
/// This is the Flutter equivalent of Swift's `ONNXTTSService`.
/// It uses the native runanywhere-core library for speech synthesis.
///
/// ## Usage
///
/// ```dart
/// final backend = NativeBackend.onnx();
/// final tts = OnnxTTSService(backend);
/// await tts.initialize(modelPath: '/path/to/model');
///
/// final input = TTSInput(text: 'Hello, world!');
/// final output = await tts.synthesize(input);
/// ```
class OnnxTTSService implements TTSService {
  final NativeBackend _backend;
  bool _isInitialized = false;
  bool _isSynthesizing = false;
  List<String> _voices = [];

  /// Create a new ONNX TTS service.
  OnnxTTSService(this._backend);

  /// Get the inference framework
  String get inferenceFramework => 'onnx';

  @override
  bool get isReady => _isInitialized && _backend.isTtsModelLoaded;

  /// Whether synthesis is currently in progress
  bool get isSynthesizing => _isSynthesizing;

  /// Get available voice IDs
  List<String> get availableVoices => _voices;

  @override
  Future<void> initialize({String? modelPath}) async {
    if (modelPath == null || modelPath.isEmpty) {
      _isInitialized = true;
      return;
    }

    try {
      // Load the TTS model through native backend
      _backend.loadTtsModel(
        modelPath,
        modelType: 'vits',
      );

      // Verify the model loaded successfully
      if (!_backend.isTtsModelLoaded) {
        throw Exception('TTS model failed to load');
      }

      // Get available voices
      _voices = _backend.getTtsVoices();
    } catch (e) {
      _isInitialized = false;
      rethrow;
    }

    _isInitialized = true;
  }

  @override
  Future<TTSOutput> synthesize(TTSInput input) async {
    if (!isReady) {
      throw Exception('TTS service not ready');
    }

    _isSynthesizing = true;

    try {
      final result = _backend.synthesize(
        input.text,
        voiceId: input.voiceId,
        speed: input.rate,
        pitch: input.pitch - 1.0, // Convert from 0.5-2.0 range to -0.5-1.0
      );

      final samples = result['samples'] as Float32List;
      final sampleRate = result['sampleRate'] as int;

      // Convert Float32 samples to PCM16 bytes
      final audioData = _convertToPCM16(samples);

      return TTSOutput(
        audioData: audioData,
        format: 'pcm',
        sampleRate: sampleRate,
      );
    } finally {
      _isSynthesizing = false;
    }
  }

  @override
  Future<void> cleanup() async {
    if (_backend.isTtsModelLoaded) {
      _backend.unloadTtsModel();
    }
    _isInitialized = false;
    _voices = [];
  }

  // ============================================================================
  // Private Helpers
  // ============================================================================

  List<int> _convertToPCM16(Float32List samples) {
    final pcm16 = Uint8List(samples.length * 2);

    for (var i = 0; i < samples.length; i++) {
      // Clamp to -1.0 to 1.0
      final clamped = samples[i].clamp(-1.0, 1.0);
      // Convert to 16-bit signed integer
      final sample = (clamped * 32767).round();
      // Store as little-endian
      pcm16[i * 2] = sample & 0xFF;
      pcm16[i * 2 + 1] = (sample >> 8) & 0xFF;
    }

    return pcm16;
  }
}
