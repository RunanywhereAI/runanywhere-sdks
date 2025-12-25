import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/core/module_registry.dart';
import 'package:runanywhere/native/native_backend.dart';

/// Native VAD service using ONNX/Sherpa-ONNX backend via FFI (Silero VAD).
///
/// This is the Flutter equivalent of iOS's native VAD implementation.
class NativeVADService implements VADService {
  final NativeBackend _backend;
  bool _isInitialized = false;
  bool _isSpeechActive = false;
  double _energyThreshold = 0.5;
  final int _sampleRate = 16000;
  final double _frameLength = 0.032; // 32ms frames

  void Function(SpeechActivityEvent)? _onSpeechActivity;
  void Function(List<int>)? _onAudioBuffer;

  NativeVADService(this._backend);

  @override
  double get energyThreshold => _energyThreshold;

  @override
  set energyThreshold(double value) => _energyThreshold = value;

  @override
  int get sampleRate => _sampleRate;

  @override
  double get frameLength => _frameLength;

  @override
  bool get isSpeechActive => _isSpeechActive;

  @override
  bool get isReady => _isInitialized && _backend.isVadModelLoaded;

  @override
  void Function(SpeechActivityEvent)? get onSpeechActivity => _onSpeechActivity;

  @override
  set onSpeechActivity(void Function(SpeechActivityEvent)? callback) {
    _onSpeechActivity = callback;
  }

  @override
  void Function(List<int>)? get onAudioBuffer => _onAudioBuffer;

  @override
  set onAudioBuffer(void Function(List<int>)? callback) {
    _onAudioBuffer = callback;
  }

  @override
  Future<void> initialize({String? modelPath}) async {
    _backend.loadVadModel(
      modelPath,
      config: {'threshold': _energyThreshold},
    );

    _isInitialized = true;
  }

  @override
  Future<VADResult> detect({required List<int> audioData}) async {
    // Convert PCM16 to Float32
    final samples = _convertToFloat32(audioData);

    final result = _backend.processVad(samples, sampleRate: _sampleRate);

    final hasSpeech = result['isSpeech'] as bool;
    final confidence = result['probability'] as double;

    // Update speech state and emit events
    if (hasSpeech && !_isSpeechActive) {
      _isSpeechActive = true;
      _onSpeechActivity?.call(SpeechActivityEvent.started);
    } else if (!hasSpeech && _isSpeechActive) {
      _isSpeechActive = false;
      _onSpeechActivity?.call(SpeechActivityEvent.ended);
    }

    return VADResult(hasSpeech: hasSpeech, confidence: confidence);
  }

  @override
  void start() {
    // No-op for native VAD - it processes on demand
  }

  @override
  void stop() {
    _isSpeechActive = false;
  }

  @override
  void reset() {
    _backend.resetVad();
    _isSpeechActive = false;
  }

  @override
  void processAudioBuffer(List<int> buffer) {
    // Convert and process
    final samples = _convertToFloat32(buffer);
    final result = _backend.processVad(samples, sampleRate: _sampleRate);

    final hasSpeech = result['isSpeech'] as bool;

    if (hasSpeech && !_isSpeechActive) {
      _isSpeechActive = true;
      _onSpeechActivity?.call(SpeechActivityEvent.started);
    } else if (!hasSpeech && _isSpeechActive) {
      _isSpeechActive = false;
      _onSpeechActivity?.call(SpeechActivityEvent.ended);
    }

    _onAudioBuffer?.call(buffer);
  }

  @override
  bool processAudioData(List<double> audioData) {
    final samples =
        Float32List.fromList(audioData.map((e) => e.toDouble()).toList());
    final result = _backend.processVad(samples, sampleRate: _sampleRate);

    final hasSpeech = result['isSpeech'] as bool;

    if (hasSpeech && !_isSpeechActive) {
      _isSpeechActive = true;
      _onSpeechActivity?.call(SpeechActivityEvent.started);
    } else if (!hasSpeech && _isSpeechActive) {
      _isSpeechActive = false;
      _onSpeechActivity?.call(SpeechActivityEvent.ended);
    }

    return hasSpeech;
  }

  @override
  void pause() {
    // No-op for native VAD
  }

  @override
  void resume() {
    // No-op for native VAD
  }

  @override
  Future<void> cleanup() async {
    if (_backend.isVadModelLoaded) {
      _backend.unloadVadModel();
    }
    _isInitialized = false;
    _isSpeechActive = false;
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
}

/// Provider for native VAD service.
class NativeVADServiceProvider implements VADServiceProvider {
  final NativeBackend _backend;

  NativeVADServiceProvider(this._backend);

  @override
  String get name => 'NativeSileroVAD';

  @override
  bool canHandle({String? modelId}) {
    if (modelId == null) return true;

    final lower = modelId.toLowerCase();
    return lower.contains('silero') ||
        lower.contains('vad') ||
        lower.endsWith('.onnx');
  }

  @override
  Future<VADService> createVADService(dynamic configuration) async {
    final service = NativeVADService(_backend);

    String? modelPath;
    double threshold = 0.5;

    if (configuration is Map) {
      modelPath = configuration['modelPath'] as String?;
      threshold = (configuration['threshold'] as num?)?.toDouble() ?? 0.5;
    } else if (configuration is String) {
      modelPath = configuration;
    }

    service.energyThreshold = threshold;
    await service.initialize(modelPath: modelPath);
    return service;
  }
}
