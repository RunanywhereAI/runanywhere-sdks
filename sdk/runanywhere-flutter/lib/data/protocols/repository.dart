//
//  repository.dart
//  RunAnywhere SDK
//
//  Base repository protocol for data persistence
//  Matches iOS Repository.swift
//

import 'package:runanywhere/data/protocols/data_source.dart';
import 'package:runanywhere/data/protocols/repository_entity.dart';

/// Base repository protocol for data persistence
///
/// Minimal interface - sync handled by SyncCoordinator.
/// Matches iOS SDK's Repository protocol.
abstract class Repository<E extends RepositoryEntity,
    R extends RemoteDataSource<E>> {
  // MARK: - Core CRUD Operations

  /// Save an entity
  Future<void> save(E entity);

  /// Fetch an entity by ID
  Future<E?> fetch(String id);

  /// Fetch all entities
  Future<List<E>> fetchAll();

  /// Delete an entity by ID
  Future<void> delete(String id);

  // MARK: - Sync Support

  /// Get the remote data source for syncing
  R? get remoteDataSource;

  /// Fetch entities pending sync
  Future<List<E>> fetchPendingSync();

  /// Mark entities as synced
  Future<void> markSynced(List<String> ids);
}

/// Base implementation of Repository with sync support
///
/// Provides default implementations for sync-related methods.
abstract class BaseRepository<E extends RepositoryEntity,
    R extends RemoteDataSource<E>> implements Repository<E, R> {
  @override
  Future<List<E>> fetchPendingSync() async {
    final all = await fetchAll();
    return all.where((entity) => entity.syncPending).toList();
  }

  @override
  Future<void> markSynced(List<String> ids) async {
    for (final id in ids) {
      final entity = await fetch(id);
      if (entity != null) {
        final synced = entity.markSynced() as E;
        await save(synced);
      }
    }
  }
}
