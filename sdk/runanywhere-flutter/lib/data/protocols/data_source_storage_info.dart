/// Information about local storage status
/// Matches iOS DataSourceStorageInfo from DataSource.swift
class DataSourceStorageInfo {
  final int? totalSpace;
  final int? availableSpace;
  final int? usedSpace;
  final int entityCount;
  final DateTime lastUpdated;

  DataSourceStorageInfo({
    this.totalSpace,
    this.availableSpace,
    this.usedSpace,
    this.entityCount = 0,
    DateTime? lastUpdated,
  }) : lastUpdated = lastUpdated ?? DateTime.now();

  factory DataSourceStorageInfo.fromJson(Map<String, dynamic> json) {
    return DataSourceStorageInfo(
      totalSpace: json['totalSpace'] as int?,
      availableSpace: json['availableSpace'] as int?,
      usedSpace: json['usedSpace'] as int?,
      entityCount: json['entityCount'] as int? ?? 0,
      lastUpdated: json['lastUpdated'] != null
          ? DateTime.parse(json['lastUpdated'] as String)
          : DateTime.now(),
    );
  }

  Map<String, dynamic> toJson() => {
        'totalSpace': totalSpace,
        'availableSpace': availableSpace,
        'usedSpace': usedSpace,
        'entityCount': entityCount,
        'lastUpdated': lastUpdated.toIso8601String(),
      };

  @override
  String toString() => 'DataSourceStorageInfo('
      'totalSpace: $totalSpace, '
      'availableSpace: $availableSpace, '
      'usedSpace: $usedSpace, '
      'entityCount: $entityCount, '
      'lastUpdated: $lastUpdated)';
}
