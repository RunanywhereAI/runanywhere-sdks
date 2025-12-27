//
//  repository_entity.dart
//  RunAnywhere SDK
//
//  Protocol for entities that can be stored in repositories and synced
//  Matches iOS RepositoryEntity.swift
//

/// Protocol for entities that can be stored in repositories and synced
///
/// Combines repository storage with sync capabilities.
/// Matches iOS SDK's RepositoryEntity protocol.
abstract class RepositoryEntity {
  /// Unique identifier
  String get id;

  /// When created
  DateTime get createdAt;

  /// When last updated
  DateTime get updatedAt;

  /// Needs sync to network
  bool get syncPending;

  /// Mark as updated (sets updatedAt and syncPending)
  RepositoryEntity markUpdated();

  /// Mark as synced (clears syncPending)
  RepositoryEntity markSynced();

  /// Convert to JSON map
  Map<String, dynamic> toJson();

  /// Convert to database map
  Map<String, dynamic> toMap();
}
