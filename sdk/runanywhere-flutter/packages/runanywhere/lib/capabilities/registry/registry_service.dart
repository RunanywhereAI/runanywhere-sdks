import 'dart:async';
import 'dart:io';

import 'package:runanywhere/core/models/common.dart';
import 'package:runanywhere/core/protocols/registry/model_registry.dart';
import 'package:runanywhere/foundation/file_operations/model_path_utils.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';

// Re-export for backward compatibility
export '../../core/protocols/registry/model_registry.dart';

/// Implementation of model registry
/// Matches iOS RegistryService pattern with local file detection
class RegistryService implements ModelRegistry {
  final Map<String, ModelInfo> _models = {};
  final SDKLogger logger = SDKLogger(category: 'RegistryService');

  RegistryService() {
    logger.debug('Initializing RegistryService');
  }

  /// Initialize registry with configuration
  Future<void> initialize({String? apiKey}) async {
    logger.info('Initializing registry with configuration');

    // Load pre-configured models
    await loadPreconfiguredModels();

    logger.info('Registry initialization complete');
  }

  /// Refresh all models to detect downloaded files
  /// Should be called after all framework adapters are registered
  Future<void> refreshDownloadedModels() async {
    await refreshAllModelsLocalPaths();
  }

  /// Load pre-configured models
  Future<void> loadPreconfiguredModels() async {
    // Placeholder - models will be registered via registerModel
    logger.debug('Pre-configured models loaded');
  }

  @override
  Future<List<ModelInfo>> discoverModels() async {
    return List.from(_models.values);
  }

  @override
  ModelInfo? getModel(String id) {
    return _models[id];
  }

  /// Get model (async for backward compatibility)
  Future<ModelInfo?> getModelAsync({required String by}) async {
    return _models[by];
  }

  @override
  void registerModel(ModelInfo model) {
    // Validate model before registering
    if (model.id.isEmpty) {
      logger.error('Attempted to register model with empty ID');
      return;
    }

    // Register immediately (synchronously) to avoid race conditions
    // This ensures the model is available in _models right away
    logger.debug('Registering model: ${model.id} - ${model.name}');
    _models[model.id] = model;
    logger.info('Successfully registered model: ${model.id}');

    // Check if model file exists locally and update localPath asynchronously
    // This updates the localPath after the model is already registered
    unawaited(_checkAndUpdateLocalPath(model).then((updatedModel) {
      if (updatedModel.localPath != model.localPath) {
        _models[updatedModel.id] = updatedModel;
        logger.info(
            'Found local file for model ${updatedModel.id}: ${updatedModel.localPath}');
      }
    }));
  }

  /// Check if model file exists locally and update localPath
  /// Matches iOS RegistryService.resolveModelPath pattern
  Future<ModelInfo> _checkAndUpdateLocalPath(ModelInfo model) async {
    final framework =
        model.preferredFramework ?? model.compatibleFrameworks.firstOrNull;
    if (framework == null) {
      return model;
    }

    // If localPath is already set, verify it still exists
    if (model.localPath != null) {
      final path = model.localPath!.toFilePath();
      final file = File(path);
      final dir = Directory(path);

      if (await file.exists() || await dir.exists()) {
        return model;
      } else {
        logger.debug(
            'Model file no longer exists for ${model.id}, clearing localPath');
        return model.copyWith(localPath: null);
      }
    }

    // Get the model folder: Models/{framework}/{modelId}/
    final modelFolder = await ModelPathUtils.getModelFolder(
      modelId: model.id,
      framework: framework,
    );

    if (!await modelFolder.exists()) {
      return model;
    }

    // Resolve model path - matches iOS resolveModelPath(in: folderURL)
    final resolvedPath = await _resolveModelPath(modelFolder);
    if (resolvedPath == null) {
      return model;
    }

    logger.info('Found downloaded model ${model.id} at: $resolvedPath');
    return model.copyWith(localPath: resolvedPath);
  }

  /// Resolve actual model path within a folder
  /// Matches iOS: if folder has exactly 1 item, return it; otherwise return folder
  Future<Uri?> _resolveModelPath(Directory folder) async {
    try {
      final contents = await folder
          .list()
          .where((e) => !e.path.split('/').last.startsWith('.')) // Skip hidden
          .toList();

      if (contents.isEmpty) {
        return null;
      }

      // If exactly 1 item, return it (handles nested archives and single files)
      if (contents.length == 1) {
        final item = contents.first;
        if (item is File) {
          return Uri.file(item.path);
        } else if (item is Directory) {
          return Uri.directory(item.path);
        }
      }

      // Multiple items - return folder itself (directory-based models)
      return folder.uri;
    } catch (e) {
      logger.error('Error resolving model path: $e');
      return null;
    }
  }

