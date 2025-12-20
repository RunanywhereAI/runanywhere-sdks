import '../hardware/hardware_acceleration.dart';
import '../model/model_info.dart';
import '../../protocols/hardware/hardware_detector.dart';

/// Resource availability information.
/// Matches iOS ResourceAvailability from Core/Models/Common/ResourceAvailability.swift
class ResourceAvailability {
  /// Available memory in bytes
  final int memoryAvailable;

  /// Available storage in bytes
  final int storageAvailable;

  /// Available hardware accelerators
  final List<HardwareAcceleration> acceleratorsAvailable;

  /// Current thermal state
  final ThermalState thermalState;

  /// Battery level (0.0 to 1.0), null if not available
  final double? batteryLevel;

  /// Whether device is in low power mode
  final bool isLowPowerMode;

  const ResourceAvailability({
    required this.memoryAvailable,
    required this.storageAvailable,
    required this.acceleratorsAvailable,
    required this.thermalState,
    this.batteryLevel,
    this.isLowPowerMode = false,
  });

  /// Check if a model can be loaded given current resources.
  /// Returns a record with (canLoad: bool, reason: String?).
  ({bool canLoad, String? reason}) canLoad(ModelInfo model) {
    // Check memory
    final memoryNeeded = model.memoryRequired ?? 0;
    if (memoryNeeded > memoryAvailable) {
      final needed = _formatBytes(memoryNeeded);
      final available = _formatBytes(memoryAvailable);
      return (
        canLoad: false,
        reason: 'Insufficient memory: need $needed, have $available'
      );
    }

    // Check storage
    final downloadSize = model.downloadSize;
    if (downloadSize != null && downloadSize > storageAvailable) {
      final needed = _formatBytes(downloadSize);
      final available = _formatBytes(storageAvailable);
      return (
        canLoad: false,
        reason: 'Insufficient storage: need $needed, have $available'
      );
    }

    // Check thermal state
    if (thermalState == ThermalState.critical) {
      return (
        canLoad: false,
        reason: 'Device is too hot, please wait for it to cool down'
      );
    }

    // Check battery in low power mode
    if (isLowPowerMode && batteryLevel != null && batteryLevel! < 0.2) {
      return (
        canLoad: false,
        reason: 'Battery too low for model loading in Low Power Mode'
      );
    }

    return (canLoad: true, reason: null);
  }

  /// Helper to format bytes into human-readable string
  static String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  /// JSON serialization
  Map<String, dynamic> toJson() => {
        'memoryAvailable': memoryAvailable,
        'storageAvailable': storageAvailable,
        'acceleratorsAvailable':
            acceleratorsAvailable.map((a) => a.rawValue).toList(),
        'thermalState': thermalState.rawValue,
        if (batteryLevel != null) 'batteryLevel': batteryLevel,
        'isLowPowerMode': isLowPowerMode,
      };

  factory ResourceAvailability.fromJson(Map<String, dynamic> json) {
    return ResourceAvailability(
      memoryAvailable: json['memoryAvailable'] as int,
      storageAvailable: json['storageAvailable'] as int,
      acceleratorsAvailable: (json['acceleratorsAvailable'] as List<dynamic>?)
              ?.map((a) => HardwareAcceleration.fromRawValue(a as String))
              .toList() ??
          [],
      thermalState: ThermalState.fromRawValue(
          json['thermalState'] as String? ?? 'nominal'),
      batteryLevel: json['batteryLevel'] as double?,
      isLowPowerMode: json['isLowPowerMode'] as bool? ?? false,
    );
  }

  @override
  String toString() =>
      'ResourceAvailability(memory: ${_formatBytes(memoryAvailable)}, '
      'storage: ${_formatBytes(storageAvailable)}, thermal: $thermalState)';
}
