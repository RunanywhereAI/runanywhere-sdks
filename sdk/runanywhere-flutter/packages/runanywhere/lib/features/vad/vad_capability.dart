import 'dart:async';

import 'package:runanywhere/core/capabilities_base/base_capability.dart';
import 'package:runanywhere/core/module_registry.dart';
import 'package:runanywhere/core/types/sdk_component.dart';
import 'package:runanywhere/features/vad/simple_energy_vad.dart';
import 'package:runanywhere/features/vad/vad_configuration.dart';
import 'package:runanywhere/infrastructure/analytics/services/vad_analytics_service.dart';

/// Voice Activity Detection capability following the clean architecture
/// Matches iOS VADCapability from VADCapability.swift
class VADCapability extends BaseCapability<VADService> {
  @override
  SDKComponent get componentType => SDKComponent.vad;

  final VADConfiguration vadConfiguration;

  /// Analytics service for tracking VAD operations.
  /// Matches iOS VADCapability.analyticsService
  final VADAnalyticsService _analyticsService;

  VADCapability({
    required this.vadConfiguration,
    super.serviceContainer,
    VADAnalyticsService? analyticsService,
  })  : _analyticsService = analyticsService ?? VADAnalyticsService(),
        super(configuration: vadConfiguration);

  /// Whether speech is currently active.
  /// Matches iOS VADCapability.isSpeechActive property.
  bool get isSpeechActive {
    final vadService = service;
    if (vadService is SimpleEnergyVAD) {
      return vadService.isSpeechActive;
    }
    return false;
  }

  /// Current energy threshold.
  /// Matches iOS VADCapability.energyThreshold property.
  double get energyThreshold {
    final vadService = service;
    if (vadService is SimpleEnergyVAD) {
      return vadService.energyThreshold;
    }
    return 0.0;
  }

  @override
  Future<VADService> createService() async {
    // Try to get a registered VAD provider from central registry
    final provider = ModuleRegistry.shared.vadProvider(modelId: null);

    if (provider == null) {
      throw StateError(
        'No VAD service provider registered. Please register a VAD provider using ModuleRegistry.shared.registerVAD()',
      );
    }

    // Create service through provider
    final service = await provider.createVADService(vadConfiguration);
    return service;
  }

  /// Pause VAD processing.
  /// Matches iOS VADCapability.pause() method.
  void pause() {
    final vadService = service;
    if (vadService is SimpleEnergyVAD) {
      vadService.pause();
    }
    _analyticsService.trackPaused();
  }

  /// Resume VAD processing.
  /// Matches iOS VADCapability.resume() method.
  void resume() {
    final vadService = service;
    if (vadService is SimpleEnergyVAD) {
      vadService.resume();
    }
    _analyticsService.trackResumed();
  }

  /// Detect speech in audio buffer (16-bit PCM samples)
  Future<VADResult> detectSpeech({required List<int> buffer}) async {
    ensureReady();

    final vadService = service;
    if (vadService == null) {
      throw StateError('VAD service not available');
    }

    // Process using the VADService interface
    return vadService.detect(audioData: buffer);
  }

  /// Detect speech in audio samples (Float32 format)
  Future<VADResult> detectSpeechFromSamples({
    required List<double> samples,
  }) async {
    ensureReady();

    final vadService = service;
    if (vadService == null) {
      throw StateError('VAD service not available');
    }

    // For SimpleEnergyVAD, use the direct method and get proper confidence
    if (vadService is SimpleEnergyVAD) {
      final isSpeechDetected = vadService.processAudioData(samples);
      // Get statistics to calculate confidence based on current energy level
      final stats = vadService.getStatistics();
      final currentEnergy = stats['current'] ?? 0.0;
      final threshold = stats['threshold'] ?? vadService.energyThreshold;

      // Calculate confidence based on energy level relative to threshold
      final confidence = _calculateConfidence(currentEnergy, threshold);

      return VADResult(
        hasSpeech: isSpeechDetected,
        confidence: confidence,
      );
    }

    // Convert float samples to 16-bit PCM for generic VADService
    final pcmSamples = samples.map((s) => (s * 32768.0).toInt()).toList();
    return vadService.detect(audioData: pcmSamples);
  }

