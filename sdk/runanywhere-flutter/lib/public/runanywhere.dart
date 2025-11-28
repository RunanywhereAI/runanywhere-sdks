import 'dart:async';
import '../foundation/dependency_injection/service_container.dart';
import '../foundation/error_types/sdk_error.dart';
import '../foundation/logging/sdk_logger.dart';
import '../foundation/security/keychain_manager.dart';
import '../foundation/device_identity/device_manager.dart';
import '../foundation/configuration/sdk_constants.dart';
import 'configuration/sdk_environment.dart';
import 'events/event_bus.dart';
import 'events/sdk_event.dart';
import 'models/models.dart';
import '../capabilities/text_generation/generation_service.dart';
import '../capabilities/model_loading/models/loaded_model.dart';
import '../capabilities/structured_output/structured_output_handler.dart';
import '../capabilities/analytics/analytics_service.dart';
import '../core/module_registry.dart' show STTOptions;

// Export generation options
export '../capabilities/text_generation/generation_service.dart' show RunAnywhereGenerationOptions, GenerationResult, PerformanceMetrics;

/// The clean, event-based RunAnywhere SDK
/// Single entry point with both event-driven and async/await patterns
class RunAnywhere {
  // Internal state management
  static SDKInitParams? _initParams;
  static SDKEnvironment? _currentEnvironment;
  static bool _isInitialized = false;

  /// Access to service container
  static ServiceContainer get serviceContainer => ServiceContainer.shared;

  /// Check if SDK is initialized
  static bool get isSDKInitialized => _isInitialized;

  /// Access to all SDK events for subscription-based patterns
  static EventBus get events => EventBus.shared;

  /// Initialize the RunAnywhere SDK
  ///
  /// This method performs simple, fast initialization with no network calls:
  ///
  /// 1. **Validation**: Validate API key and parameters
  /// 2. **Logging**: Initialize logging system based on environment
  /// 3. **Storage**: Store parameters locally (no keychain for dev mode)
  /// 4. **State**: Mark SDK as initialized
  ///
  /// NO network calls, NO device registration, NO complex bootstrapping.
  /// Device registration happens lazily on first API call.
  ///
  /// [apiKey] Your RunAnywhere API key from the console
  /// [baseURL] Backend API base URL
  /// [environment] SDK environment (development/staging/production)
  ///
  /// Throws [SDKError] if validation fails
  static Future<void> initialize({
    required String apiKey,
    required String baseURL,
    SDKEnvironment environment = SDKEnvironment.production,
  }) async {
    final uri = Uri.tryParse(baseURL);
    if (uri == null) {
      throw SDKError.validationFailed('Invalid base URL: $baseURL');
    }

    await initializeWithParams(
      SDKInitParams(
        apiKey: apiKey,
        baseURL: uri,
        environment: environment,
      ),
    );
  }

  /// Initialize the SDK with parameters
  static Future<void> initializeWithParams(SDKInitParams params) async {
    if (_isInitialized) {
      return;
    }

    final logger = SDKLogger(category: 'RunAnywhere.Init');
    EventBus.shared.publish(SDKInitializationStarted());

    try {
      // Step 1: Validate API key (skip in development mode)
      if (params.environment != SDKEnvironment.development) {
        if (params.apiKey.isEmpty) {
          throw SDKError.invalidAPIKey('API key cannot be empty');
        }
      }

      // Step 2: Store parameters locally
      _initParams = params;
      _currentEnvironment = params.environment;

      // Only store in keychain for non-development environments
      if (params.environment != SDKEnvironment.development) {
        await KeychainManager.shared.storeSDKParams(
          apiKey: params.apiKey,
          baseURL: params.baseURL,
          environment: params.environment.name,
        );
      }

      // Step 3: Setup local services only (no network calls)
      await serviceContainer.setupLocalServices(
        apiKey: params.apiKey,
        baseURL: params.baseURL,
        environment: params.environment,
      );

      // Mark as initialized
      _isInitialized = true;

      logger.info(
        '✅ SDK initialization completed successfully (${params.environment.description} mode)',
      );
      EventBus.shared.publish(SDKInitializationCompleted());

      // Step 4: Device registration (after marking as initialized)
      // For development mode: Register immediately
      // For production/staging: Lazy registration on first API call
      if (params.environment == SDKEnvironment.development) {
        // Trigger device registration in background (non-blocking)
        unawaited(_ensureDeviceRegistered());
      }
    } catch (e) {
      logger.error('❌ SDK initialization failed: $e');
      _initParams = null;
      _currentEnvironment = null;
      _isInitialized = false;
      EventBus.shared.publish(SDKInitializationFailed(e));
      rethrow;
    }
  }

