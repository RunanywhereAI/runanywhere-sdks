//
//  local_telemetry_data_source.dart
//  RunAnywhere SDK
//
//  Local data source for managing telemetry data in SQLite database
//  Matches iOS SDK's LocalTelemetryDataSource.swift
//

import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';

import '../../../foundation/logging/sdk_logger.dart';
import '../constants/analytics_constants.dart';
import '../models/domain/telemetry_data.dart';
import '../models/domain/telemetry_event_type.dart';

/// Storage info for data source
class DataSourceStorageInfo {
  final int entityCount;
  final DateTime lastUpdated;

  const DataSourceStorageInfo({
    required this.entityCount,
    required this.lastUpdated,
  });
}

/// Errors that can occur in data sources
enum DataSourceError {
  storageUnavailable,
  databaseError,
  entityNotFound,
}

/// Exception wrapping DataSourceError
class DataSourceException implements Exception {
  final DataSourceError error;
  final String? message;
  final Object? cause;

  const DataSourceException(this.error, {this.message, this.cause});

  @override
  String toString() =>
      'DataSourceException($error${message != null ? ': $message' : ''})';
}

/// Local data source for managing telemetry data in SQLite database
class LocalTelemetryDataSource {
  final SDKLogger _logger = SDKLogger(category: 'LocalTelemetryDataSource');
  final int _batchSize = AnalyticsConstants.telemetryBatchSize;

  Database? _database;
  bool _isInitialized = false;

  /// Singleton instance
  static final LocalTelemetryDataSource shared = LocalTelemetryDataSource._();

  LocalTelemetryDataSource._();

  /// Factory constructor for testing with custom database
  LocalTelemetryDataSource.withDatabase(Database database)
      : _database = database,
        _isInitialized = true;

  /// Initialize the database
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      final documentsDirectory = await getApplicationDocumentsDirectory();
      final dbPath =
          '${documentsDirectory.path}/${AnalyticsConstants.databaseName}';

      _database = await openDatabase(
        dbPath,
        version: AnalyticsConstants.databaseVersion,
        onCreate: (db, version) async {
          await db.execute(createTelemetryTableSql);
          await db.execute(createTelemetryTimestampIndexSql);
          await db.execute(createTelemetrySyncPendingIndexSql);
          _logger.info('Telemetry database created');
        },
        onUpgrade: (db, oldVersion, newVersion) async {
          // Handle migrations here if needed
          _logger.info(
              'Telemetry database upgraded from $oldVersion to $newVersion');
        },
      );

