import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/core/module_registry.dart';
import 'package:runanywhere/native/native_backend.dart';

/// Speech activity events
enum SpeechActivityEvent {
  started,
  ended,
}

/// ONNX-based Voice Activity Detection service.
///
/// This is the Flutter equivalent of Swift's Silero VAD implementation.
/// It uses the native runanywhere-core library for speech detection.
///
/// ## Usage
///
/// ```dart
/// final backend = NativeBackend.onnx();
/// final vad = OnnxVADService(backend);
/// await vad.initialize();
///
/// final result = await vad.process(audioData: audioBytes);
/// if (result.isSpeech) {
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

  /// Get the energy threshold
  double get energyThreshold => _energyThreshold;

  /// Set the energy threshold
  set energyThreshold(double value) => _energyThreshold = value;

  /// Get the sample rate
  int get sampleRate => _sampleRate;

  /// Get the frame length in seconds
  double get frameLength => _frameLength;

  /// Whether speech is currently active
  bool get isSpeechActive => _isSpeechActive;

  @override
  bool get isReady => _isInitialized && _backend.isVadModelLoaded;

  /// Get speech activity callback
  void Function(SpeechActivityEvent)? get onSpeechActivity => _onSpeechActivity;

  /// Set speech activity callback
  set onSpeechActivity(void Function(SpeechActivityEvent)? callback) {
    _onSpeechActivity = callback;
  }

  /// Get audio buffer callback
  void Function(List<int>)? get onAudioBuffer => _onAudioBuffer;

  /// Set audio buffer callback
  set onAudioBuffer(void Function(List<int>)? callback) {
    _onAudioBuffer = callback;
  }

  @override
  Future<void> initialize({String? modelPath}) async {
    _backend.loadVadModel(modelPath);
    _isInitialized = true;
  }

  @override
  Future<VADResult> process(List<int> audioData) async {
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
      isSpeech: hasSpeech,
      confidence: confidence,
    );
  }

  /// Start VAD processing
  void start() {
    _isRunning = true;
  }

  /// Stop VAD processing
  void stop() {
    _isRunning = false;
    _isSpeechActive = false;
  }

  /// Reset VAD state
  void reset() {
    _isSpeechActive = false;
  }

  /// Process audio buffer
  void processAudioBuffer(List<int> buffer) {
    if (!_isRunning) return;

    // Forward to audio buffer callback if set
    _onAudioBuffer?.call(buffer);

    // Process for VAD
    unawaited(process(buffer));
  }

  /// Process audio data as float samples
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

  /// Pause VAD processing
  void pause() {
    _isRunning = false;
  }

  /// Resume VAD processing
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
