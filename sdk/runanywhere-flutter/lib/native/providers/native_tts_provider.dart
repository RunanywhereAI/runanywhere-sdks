import 'dart:async';
import 'dart:typed_data';

import '../../core/module_registry.dart';
import '../native_backend.dart';

/// Native TTS service using ONNX/Sherpa-ONNX backend via FFI (Piper/VITS models).
///
/// This is the Flutter equivalent of iOS's ONNXTTSService.
class NativeTTSService implements TTSService {
  final NativeBackend _backend;
  String? _modelPath;
  bool _isInitialized = false;
  bool _isSynthesizing = false;

  NativeTTSService(this._backend);

  Future<void> initializeWithPath(String modelPath) async {
    _modelPath = modelPath;

    // Load TTS model (VITS/Piper type)
    _backend.loadTtsModel(
      modelPath,
      modelType: 'vits',
    );

    _isInitialized = true;
  }

  @override
  Future<void> initialize() async {
    if (_modelPath != null) {
      await initializeWithPath(_modelPath!);
    }
    _isInitialized = true;
  }

  bool get isReady => _isInitialized && _backend.isTtsModelLoaded;

  @override
  bool get isSynthesizing => _isSynthesizing;

  @override
  List<String> get availableVoices {
    if (!isReady) return [];
    return _backend.getTtsVoices();
  }

  @override
  Future<List<int>> synthesize({
    required String text,
    required TTSOptions options,
  }) async {
    if (!isReady) {
      throw Exception('TTS service not initialized');
    }

    _isSynthesizing = true;

    try {
      final result = _backend.synthesize(
        text,
        voiceId: options.voice,
        speed: options.rate,
        pitch: options.pitch - 1.0, // Convert 0-2 range to semitones
      );

      final samples = result['samples'] as Float32List;
      final sampleRate = result['sampleRate'] as int;

      // Convert Float32 to PCM16 WAV bytes
      return _convertToWav(samples, sampleRate);
    } finally {
      _isSynthesizing = false;
    }
  }

  @override
  Future<void> synthesizeStream({
    required String text,
    required TTSOptions options,
    required void Function(List<int>) onChunk,
  }) async {
    // For now, synthesize full and emit as single chunk
    // VITS/Piper doesn't natively support streaming
    final audio = await synthesize(text: text, options: options);
    onChunk(audio);
  }

  @override
  void stop() {
    _isSynthesizing = false;
    _backend.cancelTts();
  }

  @override
  Future<void> cleanup() async {
    if (_backend.isTtsModelLoaded) {
      _backend.unloadTtsModel();
    }
    _isInitialized = false;
    _isSynthesizing = false;
  }

  List<int> _convertToWav(Float32List samples, int sampleRate) {
    // Convert Float32 to PCM16 WAV bytes
    const bytesPerSample = 2;
    const numChannels = 1;
    final dataSize = samples.length * bytesPerSample;
    final fileSize = 44 + dataSize; // WAV header is 44 bytes

    final buffer = ByteData(fileSize);

    // RIFF header
    buffer.setUint8(0, 0x52); // R
    buffer.setUint8(1, 0x49); // I
    buffer.setUint8(2, 0x46); // F
    buffer.setUint8(3, 0x46); // F
    buffer.setUint32(4, fileSize - 8, Endian.little);
    buffer.setUint8(8, 0x57); // W
    buffer.setUint8(9, 0x41); // A
    buffer.setUint8(10, 0x56); // V
    buffer.setUint8(11, 0x45); // E

    // fmt chunk
    buffer.setUint8(12, 0x66); // f
    buffer.setUint8(13, 0x6D); // m
    buffer.setUint8(14, 0x74); // t
    buffer.setUint8(15, 0x20); // (space)
    buffer.setUint32(16, 16, Endian.little); // Chunk size
    buffer.setUint16(20, 1, Endian.little); // Audio format (PCM)
    buffer.setUint16(22, numChannels, Endian.little); // Channels
    buffer.setUint32(24, sampleRate, Endian.little); // Sample rate
    buffer.setUint32(28, sampleRate * numChannels * bytesPerSample,
        Endian.little); // Byte rate
    buffer.setUint16(
        32, numChannels * bytesPerSample, Endian.little); // Block align
    buffer.setUint16(34, bytesPerSample * 8, Endian.little); // Bits per sample

    // data chunk
    buffer.setUint8(36, 0x64); // d
    buffer.setUint8(37, 0x61); // a
    buffer.setUint8(38, 0x74); // t
    buffer.setUint8(39, 0x61); // a
    buffer.setUint32(40, dataSize, Endian.little);

    // PCM data
    for (var i = 0; i < samples.length; i++) {
      final sample = samples[i];
      final clampedSample = sample.clamp(-1.0, 1.0);
      final int16Sample = (clampedSample * 32767).round().clamp(-32768, 32767);
      buffer.setInt16(44 + i * 2, int16Sample, Endian.little);
    }

    return buffer.buffer.asUint8List();
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
  Future<dynamic> createTTSService(dynamic configuration) async {
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
