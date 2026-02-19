import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:runanywhere/capabilities/voice/models/voice_session.dart';
import 'package:runanywhere/capabilities/voice/models/voice_session_handle.dart';
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/core/types/storage_types.dart';
import 'package:runanywhere/data/network/http_service.dart';
import 'package:runanywhere/data/network/telemetry_service.dart';
import 'package:runanywhere/foundation/configuration/sdk_constants.dart';
import 'package:runanywhere/foundation/dependency_injection/service_container.dart'
    hide SDKInitParams;
import 'package:runanywhere/foundation/error_types/sdk_error.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/infrastructure/download/download_service.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_auth.dart';
import 'package:runanywhere/native/dart_bridge_device.dart';
import 'package:runanywhere/native/dart_bridge_model_paths.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart'
    hide ModelInfo;
import 'package:runanywhere/native/dart_bridge_structured_output.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';
import 'package:runanywhere/public/types/types.dart';

/// The RunAnywhere SDK entry point
///
/// Matches Swift `RunAnywhere` enum from Public/RunAnywhere.swift
class RunAnywhere {
  static SDKInitParams? _initParams;
  static SDKEnvironment? _currentEnvironment;
  static bool _isInitialized = false;
  static bool _hasRunDiscovery = false;
  static final List<ModelInfo> _registeredModels = [];

  // Note: LLM state is managed by DartBridgeLLM's native handle
  // Use DartBridge.llm.currentModelId and DartBridge.llm.isLoaded

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
  ///
  /// Matches Swift `RunAnywhere.performCoreInit()` flow:
  /// - Phase 1: DartBridge.initialize() (sync, ~1-5ms)
  /// - Phase 2: DartBridge.initializeServices() (async, ~100-500ms)
  static Future<void> initializeWithParams(SDKInitParams params) async {
    if (_isInitialized) return;

    final logger = SDKLogger('RunAnywhere.Init');
    EventBus.shared.publish(SDKInitializationStarted());

    try {
      _currentEnvironment = params.environment;
      _initParams = params;

      // =========================================================================
      // PHASE 1: Core Init (sync, ~1-5ms, no network)
      // Matches Swift: RunAnywhere.performCoreInit() → CppBridge.initialize()
      // =========================================================================
      DartBridge.initialize(params.environment);
      logger.debug('DartBridge initialized with platform adapter');

      // =========================================================================
      // PHASE 2: Services Init (async, ~100-500ms, may need network)
      // Matches Swift: RunAnywhere.completeServicesInitialization()
      // =========================================================================

      // Step 2.1: Initialize service bridges with credentials
      // Matches Swift: CppBridge.State.initialize() + CppBridge.initializeServices()
      await DartBridge.initializeServices(
        apiKey: params.apiKey,
        baseURL: params.baseURL.toString(),
        deviceId: DartBridgeDevice.cachedDeviceId,
      );
      logger.debug('Service bridges initialized');

      // Step 2.2: Set base directory for model paths
      // Matches Swift: CppBridge.ModelPaths.setBaseDirectory(documentsURL)
      await DartBridge.modelPaths.setBaseDirectory();
      logger.debug('Model paths base directory configured');

      // Step 2.3: Setup local services (HTTP, etc.)
      await serviceContainer.setupLocalServices(
        apiKey: params.apiKey,
        baseURL: params.baseURL,
        environment: params.environment,
      );

      // Step 2.4: Register device with backend (REQUIRED before authentication)
      // Matches Swift: CppBridge.Device.registerIfNeeded(environment:)
      // The device must be registered in the backend database before auth can work
      logger.debug('Registering device with backend...');
      await _registerDeviceIfNeeded(params, logger);

      // Step 2.5: Authenticate with backend (production/staging only)
      // Matches Swift: CppBridge.Auth.authenticate(apiKey:) in setupHTTP()
      // This gets access_token and refresh_token from backend for subsequent API calls
      if (params.environment != SDKEnvironment.development) {
        logger.debug('Authenticating with backend...');
        await _authenticateWithBackend(params, logger);
      }

      // Step 2.6: Initialize model registry
      // CRITICAL: Uses the GLOBAL C++ registry via rac_get_model_registry()
      // Models must be in the global registry for rac_llm_component_load_model to find them
      logger.debug('Initializing model registry...');
      await DartBridgeModelRegistry.instance.initialize();

      // NOTE: Discovery is NOT run here. It runs lazily on first availableModels() call.
      // This matches Swift's Phase 2 behavior where discovery runs in background AFTER
      // models have been registered by the app.

      _isInitialized = true;
      logger.info('✅ SDK initialized (${params.environment.description})');
      EventBus.shared.publish(SDKInitializationCompleted());

      // Track successful SDK initialization
      TelemetryService.shared.trackSDKInit(
        environment: params.environment.name,
        success: true,
      );
    } catch (e) {
      logger.error('❌ SDK initialization failed: $e');
      _initParams = null;
      _currentEnvironment = null;
      _isInitialized = false;
      _hasRunDiscovery = false;
      EventBus.shared.publish(SDKInitializationFailed(e));

      // Track failed SDK initialization
      TelemetryService.shared.trackSDKInit(
        environment: params.environment.name,
        success: false,
      );
      TelemetryService.shared.trackError(
        errorCode: 'sdk_init_failed',
        errorMessage: e.toString(),
      );

      rethrow;
    }
  }

  /// Register device with backend if not already registered.
  /// Matches Swift: CppBridge.Device.registerIfNeeded(environment:)
  /// This MUST happen before authentication.
  static Future<void> _registerDeviceIfNeeded(
    SDKInitParams params,
    SDKLogger logger,
  ) async {
    try {
      // First ensure DartBridgeDevice is fully registered with callbacks
      await DartBridgeDevice.register(
        environment: params.environment,
        baseURL: params.baseURL.toString(),
      );

      // Then call the C++ device registration
      await DartBridgeDevice.instance.registerIfNeeded();
      logger.debug('Device registration check completed');
    } catch (e) {
      // Device registration failures are non-critical
      // App can still work offline with local models
      logger.warning('Device registration failed (non-critical): $e');
    }
  }

