//
//  remote_model_info_data_source.dart
//  RunAnywhere SDK
//
//  Remote data source for syncing model info with backend
//  Matches iOS SDK's RemoteModelInfoDataSource.swift
//

import '../../../core/models/model/model_info.dart';
import '../../../data/network/api_client.dart';
import '../../../data/network/api_endpoint.dart';
import '../../../foundation/logging/sdk_logger.dart';

/// Remote data source for syncing model info with backend
class RemoteModelInfoDataSource {
  final SDKLogger _logger = SDKLogger(category: 'RemoteModelInfoDataSource');
  final APIClient _apiClient;

  RemoteModelInfoDataSource({
    required APIClient apiClient,
  }) : _apiClient = apiClient;

  /// Check if the remote data source is available
  Future<bool> isAvailable() async {
    try {
      // Check if we can reach the server
      await _apiClient.get<Map<String, dynamic>>(
        APIEndpoint.healthCheck,
        requiresAuth: false,
        fromJson: (json) => json,
      );
      return true;
    } catch (e) {
      _logger.debug('Remote data source not available: $e');
      return false;
    }
  }

  /// Validate configuration
  Future<void> validateConfiguration() async {
    // API client handles its own configuration validation
  }

  /// Test connection to remote
  Future<bool> testConnection() async {
    return await isAvailable();
  }

  // MARK: - Sync Operations

  /// Sync a batch of models to the backend
  ///
  /// Returns list of successfully synced model IDs
  Future<List<String>> syncBatch(List<ModelInfo> batch) async {
    if (batch.isEmpty) return [];

    final List<String> syncedIds = [];

    for (final model in batch) {
      try {
        await _apiClient.post<Map<String, dynamic>>(
          APIEndpoint.models,
          model.toJson(),
          requiresAuth: true,
          fromJson: (json) => json,
        );

        syncedIds.add(model.id);
        _logger.debug('Synced model: ${model.id}');
      } catch (e) {
        _logger.error('Failed to sync model ${model.id}: $e');
        // Continue with remaining models
      }
    }

    _logger.info('Synced ${syncedIds.length} of ${batch.length} models');
    return syncedIds;
  }

  /// Fetch a single model from remote
  ///
  /// Note: This is typically handled by ModelAssignmentService
  Future<ModelInfo?> fetch(String id) async {
    try {
      final response = await _apiClient.getWithPath<Map<String, dynamic>>(
        '${APIEndpoint.models.path}/$id',
        requiresAuth: true,
        fromJson: (json) => json,
      );

      return ModelInfo.fromJson(response);
    } catch (e) {
      _logger.error('Failed to fetch model $id: $e');
      return null;
    }
  }

  /// Fetch all models from remote
  ///
  /// Note: This is typically handled by ModelAssignmentService
  Future<List<ModelInfo>> fetchAll({Map<String, dynamic>? params}) async {
    try {
      final response = await _apiClient.get<List<dynamic>>(
        APIEndpoint.models,
        requiresAuth: true,
        fromJson: (json) => json as List<dynamic>,
      );

      return response
          .map((m) => ModelInfo.fromJson(m as Map<String, dynamic>))
          .toList();
    } catch (e) {
      _logger.error('Failed to fetch all models: $e');
      return [];
    }
  }

  /// Save a model to remote
  Future<ModelInfo?> save(ModelInfo entity) async {
    try {
      final response = await _apiClient.post<Map<String, dynamic>>(
        APIEndpoint.models,
        entity.toJson(),
        requiresAuth: true,
        fromJson: (json) => json,
      );

      return ModelInfo.fromJson(response);
    } catch (e) {
      _logger.error('Failed to save model ${entity.id}: $e');
      return null;
    }
  }

  /// Delete a model from remote
  ///
  /// Note: DELETE operations are not currently supported by the NetworkService.
  /// This is a placeholder for future implementation.
  Future<void> delete(String id) async {
    _logger.warning('Delete operation not implemented for remote models');
    // Delete operations would require adding DELETE method to APIClient
    // For now, we just log and return
  }
}
