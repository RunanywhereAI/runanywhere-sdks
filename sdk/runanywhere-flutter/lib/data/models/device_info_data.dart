import 'package:uuid/uuid.dart';

import '../protocols/repository_entity.dart';

/// Device architecture types
/// Matches iOS DeviceArchitecture from DeviceInfoData.swift
enum DeviceArchitecture {
  arm64('arm64', 'ARM64'),
  x86_64('x86_64', 'Intel x86_64'),
  unknown('unknown', 'Unknown');

  const DeviceArchitecture(this.rawValue, this.displayName);
  final String rawValue;
  final String displayName;

  static DeviceArchitecture fromString(String value) {
    return DeviceArchitecture.values.firstWhere(
      (e) => e.rawValue == value,
      orElse: () => DeviceArchitecture.unknown,
    );
  }
}

/// GPU family types for Apple devices
/// Matches iOS GPUFamily from DeviceInfoData.swift
enum GPUFamily {
  appleGPU('apple_gpu', 'Apple GPU'),
  intel('intel', 'Intel Graphics'),
  amd('amd', 'AMD Graphics'),
  unknown('unknown', 'Unknown GPU');

  const GPUFamily(this.rawValue, this.displayName);
  final String rawValue;
  final String displayName;

  static GPUFamily fromString(String value) {
    return GPUFamily.values.firstWhere(
      (e) => e.rawValue == value,
      orElse: () => GPUFamily.unknown,
    );
  }
}

/// Device form factor types
/// Matches iOS DeviceFormFactor from DeviceInfoData.swift
enum DeviceFormFactor {
  phone('phone', 'Phone'),
  tablet('tablet', 'Tablet'),
  desktop('desktop', 'Desktop'),
  laptop('laptop', 'Laptop'),
  watch('watch', 'Watch'),
  tv('tv', 'TV'),
  unknown('unknown', 'Unknown');

  const DeviceFormFactor(this.rawValue, this.displayName);
  final String rawValue;
  final String displayName;

  static DeviceFormFactor fromString(String value) {
    return DeviceFormFactor.values.firstWhere(
      (e) => e.rawValue == value,
      orElse: () => DeviceFormFactor.unknown,
    );
  }
}

/// Battery state types
/// Matches iOS BatteryState from DeviceInfoData.swift
enum BatteryState {
  unknown('unknown', 'Unknown'),
  unplugged('unplugged', 'Not Charging'),
  charging('charging', 'Charging'),
  full('full', 'Fully Charged');

  const BatteryState(this.rawValue, this.displayName);
  final String rawValue;
  final String displayName;

  static BatteryState fromString(String value) {
    return BatteryState.values.firstWhere(
      (e) => e.rawValue == value,
      orElse: () => BatteryState.unknown,
    );
  }
}

/// Device information data structure for sync and storage
/// Leverages existing DeviceKitAdapter for comprehensive device detection
/// Matches iOS DeviceInfoData from DeviceInfoData.swift
class DeviceInfoData implements RepositoryEntity {
  /// Unique identifier for this device (persistent UUID)
  @override
  final String id;

  /// Device model (e.g., "iPhone 16 Pro", "MacBook Pro M4")
  final String deviceModel;

  /// Device name (user-assigned name like "John's iPhone")
  final String deviceName;

  /// Operating system version
  final String osVersion;

  /// Device form factor
  final DeviceFormFactor formFactor;

  /// Processor architecture
  final DeviceArchitecture architecture;

  /// Chip name (e.g., "A18 Pro", "M4")
  final String chipName;

  /// Total memory in bytes
  final int totalMemory;

  /// Available memory in bytes (at collection time)
  final int availableMemory;

  /// Whether device has Neural Engine
  final bool hasNeuralEngine;

  /// Number of Neural Engine cores
  final int neuralEngineCores;

  /// GPU family
  final GPUFamily gpuFamily;

  /// Battery level (0.0-1.0, null for devices without battery)
  final double? batteryLevel;

  /// Battery charging state
  final BatteryState? batteryState;

  /// Low power mode enabled
  final bool isLowPowerMode;

  /// Core count (total CPU cores)
  final int coreCount;

  /// Performance cores count
  final int performanceCores;

  /// Efficiency cores count
  final int efficiencyCores;

  // MARK: - RepositoryEntity Protocol Requirements
  @override
  final DateTime createdAt;

  @override
  DateTime updatedAt;

  @override
  bool syncPending;

