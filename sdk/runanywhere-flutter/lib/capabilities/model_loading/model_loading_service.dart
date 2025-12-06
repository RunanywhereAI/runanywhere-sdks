import 'dart:async';
import 'models/loaded_model.dart';
import '../registry/registry_service.dart';
import '../memory/memory_service.dart';
import '../../foundation/logging/sdk_logger.dart';
import '../../foundation/error_types/sdk_error.dart';
import '../../core/service_registry/unified_service_registry.dart';
import '../../core/models/framework/framework_modality.dart';
import '../../core/model_lifecycle_manager.dart';
import '../../core/module_registry.dart';

/// Service responsible for loading models
/// Ensures thread-safe access and prevents concurrent duplicate loads
/// Matches iOS ModelLoadingService from Capabilities/ModelLoading/Services/ModelLoadingService.swift
class ModelLoadingService {
  final ModelRegistry registry;
  final UnifiedServiceRegistry adapterRegistry;
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
      logger.info(
          '⏳ Model load already in progress, awaiting existing task: $modelId');
      return await _inflightLoads[modelId]!;
    }

    // Create a new loading task
    final loadTask = _performLoad(modelId);

    // Store the task to prevent duplicate loads
    _inflightLoads[modelId] = loadTask;

    // Ensure task is removed when complete
    loadTask.whenComplete(() {
      _inflightLoads.remove(modelId);
    });

    return await loadTask;
  }

  /// Perform the actual model loading
  Future<LoadedModel> _performLoad(String modelId) async {
    final startTime = DateTime.now();

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

    // Check if this is a built-in model
    final isBuiltIn = modelInfo.localPath?.scheme == 'builtin';

    if (!isBuiltIn) {
      // Check model file exists for non-built-in models
      if (modelInfo.localPath == null) {
        throw SDKError.modelNotFound("Model '$modelId' not downloaded");
      }
    } else {
      logger.info('🏗️ Built-in model detected, skipping file check');
    }

    // ModelLoadingService handles LLM models only
    if (modelInfo.category.rawValue == 'speech-recognition' ||
        modelInfo.preferredFramework?.rawValue == 'WhisperKit') {
      logger.error('❌ Cannot load STT model through ModelLoadingService');
      throw SDKError.modelLoadFailed(
        modelId,
        "Model '$modelId' is a speech recognition model. STT models are loaded automatically through STTComponent.",
      );
    }

    // Check memory availability
    final memoryRequired =
        modelInfo.memoryRequired ?? 1024 * 1024 * 1024; // Default 1GB
    final canAllocate = await memoryService.canAllocate(memoryRequired);
    if (!canAllocate) {
      logger.warning(
          'Memory might be insufficient: ${memoryRequired ~/ (1024 * 1024)}MB required');
    }

    // Get framework and model name for lifecycle tracking
    final framework = modelInfo.preferredFramework;
    final modelName = modelInfo.name;

    // Notify lifecycle manager
    ModelLifecycleTracker.shared.modelWillLoad(
      modelId: modelId,
      modelName: modelName,
      framework: framework!,
      modality: Modality.llm,
    );

    // ModelLoadingService handles LLMs only; constrain to text-to-text modality
    const modality = FrameworkModality.textToText;

    // Find all adapters that can handle this model via UnifiedServiceRegistry
    logger.info('🚀 Finding adapters for model (modality: $modality)');
    final adapters = adapterRegistry.findAllAdapters(
      model: modelInfo,
      modality: modality,
    );

    // Fallback to ModuleRegistry if no unified adapters found
    if (adapters.isEmpty) {
      logger.info('Falling back to ModuleRegistry for LLM provider');
      final provider = ModuleRegistry.shared.llmProvider(modelId: modelId);
      if (provider == null) {
        logger.error(
            '❌ No adapter found for model with preferred framework: ${modelInfo.preferredFramework?.rawValue ?? "none"}');
        logger.error(
            '❌ Compatible frameworks: ${modelInfo.compatibleFrameworks.map((f) => f.rawValue).toList()}');

        ModelLifecycleTracker.shared.modelLoadFailed(
          modelId: modelId,
          modality: Modality.llm,
          error: 'No adapter found for model',
        );

        throw SDKError.featureNotAvailable(
            'No LLM provider available for model: $modelId');
      }

      logger.info('✅ Found adapter: ${provider.name}');

      try {
        // Create LLM configuration
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

        final loadTimeMs = DateTime.now().difference(startTime).inMilliseconds;

        // Notify lifecycle manager of successful load
        ModelLifecycleTracker.shared.modelDidLoad(
          modelId: modelId,
          modelName: modelName,
          framework: framework,
          modality: Modality.llm,
          memoryUsage: modelInfo.memoryRequired,
          llmService: service,
        );

        logger.info('✅ Model loaded successfully in ${loadTimeMs}ms');
        return loaded;
      } catch (e) {
        final loadTimeMs = DateTime.now().difference(startTime).inMilliseconds;

        ModelLifecycleTracker.shared.modelLoadFailed(
          modelId: modelId,
          modality: Modality.llm,
          error: e.toString(),
        );

        logger.error('❌ Failed to load model after ${loadTimeMs}ms: $e');
        throw SDKError.modelLoadFailed(modelId, e);
      }
    }

    logger.info(
        '✅ Found ${adapters.length} adapter(s) capable of loading this model');

    // Try to load with each adapter (primary + fallbacks)
    Object? lastError;
    for (var index = 0; index < adapters.length; index++) {
      final adapter = adapters[index];
      final isPrimary = index == 0;
      logger.info(isPrimary
          ? '🚀 Trying primary adapter: ${adapter.framework.rawValue}'
          : '🔄 Trying fallback adapter: ${adapter.framework.rawValue}');

      try {
        final service = await adapter.loadModel(modelInfo, modality);
        logger.info(
            '✅ Model loaded successfully with ${adapter.framework.rawValue}');

        // Cast to LLMService (by construction: text-to-text modality)
        if (service is! LLMService) {
          throw SDKError.modelLoadFailed(
            modelId,
            "Adapter '${adapter.framework.rawValue}' did not return an LLMService for text-to-text modality",
          );
        }

        // Create loaded model
        final loaded = LoadedModel(
          model: modelInfo,
          service: service,
        );

        // Register loaded model
        _loadedModels[modelId] = loaded;

        final loadTimeMs = DateTime.now().difference(startTime).inMilliseconds;

        // Notify lifecycle manager of successful load
        ModelLifecycleTracker.shared.modelDidLoad(
          modelId: modelId,
          modelName: modelName,
          framework: adapter.framework,
          modality: Modality.llm,
          memoryUsage: modelInfo.memoryRequired,
          llmService: service,
        );

        logger.info('✅ Model loaded successfully in ${loadTimeMs}ms');
        return loaded;
      } catch (e) {
        logger.error(
            '❌ Failed to load model with ${adapter.framework.rawValue}: $e');
        lastError = e;
        // Continue to next adapter
      }
    }

    // All adapters failed
    logger.error('❌ All adapters failed to load model');

    ModelLifecycleTracker.shared.modelLoadFailed(
      modelId: modelId,
      modality: Modality.llm,
      error: lastError?.toString() ??
          'Failed to load model with any available adapter',
    );

    throw lastError ??
        SDKError.modelLoadFailed(
            modelId, 'Failed to load model with any available adapter');
  }

  /// Unload a model
  Future<void> unloadModel(String modelId) async {
    final loaded = _loadedModels[modelId];
    if (loaded == null) {
      return;
    }

    ModelLifecycleTracker.shared.modelWillUnload(
      modelId: modelId,
      modality: Modality.llm,
    );

    // Unload through service
    await loaded.service.cleanup();

    // Remove from loaded models
    _loadedModels.remove(modelId);

    ModelLifecycleTracker.shared.modelDidUnload(
      modelId: modelId,
      modality: Modality.llm,
    );

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
