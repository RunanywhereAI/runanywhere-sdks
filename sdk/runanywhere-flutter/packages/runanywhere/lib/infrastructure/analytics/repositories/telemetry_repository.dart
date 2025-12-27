//
//  telemetry_repository.dart
//  RunAnywhere SDK
//
//  Repository for telemetry data persistence.
//  Matches iOS SDK's TelemetryRepositoryImpl.swift
//

import 'dart:async';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/infrastructure/analytics/data_sources/local_telemetry_data_source.dart';
import 'package:runanywhere/infrastructure/analytics/data_sources/remote_telemetry_data_source.dart';
import 'package:runanywhere/infrastructure/analytics/models/domain/telemetry_data.dart';
import 'package:runanywhere/infrastructure/analytics/models/domain/telemetry_event_type.dart';

/// Repository for managing telemetry data using DataSource pattern
///
/// This class is a facade that wraps:
/// - LocalTelemetryDataSource for persistence
/// - RemoteTelemetryDataSource for sync
///
/// Matches iOS SDK's TelemetryRepositoryImpl pattern.
class TelemetryRepository {
  final SDKLogger _logger = SDKLogger(category: 'TelemetryRepository');

  final LocalTelemetryDataSource _localDataSource;
  final RemoteTelemetryDataSource _remoteDataSource;

  /// Expose remote data source for sync coordinator
  RemoteTelemetryDataSource get remoteDataSource => _remoteDataSource;

  /// Create a TelemetryRepository with data sources
  TelemetryRepository({
    required LocalTelemetryDataSource localDataSource,
    required RemoteTelemetryDataSource remoteDataSource,
  })  : _localDataSource = localDataSource,
        _remoteDataSource = remoteDataSource;

  /// Create a TelemetryRepository using shared/singleton data sources
  factory TelemetryRepository.withShared({
    required RemoteTelemetryDataSource remoteDataSource,
  }) {
    return TelemetryRepository(
      localDataSource: LocalTelemetryDataSource.shared,
      remoteDataSource: remoteDataSource,
    );
  }

  // MARK: - Core Repository Operations

  /// Save a telemetry event
  Future<void> save(TelemetryData entity) async {
    await _localDataSource.store(entity);
    _logger.debug('Saved telemetry event: ${entity.id}');
  }

  /// Fetch a telemetry event by ID
  Future<TelemetryData?> fetch(String id) async {
    return _localDataSource.load(id);
  }

  /// Fetch all telemetry events
  Future<List<TelemetryData>> fetchAll() async {
    return _localDataSource.loadAll();
  }

  /// Delete a telemetry event by ID
  Future<void> delete(String id) async {
    await _localDataSource.remove(id);
  }

  // MARK: - Sync Support

  /// Fetch telemetry events pending sync
  Future<List<TelemetryData>> fetchPendingSync() async {
    return _localDataSource.loadPendingSync();
  }

  /// Mark telemetry events as synced
  Future<void> markSynced(List<String> ids) async {
    await _localDataSource.markSynced(ids);
    _logger.debug('Marked ${ids.length} telemetry events as synced');
  }

  // MARK: - TelemetryRepository Protocol Methods

  /// Track a new telemetry event
  ///
  /// Creates a TelemetryData instance and saves it locally.
  /// The event will be synced to the backend via TelemetrySyncService.
  Future<void> trackEvent(
    TelemetryEventType type, {
    required Map<String, String> properties,
  }) async {
    final event = TelemetryData(
      eventType: type.rawValue,
      properties: properties,
    );

    await save(event);
  }

  /// Track an event with string type (for AnalyticsQueueManager compatibility)
  Future<void> trackEventWithType(
    String eventType, {
    required Map<String, String> properties,
  }) async {
    final event = TelemetryData(
      eventType: eventType,
      properties: properties,
    );

    await save(event);
  }

  /// Fetch telemetry events within a date range
  Future<List<TelemetryData>> fetchByDateRange({
    required DateTime from,
    required DateTime to,
  }) async {
    return _localDataSource.loadByTimeRange(start: from, end: to);
  }

  /// Fetch telemetry events that haven't been synced (alias for fetchPendingSync)
  Future<List<TelemetryData>> fetchUnsent() async {
    return fetchPendingSync();
  }

  /// Mark telemetry events as sent/synced (alias for markSynced)
  Future<void> markAsSent(List<String> ids) async {
    await markSynced(ids);
    _logger.info('Marked ${ids.length} telemetry events as sent');
  }

  /// Clean up telemetry events older than specified date
  Future<void> cleanup({required DateTime olderThan}) async {
    await _localDataSource.deleteOldEvents(before: olderThan);
  }

  // MARK: - Additional Operations

  /// Get storage information
  Future<DataSourceStorageInfo> getStorageInfo() async {
    return _localDataSource.getStorageInfo();
  }

  /// Clear all telemetry events
  Future<int> clear() async {
    return _localDataSource.clear();
  }

  /// Apply retention policy
  Future<int> applyRetentionPolicy() async {
    return _localDataSource.applyRetentionPolicy();
  }

  /// Initialize the repository (ensures database is ready)
  Future<void> initialize() async {
    await _localDataSource.initialize();
    _logger.info('TelemetryRepository initialized');
  }
}
