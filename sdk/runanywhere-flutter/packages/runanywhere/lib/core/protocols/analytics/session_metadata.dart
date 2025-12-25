import 'package:uuid/uuid.dart';

/// Simple session metadata
///
/// Corresponds to iOS SDK's SessionMetadata struct in UnifiedAnalytics.swift
class SessionMetadata {
  /// Unique identifier for this session
  final String id;

  /// Model ID associated with this session (if any)
  final String? modelId;

  /// Type of session
  final String type;

  const SessionMetadata({
    required this.id,
    this.modelId,
    this.type = 'default',
  });

  /// Create a new session with a generated UUID
  factory SessionMetadata.create({
    String? modelId,
    String type = 'default',
  }) {
    return SessionMetadata(
      id: const Uuid().v4(),
      modelId: modelId,
      type: type,
    );
  }

  /// Create a copy with updated values
  SessionMetadata copyWith({
    String? id,
    String? modelId,
    String? type,
  }) {
    return SessionMetadata(
      id: id ?? this.id,
      modelId: modelId ?? this.modelId,
      type: type ?? this.type,
    );
  }

  @override
  String toString() =>
      'SessionMetadata(id: $id, modelId: $modelId, type: $type)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionMetadata &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          modelId == other.modelId &&
          type == other.type;

  @override
  int get hashCode => Object.hash(id, modelId, type);
}
