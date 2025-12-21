import 'dart:async';
import 'dart:typed_data';

import '../../../features/vad/vad_service.dart';
import '../../../native/native_backend.dart';

/// ONNX-based Voice Activity Detection service.
///
/// This is the Flutter equivalent of Swift's Silero VAD implementation.
/// It uses the native runanywhere-core library for speech detection.
///
/// ## Usage
///
/// ```dart
/// final backend = NativeBackend();
/// backend.create('onnx');
///
/// final vad = OnnxVADService(backend);
/// await vad.initialize();
///
/// final result = await vad.detect(audioData: audioBytes);
/// if (result.hasSpeech) {
///   print('Speech detected with confidence: ${result.confidence}');
/// }
/// ```
class OnnxVADService implements VADService {
  final NativeBackend _backend;
  bool _isInitialized = false;
  bool _isSpeechActive = false;
  bool _isRunning = false;

  double _energyThreshold = 0.5;
  final int _sampleRate = 16000;
  final double _frameLength = 0.032; // 32ms frames

  void Function(SpeechActivityEvent)? _onSpeechActivity;
  void Function(List<int>)? _onAudioBuffer;

  /// Create a new ONNX VAD service.
  OnnxVADService(this._backend);

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
    _backend.loadVadModel(modelPath);
    _isInitialized = true;
  }

  @override
  Future<VADResult> detect({required List<int> audioData}) async {
    // Convert PCM16 to Float32
    final samples = _convertToFloat32(audioData);

    final result = _backend.processVad(samples);
    final hasSpeech = result['isSpeech'] as bool? ?? false;
    final confidence = (result['probability'] as num?)?.toDouble() ?? 0.0;

    // Track speech state changes
    if (hasSpeech != _isSpeechActive) {
      _isSpeechActive = hasSpeech;
      if (hasSpeech) {
        _onSpeechActivity?.call(SpeechActivityEvent.started);
      } else {
        _onSpeechActivity?.call(SpeechActivityEvent.ended);
      }
    }

    return VADResult(
      hasSpeech: hasSpeech,
      confidence: confidence,
    );
  }

  @override
  void start() {
    _isRunning = true;
  }

  @override
  void stop() {
    _isRunning = false;
    _isSpeechActive = false;
  }

  @override
  void reset() {
    _backend.resetVad();
    _isSpeechActive = false;
  }

  @override
  void processAudioBuffer(List<int> buffer) {
    if (!_isRunning) return;

    // Forward to audio buffer callback if set
    _onAudioBuffer?.call(buffer);

    // Process for VAD
    detect(audioData: buffer);
  }

  @override
  bool processAudioData(List<double> audioData) {
    if (!_isRunning) return false;

    // Convert double samples to Float32List
    final samples =
        Float32List.fromList(audioData.map((d) => d.toDouble()).toList());

    final result = _backend.processVad(samples);
    final hasSpeech = result['isSpeech'] as bool? ?? false;

    // Track speech state changes
    if (hasSpeech != _isSpeechActive) {
      _isSpeechActive = hasSpeech;
      if (hasSpeech) {
        _onSpeechActivity?.call(SpeechActivityEvent.started);
      } else {
        _onSpeechActivity?.call(SpeechActivityEvent.ended);
      }
    }

    return hasSpeech;
  }

  @override
  void pause() {
    _isRunning = false;
  }

  @override
  void resume() {
    _isRunning = true;
  }

  @override
  Future<void> cleanup() async {
    stop();
    if (_backend.isVadModelLoaded) {
      _backend.unloadVadModel();
    }
    _isInitialized = false;
  }

  // ============================================================================
  // Streaming Methods (additional, not in base protocol)
  // ============================================================================

  /// Create a streaming VAD session.
  Object createStream({Map<String, dynamic>? config}) {
    return _backend.createVadStream(config: config);
  }

  /// Destroy streaming session.
  void destroyStream(Object stream) {
    _backend.destroyVadStream(stream as dynamic);
  }

  // ============================================================================
  // Private Helpers
  // ============================================================================

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
