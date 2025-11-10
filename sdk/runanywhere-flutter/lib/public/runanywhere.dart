import 'dart:async';
import 'dart:typed_data';

import 'events/event_bus.dart';
import 'events/sdk_event.dart';
import 'errors/sdk_error.dart';
import 'models/configuration/sdk_init_params.dart';
import 'models/configuration/sdk_environment.dart';
import 'models/generation_result.dart';
import 'models/generation_options.dart';
import 'models/model_info.dart';
import '../foundation/dependency_injection/service_container.dart';
import '../foundation/logging/logger/sdk_logger.dart';
import '../capabilities/voice/models/stt_error.dart';
import '../capabilities/voice/models/stt_options.dart';

/// Main RunAnywhere SDK class
/// Similar to Swift SDK's RunAnywhere enum
class RunAnywhere {
  // Internal state
  static SDKInitParams? _initParams;
  static SDKEnvironment? _currentEnvironment;
  static bool _isInitialized = false;

  // Service container access
  static ServiceContainer get serviceContainer => ServiceContainer.shared;

  // Event bus access
  static EventBus get events => EventBus.shared;

  // Check if initialized
  static bool get isSDKInitialized => _isInitialized;

  /// Initialize the SDK
  static Future<void> initialize({
    required String apiKey,
    required String baseURL,
    SDKEnvironment environment = SDKEnvironment.production,
    SupabaseConfig? supabaseConfig,
  }) async {
    if (_isInitialized) return;

    final logger = SDKLogger(category: 'RunAnywhere.Init');
    EventBus.shared.publish(SDKInitializationEvent.started());

    try {
      // Step 1: Validate API key (skip in development mode)
      if (environment != SDKEnvironment.development) {
        if (apiKey.isEmpty) {
          throw SDKError.invalidAPIKey('API key cannot be empty');
        }
      }

      // Step 2: Initialize logging
      // TODO: Implement setLogLevel

      // Step 3: Store parameters
      _initParams = SDKInitParams.fromString(
        apiKey: apiKey,
        baseURL: baseURL,
        environment: environment,
        supabaseConfig: supabaseConfig,
      );
      _currentEnvironment = environment;

      // Step 4: Initialize database
      // TODO: Implement DatabaseManager

      // Step 5: Setup local services
      await serviceContainer.setupLocalServices(_initParams!);

      _isInitialized = true;

      logger.info('✅ SDK initialization completed successfully (${environment.description} mode)');
      EventBus.shared.publish(SDKInitializationEvent.completed());

      // Step 6: Lazy device registration (in background for dev mode)
      if (environment == SDKEnvironment.development) {
        unawaited(_ensureDeviceRegistered());
      }
    } catch (e) {
      logger.error('❌ SDK initialization failed: $e');
      _isInitialized = false;
      EventBus.shared.publish(SDKInitializationEvent.failed(
        SDKError('Initialization failed: $e') as Error?,
      ));
      rethrow;
    }
  }

  /// Simple text generation
  static Future<String> chat(String prompt) async {
    final result = await generate(prompt);
    return result.text;
  }

  /// Text generation with options
  static Future<GenerationResult> generate(
    String prompt, {
    RunAnywhereGenerationOptions? options,
  }) async {
    EventBus.shared.publish(SDKGenerationEvent.started(prompt: prompt));

    try {
      if (!_isInitialized) {
        throw SDKError.notInitialized();
      }

      await _ensureDeviceRegistered();

      final result = await serviceContainer.generationService.generate(
        prompt: prompt,
        options: options ?? RunAnywhereGenerationOptions(),
      );

      EventBus.shared.publish(SDKGenerationEvent.completed(
        response: result.text,
        tokensUsed: result.tokensUsed,
        latencyMs: result.latencyMs,
      ));

      return result;
    } catch (e) {
      EventBus.shared.publish(SDKGenerationEvent.failed(
        SDKError('Generation failed: $e') as Error?,
      ));
      rethrow;
    }
  }

  /// Streaming text generation
  static Stream<String> generateStream(
    String prompt, {
    RunAnywhereGenerationOptions? options,
  }) {
    EventBus.shared.publish(SDKGenerationEvent.started(prompt: prompt));

    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    return serviceContainer.streamingService.generateStream(
      prompt: prompt,
      options: options ?? RunAnywhereGenerationOptions(),
    );
  }

  /// Voice transcription
  static Future<String> transcribe(Uint8List audioData) async {
    EventBus.shared.publish(SDKVoiceEvent.transcriptionStarted());

    try {
      if (!_isInitialized) {
        throw SDKError.notInitialized();
      }

      await _ensureDeviceRegistered();

      final voiceService = await serviceContainer.voiceCapabilityService
          .findVoiceService('whisper-base');

      if (voiceService == null) {
        throw STTError.noVoiceServiceAvailable();
      }

      await voiceService.initialize(modelPath: 'whisper-base');
      final result = await voiceService.transcribe(
        audioData: audioData,
        options: STTOptions(),
      );

      EventBus.shared.publish(SDKVoiceEvent.transcriptionFinal(
        text: result.transcript,
      ));

      return result.transcript;
    } catch (e) {
      EventBus.shared.publish(SDKVoiceEvent.pipelineError(
        SDKError('Voice pipeline error: $e') as Error?,
      ));
      rethrow;
    }
  }

  /// Load a model
  static Future<void> loadModel(String modelId) async {
    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: modelId));

    try {
      if (!_isInitialized) {
        throw SDKError.notInitialized();
      }

      await _ensureDeviceRegistered();

      final loadedModel = await serviceContainer.modelLoadingService
          .loadModel(modelId);

      serviceContainer.generationService.setCurrentModel(loadedModel);

      EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: modelId));
    } catch (e) {
      EventBus.shared.publish(SDKModelEvent.loadFailed(
        modelId: modelId,
        error: SDKError('Model loading failed: $e') as Error?,
      ));
      rethrow;
    }
  }

  /// Get available models
  static Future<List<ModelInfo>> availableModels() async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    return await serviceContainer.modelRegistry.discoverModels();
  }

  /// Get current environment
  static SDKEnvironment? getCurrentEnvironment() {
    return _currentEnvironment;
  }

  /// Check if device is registered
  static bool isDeviceRegistered() {
    // TODO: Implement device registration check
    return false;
  }

  /// Reset SDK state (for testing)
  static void reset() {
    final logger = SDKLogger(category: 'RunAnywhere.Reset');
    logger.info('Resetting SDK state...');

    _isInitialized = false;
    _initParams = null;
    _currentEnvironment = null;

    serviceContainer.reset();

    logger.info('SDK state reset completed');
  }

  // Private helper methods
  static Future<void> _ensureDeviceRegistered() async {
    // TODO: Implement device registration
    // Similar to Swift SDK's ensureDeviceRegistered()
  }
}