  DeviceInfoData({
    String? id,
    required this.deviceModel,
    required this.deviceName,
    required this.osVersion,
    this.formFactor = DeviceFormFactor.unknown,
    required this.architecture,
    required this.chipName,
    required this.totalMemory,
    required this.availableMemory,
    required this.hasNeuralEngine,
    required this.neuralEngineCores,
    this.gpuFamily = GPUFamily.unknown,
    this.batteryLevel,
    this.batteryState,
    this.isLowPowerMode = false,
    required this.coreCount,
    required this.performanceCores,
    required this.efficiencyCores,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncPending = true,
  })  : id = id ?? const Uuid().v4(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'deviceModel': deviceModel,
        'deviceName': deviceName,
        'osVersion': osVersion,
        'formFactor': formFactor.rawValue,
        'architecture': architecture.rawValue,
        'chipName': chipName,
        'totalMemory': totalMemory,
        'availableMemory': availableMemory,
        'hasNeuralEngine': hasNeuralEngine,
        'neuralEngineCores': neuralEngineCores,
        'gpuFamily': gpuFamily.rawValue,
        'batteryLevel': batteryLevel,
        'batteryState': batteryState?.rawValue,
        'isLowPowerMode': isLowPowerMode,
        'coreCount': coreCount,
        'performanceCores': performanceCores,
        'efficiencyCores': efficiencyCores,
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'syncPending': syncPending,
      };

  factory DeviceInfoData.fromJson(Map<String, dynamic> json) {
    return DeviceInfoData(
      id: json['id'] as String,
      deviceModel: json['deviceModel'] as String,
      deviceName: json['deviceName'] as String,
      osVersion: json['osVersion'] as String,
      formFactor: DeviceFormFactor.fromString(json['formFactor'] as String? ?? 'unknown'),
      architecture: DeviceArchitecture.fromString(json['architecture'] as String? ?? 'unknown'),
      chipName: json['chipName'] as String,
      totalMemory: json['totalMemory'] as int,
      availableMemory: json['availableMemory'] as int,
      hasNeuralEngine: json['hasNeuralEngine'] as bool,
      neuralEngineCores: json['neuralEngineCores'] as int,
      gpuFamily: GPUFamily.fromString(json['gpuFamily'] as String? ?? 'unknown'),
      batteryLevel: json['batteryLevel'] as double?,
      batteryState: json['batteryState'] != null
          ? BatteryState.fromString(json['batteryState'] as String)
          : null,
      isLowPowerMode: json['isLowPowerMode'] as bool? ?? false,
      coreCount: json['coreCount'] as int,
      performanceCores: json['performanceCores'] as int,
      efficiencyCores: json['efficiencyCores'] as int,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      syncPending: json['syncPending'] as bool? ?? true,
    );
  }

  /// Copy with modifications
  DeviceInfoData copyWith({
    String? id,
    String? deviceModel,
    String? deviceName,
    String? osVersion,
    DeviceFormFactor? formFactor,
    DeviceArchitecture? architecture,
    String? chipName,
    int? totalMemory,
    int? availableMemory,
    bool? hasNeuralEngine,
    int? neuralEngineCores,
    GPUFamily? gpuFamily,
    double? batteryLevel,
    BatteryState? batteryState,
    bool? isLowPowerMode,
    int? coreCount,
    int? performanceCores,
    int? efficiencyCores,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? syncPending,
  }) {
    return DeviceInfoData(
      id: id ?? this.id,
      deviceModel: deviceModel ?? this.deviceModel,
      deviceName: deviceName ?? this.deviceName,
      osVersion: osVersion ?? this.osVersion,
      formFactor: formFactor ?? this.formFactor,
      architecture: architecture ?? this.architecture,
      chipName: chipName ?? this.chipName,
      totalMemory: totalMemory ?? this.totalMemory,
      availableMemory: availableMemory ?? this.availableMemory,
      hasNeuralEngine: hasNeuralEngine ?? this.hasNeuralEngine,
      neuralEngineCores: neuralEngineCores ?? this.neuralEngineCores,
      gpuFamily: gpuFamily ?? this.gpuFamily,
      batteryLevel: batteryLevel ?? this.batteryLevel,
      batteryState: batteryState ?? this.batteryState,
      isLowPowerMode: isLowPowerMode ?? this.isLowPowerMode,
      coreCount: coreCount ?? this.coreCount,
      performanceCores: performanceCores ?? this.performanceCores,
      efficiencyCores: efficiencyCores ?? this.efficiencyCores,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncPending: syncPending ?? this.syncPending,
    );
  }

  @override
  void markUpdated() {
    updatedAt = DateTime.now();
    syncPending = true;
  }

  @override
  void markSynced() {
    syncPending = false;
  }

  @override
  String toString() => 'DeviceInfoData('
      'id: $id, '
      'deviceModel: $deviceModel, '
      'osVersion: $osVersion, '
      'formFactor: ${formFactor.displayName})';
}
