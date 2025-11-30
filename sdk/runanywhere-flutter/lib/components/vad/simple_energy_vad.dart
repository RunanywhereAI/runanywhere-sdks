import 'dart:async';
import 'dart:math' as math;
import '../../core/module_registry.dart';
import '../../foundation/logging/sdk_logger.dart';

/// Speech activity events
enum SpeechActivityEvent {
  started,
  ended;

  String get value {
    switch (this) {
      case SpeechActivityEvent.started:
        return 'started';
      case SpeechActivityEvent.ended:
        return 'ended';
    }
  }
}

/// Simple energy-based Voice Activity Detection
/// Based on iOS WhisperKit's EnergyVAD implementation but simplified for real-time audio processing
class SimpleEnergyVAD implements VADService {
  final SDKLogger _logger = SDKLogger(category: 'SimpleEnergyVAD');

  /// Energy threshold for voice activity detection (0.0 to 1.0)
  /// Values above this threshold indicate voice activity
  double energyThreshold = 0.005; // Even lower threshold for better short phrase detection

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
  bool _isPaused = false; // Track paused state
  bool _isTTSActive = false; // Track if TTS is currently playing

  // Hysteresis parameters to prevent rapid on/off switching
  final int _voiceStartThreshold = 1; // frames of voice to start - reduced to 1 frame for better short phrase detection
  final int _voiceEndThreshold = 8; // frames of silence to end (0.8 seconds at 100ms frames) - shorter for quicker responsiveness

  // Enhanced hysteresis for TTS mode
  final int _ttsVoiceStartThreshold = 10; // Much more frames needed during TTS to prevent feedback
  final int _ttsVoiceEndThreshold = 5; // Quicker end during TTS

  // Calibration properties
  bool _isCalibrating = false;
  final List<double> _calibrationSamples = [];
  int _calibrationFrameCount = 0;
  final int _calibrationFramesNeeded = 20; // ~2 seconds at 100ms frames
  double _ambientNoiseLevel = 0.0;
  double _calibrationMultiplier = 2.5; // Threshold = ambientNoise * multiplier - higher to reduce false positives

  // Debug statistics
  final List<double> _recentEnergyValues = [];
  final int _maxRecentValues = 50;
  int _debugFrameCount = 0;

  /// Initialize the VAD with specified parameters
  SimpleEnergyVAD({
    this.sampleRate = 16000,
    double frameLength = 0.1,
    double energyThreshold = 0.005,
  })  : frameLengthSamples = (frameLength * sampleRate).toInt(),
        energyThreshold = energyThreshold {
    _logger.info(
      'SimpleEnergyVAD initialized - sampleRate: $sampleRate, frameLength: $frameLengthSamples samples, threshold: $energyThreshold',
    );
  }

  // VADService interface implementation
  @override
  Future<void> initialize({String? modelPath}) async {
    start();
    // Start automatic calibration
    await startCalibration();
  }

  @override
  bool get isReady => _isActive;

