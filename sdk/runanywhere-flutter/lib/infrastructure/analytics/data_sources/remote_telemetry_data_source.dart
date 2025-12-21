//
//  remote_telemetry_data_source.dart
//  RunAnywhere SDK
//
//  Remote data source for sending telemetry data to API server.
//  Matches iOS RemoteTelemetryDataSource.swift exactly.
//

import 'dart:async';

import '../../../data/network/api_endpoint.dart';
import '../../../data/network/network_service.dart';
import '../../../foundation/logging/sdk_logger.dart';
import '../../../public/configuration/sdk_environment.dart';
import '../../device/services/device_identity.dart';
import '../models/domain/telemetry_data.dart';
import '../models/output/telemetry_batch_models.dart';
import '../models/output/telemetry_event_payload.dart';
import 'local_telemetry_data_source.dart';

/// Remote data source for sending telemetry data to API server.
/// Routes to correct analytics endpoint based on environment.
class RemoteTelemetryDataSource {
  final NetworkService? _networkService;
  final SDKEnvironment _environment;
  final SDKLogger _logger = SDKLogger(category: 'RemoteTelemetryDataSource');

  RemoteTelemetryDataSource({
    NetworkService? networkService,
    SDKEnvironment environment = SDKEnvironment.development,
  })  : _networkService = networkService,
        _environment = environment;

  // MARK: - DataSource Protocol

  /// Check if the data source is available
  Future<bool> isAvailable() async {
    if (_networkService == null) {
      return false;
    }

    // Telemetry should work even if connection test fails
    // We'll queue events locally
    return true;
  }

  /// Validate configuration
  Future<void> validateConfiguration() async {
    if (_networkService == null) {
      throw const DataSourceException(
        DataSourceError.storageUnavailable,
        message: 'API client not configured',
      );
    }
  }

  // MARK: - Sync Support

  /// Sync a batch of telemetry events, returns list of synced event IDs
  Future<List<String>> syncBatch(List<TelemetryData> batch) async {
    if (_networkService == null) {
      throw const DataSourceException(
        DataSourceError.storageUnavailable,
        message: 'Network service not available',
      );
    }

    final syncedIds = <String>[];

    // Convert TelemetryData to typed TelemetryEventPayload for API transmission
    final typedEvents =
        batch.map((e) => TelemetryEventPayload.fromTelemetryData(e)).toList();

    final deviceId = await DeviceIdentity.persistentUUID;
    final batchRequest = TelemetryBatchRequest(
      events: typedEvents,
      deviceId: deviceId,
      timestamp: DateTime.now(),
    );

    try {
      // POST typed batch to analytics endpoint based on environment
      final endpoint = APIEndpointEnvironment.analyticsEndpoint(_environment);

      final response = await _networkService!.post<TelemetryBatchResponse>(
        endpoint,
        batchRequest.toJson(),
        requiresAuth: _environment != SDKEnvironment.development,
        fromJson: TelemetryBatchResponse.fromJson,
      );

      if (response.success) {
        syncedIds.addAll(batch.map((e) => e.id));
      } else {
        // Still mark as synced to avoid infinite retries
        syncedIds.addAll(batch.map((e) => e.id));
      }
    } catch (e) {
      _logger.error('Failed to sync telemetry batch: $e');
    }

    return syncedIds;
  }

  /// Test connection to telemetry endpoint
  Future<bool> testConnection() async {
    if (_networkService == null) {
      return false;
    }

    try {
      // Assume available for telemetry - actual test would call health endpoint
      return true;
    } catch (_) {
      return false;
    }
  }

  // MARK: - Telemetry-specific methods

  /// Send batch of telemetry events (immediate send, no local storage)
  Future<void> sendBatch(List<TelemetryData> events) async {
    if (_networkService == null) {
      throw const DataSourceException(
        DataSourceError.storageUnavailable,
        message: 'Network service not available',
      );
    }

    if (events.isEmpty) {
      return;
    }

    // Convert to typed payloads
    final typedEvents =
        events.map((e) => TelemetryEventPayload.fromTelemetryData(e)).toList();

    final deviceId = await DeviceIdentity.persistentUUID;
    final batchRequest = TelemetryBatchRequest(
      events: typedEvents,
      deviceId: deviceId,
      timestamp: DateTime.now(),
    );

    // Use analytics endpoint based on environment
    final endpoint = APIEndpointEnvironment.analyticsEndpoint(_environment);

    final response = await _networkService!.post<TelemetryBatchResponse>(
      endpoint,
      batchRequest.toJson(),
      requiresAuth: _environment != SDKEnvironment.development,
      fromJson: TelemetryBatchResponse.fromJson,
    );

    if (!response.success) {
      _logger.warning(
          'Telemetry send partial failure: ${response.errors?.join(', ') ?? 'unknown'}');
    }
  }
}
