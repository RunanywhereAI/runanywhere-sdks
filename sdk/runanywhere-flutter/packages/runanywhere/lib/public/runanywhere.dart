import 'dart:async';

import 'package:runanywhere/core/module_registry.dart' as registry;
import 'package:runanywhere/core/module_registry.dart'
    show ModuleRegistry, LLMService;
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/core/types/storage_types.dart';
import 'package:runanywhere/core/models/framework/llm_framework.dart';
import 'package:runanywhere/foundation/configuration/sdk_constants.dart';
import 'package:runanywhere/foundation/dependency_injection/service_container.dart'
    hide SDKInitParams;
import 'package:runanywhere/foundation/error_types/sdk_error.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/infrastructure/download/download_service.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';

// ============================================================================
// Message Role
// ============================================================================

/// Role of a message in a conversation
enum MessageRole {
  system,
  user,
  assistant;

  String get rawValue => name;
}

// ============================================================================
// LLM Generation Types
// ============================================================================

/// Options for LLM text generation
/// Matches Swift's LLMGenerationOptions
class LLMGenerationOptions {
  final int maxTokens;
  final double temperature;
  final double topP;
  final List<String> stopSequences;
  final bool streamingEnabled;
  final InferenceFramework? preferredFramework;
  final String? systemPrompt;

  const LLMGenerationOptions({
    this.maxTokens = 100,
    this.temperature = 0.8,
    this.topP = 1.0,
    this.stopSequences = const [],
    this.streamingEnabled = false,
    this.preferredFramework,
    this.systemPrompt,
  });
}

/// Result of LLM text generation
/// Matches Swift's LLMGenerationResult
class LLMGenerationResult {
  final String text;
  final String? thinkingContent;
  final int inputTokens;
  final int tokensUsed;
  final String modelUsed;
  final double latencyMs;
  final String? framework;
  final double tokensPerSecond;
  final double? timeToFirstTokenMs;
  final int thinkingTokens;
  final int responseTokens;

  const LLMGenerationResult({
    required this.text,
    this.thinkingContent,
    required this.inputTokens,
    required this.tokensUsed,
    required this.modelUsed,
    required this.latencyMs,
    this.framework,
    required this.tokensPerSecond,
    this.timeToFirstTokenMs,
    this.thinkingTokens = 0,
    this.responseTokens = 0,
  });
}

/// Result of streaming LLM text generation
/// Matches Swift's LLMStreamingResult
class LLMStreamingResult {
  final Stream<String> stream;
  final Future<LLMGenerationResult> result;

  const LLMStreamingResult({
    required this.stream,
    required this.result,
  });
}

// ============================================================================
// Capability Classes - Metadata about loaded STT/TTS capabilities
// ============================================================================

/// Speech-to-Text capability information
class STTCapability {
  final String modelId;
  final String? modelName;

  const STTCapability({
    required this.modelId,
    this.modelName,
  });
}

/// Text-to-Speech capability information
class TTSCapability {
  final String voiceId;
  final String? voiceName;

  const TTSCapability({
    required this.voiceId,
    this.voiceName,
  });
}

// ============================================================================
// Download Progress
// ============================================================================

/// Download progress information
/// Matches Swift `DownloadProgress`.
class DownloadProgress {
  final int bytesDownloaded;
  final int totalBytes;
  final DownloadProgressState state;
  final DownloadProgressStage stage;

  const DownloadProgress({
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.state,
    this.stage = DownloadProgressStage.downloading,
  });

  /// Overall progress from 0.0 to 1.0
  double get overallProgress =>
      totalBytes > 0 ? bytesDownloaded / totalBytes : 0.0;

  /// Legacy alias for overallProgress
  double get percentage => overallProgress;
}

/// Download progress state
enum DownloadProgressState {
  downloading,
  completed,
  failed,
  cancelled;

  bool get isCompleted => this == DownloadProgressState.completed;
  bool get isFailed => this == DownloadProgressState.failed;
}

/// Download progress stage (more detailed than state)
enum DownloadProgressStage {
  queued,
  downloading,
  extracting,
  verifying,
  completed,
  failed,
  cancelled,
}

/// Supabase configuration for development mode
class SupabaseConfig {
  final Uri projectURL;
  final String anonKey;

  const SupabaseConfig({
    required this.projectURL,
    required this.anonKey,
  });
}

