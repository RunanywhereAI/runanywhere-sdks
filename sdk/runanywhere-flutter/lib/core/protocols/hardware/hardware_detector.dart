/// Hardware Detector Protocol
/// Similar to Swift SDK's HardwareDetector
abstract class HardwareDetector {
  /// Detect device capabilities
  Future<DeviceCapabilities> detectCapabilities();

  /// Get available memory
  Future<int> getAvailableMemory();

  /// Check if Neural Engine is available
  bool hasNeuralEngine();

  /// Check if GPU is available
  bool hasGPU();
}

/// Device Capabilities
class DeviceCapabilities {
  final String processorName;
  final int totalMemory;
  final int availableMemory;
  final bool hasNeuralEngine;
  final bool hasGPU;
  final List<String> supportedAccelerators;

  DeviceCapabilities({
    required this.processorName,
    required this.totalMemory,
    required this.availableMemory,
    required this.hasNeuralEngine,
    required this.hasGPU,
    required this.supportedAccelerators,
  });
}