      _isInitialized = true;
      _logger.info('LocalTelemetryDataSource initialized');
    } catch (e) {
      _logger.error('Failed to initialize database: $e');
      throw DataSourceException(
        DataSourceError.databaseError,
        message: 'Failed to initialize database',
        cause: e,
      );
    }
  }

  /// Check if the data source is available
  Future<bool> isAvailable() async {
    if (!_isInitialized || _database == null) return false;

    try {
      final result = await _database!.rawQuery(
        "SELECT name FROM sqlite_master WHERE type='table' AND name='$telemetryTableName'",
      );
      return result.isNotEmpty;
    } catch (e) {
      _logger.debug('Database table not available: $e');
      return false;
    }
  }

  /// Validate configuration
  Future<void> validateConfiguration() async {
    if (!await isAvailable()) {
      throw const DataSourceException(DataSourceError.storageUnavailable);
    }
  }

  // MARK: - CRUD Operations

  /// Load a single telemetry event by ID
  Future<TelemetryData?> load(String id) async {
    await _ensureInitialized();
    _logger.debug('Loading telemetry event: $id');

    try {
      final result = await _database!.query(
        telemetryTableName,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );

      if (result.isEmpty) return null;
      return TelemetryData.fromMap(result.first);
    } catch (e) {
      _logger.error('Failed to load telemetry event: $e');
      rethrow;
    }
  }

  /// Load all telemetry events (ordered by timestamp descending)
  Future<List<TelemetryData>> loadAll() async {
    await _ensureInitialized();
    _logger.debug('Loading all telemetry events');

    try {
      final result = await _database!.query(
        telemetryTableName,
        orderBy: 'timestamp DESC',
      );

      return result.map((row) => TelemetryData.fromMap(row)).toList();
    } catch (e) {
      _logger.error('Failed to load all telemetry events: $e');
      rethrow;
    }
  }

  /// Store a telemetry event
  Future<void> store(TelemetryData entity) async {
    await _ensureInitialized();
    _logger.debug('Storing telemetry event: ${entity.id}');

    try {
      final entityToSave = entity.markUpdated();

      await _database!.insert(
        telemetryTableName,
        entityToSave.toMap(),
        conflictAlgorithm: ConflictAlgorithm.replace,
      );

      _logger.debug('Telemetry event stored successfully: ${entity.id}');
    } catch (e) {
      _logger.error('Failed to store telemetry event: $e');
      rethrow;
    }
  }

  /// Remove a telemetry event by ID
  Future<bool> remove(String id) async {
    await _ensureInitialized();
    _logger.debug('Removing telemetry event: $id');

    try {
      final deleted = await _database!.delete(
        telemetryTableName,
        where: 'id = ?',
        whereArgs: [id],
      );

      if (deleted > 0) {
        _logger.debug('Telemetry event removed successfully: $id');
        return true;
      } else {
        _logger.debug('Telemetry event not found for removal: $id');
        return false;
      }
    } catch (e) {
      _logger.error('Failed to remove telemetry event: $e');
      rethrow;
    }
  }

  /// Clear all telemetry events
  Future<int> clear() async {
    await _ensureInitialized();
    _logger.debug('Clearing all telemetry events');

    try {
      final deletedCount = await _database!.delete(telemetryTableName);
      _logger.info('Cleared $deletedCount telemetry events');
      return deletedCount;
    } catch (e) {
      _logger.error('Failed to clear telemetry events: $e');
      rethrow;
    }
  }

  /// Get storage information
  Future<DataSourceStorageInfo> getStorageInfo() async {
    await _ensureInitialized();

    try {
      final countResult = await _database!.rawQuery(
        'SELECT COUNT(*) as count FROM $telemetryTableName',
      );
      final count = Sqflite.firstIntValue(countResult) ?? 0;

      return DataSourceStorageInfo(
        entityCount: count,
        lastUpdated: DateTime.now(),
      );
    } catch (e) {
      _logger.error('Failed to get storage info: $e');
      rethrow;
    }
  }

  // MARK: - Telemetry-specific methods

  /// Load pending sync events (up to batch size)
  Future<List<TelemetryData>> loadPendingSync() async {
    await _ensureInitialized();

    try {
      final result = await _database!.query(
        telemetryTableName,
        where: 'sync_pending = ?',
        whereArgs: [1],
        limit: _batchSize,
      );

      return result.map((row) => TelemetryData.fromMap(row)).toList();
    } catch (e) {
      _logger.error('Failed to load pending sync events: $e');
      rethrow;
    }
  }

  /// Mark events as synced
  Future<void> markSynced(List<String> ids) async {
    if (ids.isEmpty) return;
    await _ensureInitialized();

    try {
      await _database!.transaction((txn) async {
        for (final id in ids) {
          await txn.update(
            telemetryTableName,
            {'sync_pending': 0},
            where: 'id = ?',
            whereArgs: [id],
          );
        }
      });

      _logger.debug('Marked ${ids.length} events as synced');
    } catch (e) {
      _logger.error('Failed to mark events as synced: $e');
      rethrow;
    }
  }

  /// Load events by type
  Future<List<TelemetryData>> loadByType(TelemetryEventType type) async {
    await _ensureInitialized();

    try {
      final result = await _database!.query(
        telemetryTableName,
        where: 'event_type = ?',
        whereArgs: [type.rawValue],
        orderBy: 'timestamp DESC',
      );

      return result.map((row) => TelemetryData.fromMap(row)).toList();
    } catch (e) {
      _logger.error('Failed to load events by type: $e');
      rethrow;
    }
  }

  /// Delete old events before a given date
  Future<int> deleteOldEvents({required DateTime before}) async {
    await _ensureInitialized();

    try {
      final deletedCount = await _database!.delete(
        telemetryTableName,
        where: 'timestamp < ?',
        whereArgs: [before.millisecondsSinceEpoch],
      );

      _logger.info('Deleted $deletedCount old telemetry events');
      return deletedCount;
    } catch (e) {
      _logger.error('Failed to delete old events: $e');
      rethrow;
    }
  }

  /// Delete events by time range
  Future<int> deleteByTimeRange({
    required DateTime start,
    required DateTime end,
  }) async {
    await _ensureInitialized();

    try {
      final deletedCount = await _database!.delete(
        telemetryTableName,
        where: 'timestamp >= ? AND timestamp <= ?',
        whereArgs: [
          start.millisecondsSinceEpoch,
          end.millisecondsSinceEpoch,
        ],
      );

      _logger.info('Deleted $deletedCount telemetry events in time range');
      return deletedCount;
    } catch (e) {
      _logger.error('Failed to delete events by time range: $e');
      rethrow;
    }
  }

  /// Load events by time range
  Future<List<TelemetryData>> loadByTimeRange({
    required DateTime start,
    required DateTime end,
  }) async {
    await _ensureInitialized();

    try {
      final result = await _database!.query(
        telemetryTableName,
        where: 'timestamp >= ? AND timestamp <= ?',
        whereArgs: [
          start.millisecondsSinceEpoch,
          end.millisecondsSinceEpoch,
        ],
        orderBy: 'timestamp DESC',
      );

      return result.map((row) => TelemetryData.fromMap(row)).toList();
    } catch (e) {
      _logger.error('Failed to load events by time range: $e');
      rethrow;
    }
  }

  /// Apply retention policy - delete events older than retention period
  Future<int> applyRetentionPolicy() async {
    final cutoffDate = DateTime.now().subtract(
      AnalyticsConstants.telemetryRetentionPeriod,
    );
    return deleteOldEvents(before: cutoffDate);
  }

  /// Close the database
  Future<void> close() async {
    if (_database != null && _database!.isOpen) {
      await _database!.close();
      _database = null;
      _isInitialized = false;
      _logger.info('LocalTelemetryDataSource closed');
    }
  }

  // MARK: - Private helpers

  Future<void> _ensureInitialized() async {
    if (!_isInitialized) {
      await initialize();
    }
    if (_database == null) {
      throw const DataSourceException(
        DataSourceError.storageUnavailable,
        message: 'Database not available',
      );
    }
  }
}