  /// Authenticate with backend for production/staging environments.
  /// Matches Swift: CppBridge.Auth.authenticate(apiKey:) in setupHTTP()
  static Future<void> _authenticateWithBackend(
    SDKInitParams params,
    SDKLogger logger,
  ) async {
    try {
      // Initialize auth manager first
      await DartBridgeAuth.initialize(
        environment: params.environment,
        baseURL: params.baseURL.toString(),
      );

      // Get device ID - MUST fetch properly, not just check cache
      // This matches Swift's DeviceIdentity.persistentUUID and Kotlin's CppBridgeDevice.getDeviceId()
      final deviceId = await DartBridgeDevice.instance.getDeviceId();
      logger.debug('Authenticating with device ID: $deviceId');

      // Authenticate with backend to get JWT tokens
      final result = await DartBridgeAuth.instance.authenticate(
        apiKey: params.apiKey,
        deviceId: deviceId,
      );

      if (result.isSuccess) {
        logger.info('Authenticated for ${params.environment.description}');
        // Set access token on HTTP service for subsequent requests
        if (result.data?.accessToken != null) {
          HTTPService.shared.setToken(result.data!.accessToken!);
        }
      } else {
        // Log warning but don't fail - telemetry will fail silently
        // and offline inference will still work
        logger.warning(
          'Authentication failed: ${result.error}',
          metadata: {'environment': params.environment.name},
        );
      }
    } catch (e) {
      // Log warning but don't fail initialization
      logger.warning(
        'Authentication error: $e',
        metadata: {'environment': params.environment.name},
      );
    }
  }

  /// Get all available models from C++ registry.
  ///
  /// Returns all models that can be used with the SDK, including:
  /// - Models registered via `registerModel()`
  /// - Models discovered on filesystem during SDK init
  ///
  /// This reads from the C++ registry, which contains the authoritative
  /// model state including localPath for downloaded models.
  ///
  /// Matches Swift: `return await CppBridge.ModelRegistry.shared.getAll()`
  static Future<List<ModelInfo>> availableModels() async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    // Run discovery lazily on first call
    // This ensures models are already registered before discovery runs
    // (discovery updates local_path for registered models only)
    if (!_hasRunDiscovery) {
      await _runDiscovery();
    }

    // Read from C++ registry - this is the authoritative source
    // Discovery populates localPath for downloaded models
    final cppModels =
        await DartBridgeModelRegistry.instance.getAllPublicModels();

    // Merge with _registeredModels to include full metadata (downloadURL, etc.)
    // C++ registry models may have localPath but lack some metadata
    final uniqueModels = <String, ModelInfo>{};

    // First add C++ registry models (have authoritative localPath)
    for (final model in cppModels) {
      uniqueModels[model.id] = model;
    }

    // Then merge _registeredModels to fill in any missing metadata
    for (final dartModel in _registeredModels) {
      final existing = uniqueModels[dartModel.id];
      if (existing != null) {
        // Merge: use C++ localPath but keep Dart's downloadURL and other metadata
        uniqueModels[dartModel.id] = ModelInfo(
          id: dartModel.id,
          name: dartModel.name,
          category: dartModel.category,
          format: dartModel.format,
          framework: dartModel.framework,
          downloadURL: dartModel.downloadURL,
          localPath: existing.localPath ?? dartModel.localPath,
          artifactType: dartModel.artifactType,
          downloadSize: dartModel.downloadSize,
          contextLength: dartModel.contextLength,
          supportsThinking: dartModel.supportsThinking,
          thinkingPattern: dartModel.thinkingPattern,
          description: dartModel.description,
          source: dartModel.source,
        );
      } else {
        // Model only in Dart list (not yet saved to C++ registry)
        uniqueModels[dartModel.id] = dartModel;
      }
    }