/// The RunAnywhere SDK entry point
///
/// Matches Swift `RunAnywhere` enum from Public/RunAnywhere.swift
class RunAnywhere {
  static SDKInitParams? _initParams;
  static SDKEnvironment? _currentEnvironment;
  static bool _isInitialized = false;
  static final List<ModelInfo> _registeredModels = [];

  // Callbacks to collect models from registered modules
  static final List<List<ModelInfo> Function()> _modelCollectors = [];

  /// Access to service container
  static ServiceContainer get serviceContainer => ServiceContainer.shared;

  /// Check if SDK is initialized
  static bool get isSDKInitialized => _isInitialized;

  /// Check if SDK is active
  static bool get isActive => _isInitialized && _initParams != null;

  /// Get initialization parameters
  static SDKInitParams? get initParams => _initParams;

  /// Current environment
  static SDKEnvironment? get environment => _currentEnvironment;

  /// Get current environment (alias for environment getter)
  /// Matches Swift pattern for explicit method call
  static SDKEnvironment? getCurrentEnvironment() => _currentEnvironment;

  /// SDK version
  static String get version => SDKConstants.version;

  /// Event bus for SDK events
  static EventBus get events => EventBus.shared;

  /// Initialize the SDK
  static Future<void> initialize({
    String? apiKey,
    String? baseURL,
    SDKEnvironment environment = SDKEnvironment.development,
  }) async {
    final SDKInitParams params;

    if (environment == SDKEnvironment.development) {
      params = SDKInitParams(
        apiKey: apiKey ?? '',
        baseURL: Uri.parse(baseURL ?? 'https://api.runanywhere.ai'),
        environment: environment,
      );
    } else {
      if (apiKey == null || apiKey.isEmpty) {
        throw SDKError.validationFailed(
          'API key is required for ${environment.description} mode',
        );
      }
      if (baseURL == null || baseURL.isEmpty) {
        throw SDKError.validationFailed(
          'Base URL is required for ${environment.description} mode',
        );
      }
      final uri = Uri.tryParse(baseURL);
      if (uri == null) {
        throw SDKError.validationFailed('Invalid base URL: $baseURL');
      }
      params = SDKInitParams(
        apiKey: apiKey,
        baseURL: uri,
        environment: environment,
      );
    }

    await initializeWithParams(params);
  }

  /// Initialize with params
  static Future<void> initializeWithParams(SDKInitParams params) async {
    if (_isInitialized) return;

    final logger = SDKLogger('RunAnywhere.Init');
    EventBus.shared.publish(SDKInitializationStarted());

    try {
      _currentEnvironment = params.environment;
      _initParams = params;

      await serviceContainer.setupLocalServices(
        apiKey: params.apiKey,
        baseURL: params.baseURL,
        environment: params.environment,
      );

      _isInitialized = true;
      logger.info('✅ SDK initialized (${params.environment.description})');
      EventBus.shared.publish(SDKInitializationCompleted());
    } catch (e) {
      logger.error('❌ SDK initialization failed: $e');
      _initParams = null;
      _currentEnvironment = null;
      _isInitialized = false;
      EventBus.shared.publish(SDKInitializationFailed(e));
      rethrow;
    }
  }

  /// Get available models
  ///
  /// Returns all models registered via:
  /// - `registerModel()` / `registerModelWithURL()` on RunAnywhere
  /// - `addModel()` on module classes (LlamaCpp, Onnx, etc.)
  /// - Module collectors registered via `registerModelCollector()`
  static Future<List<ModelInfo>> availableModels() async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    // Collect models from all sources
    final allModels = <ModelInfo>[..._registeredModels];

    // Collect from registered module collectors
    for (final collector in _modelCollectors) {
      try {
        allModels.addAll(collector());
      } catch (e) {
        SDKLogger('RunAnywhere').warning('Model collector failed: $e');
      }
    }

    // Remove duplicates by ID
    final uniqueModels = <String, ModelInfo>{};
    for (final model in allModels) {
      uniqueModels[model.id] = model;
    }

