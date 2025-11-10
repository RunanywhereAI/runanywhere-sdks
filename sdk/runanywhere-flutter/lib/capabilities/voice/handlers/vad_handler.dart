import 'dart:typed_data';

/// VAD Handler for voice activity detection
/// Similar to Swift SDK's VADHandler
class VADHandler {
  final double _energyThreshold;
  bool _isSpeaking = false;

  VADHandler({double energyThreshold = 0.01}) : _energyThreshold = energyThreshold;

  /// Process audio data and detect speech
  bool processAudioData(Uint8List audioData) {
    // Calculate energy
    final energy = _calculateEnergy(audioData);
    
    // Simple threshold-based detection
    if (energy > _energyThreshold) {
      _isSpeaking = true;
      return true;
    } else {
      _isSpeaking = false;
      return false;
    }
  }

  /// Check if currently speaking
  bool get isSpeaking => _isSpeaking;

  /// Calculate audio energy
  double _calculateEnergy(Uint8List audioData) {
    if (audioData.isEmpty) return 0.0;

    double sum = 0.0;
    for (final sample in audioData) {
      final normalized = (sample - 128) / 128.0;
      sum += normalized * normalized;
    }

    return sum / audioData.length;
  }
}