  /// Ensure device is registered with backend (lazy registration)
  static Future<void> _ensureDeviceRegistered() async {
    try {
      final deviceId = await DeviceManager.shared.getDeviceId();
      final logger = SDKLogger(category: 'RunAnywhere.DeviceReg');
      logger.info('✅ Device registered: ${deviceId.substring(0, 8)}...');
    } catch (e) {
      final logger = SDKLogger(category: 'RunAnywhere.DeviceReg');
      logger.warning('⚠️ Device registration failed (non-critical): $e');
    }
  }

  /// Simple text generation with automatic event publishing
  /// [prompt] The text prompt
  /// Returns Generated response (text only)
  static Future<String> chat(String prompt) async {
    final result = await generate(prompt);
    return result.text;
  }

  /// Text generation with options
  /// [prompt] The text prompt
  /// [options] Generation options (optional, defaults to maxTokens: 100)
  /// Returns Generated response
  static Future<GenerationResult> generate(
    String prompt, {
    RunAnywhereGenerationOptions? options,
  }) async {
    EventBus.shared.publish(SDKGenerationEvent.started(prompt: prompt));

    try {
      // Ensure initialized
      if (!_isInitialized) {
        throw SDKError.notInitialized();
      }

      // Lazy device registration on first API call
      await _ensureDeviceRegistered();

      // Use options directly or defaults
      final genOptions = options ?? RunAnywhereGenerationOptions();
      final result = await serviceContainer.generationService.generate(
        prompt: prompt,
        options: genOptions,
      );

      EventBus.shared.publish(SDKGenerationEvent.completed(
        response: result.text,
        tokensUsed: result.tokensUsed,
        latencyMs: result.latencyMs,
      ));

      if (result.savedAmount > 0) {
        EventBus.shared.publish(SDKGenerationEvent.costCalculated(
          amount: 0,
          savedAmount: result.savedAmount,
        ));
      }

      return result;
    } catch (e) {
      EventBus.shared.publish(SDKGenerationEvent.failed(e));
      rethrow;
    }
  }

  /// Streaming text generation
  /// [prompt] The text prompt
  /// [options] Generation options (optional)
  /// Returns Stream of tokens
  static Stream<String> generateStream(
    String prompt, {
    RunAnywhereGenerationOptions? options,
  }) {
    EventBus.shared.publish(SDKGenerationEvent.started(prompt: prompt));

    // Ensure initialized
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    // Lazy device registration on first API call
    unawaited(_ensureDeviceRegistered());

    final genOptions = options ?? RunAnywhereGenerationOptions();
    return serviceContainer.streamingService.generateStream(
      prompt: prompt,
      options: genOptions,
    );
  }

