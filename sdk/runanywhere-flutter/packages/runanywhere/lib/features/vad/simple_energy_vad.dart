/// Simple Energy VAD
///
/// Simple energy-based Voice Activity Detection.
/// Based on iOS WhisperKit's EnergyVAD implementation.
library simple_energy_vad;

import 'dart:async';
import 'dart:math' as math;

import 'package:runanywhere/core/module_registry.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';

/// Speech activity events
enum SpeechActivityEvent {
  started,
  ended,
}

/// Simple energy-based Voice Activity Detection
/// Based on iOS WhisperKit's EnergyVAD implementation but simplified for real-time audio processing
class SimpleEnergyVAD implements VADService {
  final SDKLogger _logger = SDKLogger('SimpleEnergyVAD');

  /// Energy threshold for voice activity detection (0.0 to 1.0)
  double energyThreshold = 0.005;

  /// Base threshold before any adjustments
  double _baseEnergyThreshold = 0.005;

  /// Multiplier applied during TTS playback to prevent feedback
  double _ttsThresholdMultiplier = 3.0;

  /// Sample rate of the audio (typically 16000 Hz)
  final int sampleRate;

  /// Length of each analysis frame in samples
  final int frameLengthSamples;

  /// Frame length in seconds
  double get frameLength => frameLengthSamples / sampleRate;

  /// Speech activity callback
  void Function(SpeechActivityEvent)? onSpeechActivity;

  /// Optional callback for processed audio buffers
  void Function(List<int>)? onAudioBuffer;

  // State tracking
  bool _isActive = false;
  bool _isCurrentlySpeaking = false;
  int _consecutiveSilentFrames = 0;
  int _consecutiveVoiceFrames = 0;
  bool _isPaused = false;
  bool _isTTSActive = false;

  // Hysteresis parameters
  final int _voiceStartThreshold = 1;
  final int _voiceEndThreshold = 8;
  final int _ttsVoiceStartThreshold = 10;
  final int _ttsVoiceEndThreshold = 5;

  // Calibration properties
  bool _isCalibrating = false;
  final List<double> _calibrationSamples = [];
  int _calibrationFrameCount = 0;
  final int _calibrationFramesNeeded = 20;
  double _ambientNoiseLevel = 0.0;
  double _calibrationMultiplier = 2.5;

  // Debug statistics
  final List<double> _recentEnergyValues = [];
  final int _maxRecentValues = 50;
  int _debugFrameCount = 0;
  double _lastEnergyLevel = 0.0;

  /// Initialize the VAD with specified parameters
  SimpleEnergyVAD({
    this.sampleRate = 16000,
    double frameLength = 0.1,
    this.energyThreshold = 0.005,
  }) : frameLengthSamples = (frameLength * sampleRate).toInt() {
    _logger.info(
      'SimpleEnergyVAD initialized - sampleRate: $sampleRate, frameLength: $frameLengthSamples samples, threshold: $energyThreshold',
    );
  }

  @override
  Future<void> initialize({String? modelPath}) async {
    start();
    await startCalibration();
  }

  @override
  bool get isReady => _isActive;

  @override
  Future<VADResult> process(List<int> audioData) async {
    processAudioBuffer(audioData);
    final confidence = _calculateConfidence(_lastEnergyLevel);
    return VADResult(
      isSpeech: _isCurrentlySpeaking,
      confidence: confidence,
    );
  }

  @override
  Future<void> cleanup() async {
    stop();
    _recentEnergyValues.clear();
    _calibrationSamples.clear();
  }

  /// Current speech activity state
  bool get isSpeechActive => _isCurrentlySpeaking;

  /// Reset the VAD state
  void reset() {
    stop();
    _isCurrentlySpeaking = false;
    _consecutiveSilentFrames = 0;
    _consecutiveVoiceFrames = 0;
  }

  /// Start voice activity detection
  void start() {
    if (_isActive) return;

    _isActive = true;
    _isCurrentlySpeaking = false;
    _consecutiveSilentFrames = 0;
    _consecutiveVoiceFrames = 0;

    _logger.info('SimpleEnergyVAD started');
  }

