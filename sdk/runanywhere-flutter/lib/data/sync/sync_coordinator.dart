//
//  sync_coordinator.dart
//  RunAnywhere SDK
//
//  Centralized sync coordination for all repositories
//  Matches iOS SyncCoordinator.swift
//

import 'dart:async';

import '../../foundation/logging/sdk_logger.dart';
import '../protocols/remote_data_source.dart';
import '../protocols/repository.dart';
import '../protocols/repository_entity.dart';
import 'models/sync_progress.dart';

/// Centralized coordinator for syncing data between local storage and remote API
///
/// Matches iOS SDK's SyncCoordinator actor pattern.
/// Uses Streams for reactive state updates instead of iOS's AsyncSequence.
class SyncCoordinator {
  final SDKLogger _logger = SDKLogger(category: 'SyncCoordinator');

  // Configuration
  static const int _batchSize = 100;

  // Track active sync operations
  final Set<String> _activeSyncs = {};

  // Auto-sync timer
  Timer? _syncTimer;

  // Progress stream
  final StreamController<SyncProgress> _progressController =
      StreamController<SyncProgress>.broadcast();

  /// Stream of sync progress updates
  Stream<SyncProgress> get progressStream => _progressController.stream;

  // MARK: - Initialization

  /// Create a SyncCoordinator
  SyncCoordinator({bool enableAutoSync = false}) {
    if (enableAutoSync) {
      // Start auto-sync in the background (fire and forget)
      // ignore: discarded_futures
      Future.microtask(() => startAutoSync());
    }
    _logger.debug('SyncCoordinator initialized');
  }

  /// Dispose the coordinator and cleanup resources
  void dispose() {
    _syncTimer?.cancel();
    // ignore: discarded_futures
    _progressController.close();
    _logger.debug('SyncCoordinator disposed');
  }

  // MARK: - Generic Sync Methods

  /// Sync any repository with RepositoryEntity entities
  ///
  /// Uses the repository's remote data source to handle the actual sync.
  /// Emits progress updates through [progressStream].
  Future<void> sync<E extends RepositoryEntity, R extends RemoteDataSource<E>>(
    Repository<E, R> repository,
  ) async {
    final typeName = E.toString();

    // Check if sync already in progress
    if (_activeSyncs.contains(typeName)) {
      _logger.debug('Sync already in progress for $typeName');
      return;
    }

    // Check if remote data source is available
    final remoteDataSource = repository.remoteDataSource;
    if (remoteDataSource == null) {
      _logger.debug('No remote data source available for $typeName');
      return;
    }

    _activeSyncs.add(typeName);

    try {
      // Fetch pending items from repository
      final pending = await repository.fetchPendingSync();

      if (pending.isEmpty) {
        _logger.debug('No pending items to sync for $typeName');
        _emitProgress(SyncProgress.idle(typeName));
        return;
      }

      _logger.info('Syncing ${pending.length} $typeName items');

      // Emit initial progress
      _emitProgress(SyncProgress.syncing(
        typeName,
        totalItems: pending.length,
      ));

      var successCount = 0;
      final List<String> failedIds = [];

      // Process in batches
      final batches = _chunkList(pending, _batchSize);

      for (var batchIndex = 0; batchIndex < batches.length; batchIndex++) {
        final batch = batches[batchIndex];

        try {
          // Use the remote data source to sync
          final syncedIds = await remoteDataSource.syncBatch(batch);

          // Mark successfully synced items
          if (syncedIds.isNotEmpty) {
            await repository.markSynced(syncedIds);
            successCount += syncedIds.length;
          }

          // Track any that didn't sync
          final batchIds = batch.map((e) => e.id).toSet();
          final failedInBatch = batchIds.difference(syncedIds.toSet());
          failedIds.addAll(failedInBatch);

          // Emit progress update
          _emitProgress(SyncProgress.syncing(
            typeName,
            totalItems: pending.length,
            syncedItems: successCount,
            failedItems: failedIds.length,
          ));
        } catch (e) {
          _logger.error('Failed to sync batch: $e');
          final batchIds = batch.map((e) => e.id).toList();
          failedIds.addAll(batchIds);

          // Emit progress update with failures
          _emitProgress(SyncProgress.syncing(
            typeName,
            totalItems: pending.length,
            syncedItems: successCount,
            failedItems: failedIds.length,
          ));
        }
      }

      // Emit final progress
      if (successCount > 0 || failedIds.isEmpty) {
        _logger.info('Successfully synced $successCount $typeName items');
        _emitProgress(SyncProgress.completed(
          typeName,
          totalItems: pending.length,
          syncedItems: successCount,
          failedItems: failedIds.length,
        ));
      }

      if (failedIds.isNotEmpty) {
        _logger.warning('Failed to sync ${failedIds.length} $typeName items');
        _emitProgress(SyncProgress.completed(
          typeName,
          totalItems: pending.length,
          syncedItems: successCount,
          failedItems: failedIds.length,
        ));
      }
    } catch (e) {
      _logger.error('Sync operation failed for $typeName: $e');
      _emitProgress(SyncProgress.error(
        typeName,
        errorMessage: e.toString(),
      ));
      rethrow;
    } finally {
      _activeSyncs.remove(typeName);
    }
  }

  // MARK: - Auto Sync

  /// Start automatic sync timer
  void startAutoSync() {
    _syncTimer?.cancel();

    // Trigger auto-sync every 5 minutes
    _syncTimer = Timer.periodic(const Duration(minutes: 5), (timer) {
      _logger.debug('Auto-sync timer triggered');
      // Individual services will call sync() with their repositories
    });

    _logger.info('Auto-sync started');
  }

  /// Stop auto sync
  void stopAutoSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _logger.info('Auto-sync stopped');
  }

  // MARK: - Manual Sync Control

  /// Check if sync is in progress for a given entity type
  bool isSyncing<E extends RepositoryEntity>() {
    final typeName = E.toString();
    return _activeSyncs.contains(typeName);
  }

  /// Check if sync is in progress for a given type name
  bool isSyncingType(String typeName) {
    return _activeSyncs.contains(typeName);
  }

  /// Force sync all pending data
  ///
  /// This will be called by individual services.
  /// Each service will call sync() with their repository.
  Future<void> syncAll() async {
    _logger.info('Manual sync all triggered');
    // Services will implement their own sync logic
  }

  // MARK: - Private Helpers

  /// Emit sync progress update
  void _emitProgress(SyncProgress progress) {
    if (!_progressController.isClosed) {
      _progressController.add(progress);
    }
  }

  /// Chunk a list into batches of specified size
  List<List<T>> _chunkList<T>(List<T> list, int chunkSize) {
    final List<List<T>> chunks = [];
    for (var i = 0; i < list.length; i += chunkSize) {
      final end = (i + chunkSize < list.length) ? i + chunkSize : list.length;
      chunks.add(list.sublist(i, end));
    }
    return chunks;
  }
}