  /// Simple voice transcription
  /// [audioData] Audio data to transcribe
  /// Returns Transcribed text
  static Future<String> transcribe(List<int> audioData) async {
    EventBus.shared.publish(SDKVoiceTranscriptionStarted());

    try {
      // Ensure initialized
      if (!_isInitialized) {
        throw SDKError.notInitialized();
      }

      // Lazy device registration on first API call
      await _ensureDeviceRegistered();

      // Use voice capability service directly
      final voiceService = await serviceContainer.voiceCapabilityService
          .findVoiceService(modelId: 'whisper-base');
      if (voiceService == null) {
        throw SDKError.featureNotAvailable('No voice service available');
      }

      await voiceService.initialize(modelPath: 'whisper-base');
      final result = await voiceService.transcribe(
        audioData: audioData,
        options: STTOptions(),
      );

      EventBus.shared.publish(
        SDKVoiceTranscriptionFinal(text: result.transcript),
      );
      return result.transcript;
    } catch (e) {
      EventBus.shared.publish(SDKVoicePipelineError(error: e));
      rethrow;
    }
  }

  /// Load a model by ID
  /// [modelId] The model identifier
  static Future<void> loadModel(String modelId) async {
    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: modelId));

    try {
      // Ensure initialized
      if (!_isInitialized) {
        throw SDKError.notInitialized();
      }

      // Lazy device registration on first API call
      await _ensureDeviceRegistered();

      final loadedModel =
          await serviceContainer.modelLoadingService.loadModel(modelId);

      // IMPORTANT: Set the loaded model in the generation service
      serviceContainer.generationService.setCurrentModel(loadedModel);

      EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: modelId));
    } catch (e) {
      EventBus.shared.publish(
        SDKModelEvent.loadFailed(modelId: modelId, error: e),
      );
      rethrow;
    }
  }

  /// Get available models
  /// Returns Array of available models
  static Future<List<ModelInfo>> availableModels() async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    // Use model registry to get available models
    final models = await serviceContainer.modelRegistry.discoverModels();
    return models;
  }

  /// Get currently loaded model
  /// Returns Currently loaded model info
  static ModelInfo? get currentModel {
    if (!_isInitialized) {
      return null;
    }

    // Get the current model from the generation service
    final loadedModel = serviceContainer.generationService.getCurrentModel();
    return loadedModel?.model;
  }

  /// Get current SDK version
  /// Returns SDK version string
  static String getSDKVersion() {
    return SDKConstants.version;
  }

  /// Get current environment
  /// Returns Current SDK environment
  static SDKEnvironment? getCurrentEnvironment() {
    return _currentEnvironment;
  }

  /// Check if device is registered
  /// Returns true if device has been registered with backend
  static Future<bool> isDeviceRegistered() async {
    final deviceId = await DeviceManager.shared.getDeviceId();
    return deviceId.isNotEmpty;
  }

  /// Generate structured output that conforms to a Generatable type
  /// [type] The type to generate (must implement Generatable)
  /// [prompt] The prompt to generate from
  /// [options] Generation options (optional)
  /// Returns The generated object of the specified type
  static Future<T> generateStructuredOutput<T>({
    required Type type,
    required String prompt,
    RunAnywhereGenerationOptions? options,
  }) async {
    // Import structured output handler
    final handler = StructuredOutputHandler();

    // Get schema from type
    final schema = (type as dynamic).jsonSchema as String?;
    if (schema == null) {
      throw ArgumentError('Type must implement Generatable with jsonSchema');
    }

    // Build prompt with schema
    final enhancedPrompt = handler.buildPromptWithSchema(
      originalPrompt: prompt,
      schema: schema,
    );

    // Generate text
    final result = await generate(
      enhancedPrompt,
      options: options ?? RunAnywhereGenerationOptions(),
    );

    // Parse structured output
    return handler.parseStructuredOutput(
      from: result.text,
      type: type,
    ) as T;
  }

  /// Reset SDK state (for testing purposes)
  static void reset() {
    final logger = SDKLogger(category: 'RunAnywhere.Reset');
    logger.info('Resetting SDK state...');

    // Clear initialization state
    _isInitialized = false;
    _initParams = null;
    _currentEnvironment = null;

    // Reset service container if needed
    serviceContainer.reset();

    logger.info('SDK state reset completed');
  }
}

/// Helper function to mark futures as unawaited
void unawaited(Future<void> future) {
  // Intentionally not awaiting
}