  /// Stop voice activity detection
  void stop() {
    if (!_isActive) return;

    if (_isCurrentlySpeaking) {
      _isCurrentlySpeaking = false;
      _logger.info('🎙️ VAD: SPEECH ENDED (stopped)');
      onSpeechActivity?.call(SpeechActivityEvent.ended);
    }

    _isActive = false;
    _consecutiveSilentFrames = 0;
    _consecutiveVoiceFrames = 0;

    _logger.info('SimpleEnergyVAD stopped');
  }

  /// Process an audio buffer for voice activity detection
  void processAudioBuffer(List<int> buffer) {
    if (!_isActive) return;
    if (_isTTSActive) return;
    if (_isPaused) return;
    if (buffer.isEmpty) return;

    final audioData = _convertPCMToFloat(buffer);
    final energy = _calculateAverageEnergy(audioData);
    _lastEnergyLevel = energy;

    _updateDebugStatistics(energy);

    if (_isCalibrating) {
      _handleCalibrationFrame(energy);
      return;
    }

    final hasVoice = energy > energyThreshold;

    if (_debugFrameCount % 10 == 0) {
      final avgRecent = _recentEnergyValues.isEmpty
          ? 0.0
          : _recentEnergyValues.reduce((a, b) => a + b) /
              _recentEnergyValues.length;
      final maxRecent = _recentEnergyValues.isEmpty
          ? 0.0
          : _recentEnergyValues.reduce(math.max);

      _logger.info(
        '📊 VAD Stats - Current: ${energy.toStringAsFixed(6)} | '
        'Threshold: ${energyThreshold.toStringAsFixed(6)} | '
        'Voice: ${hasVoice ? "✅" : "❌"} | '
        'Avg: ${avgRecent.toStringAsFixed(6)} | '
        'Max: ${maxRecent.toStringAsFixed(6)}',
      );
    }
    _debugFrameCount++;

    _updateVoiceActivityState(hasVoice);
    onAudioBuffer?.call(buffer);
  }

  /// Calculate the RMS energy of an audio signal
  double _calculateAverageEnergy(List<double> signal) {
    if (signal.isEmpty) return 0.0;

    double sumSquares = 0.0;
    for (final sample in signal) {
      sumSquares += sample * sample;
    }

    return math.sqrt(sumSquares / signal.length);
  }

  /// Calculate confidence value (0.0 to 1.0)
  double _calculateConfidence(double energyLevel) {
    if (energyThreshold == 0.0) return 0.0;

    final ratio = energyLevel / energyThreshold;

    if (ratio < 0.5) {
      return ratio * 0.6;
    } else if (ratio < 2.0) {
      return 0.3 + (ratio - 0.5) * 0.267;
    } else {
      final normalized = math.min((ratio - 2.0) / 3.0, 1.0);
      return 0.7 + normalized * 0.3;
    }
  }

  /// Update voice activity state with hysteresis
  void _updateVoiceActivityState(bool hasVoice) {
    final startThreshold =
        _isTTSActive ? _ttsVoiceStartThreshold : _voiceStartThreshold;
    final endThreshold =
        _isTTSActive ? _ttsVoiceEndThreshold : _voiceEndThreshold;

    if (hasVoice) {
      _consecutiveVoiceFrames++;
      _consecutiveSilentFrames = 0;

      if (!_isCurrentlySpeaking && _consecutiveVoiceFrames >= startThreshold) {
        if (_isTTSActive) {
          _logger.warning('⚠️ Voice detected during TTS - ignoring.');
          return;
        }

        _isCurrentlySpeaking = true;
        _logger.info('🎙️ VAD: SPEECH STARTED');
        onSpeechActivity?.call(SpeechActivityEvent.started);
      }
    } else {
      _consecutiveSilentFrames++;
      _consecutiveVoiceFrames = 0;

      if (_isCurrentlySpeaking && _consecutiveSilentFrames >= endThreshold) {
        _isCurrentlySpeaking = false;
        _logger.info('🎙️ VAD: SPEECH ENDED');
        onSpeechActivity?.call(SpeechActivityEvent.ended);
      }
    }
  }