    return List.unmodifiable(uniqueModels.values.toList());
  }

  /// Register a model collector callback from a module
  ///
  /// Modules can call this to register their model list getter so that
  /// `availableModels()` includes models from all registered modules.
  static void registerModelCollector(List<ModelInfo> Function() collector) {
    _modelCollectors.add(collector);
  }

  /// Get currently loaded model
  static ModelInfo? get currentModel => null;

  /// Get loaded STT capability (null if no STT model is loaded)
  static STTCapability? get loadedSTTCapability => null;

  /// Get loaded TTS capability (null if no TTS voice is loaded)
  static TTSCapability? get loadedTTSCapability => null;

  /// Load a model by ID
  static Future<void> loadModel(String modelId) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }
    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: modelId));
    EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: modelId));
  }

  /// Load an STT model
  static Future<void> loadSTTModel(String modelId) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }
    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: modelId));
    EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: modelId));
  }

  /// Load a TTS voice
  static Future<void> loadTTSVoice(String voiceId) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }
    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: voiceId));
    EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: voiceId));
  }

  /// Unload current model
  static Future<void> unloadModel() async {
    if (!_isInitialized) return;
  }

  // ============================================================================
  // Text Generation (LLM)
  // ============================================================================

  /// Simple text generation - returns only the generated text
  ///
  /// Matches Swift `RunAnywhere.chat(_:)`.
  ///
  /// ```dart
  /// final response = await RunAnywhere.chat('Hello, world!');
  /// print(response);
  /// ```
  static Future<String> chat(String prompt) async {
    final result = await generate(prompt);
    return result.text;
  }

  /// Full text generation with metrics
  ///
  /// Matches Swift `RunAnywhere.generate(_:options:)`.
  ///
  /// ```dart
  /// final result = await RunAnywhere.generate(
  ///   'Explain quantum computing',
  ///   options: LLMGenerationOptions(maxTokens: 200, temperature: 0.7),
  /// );
  /// print('Response: ${result.text}');
  /// print('Latency: ${result.latencyMs}ms');
  /// ```
  static Future<LLMGenerationResult> generate(
    String prompt, {
    LLMGenerationOptions? options,
  }) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    final opts = options ?? const LLMGenerationOptions();
    final startTime = DateTime.now();

    // Get the LLM provider from ModuleRegistry
    final provider = ModuleRegistry.shared.llmProvider();
    if (provider == null) {
      throw SDKError.componentNotReady(
        'No LLM provider available. Register a module first (e.g., LlamaCpp.register())',
      );
    }

    // Create and use the LLM service
    final llmService = await provider.createLLMService(null);
    _activeLLMService = llmService;

    if (!llmService.isReady) {
      throw SDKError.componentNotReady(
        'LLM service is not ready. Load a model first.',
      );
    }

    try {
      // Convert public LLMGenerationOptions to module registry LLMGenerationOptions
      final moduleOpts = registry.LLMGenerationOptions(
        maxTokens: opts.maxTokens,
        temperature: opts.temperature,
        topP: opts.topP,
        stopSequences: opts.stopSequences,
        streamingEnabled: opts.streamingEnabled,
        systemPrompt: opts.systemPrompt,
        preferredFramework: opts.preferredFramework,
      );

      final result = await llmService.generate(
        prompt: prompt,
        options: moduleOpts,
      );

      final endTime = DateTime.now();
      final latencyMs = endTime.difference(startTime).inMicroseconds / 1000.0;

      return LLMGenerationResult(
        text: result.text,
        inputTokens: result.inputTokens,
        tokensUsed: result.tokensUsed,
        modelUsed: result.modelUsed,
        latencyMs: latencyMs,
        framework: result.framework,
        tokensPerSecond: result.tokensPerSecond,
      );
    } catch (e) {
      throw SDKError.generationFailed('$e');
    }
  }

  /// Streaming text generation
  ///
  /// Matches Swift `RunAnywhere.generateStream(_:options:)`.
  ///
  /// ```dart
  /// final result = await RunAnywhere.generateStream('Tell me a story');
  /// await for (final token in result.stream) {
  ///   print(token);
  /// }
  /// final metrics = await result.result;
  /// print('Tokens: ${metrics.tokensUsed}');
  /// ```
  static Future<LLMStreamingResult> generateStream(
    String prompt, {
    LLMGenerationOptions? options,
  }) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    final opts = options ?? const LLMGenerationOptions();
    final startTime = DateTime.now();

    // Get the LLM provider from ModuleRegistry
    final provider = ModuleRegistry.shared.llmProvider();
    if (provider == null) {
      throw SDKError.componentNotReady(
        'No LLM provider available. Register a module first (e.g., LlamaCpp.register())',
      );
    }

    // Create and use the LLM service
    final llmService = await provider.createLLMService(null);
    _activeLLMService = llmService;

    if (!llmService.isReady) {
      throw SDKError.componentNotReady(
        'LLM service is not ready. Load a model first.',
      );
    }

    // Create a broadcast stream controller for the tokens
    final controller = StreamController<String>.broadcast();
    final allTokens = <String>[];

    // Convert public LLMGenerationOptions to module registry LLMGenerationOptions
    final moduleOpts = registry.LLMGenerationOptions(
      maxTokens: opts.maxTokens,
      temperature: opts.temperature,
      topP: opts.topP,
      stopSequences: opts.stopSequences,
      streamingEnabled: opts.streamingEnabled,
      systemPrompt: opts.systemPrompt,
      preferredFramework: opts.preferredFramework,
    );

    // Start streaming generation
    final tokenStream = llmService.generateStream(
      prompt: prompt,
      options: moduleOpts,
    );

    // Forward tokens and collect them
    final subscription = tokenStream.listen(
      (token) {
        allTokens.add(token);
        if (!controller.isClosed) {
          controller.add(token);
        }
      },
      onError: (Object error) {
        if (!controller.isClosed) {
          controller.addError(error);
        }
      },
      onDone: () {
        if (!controller.isClosed) {
          controller.close();
        }
      },
    );

    // Track the active stream for cancellation
    _activeStreamSubscription = subscription;

    // Build result future that completes when stream is done
    final resultFuture = controller.stream.toList().then((_) {
      final endTime = DateTime.now();
      final latencyMs = endTime.difference(startTime).inMicroseconds / 1000.0;
      final tokensPerSecond =
          latencyMs > 0 ? allTokens.length / (latencyMs / 1000) : 0.0;

      return LLMGenerationResult(
        text: allTokens.join(),
        inputTokens: (prompt.length / 4).ceil(),
        tokensUsed: allTokens.length,
        modelUsed: llmService.isReady ? 'loaded' : 'none',
        latencyMs: latencyMs,
        framework: null,
        tokensPerSecond: tokensPerSecond,
      );
    });

    return LLMStreamingResult(
      stream: controller.stream,
      result: resultFuture,
    );
  }

  // Active stream subscription for cancellation
  static StreamSubscription<String>? _activeStreamSubscription;
  // Active LLM service for cancellation
  static LLMService? _activeLLMService;

  /// Cancel ongoing generation
  static Future<void> cancelGeneration() async {
    // Cancel active stream subscription
    await _activeStreamSubscription?.cancel();
    _activeStreamSubscription = null;

    // Cancel in the LLM service if available
    await _activeLLMService?.cancel();
    _activeLLMService = null;
  }

  /// Download a model by ID
  ///
  /// Matches Swift `RunAnywhere.downloadModel(_:)`.
  ///
  /// ```dart
  /// await for (final progress in RunAnywhere.downloadModel('my-model-id')) {
  ///   print('Progress: ${(progress.percentage * 100).toStringAsFixed(1)}%');
  ///   if (progress.state.isCompleted) break;
  /// }
  /// ```
  static Stream<DownloadProgress> downloadModel(String modelId) async* {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    final logger = SDKLogger('RunAnywhere.Download');
    logger.info('📥 Starting download for model: $modelId');

    await for (final progress
        in ModelDownloadService.shared.downloadModel(modelId)) {
      // Convert internal progress to public DownloadProgress
      yield DownloadProgress(
        bytesDownloaded: progress.bytesDownloaded,
        totalBytes: progress.totalBytes,
        state: _mapDownloadStage(progress.stage),
      );

      // Log progress at intervals
      if (progress.stage == ModelDownloadStage.downloading) {
        final pct = (progress.overallProgress * 100).toStringAsFixed(1);
        if (progress.bytesDownloaded % (1024 * 1024) < 10000) {
          // Log every ~1MB
          logger.debug('Download progress: $pct%');
        }
      } else if (progress.stage == ModelDownloadStage.extracting) {
        logger.info('Extracting model...');
      } else if (progress.stage == ModelDownloadStage.completed) {
        logger.info('✅ Download completed for model: $modelId');
      } else if (progress.stage == ModelDownloadStage.failed) {
        logger.error('❌ Download failed: ${progress.error}');
      }
    }
  }

  /// Map internal download stage to public state
  static DownloadProgressState _mapDownloadStage(ModelDownloadStage stage) {
    switch (stage) {
      case ModelDownloadStage.downloading:
      case ModelDownloadStage.extracting:
      case ModelDownloadStage.verifying:
        return DownloadProgressState.downloading;
      case ModelDownloadStage.completed:
        return DownloadProgressState.completed;
      case ModelDownloadStage.failed:
        return DownloadProgressState.failed;
      case ModelDownloadStage.cancelled:
        return DownloadProgressState.cancelled;
    }
  }

  /// Delete a stored model
  static Future<void> deleteStoredModel(
    String modelId,
    LLMFramework framework,
  ) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }
    EventBus.shared.publish(SDKModelEvent.deleted(modelId: modelId));
  }

  /// Register a model from URL
  static ModelInfo registerModelWithURL({
    String? id,
    required String name,
    required Uri url,
    required LLMFramework framework,
    ModelCategory modality = ModelCategory.language,
    int? memoryRequirement,
    bool supportsThinking = false,
  }) {
    final modelId =
        id ?? name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-');

    final format = _inferFormat(url.path);
    final inferenceFramework = _mapFramework(framework);

    final model = ModelInfo(
      id: modelId,
      name: name,
      category: modality,
      format: format,
      framework: inferenceFramework,
      downloadURL: url,
      downloadSize: memoryRequirement,
      supportsThinking: supportsThinking,
    );

    _registeredModels.add(model);
    return model;
  }

  /// Register a model from URL string
  static ModelInfo? registerModelFromString({
    String? id,
    required String name,
    required String urlString,
    required LLMFramework framework,
    ModelCategory modality = ModelCategory.language,
    int? memoryRequirement,
    bool supportsThinking = false,
  }) {
    final url = Uri.tryParse(urlString);
    if (url == null) return null;

    return registerModelWithURL(
      id: id,
      name: name,
      url: url,
      framework: framework,
      modality: modality,
      memoryRequirement: memoryRequirement,
      supportsThinking: supportsThinking,
    );
  }

  /// Get storage info
  static Future<StorageInfo> getStorageInfo() async {
    return StorageInfo.empty;
  }

  /// Get downloaded models with info
  static Future<List<StoredModel>> getDownloadedModelsWithInfo() async {
    return [];
  }

  /// Reset SDK state
  static void reset() {
    _isInitialized = false;
    _initParams = null;
    _currentEnvironment = null;
    _registeredModels.clear();
    _modelCollectors.clear();
    serviceContainer.reset();
  }

  // ============================================================================
  // Model Registration (matches Swift RunAnywhere.registerModel pattern)
  // ============================================================================

  /// Register a model with the SDK.
  ///
  /// Matches Swift `RunAnywhere.registerModel(id:name:url:framework:modality:artifactType:memoryRequirement:)`.
  ///
  /// ```dart
  /// RunAnywhere.registerModel(
  ///   id: 'smollm2-360m-q8_0',
  ///   name: 'SmolLM2 360M Q8_0',
  ///   url: Uri.parse('https://huggingface.co/.../model.gguf'),
  ///   framework: InferenceFramework.llamaCpp,
  ///   memoryRequirement: 500000000,
  /// );
  /// ```
  static ModelInfo registerModel({
    String? id,
    required String name,
    required Uri url,
    required InferenceFramework framework,
    ModelCategory modality = ModelCategory.language,
    ModelArtifactType? artifactType,
    int? memoryRequirement,
    bool supportsThinking = false,
  }) {
    final modelId =
        id ?? name.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '-');

    final format = _inferFormat(url.path);

    final model = ModelInfo(
      id: modelId,
      name: name,
      category: modality,
      format: format,
      framework: framework,
      downloadURL: url,
      artifactType: artifactType ?? ModelArtifactType.infer(url, format),
      downloadSize: memoryRequirement,
      supportsThinking: supportsThinking,
      source: ModelSource.local,
    );

    _registeredModels.add(model);
    return model;
  }

  static ModelFormat _inferFormat(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.gguf')) return ModelFormat.gguf;
    if (lower.endsWith('.onnx')) return ModelFormat.onnx;
    if (lower.endsWith('.bin')) return ModelFormat.bin;
    if (lower.endsWith('.ort')) return ModelFormat.ort;
    return ModelFormat.unknown;
  }

  static InferenceFramework _mapFramework(LLMFramework framework) {
    switch (framework) {
      case LLMFramework.llamaCpp:
        return InferenceFramework.llamaCpp;
      case LLMFramework.onnx:
        return InferenceFramework.onnx;
      case LLMFramework.foundationModels:
        return InferenceFramework.foundationModels;
      case LLMFramework.systemTTS:
        return InferenceFramework.systemTTS;
      default:
        return InferenceFramework.unknown;
    }
  }
}
