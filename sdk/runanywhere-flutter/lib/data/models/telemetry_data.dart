import 'package:uuid/uuid.dart';

import '../../core/types/telemetry_event_type.dart';
import '../protocols/repository_entity.dart';

/// Persisted telemetry event data
/// Matches iOS TelemetryData from TelemetryData.swift
class TelemetryData implements RepositoryEntity {
  @override
  final String id;

  final String eventType;
  final Map<String, String> properties;
  final DateTime timestamp;

  @override
  final DateTime createdAt;

  @override
  DateTime updatedAt;

  @override
  bool syncPending;

  TelemetryData({
    String? id,
    required this.eventType,
    this.properties = const {},
    DateTime? timestamp,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncPending = true,
  })  : id = id ?? const Uuid().v4(),
        timestamp = timestamp ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Create from TelemetryEventType enum
  factory TelemetryData.fromEventType(
    TelemetryEventType type, {
    Map<String, String> properties = const {},
  }) {
    return TelemetryData(
      eventType: type.rawValue,
      properties: properties,
    );
  }

  @override
  Map<String, dynamic> toJson() => {
        'id': id,
        'eventType': eventType,
        'properties': properties,
        'timestamp': timestamp.toIso8601String(),
        'createdAt': createdAt.toIso8601String(),
        'updatedAt': updatedAt.toIso8601String(),
        'syncPending': syncPending,
      };

  factory TelemetryData.fromJson(Map<String, dynamic> json) {
    return TelemetryData(
      id: json['id'] as String,
      eventType: json['eventType'] as String,
      properties: Map<String, String>.from(json['properties'] as Map? ?? {}),
      timestamp: DateTime.parse(json['timestamp'] as String),
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      syncPending: json['syncPending'] as bool? ?? true,
    );
  }

  /// Get the TelemetryEventType enum value if possible
  TelemetryEventType? get eventTypeEnum => TelemetryEventType.fromString(eventType);

  /// Copy with modifications
  TelemetryData copyWith({
    String? id,
    String? eventType,
    Map<String, String>? properties,
    DateTime? timestamp,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? syncPending,
  }) {
    return TelemetryData(
      id: id ?? this.id,
      eventType: eventType ?? this.eventType,
      properties: properties ?? this.properties,
      timestamp: timestamp ?? this.timestamp,
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
  String toString() => 'TelemetryData('
      'id: $id, '
      'eventType: $eventType, '
      'timestamp: $timestamp, '
      'syncPending: $syncPending)';
}
