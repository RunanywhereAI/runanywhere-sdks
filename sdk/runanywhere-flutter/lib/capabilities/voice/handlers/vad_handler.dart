// ignore_for_file: unused_import
import 'dart:async';

import '../../../components/vad/vad_service.dart';
import '../../../foundation/logging/sdk_logger.dart';
import '../../../components/vad/simple_energy_vad.dart';

/// Configuration for VAD component used by the handler.
class VADConfiguration {
  /// Energy threshold for voice detection
  final double energyThreshold;

  /// Sample rate (default 16000)
  final int sampleRate;

  /// Frame length in seconds (default 0.1)
  final double frameLength;

  const VADConfiguration({
    this.energyThreshold = 0.005,
    this.sampleRate = 16000,
    this.frameLength = 0.1,
  });
}

/// Temporary bridge handler for VAD to work with existing VoicePipelineManager
/// This will be removed once VoicePipelineManager is refactored to use the new component architecture
/// Matches iOS VADHandler from Capabilities/Voice/Handlers/VADHandler.swift
class VADHandler {
  final SDKLogger _logger = SDKLogger(category: 'VADHandler');
  SimpleEnergyVAD? _vadComponent;

  /// Creates a new VAD handler
  VADHandler();

  /// Process audio buffer for VAD
  /// - Parameters:
  ///   - buffer: Audio samples (16-bit PCM or Float32)
  ///   - vadService: Optional VAD service to use directly
  /// - Returns: Whether speech is detected
  Future<bool> processAudioBuffer(
    List<int> buffer, {
    VADService? vadService,
  }) async {
    // If a VAD service is provided, use it directly
    if (vadService != null) {
      vadService.processAudioBuffer(buffer);
      return vadService.isSpeechActive;
    }

    // Otherwise, try to use the component
    if (_vadComponent == null) {
      // Create a default VAD component
      const config = VADConfiguration();
      _vadComponent = SimpleEnergyVAD(
        sampleRate: config.sampleRate,
        frameLength: config.frameLength,
        energyThreshold: config.energyThreshold,
      );
      await _vadComponent!.initialize();
    }

    final vadComponent = _vadComponent;
    if (vadComponent == null) {
      _logger.warning('No VAD service available');
      return false;
    }

    final result = await vadComponent.detect(audioData: buffer);
    return result.hasSpeech;
  }

  /// Process float audio data for VAD
  /// - Parameters:
  ///   - audioData: Audio samples as Float32 (-1.0 to 1.0)
  ///   - vadService: Optional VAD service to use directly
  /// - Returns: Whether speech is detected
  Future<bool> processAudioData(
    List<double> audioData, {
    VADService? vadService,
  }) async {
    // If a VAD service is provided, use it directly
    if (vadService != null) {
      return vadService.processAudioData(audioData);
    }

    // Otherwise, try to use the component
    if (_vadComponent == null) {
      // Create a default VAD component
      const config = VADConfiguration();
      _vadComponent = SimpleEnergyVAD(
        sampleRate: config.sampleRate,
        frameLength: config.frameLength,
        energyThreshold: config.energyThreshold,
      );
      await _vadComponent!.initialize();
    }

    final vadComponent = _vadComponent;
    if (vadComponent == null) {
      _logger.warning('No VAD service available');
      return false;
    }

    return vadComponent.processAudioData(audioData);
  }

  /// Reset the handler
  void reset() {
    _vadComponent?.reset();
  }

  /// Cleanup resources
  Future<void> cleanup() async {
    await _vadComponent?.cleanup();
    _vadComponent = null;
  }
}
