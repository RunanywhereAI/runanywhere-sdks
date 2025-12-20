//
//  model_info_repository.dart
//  RunAnywhere SDK
//
//  Repository facade for model info operations
//  Matches iOS SDK's ModelInfoRepositoryImpl.swift
//

import '../../../core/models/framework/llm_framework.dart';
import '../../../core/models/model/model_category.dart';
import '../../../core/models/model/model_info.dart';
import '../../../foundation/logging/sdk_logger.dart';
import '../data_sources/local_model_info_data_source.dart';
import '../data_sources/remote_model_info_data_source.dart';

/// Repository facade for model info operations
///
/// Wraps LocalModelInfoDataSource and RemoteModelInfoDataSource
/// to provide a unified API for model management.
class ModelInfoRepository {
  final SDKLogger _logger = SDKLogger(category: 'ModelInfoRepository');

  final LocalModelInfoDataSource _localDataSource;
  final RemoteModelInfoDataSource? _remoteDataSource;

  ModelInfoRepository({
    LocalModelInfoDataSource? localDataSource,
    RemoteModelInfoDataSource? remoteDataSource,
  })  : _localDataSource = localDataSource ?? LocalModelInfoDataSource.shared,
        _remoteDataSource = remoteDataSource;

  /// Get the remote data source for advanced operations
  RemoteModelInfoDataSource? get remoteDataSource => _remoteDataSource;

  // MARK: - Core CRUD Operations

  /// Save a model to local storage
  Future<void> save(ModelInfo model) async {
    await _localDataSource.store(model);
    _logger.debug('Saved model: ${model.id}');
  }

  /// Fetch a model by ID
  Future<ModelInfo?> fetch(String id) async {
    return await _localDataSource.load(id);
  }

  /// Fetch all models
  Future<List<ModelInfo>> fetchAll() async {
    return await _localDataSource.loadAll();
  }

  /// Delete a model by ID
  Future<bool> delete(String id) async {
    final deleted = await _localDataSource.remove(id);
    if (deleted) {
      _logger.debug('Deleted model: $id');
    }
    return deleted;
  }

  // MARK: - Model-specific Queries

  /// Fetch models by framework
  Future<List<ModelInfo>> fetchByFramework(LLMFramework framework) async {
    return await _localDataSource.findByFramework(framework);
  }

  /// Fetch models by category
  Future<List<ModelInfo>> fetchByCategory(ModelCategory category) async {
    return await _localDataSource.findByCategory(category);
  }

  /// Fetch downloaded models
  Future<List<ModelInfo>> fetchDownloaded() async {
    return await _localDataSource.findDownloaded();
  }

  // MARK: - Sync Support

  /// Fetch models pending sync
  Future<List<ModelInfo>> fetchPendingSync() async {
    return await _localDataSource.loadPendingSync();
  }

  /// Mark models as synced
  Future<void> markSynced(List<String> ids) async {
    await _localDataSource.markSynced(ids);
    _logger.debug('Marked ${ids.length} models as synced');
  }

  // MARK: - Update Operations

  /// Update download status for a model
  Future<void> updateDownloadStatus(String modelId, Uri? localPath) async {
    await _localDataSource.updateDownloadStatus(modelId, localPath);
    _logger.debug('Updated download status for model: $modelId');
  }

  /// Update last used timestamp for a model
  Future<void> updateLastUsed(String modelId) async {
    await _localDataSource.updateLastUsed(modelId);
    _logger.debug('Updated last used for model: $modelId');
  }

  // MARK: - Cleanup Operations

  /// Clear all models from local storage
  Future<int> clearAll() async {
    final count = await _localDataSource.clear();
    _logger.info('Cleared $count models from local storage');
    return count;
  }

  // MARK: - Storage Info

  /// Get storage information
  Future<int> getModelCount() async {
    final info = await _localDataSource.getStorageInfo();
    return info.entityCount;
  }
}
