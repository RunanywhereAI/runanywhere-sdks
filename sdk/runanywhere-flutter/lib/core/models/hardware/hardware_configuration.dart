import 'dart:io';

import 'hardware_acceleration.dart';

/// Memory management mode for framework adapters
/// Matches iOS HardwareConfiguration.MemoryMode
enum MemoryMode {
  conservative('conservative'),
  balanced('balanced'),
  aggressive('aggressive');

  final String rawValue;

  const MemoryMode(this.rawValue);

  /// Create from raw string value
  static MemoryMode fromRawValue(String value) {
    return MemoryMode.values.firstWhere(
      (m) => m.rawValue == value,
      orElse: () => MemoryMode.balanced,
    );
  }
}

/// Simplified hardware configuration for framework adapters
/// Matches iOS HardwareConfiguration from Capabilities/DeviceCapability/Models/HardwareConfiguration.swift
class HardwareConfiguration {
  /// Primary hardware accelerator to use (auto will select best available)
  final HardwareAcceleration primaryAccelerator;

  /// Memory management mode
  final MemoryMode memoryMode;

  /// Number of CPU threads to use for processing
  final int threadCount;

  /// Default thread count (uses runtime value)
  static int get defaultThreadCount => Platform.numberOfProcessors;

  HardwareConfiguration({
    this.primaryAccelerator = HardwareAcceleration.auto,
    this.memoryMode = MemoryMode.balanced,
    int? threadCount,
  }) : threadCount = threadCount ?? Platform.numberOfProcessors;

  /// Default configuration with balanced settings
  static HardwareConfiguration get defaultConfig => HardwareConfiguration();

  /// Create a copy with modified fields
  HardwareConfiguration copyWith({
    HardwareAcceleration? primaryAccelerator,
    MemoryMode? memoryMode,
    int? threadCount,
  }) {
    return HardwareConfiguration(
      primaryAccelerator: primaryAccelerator ?? this.primaryAccelerator,
      memoryMode: memoryMode ?? this.memoryMode,
      threadCount: threadCount ?? this.threadCount,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is HardwareConfiguration &&
          runtimeType == other.runtimeType &&
          primaryAccelerator == other.primaryAccelerator &&
          memoryMode == other.memoryMode &&
          threadCount == other.threadCount;

  @override
  int get hashCode =>
      primaryAccelerator.hashCode ^ memoryMode.hashCode ^ threadCount.hashCode;

  @override
  String toString() =>
      'HardwareConfiguration(accelerator: $primaryAccelerator, memoryMode: $memoryMode, threads: $threadCount)';

  /// Create from JSON map
  factory HardwareConfiguration.fromJson(Map<String, dynamic> json) {
    return HardwareConfiguration(
      primaryAccelerator: HardwareAcceleration.fromRawValue(
        json['primaryAccelerator'] as String? ?? 'Auto',
      ),
      memoryMode: MemoryMode.fromRawValue(
        json['memoryMode'] as String? ?? 'balanced',
      ),
      threadCount: (json['threadCount'] as num?)?.toInt(),
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'primaryAccelerator': primaryAccelerator.rawValue,
      'memoryMode': memoryMode.rawValue,
      'threadCount': threadCount,
    };
  }
}
