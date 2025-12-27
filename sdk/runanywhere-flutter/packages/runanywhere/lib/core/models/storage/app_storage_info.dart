/// App storage breakdown.
/// Matches iOS AppStorageInfo from Data/Models/Storage/AppStorageInfo.swift
class AppStorageInfo {
  /// Documents directory size in bytes
  final int documentsSize;

  /// Cache directory size in bytes
  final int cacheSize;

  /// App support directory size in bytes
  final int appSupportSize;

  /// Total app storage size in bytes
  final int totalSize;

  const AppStorageInfo({
    required this.documentsSize,
    required this.cacheSize,
    required this.appSupportSize,
    required this.totalSize,
  });

  /// Create from JSON map
  factory AppStorageInfo.fromJson(Map<String, dynamic> json) {
    return AppStorageInfo(
      documentsSize: (json['documentsSize'] as num?)?.toInt() ?? 0,
      cacheSize: (json['cacheSize'] as num?)?.toInt() ?? 0,
      appSupportSize: (json['appSupportSize'] as num?)?.toInt() ?? 0,
      totalSize: (json['totalSize'] as num?)?.toInt() ?? 0,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'documentsSize': documentsSize,
      'cacheSize': cacheSize,
      'appSupportSize': appSupportSize,
      'totalSize': totalSize,
    };
  }
}
