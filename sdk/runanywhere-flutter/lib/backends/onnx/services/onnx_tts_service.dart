import 'package:flutter/foundation.dart';

import '../../../features/tts/protocol/tts_service.dart' as component_tts;
import '../../../core/module_registry.dart' show TTSOptions;
import '../../../native/native_backend.dart';

/// ONNX-based Text-to-Speech service.
///
/// This is the Flutter equivalent of Swift's `ONNXTTSService`.
/// It uses the native runanywhere-core library for speech synthesis.
///
/// ## Usage
///
/// ```dart
/// final backend = NativeBackend();
/// backend.create('onnx');
///
/// final tts = OnnxTTSService(backend);
/// await tts.initialize(modelPath: '/path/to/model');
///
/// final audio = await tts.synthesize(
///   text: 'Hello, world!',
///   options: TTSOptions(voice: 'default'),
/// );
/// ```
class OnnxTTSService implements component_tts.TTSService {
  final NativeBackend _backend;
  bool _isInitialized = false;
  bool _isSynthesizing = false;
  List<String> _voices = [];

  /// Create a new ONNX TTS service.
  OnnxTTSService(this._backend);

  @override
  Future<void> initialize({String? modelPath}) async {
    debugPrint('[ONNXTTS] initialize() called with modelPath: $modelPath');
    debugPrint(
        '[ONNXTTS] Current state - isInitialized: $_isInitialized, modelLoaded: ${_backend.isTtsModelLoaded}');

    if (modelPath == null || modelPath.isEmpty) {
      debugPrint(
          '[ONNXTTS] WARNING: No model path provided, skipping model load');
      if (!_backend.isTtsModelLoaded) {
        debugPrint(
            '[ONNXTTS] ERROR: initialize() called without modelPath and no model is loaded!');
      }
      _isInitialized = true;
      return;
    }

    try {
      debugPrint('[ONNXTTS] Loading model from: $modelPath');

      // Load the TTS model through native backend
      // This is synchronous and will throw if it fails
      _backend.loadTtsModel(
        modelPath,
        modelType: 'vits',
      );

      debugPrint('[ONNXTTS] loadTtsModel() completed, checking status...');

      // Verify the model loaded successfully
      if (!_backend.isTtsModelLoaded) {
        const error =
            'TTS model failed to load - backend reports model not loaded';
        debugPrint('[ONNXTTS] ERROR: $error');
        throw Exception(error);
      }

      debugPrint('[ONNXTTS] Model verified as loaded, getting voices...');

      // Get available voices
      _voices = _backend.getTtsVoices();

      debugPrint('[ONNXTTS] Found ${_voices.length} voices: $_voices');
    } catch (e, stackTrace) {
      debugPrint('[ONNXTTS] ERROR during initialization: $e');
      debugPrint('[ONNXTTS] Stack trace: $stackTrace');
      _isInitialized = false;
      rethrow;
    }

    _isInitialized = true;
    debugPrint(
        '[ONNXTTS] Initialization complete. isReady: $isReady (isInitialized: $_isInitialized, modelLoaded: ${_backend.isTtsModelLoaded})');
  }

  /// Check if TTS is ready.
  bool get isReady => _isInitialized && _backend.isTtsModelLoaded;

  @override
  bool get isSynthesizing => _isSynthesizing;

  @override
  List<String> get availableVoices => _voices;

  /// Whether streaming synthesis is supported.
  bool get supportsStreaming => _backend.ttsSupportsStreaming;

  @override
  Future<Uint8List> synthesize({
    required String text,
    required TTSOptions options,
  }) async {
    if (!isReady) {
      throw Exception(
          'TTS service not ready. isInitialized: $_isInitialized, modelLoaded: ${_backend.isTtsModelLoaded}');
    }

    _isSynthesizing = true;

    try {
      debugPrint(
          '[ONNXTTS] Synthesizing text: "${text.substring(0, text.length > 50 ? 50 : text.length)}..."');
      debugPrint(
          '[ONNXTTS] Voice: ${options.voice}, Rate: ${options.rate}, Pitch: ${options.pitch}');

      final result = _backend.synthesize(
        text,
        voiceId: options.voice,
        speed: options.rate,
        pitch: options.pitch - 1.0, // Convert from 0.5-2.0 range to -0.5-1.0
      );

      final samples = result['samples'] as Float32List;
      final sampleRate = result['sampleRate'] as int;

      debugPrint(
          '[ONNXTTS] Synthesis successful. Samples: ${samples.length}, Rate: $sampleRate');

      // Convert Float32 samples to PCM16 bytes
      return Uint8List.fromList(_convertToPCM16(samples, sampleRate));
    } finally {
      _isSynthesizing = false;
    }
  }

  @override
  Future<void> synthesizeStream({
    required String text,
    required TTSOptions options,
    required void Function(Uint8List chunk) onChunk,
  }) async {
    // For now, use batch synthesis and emit as single chunk
    // TODO: Implement true streaming when supported by native backend
    final audio = await synthesize(text: text, options: options);
    onChunk(audio);
  }

  @override
  void stop() {
    _backend.cancelTts();
    _isSynthesizing = false;
  }

  @override
  Future<void> cleanup() async {
    stop();
    if (_backend.isTtsModelLoaded) {
      _backend.unloadTtsModel();
    }
    _isInitialized = false;
    _voices = [];
  }

  // ============================================================================
  // Private Helpers
  // ============================================================================

  List<int> _convertToPCM16(Float32List samples, int sampleRate) {
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
