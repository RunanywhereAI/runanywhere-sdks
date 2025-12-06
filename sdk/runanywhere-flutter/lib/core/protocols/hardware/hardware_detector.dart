import '../../models/hardware/battery_info.dart';
import '../../models/hardware/device_capabilities.dart';
import '../../models/hardware/processor_info.dart';

/// Thermal state enumeration.
/// Mirrors ProcessInfo.ThermalState from iOS/macOS Foundation.
enum ThermalState {
  nominal,
  fair,
  serious,
  critical;

  String get rawValue => name;

  static ThermalState fromRawValue(String value) {
    return ThermalState.values.firstWhere(
      (s) => s.name == value,
      orElse: () => ThermalState.nominal,
    );
  }
}

/// Protocol for hardware detection.
/// Matches iOS HardwareDetector from Core/Protocols/Hardware/HardwareDetector.swift
abstract interface class HardwareDetector {
  /// Detect current device capabilities
  DeviceCapabilities detectCapabilities();

  /// Get available memory in bytes
  int getAvailableMemory();

  /// Get total memory in bytes
  int getTotalMemory();

  /// Check if Neural Engine is available
  bool hasNeuralEngine();

  /// Check if GPU is available
  bool hasGPU();

  /// Get processor information
  ProcessorInfo getProcessorInfo();

  /// Get thermal state
  ThermalState getThermalState();

  /// Get battery information (null if not available, e.g., on desktop)
  BatteryInfo? getBatteryInfo();
}

/// Default mock implementation of HardwareDetector.
/// TODO: Implement native FFI binding when bridge is ready.
class MockHardwareDetector implements HardwareDetector {
  @override
  DeviceCapabilities detectCapabilities() {
    // Mock implementation - returns minimal capabilities
    return DeviceCapabilities(
      totalMemory: getTotalMemory(),
      availableMemory: getAvailableMemory(),
      hasNeuralEngine: false,
      hasGPU: false,
      processorCount: 1,
      processorType: ProcessorType.unknown,
      supportedAccelerators: const [],
      osVersion: const OperatingSystemVersion(majorVersion: 0, minorVersion: 0),
      modelIdentifier: 'Mock Device',
    );
  }

  @override
  int getAvailableMemory() {
    // Mock: Return 2GB
    return 2 * 1024 * 1024 * 1024;
  }

  @override
  int getTotalMemory() {
    // Mock: Return 8GB
    return 8 * 1024 * 1024 * 1024;
  }

  @override
  bool hasNeuralEngine() => false;

  @override
  bool hasGPU() => false;

  @override
  ProcessorInfo getProcessorInfo() {
    return ProcessorInfo(
      chipName: 'Mock Processor',
      coreCount: 4,
      architecture: 'unknown',
    );
  }

  @override
  ThermalState getThermalState() => ThermalState.nominal;

  @override
  BatteryInfo? getBatteryInfo() => null;
}
