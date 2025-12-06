/// Hardware acceleration options
/// Matches iOS HardwareAcceleration from Capabilities/DeviceCapability/Models/HardwareAcceleration.swift
enum HardwareAcceleration {
  cpu('CPU'),
  gpu('GPU'),
  neuralEngine('NeuralEngine'),
  metal('Metal'),
  coreML('CoreML'),
  auto('Auto');

  final String rawValue;

  const HardwareAcceleration(this.rawValue);

  /// Create from raw string value
  static HardwareAcceleration fromRawValue(String value) {
    return HardwareAcceleration.values.firstWhere(
      (a) => a.rawValue == value,
      orElse: () => HardwareAcceleration.auto,
    );
  }
}
