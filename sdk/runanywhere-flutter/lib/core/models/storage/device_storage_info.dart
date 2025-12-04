/// Device storage information.
/// Matches iOS DeviceStorageInfo from Data/Models/Storage/DeviceStorageInfo.swift
class DeviceStorageInfo {
  /// Total device storage space in bytes
  final int totalSpace;

  /// Free device storage space in bytes
  final int freeSpace;

  /// Used device storage space in bytes
  final int usedSpace;

  const DeviceStorageInfo({
    required this.totalSpace,
    required this.freeSpace,
    required this.usedSpace,
  });

  /// Usage percentage (0-100)
  double get usagePercentage {
    if (totalSpace == 0) return 0;
    return (usedSpace / totalSpace) * 100;
  }

  /// Create from JSON map
  factory DeviceStorageInfo.fromJson(Map<String, dynamic> json) {
    return DeviceStorageInfo(
      totalSpace: (json['totalSpace'] as num?)?.toInt() ?? 0,
      freeSpace: (json['freeSpace'] as num?)?.toInt() ?? 0,
      usedSpace: (json['usedSpace'] as num?)?.toInt() ?? 0,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'totalSpace': totalSpace,
      'freeSpace': freeSpace,
      'usedSpace': usedSpace,
    };
  }
}