  /// Register model and save to database for persistence
  Future<void> registerModelPersistently(ModelInfo model) async {
    registerModel(model);
    // TODO: Save to database
  }

  @override
  void updateModel(ModelInfo model) {
    if (_models.containsKey(model.id)) {
      // Update immediately (synchronously) to avoid race conditions
      _models[model.id] = model;
      logger.info('Updated model: ${model.id}');
      if (model.localPath != null) {
        logger.debug('Model ${model.id} has localPath: ${model.localPath}');
      }
    }
  }

  /// Refresh all registered models to check for downloaded files
  /// This should be called on SDK initialization to detect models downloaded in previous sessions
  /// Matches iOS pattern for detecting local models on launch
  Future<void> refreshAllModelsLocalPaths() async {
    logger.info('Refreshing local paths for all registered models...');
    final modelsToUpdate = <String, ModelInfo>{};

    for (final model in _models.values) {
      final updatedModel = await _checkAndUpdateLocalPath(model);
      if (updatedModel.localPath != model.localPath) {
        modelsToUpdate[updatedModel.id] = updatedModel;
      }
    }

    // Update all models that changed
    for (final entry in modelsToUpdate.entries) {
      _models[entry.key] = entry.value;
      logger.info(
          'Updated localPath for model ${entry.key}: ${entry.value.localPath?.toFilePath() ?? "none"}');
    }

    logger.info(
        'Refreshed ${modelsToUpdate.length} models with local file detection');
  }

  @override
  void removeModel(String id) {
    _models.remove(id);
    logger.info('Removed model: $id');
  }

  /// Add a model from a download URL
  /// Matches iOS addModelFromURL pattern
  ModelInfo addModelFromURL({
    String? id,
    required String name,
    required Uri url,
    required LLMFramework framework,
    ModelCategory category = ModelCategory.language,
    ModelArtifactType? artifactType,
    int? estimatedSize,
    bool supportsThinking = false,
  }) {
    // Generate ID from URL filename if not provided
    final modelId = id ?? _generateIdFromURL(url);

    // Infer format from URL if not provided
    final format = ModelFormat.fromFilename(url.pathSegments.last);

    // Create model info with artifact type
    final model = ModelInfo(
      id: modelId,
      name: name,
      downloadURL: url,
      format: format,
      category: category,
      artifactType: artifactType,
      compatibleFrameworks: [framework],
      preferredFramework: framework,
      downloadSize: estimatedSize,
      supportsThinking: supportsThinking,
    );

    // Register the model
    registerModel(model);

    logger.info('Added model from URL: $modelId');
    return model;
  }

  /// Generate a stable ID from URL filename
  String _generateIdFromURL(Uri url) {
    final filename = url.pathSegments.last;
    // Remove extension to get base name
    final dotIndex = filename.lastIndexOf('.');
    if (dotIndex > 0) {
      return filename.substring(0, dotIndex);
    }
    return filename;
  }

  /// Get models filtered by framework
  List<ModelInfo> getModelsForFramework(LLMFramework framework) {
    return _models.values
        .where((m) => m.compatibleFrameworks.contains(framework))
        .toList();
  }

  /// Get models filtered by category
  List<ModelInfo> getModelsForCategory(ModelCategory category) {
    return _models.values.where((m) => m.category == category).toList();
  }

  /// Clear model assignments cache
  void clearCache() {
    // For now, we don't have a separate cache - this is a no-op
    // In a full implementation, this would clear any cached assignments from backend
    logger.info('Cleared model assignments cache');
  }

  @override
  List<ModelInfo> filterModels(ModelCriteria criteria) {
    if (!criteria.hasFilters) {
      return List.from(_models.values);
    }

    return _models.values.where((model) {
      // Framework filter
      if (criteria.framework != null &&
          !model.compatibleFrameworks.contains(criteria.framework)) {
        return false;
      }

      // Format filter
      if (criteria.format != null && model.format != criteria.format) {
        return false;
      }

      // Size filter
      if (criteria.maxSize != null &&
          model.downloadSize != null &&
          model.downloadSize! > criteria.maxSize!) {
        return false;
      }

      // Context length filters
      if (criteria.minContextLength != null &&
          model.contextLength != null &&
          model.contextLength! < criteria.minContextLength!) {
        return false;
      }
      if (criteria.maxContextLength != null &&
          model.contextLength != null &&
          model.contextLength! > criteria.maxContextLength!) {
        return false;
      }

      // Search filter (name contains search term)
      if (criteria.search != null &&
          !model.name.toLowerCase().contains(criteria.search!.toLowerCase())) {
        return false;
      }

      return true;
    }).toList();
  }
}
