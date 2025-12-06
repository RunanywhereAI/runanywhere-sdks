import 'dart:async';

import 'data_source.dart';
import 'repository_entity.dart';

/// Base repository protocol for data persistence
/// Minimal interface - sync handled by SyncCoordinator
/// Matches iOS Repository from Repository.swift
abstract class Repository<Entity, RemoteDS extends RemoteDataSource<Entity>> {
  // MARK: - Core CRUD Operations

  /// Save an entity
  Future<void> save(Entity entity);

  /// Fetch an entity by id
  Future<Entity?> fetch(String id);

  /// Fetch all entities
  Future<List<Entity>> fetchAll();

  /// Delete an entity by id
  Future<void> delete(String id);

  // MARK: - Sync Support

  /// Get the remote data source for syncing
  RemoteDS? get remoteDataSource;
}

/// Extension for repositories with RepositoryEntity entities
/// Provides minimal sync support - actual sync logic in SyncCoordinator
/// Matches iOS Repository extension from Repository.swift
abstract class SyncableRepository<Entity extends RepositoryEntity,
        RemoteDS extends RemoteDataSource<Entity>>
    extends Repository<Entity, RemoteDS> {
  /// Fetch entities pending sync
  Future<List<Entity>> fetchPendingSync() async {
    final all = await fetchAll();
    return all.where((entity) => entity.syncPending).toList();
  }

  /// Mark entities as synced
  Future<void> markSynced(List<String> ids) async {
    for (final id in ids) {
      final entity = await fetch(id);
      if (entity != null) {
        entity.markSynced();
        await save(entity);
      }
    }
  }
}
