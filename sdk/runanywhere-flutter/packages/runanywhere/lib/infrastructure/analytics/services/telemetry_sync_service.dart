//
//  telemetry_sync_service.dart
//  RunAnywhere SDK
//
//  Service that orchestrates local + remote telemetry data sources for sync.
//  Matches iOS SDK's SyncCoordinator pattern but specific to telemetry.
//

import 'dart:async';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/infrastructure/analytics/constants/analytics_constants.dart';
import 'package:runanywhere/infrastructure/analytics/data_sources/local_telemetry_data_source.dart';
import 'package:runanywhere/infrastructure/analytics/data_sources/remote_telemetry_data_source.dart';
import 'package:runanywhere/infrastructure/analytics/models/domain/telemetry_data.dart';

/// Service that orchestrates syncing telemetry data between local storage and remote API.
///
/// This service:
/// - Periodically syncs pending events to the backend
/// - Uses LocalTelemetryDataSource for storage
/// - Uses RemoteTelemetryDataSource for network transmission
/// - Handles batch processing and retry logic
class TelemetrySyncService {
  final LocalTelemetryDataSource _localDataSource;
  final RemoteTelemetryDataSource _remoteDataSource;
  final SDKLogger _logger = SDKLogger(category: 'TelemetrySyncService');

  // Configuration
  final int _batchSize = AnalyticsConstants.telemetryBatchSize;
  static const Duration _syncInterval = Duration(minutes: 5);

  // State tracking
  Timer? _syncTimer;
  bool _isSyncing = false;

  TelemetrySyncService({
    required LocalTelemetryDataSource localDataSource,
    required RemoteTelemetryDataSource remoteDataSource,
  })  : _localDataSource = localDataSource,
        _remoteDataSource = remoteDataSource;

  // MARK: - Public Methods

  /// Start periodic sync timer
  void startSync() {
    if (_syncTimer != null) {
      _logger.debug('Sync timer already running');
      return;
    }

    _logger.info('Starting telemetry sync service');
    _syncTimer = Timer.periodic(_syncInterval, (_) {
      unawaited(syncNow());
    });
  }

  /// Stop periodic sync timer
  void stopSync() {
    _syncTimer?.cancel();
    _syncTimer = null;
    _logger.info('Stopped telemetry sync service');
  }

  /// Immediately sync all pending telemetry events
  Future<SyncResult> syncNow() async {
    if (_isSyncing) {
      _logger.debug('Sync already in progress');
      return const SyncResult(synced: 0, failed: 0, skipped: true);
    }

    _isSyncing = true;
    try {
      return await _performSync();
    } finally {
      _isSyncing = false;
    }
  }

  /// Check if sync is currently in progress
  bool get isSyncing => _isSyncing;

  /// Check if auto-sync is enabled
  bool get isAutoSyncEnabled => _syncTimer != null;

  /// Dispose of the service
  void dispose() {
    stopSync();
  }

  // MARK: - Private Methods

  Future<SyncResult> _performSync() async {
    // Check if remote data source is available
    if (!await _remoteDataSource.isAvailable()) {
      _logger.debug('Remote data source not available');
      return const SyncResult(synced: 0, failed: 0, skipped: true);
    }

    // Fetch pending events from local storage
    List<TelemetryData> pending;
    try {
      pending = await _localDataSource.loadPendingSync();
    } catch (e) {
      _logger.error('Failed to load pending events: $e');
      return const SyncResult(synced: 0, failed: 0, skipped: true);
    }

    if (pending.isEmpty) {
      _logger.debug('No pending telemetry events to sync');
      return const SyncResult(synced: 0, failed: 0, skipped: false);
    }

    _logger.info('Syncing ${pending.length} telemetry events');

    var successCount = 0;
    var failedCount = 0;

    // Process in batches
    final batches = _chunk(pending, _batchSize);
    for (final batch in batches) {
      try {
        // Sync batch via remote data source
        final syncedIds = await _remoteDataSource.syncBatch(batch);

        // Mark successfully synced items in local storage
        if (syncedIds.isNotEmpty) {
          await _localDataSource.markSynced(syncedIds);
          successCount += syncedIds.length;
        }

        // Track any that didn't sync
        final batchIds = batch.map((e) => e.id).toSet();
        final failedInBatch = batchIds.difference(syncedIds.toSet());
        failedCount += failedInBatch.length;
      } catch (e) {
        _logger.error('Failed to sync batch: $e');
        failedCount += batch.length;
      }
    }

    if (successCount > 0) {
      _logger.info('Successfully synced $successCount telemetry events');
    }

    if (failedCount > 0) {
      _logger.warning('Failed to sync $failedCount telemetry events');
    }

    return SyncResult(
        synced: successCount, failed: failedCount, skipped: false);
  }

  /// Chunk a list into smaller batches
  List<List<T>> _chunk<T>(List<T> list, int size) {
    final chunks = <List<T>>[];
    for (var i = 0; i < list.length; i += size) {
      final end = (i + size < list.length) ? i + size : list.length;
      chunks.add(list.sublist(i, end));
    }
    return chunks;
  }
}

/// Result of a sync operation
class SyncResult {
  /// Number of events successfully synced
  final int synced;

  /// Number of events that failed to sync
  final int failed;

  /// Whether the sync was skipped (e.g., already in progress)
  final bool skipped;

  const SyncResult({
    required this.synced,
    required this.failed,
    required this.skipped,
  });

  /// Total events processed
  int get total => synced + failed;

  /// Whether all events synced successfully
  bool get isFullSuccess => failed == 0 && !skipped;

  @override
  String toString() =>
      'SyncResult(synced: $synced, failed: $failed, skipped: $skipped)';
}
