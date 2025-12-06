/// Consolidated protocol for entities that can be stored in repositories and synced
/// Combines previous Syncable and RepositoryEntity protocols to eliminate duplication
/// Matches iOS RepositoryEntity from SyncModels.swift
abstract class RepositoryEntity {
  /// Unique identifier
  String get id;

  /// When created
  DateTime get createdAt;

  /// When last updated
  DateTime get updatedAt;
  set updatedAt(DateTime value);

  /// Needs sync to network
  bool get syncPending;
  set syncPending(bool value);

  /// Mark as updated (sets updatedAt and syncPending)
  void markUpdated() {
    updatedAt = DateTime.now();
    syncPending = true;
  }

  /// Mark as synced (clears syncPending)
  void markSynced() {
    syncPending = false;
  }

  /// Convert to JSON for storage
  Map<String, dynamic> toJson();
}

/// Mixin that provides default sync behavior implementation
/// Use: class MyEntity extends Object with RepositoryEntityMixin implements RepositoryEntity
mixin RepositoryEntityMixin {
  DateTime get updatedAt;
  set updatedAt(DateTime value);
  bool get syncPending;
  set syncPending(bool value);

  void markUpdated() {
    updatedAt = DateTime.now();
    syncPending = true;
  }

  void markSynced() {
    syncPending = false;
  }
}