    return List.unmodifiable(uniqueModels.values.toList());
  }

  // ============================================================================
  // MARK: - LLM State (matches Swift RunAnywhere+ModelManagement.swift)
  // ============================================================================

  /// Get the currently loaded LLM model ID
  /// Returns null if no LLM model is loaded.
  static String? get currentModelId => DartBridge.llm.currentModelId;

  /// Check if an LLM model is currently loaded
  static bool get isModelLoaded => DartBridge.llm.isLoaded;

  /// Get the currently loaded LLM model as ModelInfo
  /// Matches Swift: `RunAnywhere.currentLLMModel`
  static Future<ModelInfo?> currentLLMModel() async {
    final modelId = currentModelId;
    if (modelId == null) return null;
    final models = await availableModels();
    return models.cast<ModelInfo?>().firstWhere(
          (m) => m?.id == modelId,
          orElse: () => null,
        );
  }

  // ============================================================================
  // MARK: - STT State (matches Swift RunAnywhere+ModelManagement.swift)
  // ============================================================================

  /// Get the currently loaded STT model ID
  /// Returns null if no STT model is loaded.
  static String? get currentSTTModelId => DartBridge.stt.currentModelId;

  /// Check if an STT model is currently loaded
  static bool get isSTTModelLoaded => DartBridge.stt.isLoaded;

  /// Get the currently loaded STT model as ModelInfo
  /// Matches Swift: `RunAnywhere.currentSTTModel`
  static Future<ModelInfo?> currentSTTModel() async {
    final modelId = currentSTTModelId;
    if (modelId == null) return null;
    final models = await availableModels();
    return models.cast<ModelInfo?>().firstWhere(
          (m) => m?.id == modelId,
          orElse: () => null,
        );
  }

  // ============================================================================
  // MARK: - TTS State (matches Swift RunAnywhere+ModelManagement.swift)
  // ============================================================================

  /// Get the currently loaded TTS voice ID
  /// Returns null if no TTS voice is loaded.
  static String? get currentTTSVoiceId => DartBridge.tts.currentVoiceId;

  /// Check if a TTS voice is currently loaded
  static bool get isTTSVoiceLoaded => DartBridge.tts.isLoaded;

  /// Get the currently loaded TTS voice as ModelInfo
  /// Matches Swift: `RunAnywhere.currentTTSVoice` (TTS uses "voice" terminology)
  static Future<ModelInfo?> currentTTSVoice() async {
    final voiceId = currentTTSVoiceId;
    if (voiceId == null) return null;
    final models = await availableModels();
    return models.cast<ModelInfo?>().firstWhere(
          (m) => m?.id == voiceId,
          orElse: () => null,
        );
  }

  /// Load a model by ID
  ///
  /// Finds the model in the registry, gets its local path, and loads it
  /// via the appropriate backend (LlamaCpp, ONNX, etc.)
  static Future<void> loadModel(String modelId) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    final logger = SDKLogger('RunAnywhere.LoadModel');
    logger.info('Loading model: $modelId');
    final startTime = DateTime.now().millisecondsSinceEpoch;

    // Emit load started event
    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: modelId));

    try {
      // Find the model in available models
      final models = await availableModels();
      final model = models.where((m) => m.id == modelId).firstOrNull;

      if (model == null) {
        throw SDKError.modelNotFound('Model not found: $modelId');
      }

      // Check if model has a local path (downloaded)
      if (model.localPath == null) {
        throw SDKError.modelNotDownloaded(
          'Model is not downloaded. Call downloadModel() first.',
        );
      }

      // Resolve the actual model file path (matches Swift resolveModelFilePath)
      // For LlamaCpp: finds the .gguf file in the model folder
      // For ONNX: returns the model directory
      final resolvedPath =
          await DartBridge.modelPaths.resolveModelFilePath(model);
      if (resolvedPath == null) {
        throw SDKError.modelNotFound(
            'Could not resolve model file path for: $modelId');
      }
      logger.info('Resolved model path: $resolvedPath');

      // Unload any existing model first via the bridge
      if (DartBridge.llm.isLoaded) {
        logger.debug('Unloading previous model');
        DartBridge.llm.unload();
      }

      // Load model directly via DartBridgeLLM (mirrors Swift CppBridge.LLM pattern)
      // The C++ layer handles finding the right backend via the service registry
      logger.debug('Loading model via C++ bridge: $resolvedPath');
      await DartBridge.llm.loadModel(resolvedPath, modelId, model.name);

      // Verify the model loaded successfully
      if (!DartBridge.llm.isLoaded) {
        throw SDKError.modelLoadFailed(
          modelId,
          'LLM model failed to load - model may not be compatible',
        );
      }

      final loadTimeMs = DateTime.now().millisecondsSinceEpoch - startTime;
      logger.info(
          'Model loaded successfully: ${model.name} (isLoaded=${DartBridge.llm.isLoaded})');

      // Track model load success
      TelemetryService.shared.trackModelLoad(
        modelId: modelId,
        modelType: 'llm',
        success: true,
        loadTimeMs: loadTimeMs,
      );

      // Emit load completed event
      EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: modelId));
    } catch (e) {
      logger.error('Failed to load model: $e');

      // Track model load failure
      TelemetryService.shared.trackModelLoad(
        modelId: modelId,
        modelType: 'llm',
        success: false,
      );
      TelemetryService.shared.trackError(
        errorCode: 'model_load_failed',
        errorMessage: e.toString(),
        context: {'model_id': modelId},
      );

      // Emit load failed event
      EventBus.shared.publish(SDKModelEvent.loadFailed(
        modelId: modelId,
        error: e.toString(),
      ));

      rethrow;
    }
  }

  /// Load an STT model
  static Future<void> loadSTTModel(String modelId) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    final logger = SDKLogger('RunAnywhere.LoadSTTModel');
    logger.info('Loading STT model: $modelId');
    final startTime = DateTime.now().millisecondsSinceEpoch;

    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: modelId));

    try {
      // Find the model
      final models = await availableModels();
      final model = models.where((m) => m.id == modelId).firstOrNull;

      if (model == null) {
        throw SDKError.modelNotFound('STT model not found: $modelId');
      }

      if (model.localPath == null) {
        throw SDKError.modelNotDownloaded(
          'STT model is not downloaded. Call downloadModel() first.',
        );
      }

      // Resolve the actual model path
      final resolvedPath =
          await DartBridge.modelPaths.resolveModelFilePath(model);
      if (resolvedPath == null) {
        throw SDKError.modelNotFound(
            'Could not resolve STT model file path for: $modelId');
      }

      // Unload any existing model first
      if (DartBridge.stt.isLoaded) {
        DartBridge.stt.unload();
      }

      // Load model directly via DartBridgeSTT (mirrors Swift CppBridge.STT pattern)
      logger.debug('Loading STT model via C++ bridge: $resolvedPath');
      await DartBridge.stt.loadModel(resolvedPath, modelId, model.name);

      if (!DartBridge.stt.isLoaded) {
        throw SDKError.sttNotAvailable(
          'STT model failed to load - model may not be compatible',
        );
      }

      final loadTimeMs = DateTime.now().millisecondsSinceEpoch - startTime;

      // Track STT model load success
      TelemetryService.shared.trackModelLoad(
        modelId: modelId,
        modelType: 'stt',
        success: true,
        loadTimeMs: loadTimeMs,
      );

      EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: modelId));
      logger.info('STT model loaded: ${model.name}');
    } catch (e) {
      logger.error('Failed to load STT model: $e');

      // Track STT model load failure
      TelemetryService.shared.trackModelLoad(
        modelId: modelId,
        modelType: 'stt',
        success: false,
      );
      TelemetryService.shared.trackError(
        errorCode: 'stt_model_load_failed',
        errorMessage: e.toString(),
        context: {'model_id': modelId},
      );

      EventBus.shared.publish(SDKModelEvent.loadFailed(
        modelId: modelId,
        error: e.toString(),
      ));
      rethrow;
    }
  }

  /// Unload the currently loaded STT model
  /// Matches Swift: `RunAnywhere.unloadSTTModel()`
  static Future<void> unloadSTTModel() async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    DartBridge.stt.unload();
  }

  // ============================================================================
  // MARK: - STT Transcription (matches Swift RunAnywhere+STT.swift)
  // ============================================================================

  /// Transcribe audio data to text.
  ///
  /// [audioData] - Raw audio bytes (PCM16 at 16kHz mono expected).
  ///
  /// Returns the transcribed text.
  ///
  /// Example:
  /// ```dart
  /// final text = await RunAnywhere.transcribe(audioBytes);
  /// ```
  ///
  /// Matches Swift: `RunAnywhere.transcribe(_:)`
  static Future<String> transcribe(Uint8List audioData) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    if (!DartBridge.stt.isLoaded) {
      throw SDKError.sttNotAvailable(
        'No STT model loaded. Call loadSTTModel() first.',
      );
    }

    final logger = SDKLogger('RunAnywhere.Transcribe');
    logger.debug('Transcribing ${audioData.length} bytes of audio...');
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final modelId = currentSTTModelId ?? 'unknown';
    
    // Get model name for telemetry
    final modelInfo = await DartBridgeModelRegistry.instance.getPublicModel(modelId);
    final modelName = modelInfo?.name;
    
    // Calculate audio duration from bytes (PCM16 at 16kHz mono)
    // Duration = bytes / 2 (16-bit = 2 bytes) / 16000 Hz * 1000 ms
    final calculatedDurationMs = (audioData.length / 32).round();

    try {
      final result = await DartBridge.stt.transcribe(audioData);
      final latencyMs = DateTime.now().millisecondsSinceEpoch - startTime;
      
      // Use calculated duration if C++ returns 0
      final audioDurationMs = result.durationMs > 0 ? result.durationMs : calculatedDurationMs;
      
      // Count words in transcription
      final wordCount = result.text.trim().isEmpty 
          ? 0 
          : result.text.trim().split(RegExp(r'\s+')).length;

      // Track transcription success with full metrics
      TelemetryService.shared.trackTranscription(
        modelId: modelId,
        modelName: modelName,
        audioDurationMs: audioDurationMs,
        latencyMs: latencyMs,
        wordCount: wordCount,
        confidence: result.confidence,
        language: result.language,
        isStreaming: false, // Batch transcription
      );

      logger.info(
          'Transcription complete: ${result.text.length} chars, confidence: ${result.confidence}');
      return result.text;
    } catch (e) {
      // Track transcription failure
      TelemetryService.shared.trackError(
        errorCode: 'transcription_failed',
        errorMessage: e.toString(),
        context: {'model_id': modelId},
      );

      logger.error('Transcription failed: $e');
      rethrow;
    }
  }

  /// Transcribe audio data with detailed result.
  ///
  /// [audioData] - Raw audio bytes (PCM16 at 16kHz mono expected).
  ///
  /// Returns STTResult with text, confidence, and metadata.
  ///
  /// Matches Swift: `RunAnywhere.transcribeWithOptions(_:options:)`
  static Future<STTResult> transcribeWithResult(Uint8List audioData) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    if (!DartBridge.stt.isLoaded) {
      throw SDKError.sttNotAvailable(
        'No STT model loaded. Call loadSTTModel() first.',
      );
    }

    final logger = SDKLogger('RunAnywhere.Transcribe');
    logger.debug('Transcribing ${audioData.length} bytes with details...');
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final modelId = currentSTTModelId ?? 'unknown';
    
    // Get model name for telemetry
    final modelInfo = await DartBridgeModelRegistry.instance.getPublicModel(modelId);
    final modelName = modelInfo?.name;
    
    // Calculate audio duration from bytes (PCM16 at 16kHz mono)
    final calculatedDurationMs = (audioData.length / 32).round();

    try {
      final result = await DartBridge.stt.transcribe(audioData);
      final latencyMs = DateTime.now().millisecondsSinceEpoch - startTime;
      
      // Use calculated duration if C++ returns 0
      final audioDurationMs = result.durationMs > 0 ? result.durationMs : calculatedDurationMs;
      
      // Count words in transcription
      final wordCount = result.text.trim().isEmpty 
          ? 0 
          : result.text.trim().split(RegExp(r'\s+')).length;

      // Track transcription success with full metrics
      TelemetryService.shared.trackTranscription(
        modelId: modelId,
        modelName: modelName,
        audioDurationMs: audioDurationMs,
        latencyMs: latencyMs,
        wordCount: wordCount,
        confidence: result.confidence,
        language: result.language,
        isStreaming: false, // Batch transcription
      );

      logger.info(
          'Transcription complete: ${result.text.length} chars, confidence: ${result.confidence}');
      return STTResult(
        text: result.text,
        confidence: result.confidence,
        durationMs: audioDurationMs,
        language: result.language,
      );
    } catch (e) {
      // Track transcription failure
      TelemetryService.shared.trackError(
        errorCode: 'transcription_failed',
        errorMessage: e.toString(),
        context: {'model_id': modelId},
      );

      logger.error('Transcription failed: $e');
      rethrow;
    }
  }

  /// Load a TTS voice
  static Future<void> loadTTSVoice(String voiceId) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    final logger = SDKLogger('RunAnywhere.LoadTTSVoice');
    logger.info('Loading TTS voice: $voiceId');
    final startTime = DateTime.now().millisecondsSinceEpoch;

    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: voiceId));

    try {
      // Find the voice model
      final models = await availableModels();
      final model = models.where((m) => m.id == voiceId).firstOrNull;

      if (model == null) {
        throw SDKError.modelNotFound('TTS voice not found: $voiceId');
      }

      if (model.localPath == null) {
        throw SDKError.modelNotDownloaded(
          'TTS voice is not downloaded. Call downloadModel() first.',
        );
      }

      // Resolve the actual voice path
      final resolvedPath =
          await DartBridge.modelPaths.resolveModelFilePath(model);
      if (resolvedPath == null) {
        throw SDKError.modelNotFound(
            'Could not resolve TTS voice path for: $voiceId');
      }

      // Unload any existing voice first
      if (DartBridge.tts.isLoaded) {
        DartBridge.tts.unload();
      }

      // Load voice directly via DartBridgeTTS (mirrors Swift CppBridge.TTS pattern)
      logger.debug('Loading TTS voice via C++ bridge: $resolvedPath');
      await DartBridge.tts.loadVoice(resolvedPath, voiceId, model.name);

      if (!DartBridge.tts.isLoaded) {
        throw SDKError.ttsNotAvailable(
          'TTS voice failed to load - voice may not be compatible',
        );
      }

      final loadTimeMs = DateTime.now().millisecondsSinceEpoch - startTime;

      // Track TTS voice load success
      TelemetryService.shared.trackModelLoad(
        modelId: voiceId,
        modelType: 'tts',
        success: true,
        loadTimeMs: loadTimeMs,
      );

      EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: voiceId));
      logger.info('TTS voice loaded: ${model.name}');
    } catch (e) {
      logger.error('Failed to load TTS voice: $e');

      // Track TTS voice load failure
      TelemetryService.shared.trackModelLoad(
        modelId: voiceId,
        modelType: 'tts',
        success: false,
      );
      TelemetryService.shared.trackError(
        errorCode: 'tts_voice_load_failed',
        errorMessage: e.toString(),
        context: {'voice_id': voiceId},
      );

      EventBus.shared.publish(SDKModelEvent.loadFailed(
        modelId: voiceId,
        error: e.toString(),
      ));
      rethrow;
    }
  }

  /// Unload the currently loaded TTS voice
  /// Matches Swift: `RunAnywhere.unloadTTSVoice()`
  static Future<void> unloadTTSVoice() async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    DartBridge.tts.unload();
  }

  // ============================================================================
  // MARK: - TTS Synthesis (matches Swift RunAnywhere+TTS.swift)
  // ============================================================================

  /// Synthesize speech from text.
  ///
  /// [text] - Text to synthesize.
  /// [rate] - Speech rate (0.5 to 2.0, 1.0 is normal). Optional.
  /// [pitch] - Speech pitch (0.5 to 2.0, 1.0 is normal). Optional.
  /// [volume] - Speech volume (0.0 to 1.0). Optional.
  ///
  /// Returns audio samples as Float32List and metadata.
  ///
  /// Example:
  /// ```dart
  /// final result = await RunAnywhere.synthesize('Hello world');
  /// // result.samples contains PCM audio data
  /// // result.sampleRate is typically 22050 Hz
  /// ```
  ///
  /// Matches Swift: `RunAnywhere.synthesize(_:)`
  static Future<TTSResult> synthesize(
    String text, {
    double rate = 1.0,
    double pitch = 1.0,
    double volume = 1.0,
  }) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    if (!DartBridge.tts.isLoaded) {
      throw SDKError.ttsNotAvailable(
        'No TTS voice loaded. Call loadTTSVoice() first.',
      );
    }

    final logger = SDKLogger('RunAnywhere.Synthesize');
    logger.debug(
        'Synthesizing: "${text.substring(0, text.length.clamp(0, 50))}..."');
    final startTime = DateTime.now().millisecondsSinceEpoch;
    final voiceId = currentTTSVoiceId ?? 'unknown';
    
    // Get model name for telemetry
    final modelInfo = await DartBridgeModelRegistry.instance.getPublicModel(voiceId);
    final modelName = modelInfo?.name;

    try {
      final result = await DartBridge.tts.synthesize(
        text,
        rate: rate,
        pitch: pitch,
        volume: volume,
      );
      final latencyMs = DateTime.now().millisecondsSinceEpoch - startTime;
      
      // Calculate audio size in bytes (Float32 samples = 4 bytes each)
      final audioSizeBytes = result.samples.length * 4;

      // Track synthesis success with full metrics
      TelemetryService.shared.trackSynthesis(
        voiceId: voiceId,
        modelName: modelName,
        textLength: text.length,
        audioDurationMs: result.durationMs,
        latencyMs: latencyMs,
        sampleRate: result.sampleRate,
        audioSizeBytes: audioSizeBytes,
      );

      logger.info(
          'Synthesis complete: ${result.samples.length} samples, ${result.sampleRate} Hz');
      return TTSResult(
        samples: result.samples,
        sampleRate: result.sampleRate,
        durationMs: result.durationMs,
      );
    } catch (e) {
      // Track synthesis failure
      TelemetryService.shared.trackError(
        errorCode: 'synthesis_failed',
        errorMessage: e.toString(),
        context: {'voice_id': voiceId, 'text_length': text.length},
      );

      logger.error('Synthesis failed: $e');
      rethrow;
    }
  }

  /// Unload current model
  static Future<void> unloadModel() async {
    if (!_isInitialized) return;

    final logger = SDKLogger('RunAnywhere.UnloadModel');

    if (DartBridge.llm.isLoaded) {
      final modelId = DartBridge.llm.currentModelId ?? 'unknown';
      logger.info('Unloading model: $modelId');

      EventBus.shared.publish(SDKModelEvent.unloadStarted(modelId: modelId));

      // Unload via C++ bridge (matches Swift CppBridge.LLM pattern)
      DartBridge.llm.unload();

      EventBus.shared.publish(SDKModelEvent.unloadCompleted(modelId: modelId));
      logger.info('Model unloaded');
    }
  }

  // ============================================================================
  // MARK: - Voice Agent (matches Swift RunAnywhere+VoiceAgent.swift)
  // ============================================================================

  /// Check if the voice agent is ready (all required components loaded).
  ///
  /// Returns true if STT, LLM, and TTS are all loaded and ready.
  ///
  /// Matches Swift: `RunAnywhere.isVoiceAgentReady`
  static bool get isVoiceAgentReady {
    return DartBridge.stt.isLoaded &&
        DartBridge.llm.isLoaded &&
        DartBridge.tts.isLoaded;
  }

  /// Get the current state of all voice agent components (STT, LLM, TTS).
  ///
  /// Use this to check which models are loaded and ready for the voice pipeline.
  /// Models are loaded via the individual APIs (loadSTTModel, loadModel, loadTTSVoice).
  ///
  /// Matches Swift: `RunAnywhere.getVoiceAgentComponentStates()`
  static VoiceAgentComponentStates getVoiceAgentComponentStates() {
    final sttId = currentSTTModelId;
    final llmId = currentModelId;
    final ttsId = currentTTSVoiceId;

    return VoiceAgentComponentStates(
      stt: sttId != null
          ? ComponentLoadState.loaded(modelId: sttId)
          : const ComponentLoadState.notLoaded(),
      llm: llmId != null
          ? ComponentLoadState.loaded(modelId: llmId)
          : const ComponentLoadState.notLoaded(),
      tts: ttsId != null
          ? ComponentLoadState.loaded(modelId: ttsId)
          : const ComponentLoadState.notLoaded(),
    );
  }

  /// Start a voice session with audio capture, VAD, and full voice pipeline.
  ///
  /// This is the simplest way to integrate voice assistant functionality.
  /// The session handles audio capture, VAD, and processing internally.
  ///
  /// Example:
  /// ```dart
  /// final session = await RunAnywhere.startVoiceSession();
  ///
  /// // Consume events
  /// session.events.listen((event) {
  ///   if (event is VoiceSessionListening) {
  ///     audioMeter = event.audioLevel;
  ///   } else if (event is VoiceSessionTurnCompleted) {
  ///     userText = event.transcript;
  ///     assistantText = event.response;
  ///   }
  /// });
  ///
  /// // Later...
  /// session.stop();
  /// ```
  ///
  /// Matches Swift: `RunAnywhere.startVoiceSession(config:)`
  static Future<VoiceSessionHandle> startVoiceSession({
    VoiceSessionConfig config = VoiceSessionConfig.defaultConfig,
  }) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    final logger = SDKLogger('RunAnywhere.VoiceSession');

    // Create the session handle with all necessary callbacks
    final session = VoiceSessionHandle(
      config: config,
      processAudioCallback: _processVoiceAgentAudio,
      isVoiceAgentReadyCallback: () async => isVoiceAgentReady,
      initializeVoiceAgentCallback: _initializeVoiceAgentWithLoadedModels,
    );

    logger.info('Voice session created with callbacks');

    // Start the session (this will verify voice agent readiness)
    try {
      await session.start();
      logger.info('Voice session started successfully');
    } catch (e) {
      logger.error('Failed to start voice session: $e');
      rethrow;
    }

    return session;
  }

  /// Initialize voice agent using already-loaded models.
  ///
  /// This is called internally by VoiceSessionHandle when starting a session.
  /// It verifies all components (STT, LLM, TTS) are loaded.
  ///
  /// Matches Swift: `RunAnywhere.initializeVoiceAgentWithLoadedModels()`
  static Future<void> _initializeVoiceAgentWithLoadedModels() async {
    final logger = SDKLogger('RunAnywhere.VoiceAgent');

    if (!isVoiceAgentReady) {
      throw SDKError.voiceAgentNotReady(
        'Voice agent components not ready. Load STT, LLM, and TTS models first.',
      );
    }

    try {
      await DartBridge.voiceAgent.initializeWithLoadedModels();
      logger.info('Voice agent initialized with loaded models');
    } catch (e) {
      logger.error('Failed to initialize voice agent: $e');
      rethrow;
    }
  }

  /// Process audio through the voice agent pipeline (STT -> LLM -> TTS).
  ///
  /// This is called internally by VoiceSessionHandle during audio processing.
  ///
  /// Matches Swift: `RunAnywhere.processVoiceTurn(_:)`
  static Future<VoiceAgentProcessResult> _processVoiceAgentAudio(
    Uint8List audioData,
  ) async {
    final logger = SDKLogger('RunAnywhere.VoiceAgent');
    logger.debug('Processing ${audioData.length} bytes of audio...');

    try {
      // Use the DartBridgeVoiceAgent to process the voice turn
      final result = await DartBridge.voiceAgent.processVoiceTurn(audioData);

      // Audio is already in WAV format (C++ voice agent converts Float32 TTS to WAV)
      // No conversion needed - pass directly to playback
      final synthesizedAudio = result.audioWavData.isNotEmpty
          ? result.audioWavData
          : null;

      logger.info(
        'Voice turn complete: transcript="${result.transcription.substring(0, result.transcription.length.clamp(0, 50))}", '
        'response="${result.response.substring(0, result.response.length.clamp(0, 50))}", '
        'audio=${synthesizedAudio?.length ?? 0} bytes',
      );

      return VoiceAgentProcessResult(
        speechDetected: result.transcription.isNotEmpty,
        transcription: result.transcription,
        response: result.response,
        synthesizedAudio: synthesizedAudio,
      );
    } catch (e) {
      logger.error('Voice turn processing failed: $e');
      rethrow;
    }
  }

  /// Cleanup voice agent resources.
  ///
  /// Call this when you're done with voice agent functionality.
  ///
  /// Matches Swift: `RunAnywhere.cleanupVoiceAgent()`
  static void cleanupVoiceAgent() {
    DartBridge.voiceAgent.cleanup();
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

    // Verify model is loaded via DartBridgeLLM (mirrors Swift CppBridge.LLM pattern)
    if (!DartBridge.llm.isLoaded) {
      throw SDKError.componentNotReady(
        'LLM model not loaded. Call loadModel() first.',
      );
    }

    final modelId = DartBridge.llm.currentModelId ?? 'unknown';
    
    // Get model name from registry for telemetry
    final modelInfo = await DartBridgeModelRegistry.instance.getPublicModel(modelId);
    final modelName = modelInfo?.name;

    // Determine effective system prompt - add JSON conversion instructions if structuredOutput is provided
    String? effectiveSystemPrompt = opts.systemPrompt;
    if (opts.structuredOutput != null) {
      final jsonSystemPrompt = DartBridgeStructuredOutput.shared.getSystemPrompt(
        opts.structuredOutput!.schema,
      );
      // If user already provided a system prompt, prepend the JSON instructions
      if (effectiveSystemPrompt != null && effectiveSystemPrompt.isNotEmpty) {
        effectiveSystemPrompt = '$jsonSystemPrompt\n\n$effectiveSystemPrompt';
      } else {
        effectiveSystemPrompt = jsonSystemPrompt;
      }
    }

    try {
      // Generate directly via DartBridgeLLM (calls rac_llm_component_generate)
      final result = await DartBridge.llm.generate(
        prompt,
        maxTokens: opts.maxTokens,
        temperature: opts.temperature,
        systemPrompt: effectiveSystemPrompt,
      );

      final endTime = DateTime.now();
      final latencyMs = endTime.difference(startTime).inMicroseconds / 1000.0;
      final tokensPerSecond = result.totalTimeMs > 0
          ? (result.completionTokens / result.totalTimeMs) * 1000
          : 0.0;

      // Track generation success with full metrics (mirrors other SDKs)
      TelemetryService.shared.trackGeneration(
        modelId: modelId,
        modelName: modelName,
        promptTokens: result.promptTokens,
        completionTokens: result.completionTokens,
        latencyMs: latencyMs.round(),
        temperature: opts.temperature,
        maxTokens: opts.maxTokens,
        contextLength: 8192, // Default context length for LlamaCpp
        tokensPerSecond: tokensPerSecond,
        isStreaming: false,
      );

      // Extract structured data if structuredOutput is provided
      dynamic structuredData;
      dynamic structuredData;
      if (opts.structuredOutput != null) {
        try {
          final jsonString = DartBridgeStructuredOutput.shared.extractJson(result.text);
          if (jsonString != null) {
            structuredData = jsonDecode(jsonString);
          }
        } catch (_) {
          // JSON extraction/parse failed — return text result without structured data
        }
      }

      return LLMGenerationResult(
        text: result.text,
        inputTokens: result.promptTokens,
        tokensUsed: result.completionTokens,
        modelUsed: modelId,
        latencyMs: latencyMs,
        framework: 'llamacpp',
        tokensPerSecond: tokensPerSecond,
        structuredData: structuredData,
      );
    } catch (e) {
      // Track generation failure
      TelemetryService.shared.trackError(
        errorCode: 'generation_failed',
        errorMessage: e.toString(),
        context: {'model_id': modelId},
      );
      throw SDKError.generationFailed('$e');
    }
  }

  /// Streaming text generation
  ///
  /// Matches Swift `RunAnywhere.generateStream(_:options:)`.
  ///
  /// Returns an `LLMStreamingResult` containing:
  /// - `stream`: Stream of tokens as they are generated
  /// - `result`: Future that completes with final generation metrics
  /// - `cancel`: Function to cancel the generation
  ///
  /// ```dart
  /// final result = await RunAnywhere.generateStream('Tell me a story');
  ///
  /// // Consume tokens as they arrive
  /// await for (final token in result.stream) {
  ///   print(token);
  /// }
  ///
  /// // Get final metrics after stream completes
  /// final metrics = await result.result;
  /// print('Tokens: ${metrics.tokensUsed}');
  ///
  /// // Or cancel early if needed
  /// result.cancel();
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
    DateTime? firstTokenTime;

    // Verify model is loaded via DartBridgeLLM (mirrors Swift CppBridge.LLM pattern)
    if (!DartBridge.llm.isLoaded) {
      throw SDKError.componentNotReady(
        'LLM model not loaded. Call loadModel() first.',
      );
    }

    final modelId = DartBridge.llm.currentModelId ?? 'unknown';
    
    // Get model name from registry for telemetry
    final modelInfo = await DartBridgeModelRegistry.instance.getPublicModel(modelId);
    final modelName = modelInfo?.name;

    // Determine effective system prompt - add JSON conversion instructions if structuredOutput is provided
    String? effectiveSystemPrompt = opts.systemPrompt;
    if (opts.structuredOutput != null) {
      final jsonSystemPrompt = DartBridgeStructuredOutput.shared.getSystemPrompt(
        opts.structuredOutput!.schema,
      );
      // If user already provided a system prompt, prepend the JSON instructions
      if (effectiveSystemPrompt != null && effectiveSystemPrompt.isNotEmpty) {
        effectiveSystemPrompt = '$jsonSystemPrompt\n\n$effectiveSystemPrompt';
      } else {
        effectiveSystemPrompt = jsonSystemPrompt;
      }
    }

    // Create a broadcast stream controller for the tokens
    final controller = StreamController<String>.broadcast();
    final allTokens = <String>[];

    // Start streaming generation via DartBridgeLLM
    final tokenStream = DartBridge.llm.generateStream(
      prompt,
      maxTokens: opts.maxTokens,
      temperature: opts.temperature,
      systemPrompt: effectiveSystemPrompt,
    );

    // Forward tokens and collect them, track subscription in bridge for cancellation
    DartBridge.llm.setActiveStreamSubscription(
      tokenStream.listen(
        (token) {
          // Track first token time
          firstTokenTime ??= DateTime.now();
          allTokens.add(token);
          if (!controller.isClosed) {
            controller.add(token);
          }
        },
        onError: (Object error) {
          // Track streaming generation error
          TelemetryService.shared.trackError(
            errorCode: 'streaming_generation_failed',
            errorMessage: error.toString(),
            context: {'model_id': modelId},
          );
          if (!controller.isClosed) {
            controller.addError(error);
          }
        },
        onDone: () {
          if (!controller.isClosed) {
            unawaited(controller.close());
          }
          // Clear subscription when done
          DartBridge.llm.setActiveStreamSubscription(null);
        },
      ),
    );

    // Build result future that completes when stream is done
    final resultFuture = controller.stream.toList().then((_) {
      final endTime = DateTime.now();
      final latencyMs = endTime.difference(startTime).inMicroseconds / 1000.0;
      final tokensPerSecond =
          latencyMs > 0 ? allTokens.length / (latencyMs / 1000) : 0.0;

      // Calculate time to first token
      int? timeToFirstTokenMs;
      if (firstTokenTime != null) {
        timeToFirstTokenMs = firstTokenTime!.difference(startTime).inMilliseconds;
      }

      // Estimate tokens (~4 chars per token)
      final promptTokens = (prompt.length / 4).ceil();
      final completionTokens = allTokens.length;

      // Track streaming generation success with full metrics (mirrors other SDKs)
      TelemetryService.shared.trackGeneration(
        modelId: modelId,
        modelName: modelName,
        promptTokens: promptTokens,
        completionTokens: completionTokens,
        latencyMs: latencyMs.round(),
        temperature: opts.temperature,
        maxTokens: opts.maxTokens,
        contextLength: 8192, // Default context length for LlamaCpp
        tokensPerSecond: tokensPerSecond,
        timeToFirstTokenMs: timeToFirstTokenMs,
        isStreaming: true,
      );

      // Extract structured data if structuredOutput is provided
      dynamic structuredData;
      final fullText = allTokens.join();
      dynamic structuredData;
      final fullText = allTokens.join();
      if (opts.structuredOutput != null) {
        try {
          final jsonString = DartBridgeStructuredOutput.shared.extractJson(fullText);
          if (jsonString != null) {
            structuredData = jsonDecode(jsonString);
          }
        } catch (_) {
          // JSON extraction/parse failed — return text result without structured data
        }
      }

      return LLMGenerationResult(
        text: fullText,
        inputTokens: promptTokens,
        tokensUsed: completionTokens,
        modelUsed: modelId,
        latencyMs: latencyMs,
        framework: 'llamacpp',
        tokensPerSecond: tokensPerSecond,
        structuredData: structuredData,
      );
    });

    return LLMStreamingResult(
      stream: controller.stream,
      result: resultFuture,
      cancel: () {
        // Cancel via the bridge (handles both stream subscription and native cancel)
        DartBridge.llm.cancelGeneration();
      },
    );
  }

  /// Cancel ongoing generation
  static Future<void> cancelGeneration() async {
    // Cancel via the bridge (handles both stream subscription and service)
    DartBridge.llm.cancelGeneration();
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
    final startTime = DateTime.now().millisecondsSinceEpoch;

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
        final downloadTimeMs = DateTime.now().millisecondsSinceEpoch - startTime;
        logger.info('✅ Download completed for model: $modelId');

        // Track download success
        TelemetryService.shared.trackModelDownload(
          modelId: modelId,
          success: true,
          downloadTimeMs: downloadTimeMs,
          sizeBytes: progress.totalBytes,
        );
      } else if (progress.stage == ModelDownloadStage.failed) {
        logger.error('❌ Download failed: ${progress.error}');

        // Track download failure
        TelemetryService.shared.trackModelDownload(
          modelId: modelId,
          success: false,
        );
        TelemetryService.shared.trackError(
          errorCode: 'download_failed',
          errorMessage: progress.error ?? 'Unknown error',
          context: {'model_id': modelId},
        );
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
  ///
  /// Matches Swift `RunAnywhere.deleteStoredModel(modelId:)`.
  static Future<void> deleteStoredModel(String modelId) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }
    await DartBridgeModelRegistry.instance.removeModel(modelId);
    EventBus.shared.publish(SDKModelEvent.deleted(modelId: modelId));
  }

  /// Get storage info including device storage, app storage, and downloaded models.
  ///
  /// Matches Swift: `RunAnywhere.getStorageInfo()`
  static Future<StorageInfo> getStorageInfo() async {
    if (!_isInitialized) {
      return StorageInfo.empty;
    }

    try {
      // Get device storage info
      final deviceStorage = await _getDeviceStorageInfo();

      // Get app storage info
      final appStorage = await _getAppStorageInfo();

      // Get downloaded models with sizes
      final storedModels = await getDownloadedModelsWithInfo();
      final modelMetrics = storedModels
          .map((m) =>
              ModelStorageMetrics(model: m.modelInfo, sizeOnDisk: m.size))
          .toList();

      return StorageInfo(
        appStorage: appStorage,
        deviceStorage: deviceStorage,
        models: modelMetrics,
      );
    } catch (e) {
      SDKLogger('RunAnywhere.Storage').error('Failed to get storage info: $e');
      return StorageInfo.empty;
    }
  }

  /// Get device storage information.
  static Future<DeviceStorageInfo> _getDeviceStorageInfo() async {
    try {
      // Get device storage info from documents directory
      final modelsDir = DartBridgeModelPaths.instance.getModelsDirectory();
      if (modelsDir == null) {
        return const DeviceStorageInfo(
            totalSpace: 0, freeSpace: 0, usedSpace: 0);
      }

      // Calculate total storage used by models
      final modelsDirSize = await _getDirectorySize(modelsDir);

      // For iOS/Android, we can't easily get device free space without native code
      // Return what we know: the models directory size
      return DeviceStorageInfo(
        totalSpace: modelsDirSize,
        freeSpace: 0, // Would need native code to get real free space
        usedSpace: modelsDirSize,
      );
    } catch (e) {
      return const DeviceStorageInfo(totalSpace: 0, freeSpace: 0, usedSpace: 0);
    }
  }

  /// Get app storage breakdown.
  static Future<AppStorageInfo> _getAppStorageInfo() async {
    try {
      // Get models directory size
      final modelsDir = DartBridgeModelPaths.instance.getModelsDirectory();
      final modelsDirSize =
          modelsDir != null ? await _getDirectorySize(modelsDir) : 0;

      // For now, we'll estimate cache and app support as 0
      // since we don't have a dedicated cache directory
      return AppStorageInfo(
        documentsSize: modelsDirSize,
        cacheSize: 0,
        appSupportSize: 0,
        totalSize: modelsDirSize,
      );
    } catch (e) {
      return const AppStorageInfo(
        documentsSize: 0,
        cacheSize: 0,
        appSupportSize: 0,
        totalSize: 0,
      );
    }
  }

  /// Calculate directory size recursively.
  static Future<int> _getDirectorySize(String path) async {
    try {
      final dir = Directory(path);
      if (!await dir.exists()) return 0;

      int totalSize = 0;
      await for (final entity
          in dir.list(recursive: true, followLinks: false)) {
        if (entity is File) {
          try {
            totalSize += await entity.length();
          } catch (_) {
            // Skip files we can't read
          }
        }
      }
      return totalSize;
    } catch (e) {
      return 0;
    }
  }

  /// Get downloaded models with their file sizes.
  ///
  /// Returns a list of StoredModel objects with size information populated
  /// from the actual files on disk.
  ///
  /// Matches Swift: `RunAnywhere.getDownloadedModelsWithInfo()`
  static Future<List<StoredModel>> getDownloadedModelsWithInfo() async {
    if (!_isInitialized) {
      return [];
    }

    try {
      // Get all models that have localPath set (are downloaded)
      final allModels = await availableModels();
      final downloadedModels =
          allModels.where((m) => m.localPath != null).toList();

      final storedModels = <StoredModel>[];

      for (final model in downloadedModels) {
        // Get the actual file size
        final localPath = model.localPath!.toFilePath();
        int fileSize = 0;

        try {
          // Check if it's a directory (for multi-file models) or single file
          final file = File(localPath);
          final dir = Directory(localPath);

          if (await file.exists()) {
            fileSize = await file.length();
          } else if (await dir.exists()) {
            fileSize = await _getDirectorySize(localPath);
          }
        } catch (e) {
          SDKLogger('RunAnywhere.Storage')
              .debug('Could not get size for ${model.id}: $e');
        }

        storedModels.add(StoredModel(
          modelInfo: model,
          size: fileSize,
        ));
      }

      return storedModels;
    } catch (e) {
      SDKLogger('RunAnywhere.Storage')
          .error('Failed to get downloaded models: $e');
      return [];
    }
  }

  /// Reset SDK state
  static Future<void> reset() async {
    // Flush pending telemetry events before reset
    await TelemetryService.shared.shutdown();

    _isInitialized = false;
    _hasRunDiscovery = false;
    _initParams = null;
    _currentEnvironment = null;
    _registeredModels.clear();
    DartBridgeModelRegistry.instance.shutdown();
    serviceContainer.reset();
  }

  /// Update the download status for a model in C++ registry
  ///
  /// Called by ModelDownloadService after a successful download.
  /// Matches Swift: CppBridge.ModelRegistry.shared.updateDownloadStatus()
  static Future<void> updateModelDownloadStatus(
      String modelId, String? localPath) async {
    await DartBridgeModelRegistry.instance
        .updateDownloadStatus(modelId, localPath);
  }

  /// Remove a model from the C++ registry
  ///
  /// Called when a model is deleted.
  /// Matches Swift: CppBridge.ModelRegistry.shared.remove()
  static Future<void> removeModel(String modelId) async {
    await DartBridgeModelRegistry.instance.removeModel(modelId);
  }

  /// Internal: Run discovery once on first availableModels() call
  /// This ensures models are registered before discovery runs
  static Future<void> _runDiscovery() async {
    if (_hasRunDiscovery) return;

    final logger = SDKLogger('RunAnywhere.Discovery');
    logger.debug(
        'Running lazy discovery (models should already be registered)...');

    final result =
        await DartBridgeModelRegistry.instance.discoverDownloadedModels();

    _hasRunDiscovery = true;

    if (result.discoveredModels.isNotEmpty) {
      logger.info(
          '📦 Discovered ${result.discoveredModels.length} downloaded models');
      for (final model in result.discoveredModels) {
        logger.debug(
            '  - ${model.modelId} -> ${model.localPath} (framework: ${model.framework})');
      }
    } else {
      logger.debug('No downloaded models discovered');
    }
  }

  /// Re-discover models on the filesystem via C++ registry.
  ///
  /// This scans the filesystem for downloaded models and updates the
  /// C++ registry with localPath for discovered models.
  ///
  /// Note: This is called automatically on first availableModels() call.
  /// You typically don't need to call this manually unless you've done
  /// manual file operations outside the SDK.
  ///
  /// Matches Swift: CppBridge.ModelRegistry.shared.discoverDownloadedModels()
  static Future<void> refreshDiscoveredModels() async {
    if (!_isInitialized) return;

    final logger = SDKLogger('RunAnywhere.Discovery');
    final result =
        await DartBridgeModelRegistry.instance.discoverDownloadedModels();
    if (result.discoveredModels.isNotEmpty) {
      logger.info(
          'Discovery found ${result.discoveredModels.length} downloaded models');
    }
  }

  // ============================================================================
  // Model Registration (matches Swift RunAnywhere.registerModel pattern)
  // ============================================================================

  /// Register a model with the SDK.
  ///
  /// Matches Swift `RunAnywhere.registerModel(id:name:url:framework:modality:artifactType:memoryRequirement:)`.
  ///
  /// This saves the model to the C++ registry so it can be discovered and loaded.
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

    // Save to C++ registry (fire-and-forget, matches Swift pattern)
    // This is critical for model discovery and loading to work correctly
    _saveToCppRegistry(model);

    return model;
  }

  /// Save model to C++ registry (fire-and-forget).
  /// Matches Swift: `Task { try await CppBridge.ModelRegistry.shared.save(modelInfo) }`
  static void _saveToCppRegistry(ModelInfo model) {
    // Fire-and-forget save to C++ registry
    unawaited(
      DartBridgeModelRegistry.instance.savePublicModel(model).then((success) {
        final logger = SDKLogger('RunAnywhere.Models');
        if (!success) {
          logger.warning('Failed to save model to C++ registry: ${model.id}');
        }
      }).catchError((Object error) {
        SDKLogger('RunAnywhere.Models')
            .error('Error saving model to C++ registry: $error');
      }),
    );
  }

  static ModelFormat _inferFormat(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.gguf')) return ModelFormat.gguf;
    if (lower.endsWith('.onnx')) return ModelFormat.onnx;
    if (lower.endsWith('.bin')) return ModelFormat.bin;
    if (lower.endsWith('.ort')) return ModelFormat.ort;
    return ModelFormat.unknown;
  }
}
