import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/core/models/audio_format.dart';
import 'package:runanywhere/core/module_registry.dart';
import 'package:runanywhere/features/tts/models/tts_configuration.dart';
import 'package:runanywhere/features/tts/models/tts_input.dart';
import 'package:runanywhere/features/tts/tts_output.dart';
import 'package:runanywhere/native/native_backend.dart';

/// Native TTS service using ONNX/Sherpa-ONNX backend via FFI (Piper/VITS models).
///
/// This is the Flutter equivalent of iOS's ONNXTTSService.
class NativeTTSService implements TTSService {
  final NativeBackend _backend;
  String? _modelPath;
  bool _isInitialized = false;
  bool _isSynthesizing = false;
  TTSConfiguration? _configuration;
  List<TTSVoice> _voices = [];

  NativeTTSService(this._backend);

  /// ONNX Runtime inference framework
  /// Matches iOS ONNXTTSService.inferenceFramework
  @override
  String get inferenceFramework => 'onnx';

  @override
  bool get isReady => _isInitialized && _backend.isTtsModelLoaded;

  @override
  bool get isSynthesizing => _isSynthesizing;

  @override
  List<String> get availableVoices => _voices.map((v) => v.id).toList();

  /// Initialize with a model path (convenience method)
  Future<void> initializeWithPath(String modelPath) async {
    _modelPath = modelPath;

    // Load TTS model (VITS/Piper type)
    // This is synchronous and will throw if it fails
    _backend.loadTtsModel(
      modelPath,
      modelType: 'vits',
    );

    // Verify the model loaded successfully
    if (!_backend.isTtsModelLoaded) {
      throw Exception('TTS model failed to load - model not marked as loaded');
    }

    // Get available voices
    final voiceStrings = _backend.getTtsVoices();
    _voices = voiceStrings
        .map((voiceId) => TTSVoice(
              id: voiceId,
              name: voiceId,
              language: 'en-US',
            ))
        .toList();

    _isInitialized = true;
  }

  @override
  Future<void> initialize(TTSConfiguration configuration) async {
    _configuration = configuration;

    if (configuration.modelId != null && configuration.modelId!.isNotEmpty) {
      await initializeWithPath(configuration.modelId!);
    } else if (_modelPath != null) {
      await initializeWithPath(_modelPath!);
    }

    _isInitialized = true;
  }

  @override
  Future<TTSOutput> synthesize(TTSInput input) async {
    if (!isReady) {
      throw Exception('TTS service not initialized');
    }

    _isSynthesizing = true;
    final startTime = DateTime.now();
    final text = input.ssml ?? input.text ?? '';
    final voice = input.voiceId ?? _configuration?.voice ?? 'default';
    final rate = _configuration?.speakingRate ?? 1.0;
    final pitch = _configuration?.pitch ?? 1.0;

    try {
      final result = _backend.synthesize(
        text,
        voiceId: voice,
        speed: rate,
        pitch: pitch - 1.0, // Convert 0-2 range to semitones
      );

      final samples = result['samples'] as Float32List;
      final sampleRate = result['sampleRate'] as int;

      // Convert Float32 to PCM16 bytes
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
    } finally {
      _isSynthesizing = false;
    }
  }

  @override
  Stream<Uint8List> synthesizeStream(TTSInput input) async* {
    // For now, synthesize full and emit as single chunk
    // VITS/Piper doesn't natively support streaming
    final output = await synthesize(input);
    yield output.audioData;
  }

  @override
  Future<void> stop() async {
    _isSynthesizing = false;
    _backend.cancelTts();
  }

  @override
  Future<List<TTSVoice>> getAvailableVoices() async {
    return _voices;
  }

  @override
  Future<void> cleanup() async {
    if (_backend.isTtsModelLoaded) {
      _backend.unloadTtsModel();
    }
    _isInitialized = false;
    _isSynthesizing = false;
  }

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

/// Provider for native TTS service.
///
/// This is the Flutter equivalent of iOS's ONNXTTSServiceProvider.
class NativeTTSServiceProvider implements TTSServiceProvider {
  final NativeBackend _backend;

  NativeTTSServiceProvider(this._backend);

  @override
  String get name => 'NativePiper';

  @override
  String get version => '1.0.0';

  @override
  bool canHandle({String? modelId}) {
    if (modelId == null) return true;

    final lower = modelId.toLowerCase();
    // Handle Piper/VITS TTS models
    return lower.contains('piper') ||
        lower.contains('vits') ||
        (lower.contains('tts') && lower.contains('onnx'));
  }

  @override
  Future<TTSService> createTTSService(dynamic configuration) async {
    final service = NativeTTSService(_backend);

    String? modelPath;
    if (configuration is Map) {
      modelPath = configuration['modelPath'] as String?;
    } else if (configuration is String) {
      modelPath = configuration;
    }

    if (modelPath != null) {
      await service.initializeWithPath(modelPath);
    }

    return service;
  }
}
