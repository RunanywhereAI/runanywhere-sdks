//
//  sdk_analytics_initializer.dart
//  RunAnywhere SDK
//
//  Initializes the analytics pipeline during SDK startup.
//  Wires EventPublisher -> AnalyticsQueueManager -> TelemetryRepository -> TelemetrySyncService.
//
//  Corresponds to iOS SDK's analytics initialization in RunAnywhere.swift
//

import 'dart:async';

import 'package:runanywhere/data/network/api_client.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/infrastructure/analytics/analytics_queue_manager.dart';
import 'package:runanywhere/infrastructure/analytics/data_sources/local_telemetry_data_source.dart';
import 'package:runanywhere/infrastructure/analytics/data_sources/remote_telemetry_data_source.dart';
import 'package:runanywhere/infrastructure/analytics/repositories/telemetry_repository.dart';
import 'package:runanywhere/infrastructure/analytics/services/telemetry_sync_service.dart';
import 'package:runanywhere/infrastructure/events/event_publisher.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';

/// Initializes the analytics pipeline for the SDK.
///
/// This class wires together:
/// - LocalTelemetryDataSource (SQLite storage)
/// - RemoteTelemetryDataSource (API sync)
/// - TelemetryRepository (facade)
/// - AnalyticsQueueManager (batching)
/// - TelemetrySyncService (periodic sync)
/// - EventPublisher (event routing)
///
/// Usage:
/// ```dart
/// final initializer = SDKAnalyticsInitializer();
/// await initializer.initialize(
///   apiClient: apiClient,
///   environment: SDKEnvironment.production,
/// );
/// ```
class SDKAnalyticsInitializer {
  final SDKLogger _logger = SDKLogger(category: 'SDKAnalytics');

  // Initialized components
  TelemetryRepository? _telemetryRepository;
  TelemetrySyncService? _telemetrySyncService;

  /// Get the initialized TelemetryRepository
  TelemetryRepository? get telemetryRepository => _telemetryRepository;

  /// Get the initialized TelemetrySyncService
  TelemetrySyncService? get telemetrySyncService => _telemetrySyncService;

  /// Check if analytics has been initialized
  bool get isInitialized => _telemetryRepository != null;

  /// Initialize the analytics pipeline.
  ///
  /// This method:
  /// 1. Initializes LocalTelemetryDataSource (ensures DB is ready)
  /// 2. Creates RemoteTelemetryDataSource with the APIClient
  /// 3. Creates TelemetryRepository wrapping both data sources
  /// 4. Initializes AnalyticsQueueManager with the repository
  /// 5. Initializes EventPublisher with the queue manager
  /// 6. Starts TelemetrySyncService for periodic sync
  ///
  /// [apiClient] The API client for network requests (optional for dev mode)
  /// [environment] The SDK environment
  Future<void> initialize({
    APIClient? apiClient,
    required SDKEnvironment environment,
  }) async {
    if (isInitialized) {
      _logger.debug('Analytics already initialized');
      return;
    }

    _logger.info(
        'Initializing analytics pipeline for ${environment.description}...');

    try {
      // Step 1: Initialize local data source (ensures DB is ready)
      final localDataSource = LocalTelemetryDataSource.shared;
      await localDataSource.initialize();
      _logger.debug('LocalTelemetryDataSource initialized');

      // Step 2: Create remote data source
      final remoteDataSource = RemoteTelemetryDataSource(
        networkService: apiClient,
        environment: environment,
      );
      _logger.debug('RemoteTelemetryDataSource created');

      // Step 3: Create TelemetryRepository
      _telemetryRepository = TelemetryRepository(
        localDataSource: localDataSource,
        remoteDataSource: remoteDataSource,
      );
      await _telemetryRepository!.initialize();
      _logger.debug('TelemetryRepository initialized');

      // Step 4: Initialize AnalyticsQueueManager with repository
      AnalyticsQueueManager.shared.initialize(
        telemetryRepository: _telemetryRepository!,
      );
      _logger.debug('AnalyticsQueueManager initialized');

      // Step 5: Initialize EventPublisher with queue manager
      EventPublisher.shared.initialize(
        analyticsQueue: AnalyticsQueueManager.shared,
      );
      _logger.debug('EventPublisher initialized');

      // Step 6: Create and start TelemetrySyncService
      _telemetrySyncService = TelemetrySyncService(
        localDataSource: localDataSource,
        remoteDataSource: remoteDataSource,
      );
      _telemetrySyncService!.startSync();
      _logger.debug('TelemetrySyncService started');

      _logger.info('✅ Analytics pipeline initialized');
    } catch (e) {
      _logger.error('Failed to initialize analytics pipeline: $e');
      rethrow;
    }
  }

  /// Stop the analytics pipeline.
  ///
  /// Call this during SDK cleanup to stop the sync timer.
  void stop() {
    _telemetrySyncService?.stopSync();
    _logger.info('Analytics pipeline stopped');
  }

  /// Force sync all pending telemetry events.
  ///
  /// Useful for flushing events before app shutdown.
  Future<void> syncNow() async {
    await AnalyticsQueueManager.shared.flush();
    await _telemetrySyncService?.syncNow();
  }

  /// Dispose of the analytics pipeline.
  void dispose() {
    _telemetrySyncService?.dispose();
    AnalyticsQueueManager.shared.dispose();
    _logger.info('Analytics pipeline disposed');
  }
}
