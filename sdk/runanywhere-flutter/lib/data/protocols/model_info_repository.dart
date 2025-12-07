import 'dart:async';

import '../../public/models/models.dart';

/// Repository protocol for model information persistence
/// Matches iOS ModelInfoRepository from ModelInfoRepository.swift
abstract class ModelInfoRepository {
  /// Save a model info entity
  Future<void> save(ModelInfo entity);

  /// Fetch a model by id
  Future<ModelInfo?> fetch(String id);

  /// Fetch all models
  Future<List<ModelInfo>> fetchAll();

  /// Delete a model by id
  Future<void> delete(String id);

  /// Model-specific queries - fetch models by framework
  Future<List<ModelInfo>> fetchByFramework(LLMFramework framework);

  /// Model-specific queries - fetch models by category
  Future<List<ModelInfo>> fetchByCategory(ModelCategory category);

  /// Fetch downloaded models only
  Future<List<ModelInfo>> fetchDownloaded();

  /// Update download status for a model
  Future<void> updateDownloadStatus(String modelId, {String? localPath});

  /// Update last used timestamp for a model
  Future<void> updateLastUsed(String modelId);
}
