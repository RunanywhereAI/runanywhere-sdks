import 'package:runanywhere/core/models/hardware/hardware_acceleration.dart';

/// Memory pressure levels.
/// Matches iOS MemoryPressureLevel from Capabilities/DeviceCapability/Models/DeviceCapabilities.swift
enum MemoryPressureLevel {
  low,
  medium,
  high,
  warning,
  critical;

  String get rawValue => name;

  static MemoryPressureLevel fromRawValue(String value) {
    return MemoryPressureLevel.values.firstWhere(
      (l) => l.name == value,
      orElse: () => MemoryPressureLevel.low,
    );
  }
}

/// Processor type enumeration.
/// Matches iOS ProcessorType from Capabilities/DeviceCapability/Models/DeviceCapabilities.swift
enum ProcessorType {
  a14Bionic,
  a15Bionic,
  a16Bionic,
  a17Pro,
  a18,
  a18Pro,
  m1,
  m1Pro,
  m1Max,
  m1Ultra,
  m2,
  m2Pro,
  m2Max,
  m2Ultra,
  m3,
  m3Pro,
  m3Max,
  m4,
  m4Pro,
  m4Max,
  intel,
  arm,
  unknown;

  String get rawValue => name;

  /// Whether this processor is Apple Silicon
  bool get isAppleSilicon {
    switch (this) {
      case ProcessorType.a14Bionic:
      case ProcessorType.a15Bionic:
      case ProcessorType.a16Bionic:
      case ProcessorType.a17Pro:
      case ProcessorType.a18:
      case ProcessorType.a18Pro:
      case ProcessorType.m1:
      case ProcessorType.m1Pro:
      case ProcessorType.m1Max:
      case ProcessorType.m1Ultra:
      case ProcessorType.m2:
      case ProcessorType.m2Pro:
      case ProcessorType.m2Max:
      case ProcessorType.m2Ultra:
      case ProcessorType.m3:
      case ProcessorType.m3Pro:
      case ProcessorType.m3Max:
      case ProcessorType.m4:
      case ProcessorType.m4Pro:
      case ProcessorType.m4Max:
      case ProcessorType.arm:
        return true;
      case ProcessorType.intel:
      case ProcessorType.unknown:
        return false;
    }
  }

  static ProcessorType fromRawValue(String value) {
    return ProcessorType.values.firstWhere(
      (t) => t.name == value,
      orElse: () => ProcessorType.unknown,
    );
  }
}

/// Operating system version.
class OperatingSystemVersion {
  final int majorVersion;
  final int minorVersion;
  final int patchVersion;

  const OperatingSystemVersion({
    required this.majorVersion,
    required this.minorVersion,
    this.patchVersion = 0,
  });

  @override
  String toString() => '$majorVersion.$minorVersion.$patchVersion';

  factory OperatingSystemVersion.fromJson(Map<String, dynamic> json) {
    return OperatingSystemVersion(
      majorVersion: (json['majorVersion'] as num?)?.toInt() ?? 0,
      minorVersion: (json['minorVersion'] as num?)?.toInt() ?? 0,
      patchVersion: (json['patchVersion'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'majorVersion': majorVersion,
      'minorVersion': minorVersion,
      'patchVersion': patchVersion,
    };
  }
}

/// Complete device hardware capabilities.
/// Matches iOS DeviceCapabilities from Capabilities/DeviceCapability/Models/DeviceCapabilities.swift
class DeviceCapabilities {
  /// Total device memory in bytes
  final int totalMemory;

  /// Available device memory in bytes
  final int availableMemory;

  /// Whether the device has a Neural Engine
  final bool hasNeuralEngine;

  /// Whether the device has a GPU
  final bool hasGPU;

  /// Number of processor cores
  final int processorCount;

  /// Type of processor
  final ProcessorType processorType;

  /// Supported hardware accelerators
  final List<HardwareAcceleration> supportedAccelerators;

  /// Operating system version
  final OperatingSystemVersion osVersion;

  /// Device model identifier
  final String modelIdentifier;

  const DeviceCapabilities({
    required this.totalMemory,
    required this.availableMemory,
    this.hasNeuralEngine = false,
    this.hasGPU = false,
    required this.processorCount,
    this.processorType = ProcessorType.unknown,
    this.supportedAccelerators = const [HardwareAcceleration.cpu],
    required this.osVersion,
    this.modelIdentifier = 'Unknown',
  });

  /// Memory pressure level based on available memory
  MemoryPressureLevel get memoryPressureLevel {
    final ratio = availableMemory / totalMemory;

    if (ratio < 0.1) {
      return MemoryPressureLevel.critical;
    } else if (ratio < 0.15) {
      return MemoryPressureLevel.warning;
    } else if (ratio < 0.2) {
      return MemoryPressureLevel.high;
    } else if (ratio < 0.4) {
      return MemoryPressureLevel.medium;
    } else {
      return MemoryPressureLevel.low;
    }
  }

  /// Whether the device has sufficient resources for a given model
  bool canRun({required int memoryRequired}) {
    return availableMemory >= memoryRequired;
  }

  /// Create from JSON map
  factory DeviceCapabilities.fromJson(Map<String, dynamic> json) {
    return DeviceCapabilities(
      totalMemory: (json['totalMemory'] as num?)?.toInt() ?? 0,
      availableMemory: (json['availableMemory'] as num?)?.toInt() ?? 0,
      hasNeuralEngine: json['hasNeuralEngine'] as bool? ?? false,
      hasGPU: json['hasGPU'] as bool? ?? false,
      processorCount: (json['processorCount'] as num?)?.toInt() ?? 0,
      processorType: ProcessorType.fromRawValue(
          json['processorType'] as String? ?? 'unknown'),
      supportedAccelerators: (json['supportedAccelerators'] as List<dynamic>?)
              ?.map((e) => HardwareAcceleration.fromRawValue(e as String))
              .whereType<HardwareAcceleration>()
              .toList() ??
          const [HardwareAcceleration.cpu],
      osVersion: json['osVersion'] != null
          ? OperatingSystemVersion.fromJson(
              json['osVersion'] as Map<String, dynamic>)
          : const OperatingSystemVersion(majorVersion: 0, minorVersion: 0),
      modelIdentifier: json['modelIdentifier'] as String? ?? 'Unknown',
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'totalMemory': totalMemory,
      'availableMemory': availableMemory,
      'hasNeuralEngine': hasNeuralEngine,
      'hasGPU': hasGPU,
      'processorCount': processorCount,
      'processorType': processorType.rawValue,
      'supportedAccelerators':
          supportedAccelerators.map((a) => a.rawValue).toList(),
      'osVersion': osVersion.toJson(),
      'modelIdentifier': modelIdentifier,
    };
  }
}