  /// Calculate confidence value between 0.0 and 1.0 based on energy level relative to threshold
  double _calculateConfidence(double energyLevel, double threshold) {
    if (threshold == 0.0) {
      return 0.0;
    }

    // Calculate ratio of energy to threshold
    final ratio = energyLevel / threshold;

    // Map ratio to confidence value (0.0 to 1.0)
    // ratio < 0.5: very confident no speech (maps to ~0.0-0.3)
    // ratio ~ 1.0: uncertain, near threshold (maps to ~0.5)
    // ratio > 2.0: very confident speech present (maps to ~0.7-1.0)

    if (ratio < 0.5) {
      // Far below threshold: high confidence in silence
      // Map [0, 0.5] -> [0.0, 0.3]
      return ratio * 0.6;
    } else if (ratio < 2.0) {
      // Near threshold: uncertain
      // Map [0.5, 2.0] -> [0.3, 0.7]
      return 0.3 + (ratio - 0.5) * 0.267;
    } else {
      // Far above threshold: high confidence in speech
      // Map [2.0, inf] -> [0.7, 1.0] with asymptotic approach to 1.0
      final normalized = (ratio - 2.0) / 3.0;
      return 0.7 + (normalized > 1.0 ? 1.0 : normalized) * 0.3;
    }
  }

  /// Process audio stream
  Stream<VADResult> processAudioStream(Stream<List<int>> stream) async* {
    await for (final buffer in stream) {
      yield await detectSpeech(buffer: buffer);
    }
  }

  /// Reset VAD state
  void reset() {
    final vadService = service;
    if (vadService is SimpleEnergyVAD) {
      vadService.reset();
    }
  }

  /// Set speech activity callback
  void setSpeechActivityCallback(
    void Function(SpeechActivityEvent) callback,
  ) {
    final vadService = service;
    if (vadService is SimpleEnergyVAD) {
      vadService.onSpeechActivity = callback;
    }
  }

  /// Start VAD processing.
  /// Matches iOS VADCapability.start() method.
  void start() {
    final vadService = service;
    if (vadService is SimpleEnergyVAD) {
      vadService.start();
    }
    _analyticsService.trackStarted();
  }

  /// Stop VAD processing.
  /// Matches iOS VADCapability.stop() method.
  void stop() {
    final vadService = service;
    if (vadService is SimpleEnergyVAD) {
      vadService.stop();
    }
    _analyticsService.trackStopped();
  }

  /// Get the underlying VAD service
  VADService? getService() {
    return service;
  }

  /// Start calibration of the VAD
  Future<void> startCalibration() async {
    ensureReady();

    final vadService = service;
    if (vadService is! SimpleEnergyVAD) {
      throw StateError('VAD service does not support calibration');
    }

    // Start calibration
    await vadService.startCalibration();
  }

  /// Get current VAD statistics for debugging
  Map<String, double>? getStatistics() {
    final vadService = service;
    if (vadService is! SimpleEnergyVAD) {
      return null;
    }

    return vadService.getStatistics();
  }

  /// Set calibration parameters
  void setCalibrationParameters({required double multiplier}) {
    final vadService = service;
    if (vadService is! SimpleEnergyVAD) {
      return;
    }

    vadService.setCalibrationParameters(multiplier: multiplier);
  }

  /// Set energy threshold
  void setEnergyThreshold(double threshold) {
    final vadService = service;
    if (vadService is SimpleEnergyVAD) {
      vadService.energyThreshold = threshold;
    }
  }

  /// Get energy threshold
  double? getEnergyThreshold() {
    final vadService = service;
    if (vadService is SimpleEnergyVAD) {
      return vadService.energyThreshold;
    }
    return null;
  }

  // MARK: - TTS Integration

  /// Notify VAD that TTS is about to start (to adjust sensitivity).
  /// Matches iOS VADCapability.notifyTTSWillStart() method.
  void notifyTTSWillStart() {
    final vadService = service;
    if (vadService is SimpleEnergyVAD) {
      vadService.notifyTTSWillStart();
    }
  }

  /// Notify VAD that TTS has finished.
  /// Matches iOS VADCapability.notifyTTSDidFinish() method.
  void notifyTTSDidFinish() {
    final vadService = service;
    if (vadService is SimpleEnergyVAD) {
      vadService.notifyTTSDidFinish();
    }
  }

  // MARK: - Analytics

  /// Get current VAD analytics metrics.
  /// Matches iOS VADCapability.getAnalyticsMetrics().
  VADMetrics getAnalyticsMetrics() {
    return _analyticsService.getMetrics();
  }
}
