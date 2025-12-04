import 'log_level.dart';

/// Device information for logging
///
/// Aligned with iOS: Sources/RunAnywhere/Capabilities/DeviceCapability/Models/DeviceInfo.swift
class DeviceInfo {
  final String model;
  final String osVersion;
  final String architecture;
  final int totalMemory;
  final int availableMemory;
  final bool hasNeuralEngine;
  final String? gpuFamily;

  const DeviceInfo({
    required this.model,
    required this.osVersion,
    required this.architecture,
    required this.totalMemory,
    required this.availableMemory,
    required this.hasNeuralEngine,
    this.gpuFamily,
  });

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'model': model,
      'osVersion': osVersion,
      'architecture': architecture,
      'totalMemory': totalMemory,
      'availableMemory': availableMemory,
      'hasNeuralEngine': hasNeuralEngine,
      if (gpuFamily != null) 'gpuFamily': gpuFamily,
    };
  }

  /// Create from JSON map
  factory DeviceInfo.fromJson(Map<String, dynamic> json) {
    return DeviceInfo(
      model: json['model'] as String,
      osVersion: json['osVersion'] as String,
      architecture: json['architecture'] as String,
      totalMemory: json['totalMemory'] as int,
      availableMemory: json['availableMemory'] as int,
      hasNeuralEngine: json['hasNeuralEngine'] as bool,
      gpuFamily: json['gpuFamily'] as String?,
    );
  }
}

/// Log entry structure
///
/// Aligned with iOS: Sources/RunAnywhere/Foundation/Logging/Models/LogEntry.swift
class LogEntry {
  final DateTime timestamp;
  final LogLevel level;
  final String category;
  final String message;
  final Map<String, String>? metadata;
  final DeviceInfo? deviceInfo;

  LogEntry({
    required this.timestamp,
    required this.level,
    required this.category,
    required this.message,
    Map<String, dynamic>? metadata,
    this.deviceInfo,
  }) : metadata = metadata?.map((key, value) => MapEntry(key, value.toString()));

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'timestamp': timestamp.toIso8601String(),
      'level': level.toString(),
      'category': category,
      'message': message,
      if (metadata != null) 'metadata': metadata,
      if (deviceInfo != null) 'deviceInfo': deviceInfo!.toJson(),
    };
  }

  /// Create from JSON map
  factory LogEntry.fromJson(Map<String, dynamic> json) {
    return LogEntry(
      timestamp: DateTime.parse(json['timestamp'] as String),
      level: LogLevel.values.firstWhere(
        (l) => l.toString() == json['level'],
        orElse: () => LogLevel.info,
      ),
      category: json['category'] as String,
      message: json['message'] as String,
      metadata: (json['metadata'] as Map<String, dynamic>?)?.cast<String, String>(),
      deviceInfo: json['deviceInfo'] != null
          ? DeviceInfo.fromJson(json['deviceInfo'] as Map<String, dynamic>)
          : null,
    );
  }
}
