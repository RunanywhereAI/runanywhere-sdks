import '../../core/protocols/component/component_configuration.dart';
import '../../core/types/sdk_component.dart';
import '../../foundation/error_types/sdk_error.dart';

/// Configuration for VAD component
class VADConfiguration implements ComponentConfiguration {
  /// Energy threshold for voice detection (0.0 to 1.0)
  final double energyThreshold;

  /// Sample rate in Hz
  final int sampleRate;

  /// Frame length in seconds
  final double frameLength;

  /// Enable automatic calibration
  final bool enableAutoCalibration;

  /// Calibration multiplier (threshold = ambient noise * multiplier)
  final double calibrationMultiplier;

  const VADConfiguration({
    this.energyThreshold = 0.015,
    this.sampleRate = 16000,
    this.frameLength = 0.1,
    this.enableAutoCalibration = false,
    this.calibrationMultiplier = 2.0,
  });

  @override
  void validate() {
    // Validate threshold range with better guidance
    if (energyThreshold < 0 || energyThreshold > 1.0) {
      throw SDKError.validationFailed(
        'Energy threshold must be between 0 and 1.0. Recommended range: 0.01-0.05',
      );
    }

    // Warn if threshold is too low or too high
    if (energyThreshold < 0.002) {
      throw SDKError.validationFailed(
        'Energy threshold $energyThreshold is very low and may cause false positives. Recommended minimum: 0.002',
      );
    }
    if (energyThreshold > 0.1) {
      throw SDKError.validationFailed(
        'Energy threshold $energyThreshold is very high and may miss speech. Recommended maximum: 0.1',
      );
    }

    if (sampleRate <= 0 || sampleRate > 48000) {
      throw SDKError.validationFailed(
        'Sample rate must be between 1 and 48000 Hz',
      );
    }

    if (frameLength <= 0 || frameLength > 1.0) {
      throw SDKError.validationFailed(
        'Frame length must be between 0 and 1 second',
      );
    }

    // Validate calibration multiplier
    if (calibrationMultiplier < 1.5 || calibrationMultiplier > 5.0) {
      throw SDKError.validationFailed(
        'Calibration multiplier must be between 1.5 and 5.0',
      );
    }
  }
}