  /// Convert 16-bit PCM samples to Float32
  List<double> _convertPCMToFloat(List<int> pcmSamples) {
    final floatSamples = <double>[];
    for (final sample in pcmSamples) {
      floatSamples.add(sample / 32768.0);
    }
    return floatSamples;
  }

  /// Start automatic calibration
  Future<void> startCalibration() async {
    _logger.info('🎯 Starting VAD calibration...');

    _isCalibrating = true;
    _calibrationSamples.clear();
    _calibrationFrameCount = 0;

    final timeoutSeconds = _calibrationFramesNeeded * frameLength + 2.0;
    await Future<void>.delayed(
        Duration(milliseconds: (timeoutSeconds * 1000).toInt()));

    if (_isCalibrating) {
      _completeCalibration();
    }
  }

  void _handleCalibrationFrame(double energy) {
    if (!_isCalibrating) return;

    _calibrationSamples.add(energy);
    _calibrationFrameCount++;

    if (_calibrationFrameCount >= _calibrationFramesNeeded) {
      _completeCalibration();
    }
  }

  void _completeCalibration() {
    if (!_isCalibrating || _calibrationSamples.isEmpty) return;

    final sortedSamples = List<double>.from(_calibrationSamples)..sort();
    final percentile90 = sortedSamples[math.min(
        sortedSamples.length - 1, (sortedSamples.length * 0.90).toInt())];

    _ambientNoiseLevel = percentile90;

    final oldThreshold = energyThreshold;
    final minimumThreshold = math.max(_ambientNoiseLevel * 2.5, 0.006);
    final calculatedThreshold = _ambientNoiseLevel * _calibrationMultiplier;

    energyThreshold = math.max(calculatedThreshold, minimumThreshold);

    if (energyThreshold > 0.020) {
      energyThreshold = 0.020;
    }

    _logger.info(
      '✅ VAD Calibration Complete: ${oldThreshold.toStringAsFixed(6)} → ${energyThreshold.toStringAsFixed(6)}',
    );

    _isCalibrating = false;
    _calibrationSamples.clear();
  }

  /// Pause VAD processing
  void pause() {
    if (_isPaused) return;
    _isPaused = true;
    _logger.info('⏸️ VAD paused');

    if (_isCurrentlySpeaking) {
      _isCurrentlySpeaking = false;
      onSpeechActivity?.call(SpeechActivityEvent.ended);
    }

    _recentEnergyValues.clear();
    _consecutiveSilentFrames = 0;
    _consecutiveVoiceFrames = 0;
  }

  /// Resume VAD processing
  void resume() {
    if (!_isPaused) return;

    _isPaused = false;
    _isCurrentlySpeaking = false;
    _consecutiveSilentFrames = 0;
    _consecutiveVoiceFrames = 0;
    _recentEnergyValues.clear();
    _debugFrameCount = 0;

    _logger.info('▶️ VAD resumed');
  }

  /// Notify VAD that TTS is about to start
  void notifyTTSWillStart() {
    _isTTSActive = true;
    _baseEnergyThreshold = energyThreshold;

    final newThreshold = energyThreshold * _ttsThresholdMultiplier;
    energyThreshold = math.min(newThreshold, 0.1);

    _logger.info('🔊 TTS starting - VAD blocked');

    if (_isCurrentlySpeaking) {
      _isCurrentlySpeaking = false;
      onSpeechActivity?.call(SpeechActivityEvent.ended);
    }

    _consecutiveSilentFrames = 0;
    _consecutiveVoiceFrames = 0;
  }

  /// Notify VAD that TTS has finished
  void notifyTTSDidFinish() {
    _isTTSActive = false;
    energyThreshold = _baseEnergyThreshold;

    _logger.info('🔇 TTS finished - VAD restored');

    _recentEnergyValues.clear();
    _consecutiveSilentFrames = 0;
    _consecutiveVoiceFrames = 0;
    _isCurrentlySpeaking = false;
    _debugFrameCount = 0;
  }

  void _updateDebugStatistics(double energy) {
    _recentEnergyValues.add(energy);
    if (_recentEnergyValues.length > _maxRecentValues) {
      _recentEnergyValues.removeAt(0);
    }
  }
}
