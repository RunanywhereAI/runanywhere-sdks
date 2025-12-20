import 'dart:async';
import '../../core/capabilities_base/base_capability.dart';
import '../../core/types/sdk_component.dart';
import '../../core/module_registry.dart';
import 'vad_configuration.dart';
import 'simple_energy_vad.dart';

/// Voice Activity Detection capability following the clean architecture
/// Matches iOS VADCapability from VADCapability.swift
class VADCapability extends BaseCapability<VADService> {
  @override
  SDKComponent get componentType => SDKComponent.vad;

  final VADConfiguration vadConfiguration;

  VADCapability({
    required this.vadConfiguration,
    super.serviceContainer,
  }) : super(configuration: vadConfiguration);

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

  /// Pause VAD processing
  void pause() {
    final vadService = service;
    if (vadService is SimpleEnergyVAD) {
      vadService.pause();
    }
  }

  /// Resume VAD processing
  void resume() {
    final vadService = service;
    if (vadService is SimpleEnergyVAD) {
      vadService.resume();
    }
  }

  /// Detect speech in audio buffer (16-bit PCM samples)
  Future<VADResult> detectSpeech({required List<int> buffer}) async {
    ensureReady();

    final vadService = service;
    if (vadService == null) {
      throw StateError('VAD service not available');
    }

    // Process using the VADService interface
    return await vadService.detect(audioData: buffer);
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
    return await vadService.detect(audioData: pcmSamples);
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

  /// Start VAD processing
  void start() {
    final vadService = service;
    if (vadService is SimpleEnergyVAD) {
      vadService.start();
    }
  }

  /// Stop VAD processing
  void stop() {
    final vadService = service;
    if (vadService is SimpleEnergyVAD) {
      vadService.stop();
    }
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
}
