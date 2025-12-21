import 'package:runanywhere/core/protocols/component/component_configuration.dart';

/// Output from Voice Activity Detection
class VADOutput implements ComponentOutput {
  /// Whether speech is detected
  final bool isSpeechDetected;

  /// Audio energy level
  final double energyLevel;

  /// Timestamp of this detection
  @override
  final DateTime timestamp;

  VADOutput({
    required this.isSpeechDetected,
    required this.energyLevel,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}
