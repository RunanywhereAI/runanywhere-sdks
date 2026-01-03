import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:runanywhere/core/models/audio_format.dart';
import 'package:runanywhere/features/tts/models/tts_configuration.dart';
import 'package:runanywhere/features/tts/models/tts_input.dart';
import 'package:runanywhere/features/tts/protocol/tts_service.dart';
import 'package:runanywhere/features/tts/tts_output.dart';
import 'package:runanywhere/native/native_backend.dart';

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
/// final config = TTSConfiguration(modelId: 'tts-model');
/// await tts.initialize(config);
///
/// final input = TTSInput.plainText('Hello, world!');
/// final output = await tts.synthesize(input);
/// ```
class OnnxTTSService implements TTSService {
  final NativeBackend _backend;
  bool _isInitialized = false;
  bool _isSynthesizing = false;
  List<TTSVoice> _voices = [];
  TTSConfiguration? _configuration;

  /// Create a new ONNX TTS service.
  OnnxTTSService(this._backend);

  @override
  String get inferenceFramework => 'onnx';

  @override
  bool get isReady => _isInitialized && _backend.isTtsModelLoaded;

  @override
  bool get isSynthesizing => _isSynthesizing;

  @override
  List<String> get availableVoices => _voices.map((v) => v.id).toList();

  @override
  Future<void> initialize(TTSConfiguration configuration) async {
    _configuration = configuration;
    final modelPath = configuration.modelId;
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
      final voiceStrings = _backend.getTtsVoices();
      _voices = voiceStrings
          .map((voiceId) => TTSVoice(
                id: voiceId,
                name: voiceId,
                language:
                    'en-US', // Default language, could be parsed from voice ID
              ))
          .toList();

      debugPrint('[ONNXTTS] Found ${_voices.length} voices: $voiceStrings');
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

  @override
  Future<TTSOutput> synthesize(TTSInput input) async {
    if (!isReady) {
      throw Exception(
          'TTS service not ready. isInitialized: $_isInitialized, modelLoaded: ${_backend.isTtsModelLoaded}');
    }

    _isSynthesizing = true;
    final startTime = DateTime.now();
    final text = input.ssml ?? input.text ?? '';
    final voice = input.voiceId ?? _configuration?.voice ?? 'default';
    final rate = _configuration?.speakingRate ?? 1.0;
    final pitch = _configuration?.pitch ?? 1.0;

    try {
      debugPrint(
          '[ONNXTTS] Synthesizing text: "${text.substring(0, text.length > 50 ? 50 : text.length)}..."');
      debugPrint('[ONNXTTS] Voice: $voice, Rate: $rate, Pitch: $pitch');

      final result = _backend.synthesize(
        text,
        voiceId: voice,
        speed: rate,
        pitch: pitch - 1.0, // Convert from 0.5-2.0 range to -0.5-1.0
      );

      final samples = result['samples'] as Float32List;
      final sampleRate = result['sampleRate'] as int;

      debugPrint(
          '[ONNXTTS] Synthesis successful. Samples: ${samples.length}, Rate: $sampleRate');

      // Convert Float32 samples to PCM16 bytes
      final audioData =
          Uint8List.fromList(_convertToPCM16(samples, sampleRate));
      final processingTime =
          DateTime.now().difference(startTime).inMilliseconds / 1000.0;
      final duration = samples.length / sampleRate;

      return TTSOutput(
        audioData: audioData,
        format: _configuration?.audioFormat ?? AudioFormat.pcm,
        duration: duration,
        metadata: SynthesisMetadata(
          voice: voice,
          language: input.language ?? _configuration?.language ?? 'en-US',
          processingTime: processingTime,
          characterCount: text.length,
        ),
      );
    } catch (e) {
      debugPrint('[ONNXTTS] ERROR during synthesis: $e');
      rethrow;
    } finally {
      _isSynthesizing = false;
    }
  }

  @override
  Stream<Uint8List> synthesizeStream(TTSInput input) async* {
    // For now, use batch synthesis and emit as single chunk
    // TODO: Implement true streaming when supported by native backend
    final output = await synthesize(input);
    yield output.audioData;
  }

  @override
  Future<List<TTSVoice>> getAvailableVoices() async {
    return _voices;
  }

  @override
  Future<void> stop() async {
    // Cancel any ongoing synthesis via the native backend
    _backend.cancelTts();
  }

  @override
  Future<void> cleanup() async {
    if (_backend.isTtsModelLoaded) {
      _backend.cancelTts();
      _backend.unloadTtsModel();
    }
    _isInitialized = false;
    _voices = [];
    _configuration = null;
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
