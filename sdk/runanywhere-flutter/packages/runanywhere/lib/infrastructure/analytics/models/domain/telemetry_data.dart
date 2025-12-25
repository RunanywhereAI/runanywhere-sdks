//
//  telemetry_data.dart
//  RunAnywhere SDK
//
//  Persisted telemetry event data matching iOS SDK's TelemetryData.swift
//

import 'dart:convert';

import 'package:uuid/uuid.dart';

/// Persisted telemetry event data
class TelemetryData {
  /// Unique identifier for this event
  final String id;

  /// Event type (e.g., 'model_loaded', 'generation_started')
  final String eventType;

  /// Event properties as key-value pairs
  final Map<String, String> properties;

  /// When the event occurred
  final DateTime timestamp;

  /// When this record was created
  final DateTime createdAt;

  /// When this record was last updated
  DateTime updatedAt;

  /// Whether this event is pending sync to backend
  bool syncPending;

  TelemetryData({
    String? id,
    required this.eventType,
    Map<String, String>? properties,
    DateTime? timestamp,
    DateTime? createdAt,
    DateTime? updatedAt,
    this.syncPending = true,
  })  : id = id ?? const Uuid().v4(),
        properties = properties ?? {},
        timestamp = timestamp ?? DateTime.now(),
        createdAt = createdAt ?? DateTime.now(),
        updatedAt = updatedAt ?? DateTime.now();

  /// Mark this event as updated (sets syncPending = true)
  TelemetryData markUpdated() {
    updatedAt = DateTime.now();
    syncPending = true;
    return this;
  }

  /// Mark this event as synced (sets syncPending = false)
  TelemetryData markSynced() {
    syncPending = false;
    return this;
  }

  /// Create a copy with updated fields
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
      properties: properties ?? Map.from(this.properties),
      timestamp: timestamp ?? this.timestamp,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      syncPending: syncPending ?? this.syncPending,
    );
  }

  /// Convert to a Map for database storage
  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'event_type': eventType,
      'properties': jsonEncode(properties),
      'timestamp': timestamp.millisecondsSinceEpoch,
      'created_at': createdAt.millisecondsSinceEpoch,
      'updated_at': updatedAt.millisecondsSinceEpoch,
      'sync_pending': syncPending ? 1 : 0,
    };
  }

  /// Create from database row
  factory TelemetryData.fromMap(Map<String, dynamic> map) {
    return TelemetryData(
      id: map['id'] as String,
      eventType: map['event_type'] as String,
      properties: _parseProperties(map['properties']),
      timestamp: DateTime.fromMillisecondsSinceEpoch(map['timestamp'] as int),
      createdAt: DateTime.fromMillisecondsSinceEpoch(map['created_at'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(map['updated_at'] as int),
      syncPending: (map['sync_pending'] as int) == 1,
    );
  }

  /// Parse properties from JSON string or Map
  static Map<String, String> _parseProperties(dynamic value) {
    if (value == null) return {};
    if (value is Map<String, String>) return value;
    if (value is String) {
      try {
        final decoded = jsonDecode(value);
        if (decoded is Map) {
          return decoded.map((k, v) => MapEntry(k.toString(), v.toString()));
        }
      } catch (_) {}
    }
    return {};
  }

  /// Convert to JSON map for API
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'event_type': eventType,
      'properties': properties,
      'timestamp': timestamp.toIso8601String(),
      'created_at': createdAt.toIso8601String(),
      'updated_at': updatedAt.toIso8601String(),
      'sync_pending': syncPending,
    };
  }

  /// Create from JSON map
  factory TelemetryData.fromJson(Map<String, dynamic> json) {
    return TelemetryData(
      id: json['id'] as String?,
      eventType: json['event_type'] as String,
      properties: (json['properties'] as Map<String, dynamic>?)
              ?.map((k, v) => MapEntry(k, v.toString())) ??
          {},
      timestamp: json['timestamp'] != null
          ? DateTime.parse(json['timestamp'] as String)
          : null,
      createdAt: json['created_at'] != null
          ? DateTime.parse(json['created_at'] as String)
          : null,
      updatedAt: json['updated_at'] != null
          ? DateTime.parse(json['updated_at'] as String)
          : null,
      syncPending: json['sync_pending'] as bool? ?? true,
    );
  }

  @override
  String toString() {
    return 'TelemetryData(id: $id, eventType: $eventType, timestamp: $timestamp, syncPending: $syncPending)';
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is TelemetryData && other.id == id;
  }

  @override
  int get hashCode => id.hashCode;
}

/// Database table name for telemetry
const String telemetryTableName = 'telemetry';

/// SQL to create the telemetry table
const String createTelemetryTableSql = '''
  CREATE TABLE IF NOT EXISTS $telemetryTableName (
    id TEXT PRIMARY KEY,
    event_type TEXT NOT NULL,
    properties TEXT NOT NULL,
    timestamp INTEGER NOT NULL,
    created_at INTEGER NOT NULL,
    updated_at INTEGER NOT NULL,
    sync_pending INTEGER NOT NULL DEFAULT 1
  )
''';

/// SQL to create index on timestamp for efficient queries
const String createTelemetryTimestampIndexSql = '''
  CREATE INDEX IF NOT EXISTS idx_telemetry_timestamp ON $telemetryTableName (timestamp DESC)
''';

/// SQL to create index on sync_pending for efficient sync queries
const String createTelemetrySyncPendingIndexSql = '''
  CREATE INDEX IF NOT EXISTS idx_telemetry_sync_pending ON $telemetryTableName (sync_pending)
''';
