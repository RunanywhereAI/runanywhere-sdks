import 'dart:async';
import 'models/loaded_model.dart';
import '../registry/registry_service.dart';
import '../memory/memory_service.dart';
import '../../foundation/logging/sdk_logger.dart';
import '../../foundation/error_types/sdk_error.dart';
import '../../foundation/dependency_injection/service_container.dart' show AdapterRegistry;
import '../../core/module_registry.dart';

/// Service responsible for loading models
/// Ensures thread-safe access and prevents concurrent duplicate loads
class ModelLoadingService {
  final ModelRegistry registry;
  final AdapterRegistry adapterRegistry;
  final MemoryService memoryService;
  final SDKLogger logger = SDKLogger(category: 'ModelLoadingService');

  final Map<String, LoadedModel> _loadedModels = {};
  final Map<String, Future<LoadedModel>> _inflightLoads = {};

  ModelLoadingService({
    required this.registry,
    required this.adapterRegistry,
    required this.memoryService,
  });

  /// Load a model by identifier
  /// Concurrent calls for the same model will be deduplicated
  Future<LoadedModel> loadModel(String modelId) async {
    logger.info('🚀 Loading model: $modelId');

    // Check if already loaded
    if (_loadedModels.containsKey(modelId)) {
      logger.info('✅ Model already loaded: $modelId');
      return _loadedModels[modelId]!;
    }

    // Check if a load is already in progress
    if (_inflightLoads.containsKey(modelId)) {
      logger.info('⏳ Model load already in progress, awaiting existing task: $modelId');
      return await _inflightLoads[modelId]!;
    }

    // Create a new loading task
    final loadTask = _performLoad(modelId);

    // Store the task to prevent duplicate loads
    _inflightLoads[modelId] = loadTask;

    // Ensure task is removed when complete (fire-and-forget)
    unawaited(loadTask.whenComplete(() {
      _inflightLoads.remove(modelId);
    }));

    return await loadTask;
  }

  /// Perform the actual model loading
  Future<LoadedModel> _performLoad(String modelId) async {
    // Double-check if loaded while we were waiting
    if (_loadedModels.containsKey(modelId)) {
      logger.info('✅ Model loaded by another task: $modelId');
      return _loadedModels[modelId]!;
    }

    // Get model info from registry
    final modelInfo = registry.getModel(modelId);
    if (modelInfo == null) {
      logger.error('❌ Model not found in registry: $modelId');
      throw SDKError.modelNotFound(modelId);
    }

    logger.info('✅ Found model in registry: ${modelInfo.name}');

    // Check if model file exists for non-built-in models
    if (modelInfo.localPath == null && !modelInfo.id.startsWith('builtin:')) {
      throw SDKError.modelNotFound("Model '$modelId' not downloaded");
    }

    // Check memory availability (memoryRequired is nullable now)
    final memoryNeeded = modelInfo.memoryRequired;
    if (memoryNeeded != null) {
      final canAllocate = await memoryService.canAllocate(memoryNeeded);
      if (!canAllocate) {
        logger.warning('Memory might be insufficient: ${memoryNeeded ~/ (1024 * 1024)}MB required');
      }
    }

    // Find adapter that can handle this model
    logger.info('🚀 Finding adapter for model');
    final provider = ModuleRegistry.shared.llmProvider(modelId: modelId);
    if (provider == null) {
      logger.error('❌ No adapter found for model');
      throw SDKError.featureNotAvailable('No LLM provider available for model: $modelId');
    }

    logger.info('✅ Found adapter: ${provider.name}');

    try {
      // Create LLM configuration using model's context length if available
      final config = LLMConfiguration(
        modelId: modelId,
        contextLength: modelInfo.contextLength ?? 2048,
        useGPUIfAvailable: true,
      );

      // Create service via provider
      final service = await provider.createLLMService(config);

      // Create loaded model
      final loaded = LoadedModel(
        model: modelInfo,
        service: service,
      );

      // Register loaded model
      _loadedModels[modelId] = loaded;

      logger.info('✅ Model loaded successfully');
      return loaded;
    } catch (e) {
      logger.error('❌ Failed to load model: $e');
      throw SDKError.modelLoadFailed(modelId, e);
    }
  }

  /// Unload a model
  Future<void> unloadModel(String modelId) async {
    final loaded = _loadedModels[modelId];
    if (loaded == null) {
      return;
    }

    // Unload through service
    await loaded.service.cleanup();

    // Remove from loaded models
    _loadedModels.remove(modelId);

    logger.info('✅ Model unloaded: $modelId');
  }

  /// Get currently loaded model
  LoadedModel? getLoadedModel(String modelId) {
    return _loadedModels[modelId];
  }
}

// Placeholder for LLMConfiguration
class LLMConfiguration {
  final String? modelId;
  final int contextLength;
  final bool useGPUIfAvailable;
  final String? quantizationLevel;

  LLMConfiguration({
    this.modelId,
    this.contextLength = 2048,
    this.useGPUIfAvailable = true,
    this.quantizationLevel,
  });
}