  @override
  Future<VADResult> detect({required List<int> audioData}) async {
    processAudioBuffer(audioData);
    return VADResult(
      hasSpeech: _isCurrentlySpeaking,
      confidence: energyThreshold,
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

    // If currently speaking, send end event
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

    // Complete audio blocking during TTS - don't process at all
    if (_isTTSActive) {
      return;
    }

    if (_isPaused) {
      return;
    }

    if (buffer.isEmpty) return;

    // Convert 16-bit PCM samples to Float32
    final audioData = _convertPCMToFloat(buffer);

    // Calculate energy of the entire buffer
    final energy = _calculateAverageEnergy(audioData);

    // Update debug statistics
    _updateDebugStatistics(energy);

    // Handle calibration if active
    if (_isCalibrating) {
      _handleCalibrationFrame(energy);
      return; // Don't process voice activity during calibration
    }

    final hasVoice = energy > energyThreshold;

    // Enhanced logging with more context
    final percentAboveThreshold =
        ((energy - energyThreshold) / energyThreshold) * 100;

    if (_debugFrameCount % 10 == 0) {
      // Log every 10th frame to reduce noise
      final avgRecent = _recentEnergyValues.isEmpty
          ? 0.0
          : _recentEnergyValues.reduce((a, b) => a + b) /
              _recentEnergyValues.length;
      final maxRecent = _recentEnergyValues.isEmpty
          ? 0.0
          : _recentEnergyValues.reduce(math.max);
      final minRecent = _recentEnergyValues.isEmpty
          ? 0.0
          : _recentEnergyValues.reduce(math.min);

      _logger.info(
        '📊 VAD Stats - Current: ${energy.toStringAsFixed(6)} | '
        'Threshold: ${energyThreshold.toStringAsFixed(6)} | '
        'Voice: ${hasVoice ? "✅" : "❌"} | '
        '%Above: ${percentAboveThreshold.toStringAsFixed(1)}% | '
        'Avg: ${avgRecent.toStringAsFixed(6)} | '
        'Range: [${minRecent.toStringAsFixed(6)}-${maxRecent.toStringAsFixed(6)}]',
      );
    }
    _debugFrameCount++;

    // Update state based on voice detection
    _updateVoiceActivityState(hasVoice);

    // Call audio buffer callback if provided
    onAudioBuffer?.call(buffer);
  }

  /// Process a raw audio array for voice activity detection
  bool processAudioData(List<double> audioData) {
    if (!_isActive) return false;

    // Complete audio blocking during TTS - don't process at all
    if (_isTTSActive) {
      return false;
    }

    if (_isPaused) return false;
    if (audioData.isEmpty) return false;

    // Calculate energy
    final energy = _calculateAverageEnergy(audioData);

    // Update debug statistics
    _updateDebugStatistics(energy);

    // Handle calibration if active
    if (_isCalibrating) {
      _handleCalibrationFrame(energy);
      return false; // Don't process voice activity during calibration
    }

    final hasVoice = energy > energyThreshold;

    // Enhanced debug logging
    final ratio = energy / energyThreshold;
    _logger.debug(
      '🎤 VAD: Energy=${energy.toStringAsFixed(6)} | '
      'Threshold=${energyThreshold.toStringAsFixed(6)} | '
      'Ratio=${ratio.toStringAsFixed(2)}x | '
      'Voice=${hasVoice ? "YES✅" : "NO❌"} | '
      'Ambient=${_ambientNoiseLevel.toStringAsFixed(6)}',
    );

    // Update state
    _updateVoiceActivityState(hasVoice);

    return hasVoice;
  }

  /// Calculate the RMS (Root Mean Square) energy of an audio signal
  double _calculateAverageEnergy(List<double> signal) {
    if (signal.isEmpty) return 0.0;

    double sumSquares = 0.0;
    for (final sample in signal) {
      sumSquares += sample * sample;
    }

    return math.sqrt(sumSquares / signal.length);
  }

  /// Update voice activity state with hysteresis to prevent rapid switching
  void _updateVoiceActivityState(bool hasVoice) {
    // Use different thresholds based on TTS state
    final startThreshold =
        _isTTSActive ? _ttsVoiceStartThreshold : _voiceStartThreshold;
    final endThreshold =
        _isTTSActive ? _ttsVoiceEndThreshold : _voiceEndThreshold;

    if (hasVoice) {
      _consecutiveVoiceFrames++;
      _consecutiveSilentFrames = 0;

      // Start speaking if we have enough consecutive voice frames
      if (!_isCurrentlySpeaking &&
          _consecutiveVoiceFrames >= startThreshold) {
        // Extra validation during TTS to prevent false positives
        if (_isTTSActive) {
          _logger.warning(
            '⚠️ Voice detected during TTS playback - likely feedback! Ignoring.',
          );
          return;
        }

        _isCurrentlySpeaking = true;
        _logger.info(
          '🎙️ VAD: SPEECH STARTED (energy above threshold for $_consecutiveVoiceFrames frames)',
        );
        onSpeechActivity?.call(SpeechActivityEvent.started);
      }
    } else {
      _consecutiveSilentFrames++;
      _consecutiveVoiceFrames = 0;

      // Stop speaking if we have enough consecutive silent frames
      if (_isCurrentlySpeaking && _consecutiveSilentFrames >= endThreshold) {
        _isCurrentlySpeaking = false;
        _logger.info(
          '🎙️ VAD: SPEECH ENDED (silence for $_consecutiveSilentFrames frames)',
        );
        onSpeechActivity?.call(SpeechActivityEvent.ended);
      }
    }
  }

  /// Convert 16-bit PCM samples to Float32 (-1.0 to 1.0)
  List<double> _convertPCMToFloat(List<int> pcmSamples) {
    final floatSamples = <double>[];
    for (final sample in pcmSamples) {
      // Convert from 16-bit int (-32768 to 32767) to float (-1.0 to 1.0)
      floatSamples.add(sample / 32768.0);
    }
    return floatSamples;
  }

  // MARK: - Calibration Methods

  /// Start automatic calibration to determine ambient noise level
  Future<void> startCalibration() async {
    _logger.info(
      '🎯 Starting VAD calibration - measuring ambient noise for ${_calibrationFramesNeeded * frameLength} seconds...',
    );

    _isCalibrating = true;
    _calibrationSamples.clear();
    _calibrationFrameCount = 0;

    // Wait for calibration to complete
    final timeoutSeconds = _calibrationFramesNeeded * frameLength + 2.0;
    await Future.delayed(Duration(milliseconds: (timeoutSeconds * 1000).toInt()));

    if (_isCalibrating) {
      // Force complete calibration if still running
      _completeCalibration();
    }
  }

  /// Handle a frame during calibration
  void _handleCalibrationFrame(double energy) {
    if (!_isCalibrating) return;

    _calibrationSamples.add(energy);
    _calibrationFrameCount++;

    _logger.debug(
      '📏 Calibration frame $_calibrationFrameCount/$_calibrationFramesNeeded: energy=${energy.toStringAsFixed(6)}',
    );

    if (_calibrationFrameCount >= _calibrationFramesNeeded) {
      _completeCalibration();
    }
  }

  /// Complete the calibration process
  void _completeCalibration() {
    if (!_isCalibrating || _calibrationSamples.isEmpty) return;

    // Calculate statistics from calibration samples
    final sortedSamples = List<double>.from(_calibrationSamples)..sort();
    final mean =
        _calibrationSamples.reduce((a, b) => a + b) / _calibrationSamples.length;
    final median = sortedSamples[sortedSamples.length ~/ 2];
    final percentile75 = sortedSamples[
        math.min(sortedSamples.length - 1, (sortedSamples.length * 0.75).toInt())];
    final percentile90 = sortedSamples[
        math.min(sortedSamples.length - 1, (sortedSamples.length * 0.90).toInt())];
    final max = sortedSamples.last;

    // Use 90th percentile as ambient noise level (robust to occasional spikes)
    _ambientNoiseLevel = percentile90;

    // Calculate dynamic threshold with better minimum
    final oldThreshold = energyThreshold;
    // Ensure minimum threshold is high enough to avoid false positives
    // but low enough to detect actual speech
    final minimumThreshold =
        math.max(_ambientNoiseLevel * 2.5, 0.006); // At least 2.5x ambient or 0.006
    final calculatedThreshold = _ambientNoiseLevel * _calibrationMultiplier;

    // Apply threshold with sensible bounds
    energyThreshold = math.max(calculatedThreshold, minimumThreshold);

    // Cap at reasonable maximum - balanced for speech detection without false positives
    if (energyThreshold > 0.020) {
      energyThreshold = 0.020;
      _logger.warning(
        '⚠️ Calibration detected high ambient noise. Capping threshold at 0.020',
      );
    }

    _logger.info('✅ VAD Calibration Complete:');
    _logger.info(
      '  📊 Statistics: Mean=${mean.toStringAsFixed(6)}, Median=${median.toStringAsFixed(6)}',
    );
    _logger.info(
      '  📊 Percentiles: 75th=${percentile75.toStringAsFixed(6)}, 90th=${percentile90.toStringAsFixed(6)}, Max=${max.toStringAsFixed(6)}',
    );
    _logger.info(
      '  🎯 Ambient Noise Level: ${_ambientNoiseLevel.toStringAsFixed(6)}',
    );
    _logger.info(
      '  🔧 Threshold: ${oldThreshold.toStringAsFixed(6)} → ${energyThreshold.toStringAsFixed(6)}',
    );

    _isCalibrating = false;
    _calibrationSamples.clear();
  }

  /// Manually set calibration parameters
  void setCalibrationParameters({double multiplier = 2.5}) {
    _calibrationMultiplier =
        math.max(2.0, math.min(4.0, multiplier)); // Clamp between 2.0x and 4.0x
    _logger.info('📝 Calibration multiplier set to ${_calibrationMultiplier}x');
  }

  /// Get current VAD statistics for debugging
  Map<String, double> getStatistics() {
    final recent = _recentEnergyValues.isEmpty
        ? 0.0
        : _recentEnergyValues.reduce((a, b) => a + b) / _recentEnergyValues.length;
    final maxValue =
        _recentEnergyValues.isEmpty ? 0.0 : _recentEnergyValues.reduce(math.max);
    final current = _recentEnergyValues.isEmpty ? 0.0 : _recentEnergyValues.last;

    return {
      'current': current,
      'threshold': energyThreshold,
      'ambient': _ambientNoiseLevel,
      'recentAvg': recent,
      'recentMax': maxValue,
    };
  }

  // MARK: - Pause and Resume

  /// Pause VAD processing
  void pause() {
    if (_isPaused) return;
    _isPaused = true;
    _logger.info('⏸️ VAD paused');

    // If currently speaking, send end event
    if (_isCurrentlySpeaking) {
      _isCurrentlySpeaking = false;
      onSpeechActivity?.call(SpeechActivityEvent.ended);
    }

    // Clear recent energy values to avoid false positives when resuming
    _recentEnergyValues.clear();
    _consecutiveSilentFrames = 0;
    _consecutiveVoiceFrames = 0;
  }

  /// Resume VAD processing
  void resume() {
    if (!_isPaused) return;

    _isPaused = false;

    // Reset state for clean resumption
    _isCurrentlySpeaking = false;
    _consecutiveSilentFrames = 0;
    _consecutiveVoiceFrames = 0;
    // Clear any accumulated energy values to start fresh
    _recentEnergyValues.clear();
    _debugFrameCount = 0;

    _logger.info('▶️ VAD resumed');
  }

  // MARK: - TTS Feedback Prevention

  /// Notify VAD that TTS is about to start playing
  void notifyTTSWillStart() {
    _isTTSActive = true;

    // Save base threshold
    _baseEnergyThreshold = energyThreshold;

    // Increase threshold significantly to prevent TTS audio from triggering VAD
    final newThreshold = energyThreshold * _ttsThresholdMultiplier;
    energyThreshold = math.min(newThreshold, 0.1); // Cap at 0.1 to prevent complete deafness

    _logger.info(
      '🔊 TTS starting - VAD completely blocked and threshold increased from ${_baseEnergyThreshold.toStringAsFixed(6)} to ${energyThreshold.toStringAsFixed(6)}',
    );

    // End any current speech detection
    if (_isCurrentlySpeaking) {
      _isCurrentlySpeaking = false;
      onSpeechActivity?.call(SpeechActivityEvent.ended);
    }

    // Reset counters
    _consecutiveSilentFrames = 0;
    _consecutiveVoiceFrames = 0;
  }

  /// Notify VAD that TTS has finished playing
  void notifyTTSDidFinish() {
    _isTTSActive = false;

    // Immediately restore threshold for instant response
    energyThreshold = _baseEnergyThreshold;

    _logger.info(
      '🔇 TTS finished - VAD threshold restored to ${energyThreshold.toStringAsFixed(6)}',
    );

    // Reset state for immediate readiness
    _recentEnergyValues.clear();
    _consecutiveSilentFrames = 0;
    _consecutiveVoiceFrames = 0;
    _isCurrentlySpeaking = false;

    // Prime the VAD to be ready for immediate detection
    _debugFrameCount = 0;
  }

  /// Set TTS threshold multiplier for feedback prevention
  void setTTSThresholdMultiplier(double multiplier) {
    _ttsThresholdMultiplier = math.max(2.0, math.min(5.0, multiplier));
    _logger.info('📝 TTS threshold multiplier set to ${_ttsThresholdMultiplier}x');
  }

  // MARK: - Debug Helpers

  /// Update debug statistics with new energy value
  void _updateDebugStatistics(double energy) {
    _recentEnergyValues.add(energy);
    if (_recentEnergyValues.length > _maxRecentValues) {
      _recentEnergyValues.removeAt(0);
    }
  }
}
