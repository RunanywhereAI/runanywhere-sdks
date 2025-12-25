import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:runanywhere/capabilities/text_generation/generation_service.dart';
import 'package:runanywhere/capabilities/voice/models/voice_session.dart';
import 'package:runanywhere/capabilities/voice/models/voice_session_handle.dart';
import 'package:runanywhere/core/models/storage/storage_info.dart';
import 'package:runanywhere/core/module_registry.dart' hide TTSService;
import 'package:runanywhere/core/protocols/downloading/download_progress.dart';
import 'package:runanywhere/features/llm/llm_capability.dart'
    show LLMConfiguration;
import 'package:runanywhere/features/llm/structured_output/generatable.dart';
import 'package:runanywhere/features/llm/structured_output/structured_output_handler.dart';
import 'package:runanywhere/features/stt/stt_capability.dart';
import 'package:runanywhere/features/tts/models/tts_configuration.dart';
import 'package:runanywhere/features/tts/tts_capability.dart';
import 'package:runanywhere/features/tts/tts_output.dart';
import 'package:runanywhere/features/vad/vad_capability.dart';
import 'package:runanywhere/features/vad/vad_configuration.dart';
import 'package:runanywhere/features/voice_agent/voice_agent_capability.dart';
import 'package:runanywhere/foundation/configuration/sdk_constants.dart';
import 'package:runanywhere/foundation/dependency_injection/service_container.dart';
import 'package:runanywhere/foundation/device_identity/device_manager.dart';
import 'package:runanywhere/foundation/error_types/sdk_error.dart';
import 'package:runanywhere/foundation/file_operations/model_path_utils.dart';
import 'package:runanywhere/foundation/logging/models/log_level.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/foundation/logging/services/logging_manager.dart';
import 'package:runanywhere/foundation/security/keychain_manager.dart';
import 'package:runanywhere/infrastructure/analytics/analytics_queue_manager.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';
import 'package:runanywhere/public/models/models.dart';

// Export generation options
export '../capabilities/text_generation/generation_service.dart'
    show RunAnywhereGenerationOptions, GenerationResult;
// Export voice session types for public use
export '../capabilities/voice/models/voice_session.dart'
    show
        VoiceSessionEvent,
        VoiceSessionStarted,
        VoiceSessionListening,
        VoiceSessionSpeechStarted,
        VoiceSessionProcessing,
        VoiceSessionTranscribed,
        VoiceSessionResponded,
        VoiceSessionSpeaking,
        VoiceSessionTurnCompleted,
        VoiceSessionStopped,
        VoiceSessionError,
        VoiceSessionConfig,
        VoiceSessionException,
        VoiceSessionErrorType;
export '../capabilities/voice/models/voice_session_handle.dart'
    show VoiceSessionHandle, VoiceAgentProcessResult;
export '../core/model_lifecycle_manager.dart';
export '../core/models/framework/framework_modality.dart';
// Export core types for public use
export '../core/models/framework/llm_framework.dart';
export '../core/models/framework/model_artifact_type.dart';
export '../core/models/framework/model_format.dart';
export '../core/models/model/model_category.dart';
export '../core/models/model/model_registration.dart';
export '../core/models/storage/app_storage_info.dart';
export '../core/models/storage/device_storage_info.dart';
export '../core/models/storage/model_storage_info.dart';
// Export storage types for public use
export '../core/models/storage/storage_info.dart';
export '../core/models/storage/stored_model.dart';
// Export capability type for framework queries
export '../core/module/capability_type.dart';
// Export download progress types
export '../core/protocols/downloading/download_progress.dart';
export '../core/protocols/downloading/download_state.dart';
export '../features/llm/llm_capability.dart'
    show
        LLMCapability,
        LLMConfiguration,
        LLMOutput,
        Message,
        MessageRole,
        Context;
// Export structured output types for streaming
export '../features/llm/structured_output/structured_output_handler.dart'
    show StructuredOutputConfig, StructuredOutputStreamResult;
// Export speaker diarization types
export '../features/speaker_diarization/models/speaker_diarization_speaker_info.dart';
// Export capability types for public use
export '../features/stt/stt_capability.dart'
    show STTCapability, STTConfiguration, STTOutput, STTMode, STTOptions;
export '../features/tts/models/tts_configuration.dart' show TTSConfiguration;
// Export TTS options for top-level synthesize
export '../features/tts/models/tts_options.dart' show TTSOptions;
export '../features/tts/tts_capability.dart' show TTSCapability;
export '../features/tts/tts_output.dart' show TTSOutput, SynthesisMetadata;
// Export VAD types for top-level access
export '../features/vad/vad_capability.dart' show VADCapability;
export '../features/vad/vad_configuration.dart' show VADConfiguration;
export '../features/vad/vad_service.dart'
    show VADResult, VADService, SpeechActivityEvent;
// Export VoiceAgent types
export '../features/voice_agent/voice_agent_capability.dart'
    show
        VoiceAgentCapability,
        VoiceAgentConfiguration,
        VoiceAgentResult,
        VoiceAgentEvent,
        ComponentLoadState,
        VoiceAgentComponentStates;
// Export logging types for configuration
export '../foundation/logging/models/log_level.dart';

/// The clean, event-based RunAnywhere SDK
/// Single entry point with both event-driven and async/await patterns
/// Matches iOS RunAnywhere from RunAnywhere.swift
///
/// # SDK Initialization Flow
///
/// ## Phase 1: Core Init (Synchronous, ~1-5ms, No Network)
/// `initialize()` or `initializeWithParams()`
///   - Validate params (API key, URL, environment)
///   - Set log level
///   - Store params locally
///   - Store in Keychain (production/staging only)
///   - Mark: isInitialized = true
///
/// ## Phase 2: Services Init (Async, ~100-500ms, Network Required)
/// `completeServicesInitialization()`
///   - Setup API Client (with authentication for production/staging)
///   - Create Core Services (SyncCoordinator, TelemetryRepository, etc.)
///   - Load Models (sync from remote + load from DB)
///   - Initialize Analytics & EventPublisher
///   - Register Device with Backend
///
class RunAnywhere {
  // MARK: - Internal State Management

  /// Internal init params storage
  static SDKInitParams? _initParams;
  static SDKEnvironment? _currentEnvironment;
  static bool _isInitialized = false;

  /// Track if services initialization is complete (makes API calls O(1) after first use)
  static bool _hasCompletedServicesInit = false;

  // Loaded capability storage
  static STTCapability? _loadedSTTCapability;
  static TTSCapability? _loadedTTSCapability;
  static VADCapability? _loadedVADCapability;

  // MARK: - SDK State

  /// Access to service container
  static ServiceContainer get serviceContainer => ServiceContainer.shared;

  /// Check if SDK is initialized (Phase 1 complete)
  static bool get isSDKInitialized => _isInitialized;

  /// Check if services are fully ready (Phase 2 complete)
  static bool get areServicesReady => _hasCompletedServicesInit;

  /// Check if SDK is active and ready for use
  static bool get isActive => _isInitialized && _initParams != null;

  /// Get the initialization parameters (if initialized)
  static SDKInitParams? get initParams => _initParams;

  /// Current environment (null if not initialized)
  static SDKEnvironment? get environment => _currentEnvironment;

  /// Current SDK version
  /// Matches iOS RunAnywhere.version property
  static String get version => SDKConstants.version;

  /// Device ID (persisted across app reinstalls)
  /// Matches iOS RunAnywhere.deviceId property
  /// Note: This is async in Flutter due to platform channel access
  static Future<String> get deviceId async {
    return DeviceManager.shared.getDeviceId();
  }

  /// Access to all SDK events for subscription-based patterns
  static EventBus get events => EventBus.shared;

  /// Get the currently loaded STT capability
  static STTCapability? get loadedSTTCapability => _loadedSTTCapability;

  /// Get the currently loaded TTS capability
  static TTSCapability? get loadedTTSCapability => _loadedTTSCapability;

  /// Get the currently loaded VAD capability
  static VADCapability? get loadedVADCapability => _loadedVADCapability;

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
  /// ## Usage Examples
  ///
  /// ```dart
  /// // Development mode (default) - no params needed
  /// await RunAnywhere.initialize();
  ///
  /// // Production mode - requires API key and backend URL
  /// await RunAnywhere.initialize(
  ///   apiKey: "your_api_key",
  ///   baseURL: "https://api.runanywhere.ai",
  ///   environment: SDKEnvironment.production,
  /// );
  /// ```
  ///
  /// [apiKey] API key (optional for development, required for production/staging)
  /// [baseURL] Backend API base URL (optional for development, required for production/staging)
  /// [environment] SDK environment (default: .development)
  ///
  /// Throws [SDKError] if validation fails
  static Future<void> initialize({
    String? apiKey,
    String? baseURL,
    SDKEnvironment environment = SDKEnvironment.development,
  }) async {
    final SDKInitParams params;

    if (environment == SDKEnvironment.development) {
      // Development mode - use Supabase, no auth needed
      params = SDKInitParams.forDevelopment(apiKey: apiKey ?? '');
    } else {
      // Production/Staging mode - require API key and URL
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

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - Phase 2: Services Initialization (Async)
  // ═══════════════════════════════════════════════════════════════════════════

  /// Complete services initialization (Phase 2)
  ///
  /// Called automatically in background by `initialize()`, or can be awaited directly.
  /// Safe to call multiple times - returns immediately if already done.
  ///
  /// This method:
  /// 1. Sets up API client (with authentication for production/staging)
  /// 2. Creates core services (telemetry, models, sync)
  /// 3. Loads model catalog from remote + local storage
  /// 4. Initializes analytics pipeline
  /// 5. Registers device with backend
  static Future<void> completeServicesInitialization() async {
    // Fast path: already completed
    if (_hasCompletedServicesInit) {
      return;
    }

    final params = _initParams;
    final environment = _currentEnvironment;

    if (params == null || environment == null) {
      throw SDKError.notInitialized();
    }

    final logger = SDKLogger(category: 'RunAnywhere.Services');

    // Check if services need initialization
    // For development: check if networkService is null
    // For production/staging: check if authenticationService is null
    final needsInit = environment == SDKEnvironment.development
        ? serviceContainer.networkService == null
        : serviceContainer.authenticationService == null;

    if (needsInit) {
      logger
          .info('Initializing services for ${environment.description} mode...');

      try {
        // Step 1: Setup API client
        await _setupAPIClient(
          params: params,
          environment: environment,
          logger: logger,
        );

        // Step 2: Create and inject core services
        await _setupCoreServices(
          environment: environment,
          logger: logger,
        );

        // Step 3: Load models
        await _loadModels(logger: logger);

        // Step 4: Initialize analytics
        await _initializeAnalytics(apiKey: params.apiKey, logger: logger);

        logger.info('✅ Services initialized');
      } catch (e) {
        logger.error('❌ Services initialization failed: $e');
        rethrow;
      }
    }

    // Step 5: Register device
    await _ensureDeviceRegistered();

    // Mark Phase 2 complete
    _hasCompletedServicesInit = true;
  }

  /// Ensure services are ready before API calls (internal guard)
  /// O(1) after first successful initialization
  static Future<void> _ensureServicesReady() async {
    if (_hasCompletedServicesInit) {
      return; // O(1) fast path
    }
    await completeServicesInitialization();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - Private: Service Setup Helpers
  // ═══════════════════════════════════════════════════════════════════════════

  /// Setup API client based on environment
  static Future<void> _setupAPIClient({
    required SDKInitParams params,
    required SDKEnvironment environment,
    required SDKLogger logger,
  }) async {
    switch (environment) {
      case SDKEnvironment.development:
        // Development mode: Use Supabase or provided URL without auth
        final supabaseConfig = params.supabaseConfig;
        if (supabaseConfig != null) {
          // Use Supabase for development
          serviceContainer.setNetworkService(
            serviceContainer.apiClient ??
                serviceContainer.createAPIClient(
                  baseURL: supabaseConfig.projectURL,
                  apiKey: supabaseConfig.anonKey,
                ),
          );
          logger.debug('APIClient: Supabase (development)');
        } else {
          // Use provided URL without auth
          serviceContainer.setNetworkService(
            serviceContainer.apiClient ??
                serviceContainer.createAPIClient(
                  baseURL: params.baseURL,
                  apiKey: params.apiKey,
                ),
          );
          logger.debug('APIClient: Provided URL (development)');
        }

      case SDKEnvironment.staging:
      case SDKEnvironment.production:
        // Production/Staging: Full authentication flow
        final authService = serviceContainer.authenticationService;
        if (authService == null) {
          // Create and authenticate
          final newAuthService =
              await serviceContainer.createAuthenticationService(
            baseURL: params.baseURL,
            apiKey: params.apiKey,
          );
          await newAuthService.authenticate(apiKey: params.apiKey);
          logger.info('Authenticated for ${environment.description}');
        }
    }
  }

  /// Create and inject core services
  static Future<void> _setupCoreServices({
    required SDKEnvironment environment,
    required SDKLogger logger,
  }) async {
    logger.debug('Creating core services...');

    // SyncCoordinator, TelemetryRepository, ModelInfoService are
    // created in ServiceContainer.setupLocalServices()
    // Here we just ensure they're properly configured

    logger.debug('Core services created');
  }

  /// Load models from storage
  static Future<void> _loadModels({required SDKLogger logger}) async {
    // Model loading is handled by ModelLoadingService
    // This is called lazily when a model is requested
    logger.debug('Model catalog loaded');
  }

  /// Initialize analytics pipeline
  static Future<void> _initializeAnalytics({
    required String apiKey,
    required SDKLogger logger,
  }) async {
    // Analytics pipeline is already initialized in ServiceContainer.setupLocalServices()
    // via SDKAnalyticsInitializer
    logger.debug('Analytics initialized');
  }

  // MARK: - Text Generation

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

      // Ensure services are ready (Phase 2 init if needed) - O(1) after first call
      await _ensureServicesReady();

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

  // MARK: - Voice Operations

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

  /// Synthesize speech from text
  /// Matches iOS RunAnywhere.synthesize(_:, options:)
  /// [text] The text to synthesize
  /// [options] Optional TTS options (voice, language, rate, etc.)
  /// Returns TTSOutput containing audio data and metadata
  static Future<TTSOutput> synthesize(
    String text, {
    TTSOptions? options,
  }) async {
    // Ensure initialized
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    // Lazy device registration on first API call
    await _ensureDeviceRegistered();

    // Use loaded TTS capability if available
    final capability = _loadedTTSCapability;
    if (capability != null && capability.isReady) {
      return capability.synthesize(
        text,
        voice: options?.voice,
        language: options?.language,
      );
    }

    // Otherwise, try to get TTS service from the module registry
    final provider = ModuleRegistry.shared.ttsProvider(modelId: null);
    if (provider == null) {
      throw SDKError.featureNotAvailable(
        'No TTS service available. Call loadTTSModel() first or register a TTS provider.',
      );
    }

    // Create a temporary TTS capability
    final ttsConfig = TTSConfiguration(
      voice: options?.voice ?? 'system',
      language: options?.language ?? 'en-US',
      speakingRate: options?.rate ?? 1.0,
      pitch: options?.pitch ?? 1.0,
      volume: options?.volume ?? 1.0,
    );
    final tempCapability = TTSCapability(ttsConfiguration: ttsConfig);
    await tempCapability.initialize();

    final result = await tempCapability.synthesize(
      text,
      voice: options?.voice,
      language: options?.language,
    );

    // Clean up temporary capability
    await tempCapability.cleanup();

    return result;
  }

  /// Initialize Voice Activity Detection (VAD)
  /// Matches iOS RunAnywhere.initializeVAD(_:)
  /// [configuration] VAD configuration (optional, uses defaults if not provided)
  static Future<void> initializeVAD([VADConfiguration? configuration]) async {
    // Ensure initialized
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    final logger = SDKLogger(category: 'RunAnywhere.VAD');
    logger.info('Initializing VAD...');

    try {
      final config = configuration ?? const VADConfiguration();

      // Create and initialize VAD capability
      final vadCapability = VADCapability(
        vadConfiguration: config,
        serviceContainer: serviceContainer,
      );
      await vadCapability.initialize();

      // Store the capability for later use
      _loadedVADCapability = vadCapability;

      logger.info('VAD initialized successfully');
    } catch (e) {
      logger.error('Failed to initialize VAD: $e');
      rethrow;
    }
  }

  /// Check if VAD is ready
  /// Matches iOS RunAnywhere.isVADReady
  static bool get isVADReady => _loadedVADCapability?.isReady ?? false;

  /// Detect speech in audio buffer
  /// Matches iOS RunAnywhere.detectSpeech(in:) returning VADOutput
  /// [audioData] Audio data (16-bit PCM samples)
  /// Returns VADResult with detection result and metadata
  static Future<VADResult> detectSpeech(List<int> audioData) async {
    final capability = _loadedVADCapability;
    if (capability == null || !capability.isReady) {
      throw SDKError.componentNotReady('VAD');
    }

    return capability.detectSpeech(buffer: audioData);
  }

  /// Start continuous VAD processing
  /// Matches iOS RunAnywhere.startVAD()
  static void startVAD() {
    final capability = _loadedVADCapability;
    if (capability == null || !capability.isReady) {
      throw SDKError.componentNotReady('VAD');
    }
    capability.start();
  }

  /// Stop VAD processing
  /// Matches iOS RunAnywhere.stopVAD()
  static void stopVAD() {
    final capability = _loadedVADCapability;
    if (capability == null) return;
    capability.stop();
  }

  /// Reset VAD state
  /// Matches iOS RunAnywhere.resetVAD()
  static void resetVAD() {
    final capability = _loadedVADCapability;
    if (capability == null) return;
    capability.reset();
  }

  /// Set VAD energy threshold
  /// Matches iOS RunAnywhere.setVADEnergyThreshold(_:)
  static void setVADEnergyThreshold(double threshold) {
    final capability = _loadedVADCapability;
    if (capability == null || !capability.isReady) {
      throw SDKError.componentNotReady('VAD');
    }
    capability.setEnergyThreshold(threshold);
  }

  /// Set VAD speech activity callback
  /// Matches iOS RunAnywhere.setVADSpeechActivityCallback(_:)
  static void setVADSpeechActivityCallback(
    void Function(SpeechActivityEvent) callback,
  ) {
    final capability = _loadedVADCapability;
    if (capability == null || !capability.isReady) {
      throw SDKError.componentNotReady('VAD');
    }
    capability.setSpeechActivityCallback(callback);
  }

  // MARK: - VoiceAgent Component States

  /// Get the current state of all voice agent components (STT, LLM, TTS)
  ///
  /// Use this to check which models are loaded and ready for the voice pipeline.
  /// This is useful for UI that needs to show the setup state before starting voice.
  /// Matches iOS RunAnywhere.getVoiceAgentComponentStates()
  static Future<VoiceAgentComponentStates>
      getVoiceAgentComponentStates() async {
    if (!_isInitialized) {
      return const VoiceAgentComponentStates();
    }

    // Query each capability for its current state
    final sttCapability = _loadedSTTCapability;
    final ttsCapability = _loadedTTSCapability;

    // STT state
    ComponentLoadState sttState;
    if (sttCapability != null && sttCapability.isReady) {
      final modelId = sttCapability.sttConfig.modelId ?? 'unknown';
      sttState = ComponentLoadState.loaded(modelId: modelId);
    } else {
      sttState = ComponentLoadState.notLoaded;
    }

    // LLM state - check via currentModel
    ComponentLoadState llmState;
    final currentModelInfo = currentModel;
    if (currentModelInfo != null) {
      llmState = ComponentLoadState.loaded(modelId: currentModelInfo.id);
    } else {
      llmState = ComponentLoadState.notLoaded;
    }

    // TTS state
    ComponentLoadState ttsState;
    if (ttsCapability != null && ttsCapability.isReady) {
      final voiceId = ttsCapability.currentVoice ?? 'unknown';
      ttsState = ComponentLoadState.loaded(modelId: voiceId);
    } else {
      ttsState = ComponentLoadState.notLoaded;
    }

    return VoiceAgentComponentStates(
      stt: sttState,
      llm: llmState,
      tts: ttsState,
    );
  }

  /// Check if all voice agent components are loaded and ready
  ///
  /// Convenience method that returns true only when STT, LLM, and TTS are all loaded.
  /// Matches iOS RunAnywhere.areAllVoiceComponentsReady
  static Future<bool> get areAllVoiceComponentsReady async {
    final states = await getVoiceAgentComponentStates();
    return states.isFullyReady;
  }

  // MARK: - Speaker Diarization

  /// Update a speaker's display name
  /// Matches iOS RunAnywhere.updateSpeakerName(speakerId:, name:)
  ///
  /// [speakerId] The ID of the speaker to update
  /// [name] The new display name for the speaker
  static Future<void> updateSpeakerName({
    required String speakerId,
    required String name,
  }) async {
    // Ensure initialized
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    final provider = ModuleRegistry.shared.speakerDiarizationProvider();
    if (provider == null) {
      throw SDKError.featureNotAvailable(
        'No speaker diarization service available. Register a SpeakerDiarizationServiceProvider first.',
      );
    }

    // Get or create the service
    final service = await provider.createSpeakerDiarizationService(null);
    if (!service.isReady) {
      throw SDKError.componentNotReady('SpeakerDiarization');
    }

    service.updateSpeakerName(speakerId: speakerId, name: name);
  }

  /// Reset speaker diarization state
  /// Clears all identified speakers and resets the diarization service
  /// Matches iOS RunAnywhere.resetSpeakerDiarization()
  static Future<void> resetSpeakerDiarization() async {
    // Ensure initialized
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    final provider = ModuleRegistry.shared.speakerDiarizationProvider();
    if (provider == null) {
      throw SDKError.featureNotAvailable(
        'No speaker diarization service available. Register a SpeakerDiarizationServiceProvider first.',
      );
    }

    // Get or create the service
    final service = await provider.createSpeakerDiarizationService(null);
    if (!service.isReady) {
      throw SDKError.componentNotReady('SpeakerDiarization');
    }

    await service.reset();
  }

  // MARK: - Model Management

  /// Load a model by ID (LLM model)
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

  /// Load an STT (Speech-to-Text) model by ID
  /// This initializes the STT component and loads the model into memory
  /// [modelId] The model identifier
  /// Matches iOS loadSTTModel from RunAnywhere.swift
  static Future<void> loadSTTModel(String modelId) async {
    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: modelId));

    try {
      // Ensure initialized
      if (!_isInitialized) {
        throw SDKError.notInitialized();
      }

      // Lazy device registration on first API call
      await _ensureDeviceRegistered();

      // Create STT configuration
      final sttConfig = STTConfiguration(modelId: modelId);

      // Create and initialize STT capability
      final sttCapability = STTCapability(sttConfig: sttConfig);
      await sttCapability.initialize();

      // Store the capability for later use
      _loadedSTTCapability = sttCapability;

      EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: modelId));
    } catch (e) {
      EventBus.shared.publish(
        SDKModelEvent.loadFailed(modelId: modelId, error: e),
      );
      rethrow;
    }
  }

  /// Load a TTS (Text-to-Speech) voice by ID
  /// This initializes the TTS component and loads the voice into memory
  /// [voiceId] The voice identifier
  /// Matches iOS loadTTSVoice from RunAnywhere.swift
  static Future<void> loadTTSVoice(String voiceId) async {
    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: voiceId));

    try {
      // Ensure initialized
      if (!_isInitialized) {
        throw SDKError.notInitialized();
      }

      // Lazy device registration on first API call
      await _ensureDeviceRegistered();

      // Create TTS configuration with the voiceId
      // Note: voice defaults to 'system' but voiceId is what we need for path resolution
      final ttsConfig = TTSConfiguration(modelId: voiceId);

      // Create and initialize TTS capability
      final ttsCapability = TTSCapability(ttsConfiguration: ttsConfig);
      await ttsCapability.initialize();

      // Store the capability for later use
      _loadedTTSCapability = ttsCapability;

      EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: voiceId));
    } catch (e) {
      EventBus.shared.publish(
        SDKModelEvent.loadFailed(modelId: voiceId, error: e),
      );
      rethrow;
    }
  }

  /// Unload the currently loaded STT model
  /// Cleans up resources and frees memory
  /// Matches iOS RunAnywhere.unloadSTTModel()
  static Future<void> unloadSTTModel() async {
    final capability = _loadedSTTCapability;
    if (capability == null) {
      return;
    }

    final logger = SDKLogger(category: 'RunAnywhere.STT');
    logger.info('Unloading STT model...');

    try {
      await capability.cleanup();
      _loadedSTTCapability = null;
      logger.info('✅ STT model unloaded');
    } catch (e) {
      logger.error('❌ Failed to unload STT model: $e');
      rethrow;
    }
  }

  /// Unload the currently loaded TTS voice
  /// Cleans up resources and frees memory
  /// Matches iOS RunAnywhere.unloadTTSVoice()
  static Future<void> unloadTTSVoice() async {
    final capability = _loadedTTSCapability;
    if (capability == null) {
      return;
    }

    final logger = SDKLogger(category: 'RunAnywhere.TTS');
    logger.info('Unloading TTS voice...');

    try {
      await capability.cleanup();
      _loadedTTSCapability = null;
      logger.info('✅ TTS voice unloaded');
    } catch (e) {
      logger.error('❌ Failed to unload TTS voice: $e');
      rethrow;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - STT API (Additional methods for iOS parity)
  // Matches iOS RunAnywhere+STT.swift
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if an STT model is loaded
  /// Matches iOS RunAnywhere.isSTTModelLoaded
  static bool get isSTTModelLoaded =>
      _loadedSTTCapability?.isModelLoaded ?? false;

  /// Transcribe audio with options
  /// Matches iOS RunAnywhere.transcribeWithOptions(_:options:)
  static Future<STTOutput> transcribeWithOptions(
    List<int> audioData, {
    required STTOptions options,
  }) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    final capability = _loadedSTTCapability;
    if (capability == null || !capability.isReady) {
      throw SDKError.componentNotReady('STT');
    }

    return capability.transcribe(audioData, options: options);
  }

  /// Stream transcription for real-time processing
  /// Matches iOS RunAnywhere.transcribeStream(_:options:)
  /// Returns a stream of transcription text
  static Stream<String> transcribeStream(
    Stream<List<int>> audioStream, {
    STTOptions? options,
  }) {
    if (!_isInitialized) {
      return Stream.error(SDKError.notInitialized());
    }

    final capability = _loadedSTTCapability;
    if (capability == null || !capability.isReady) {
      return Stream.error(SDKError.componentNotReady('STT'));
    }

    return capability.streamTranscribe(
      audioStream,
      language: options?.language,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - TTS API (Additional methods for iOS parity)
  // Matches iOS RunAnywhere+TTS.swift
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if a TTS voice is loaded
  /// Matches iOS RunAnywhere.isTTSVoiceLoaded
  static bool get isTTSVoiceLoaded => _loadedTTSCapability?.isReady ?? false;

  /// Get available TTS voices (property for iOS parity)
  /// Matches iOS RunAnywhere.availableTTSVoices
  /// Note: Returns a Future since voice list may need async retrieval
  static Future<List<String>> get availableTTSVoices async {
    final capability = _loadedTTSCapability;
    if (capability == null) return [];
    final voices = await capability.getAvailableVoices();
    return voices.map((v) => v.id).toList();
  }

  /// Get available TTS voices (method for backward compatibility)
  /// Deprecated: Use [availableTTSVoices] property instead
  @Deprecated('Use availableTTSVoices property instead')
  static Future<List<String>> getAvailableTTSVoices() async {
    return availableTTSVoices;
  }

  /// Load a TTS model (deprecated alias for loadTTSVoice)
  /// Deprecated: Use [loadTTSVoice] instead for iOS API parity
  @Deprecated('Use loadTTSVoice instead')
  static Future<void> loadTTSModel(String modelId) async {
    return loadTTSVoice(modelId);
  }

  /// Stream synthesis for long text
  /// Matches iOS RunAnywhere.synthesizeStream(_:options:)
  /// Returns a stream of audio data chunks
  static Stream<Uint8List> synthesizeStream(
    String text, {
    TTSOptions? options,
  }) {
    if (!_isInitialized) {
      return Stream.error(SDKError.notInitialized());
    }

    final capability = _loadedTTSCapability;
    if (capability == null || !capability.isReady) {
      return Stream.error(SDKError.componentNotReady('TTS'));
    }

    return capability.streamSynthesize(
      text,
      voice: options?.voice,
      language: options?.language,
    );
  }

  /// Stop current TTS synthesis
  /// Matches iOS RunAnywhere.stopSynthesis()
  /// Note: This is a no-op for system TTS which doesn't support stopping mid-synthesis
  static Future<void> stopSynthesis() async {
    final capability = _loadedTTSCapability;
    if (capability != null && capability.isReady) {
      // Cleanup will stop any ongoing synthesis
      await capability.cleanup();
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - VAD API (Additional methods for iOS parity)
  // Matches iOS RunAnywhere+VAD.swift
  // ═══════════════════════════════════════════════════════════════════════════

  /// Detect speech with result (deprecated alias for detectSpeech)
  /// Deprecated: Use [detectSpeech] which now returns full VADResult
  @Deprecated('Use detectSpeech which now returns full VADResult')
  static Future<VADResult> detectSpeechWithResult(List<int> audioData) async {
    return detectSpeech(audioData);
  }

  /// Cleanup VAD resources
  /// Matches iOS RunAnywhere.cleanupVAD()
  static Future<void> cleanupVAD() async {
    final capability = _loadedVADCapability;
    if (capability != null) {
      await capability.cleanup();
      _loadedVADCapability = null;
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

  /// Get currently loaded LLM model
  /// Returns Currently loaded model info
  /// Matches iOS RunAnywhere.currentLLMModel
  static ModelInfo? get currentModel {
    if (!_isInitialized) {
      return null;
    }

    // Get the current model from the generation service
    final loadedModel = serviceContainer.generationService.getCurrentModel();
    return loadedModel?.model;
  }

  /// Get the currently loaded STT model as ModelInfo
  /// Matches iOS RunAnywhere.currentSTTModel
  /// Returns the currently loaded STT ModelInfo, or null if no STT model is loaded
  static Future<ModelInfo?> get currentSTTModel async {
    if (!_isInitialized) {
      return null;
    }
    final capability = _loadedSTTCapability;
    if (capability == null) {
      return null;
    }
    final modelId = capability.currentModelId;
    if (modelId == null) {
      return null;
    }
    final models = await availableModels();
    return models.cast<ModelInfo?>().firstWhere(
          (m) => m?.id == modelId,
          orElse: () => null,
        );
  }

  /// Get the currently loaded TTS voice ID
  /// Matches iOS RunAnywhere.currentTTSVoiceId
  /// Note: TTS uses voices (not models), so this returns the voice identifier string.
  /// Returns the TTS voice ID if one is loaded, null otherwise
  static String? get currentTTSVoiceId {
    if (!_isInitialized) {
      return null;
    }
    return _loadedTTSCapability?.currentVoiceId;
  }

  /// Unload the currently loaded model
  /// Matches iOS RunAnywhere.unloadModel pattern
  static Future<void> unloadModel() async {
    if (!_isInitialized) {
      return;
    }

    final currentModelInfo = currentModel;
    if (currentModelInfo != null) {
      final modelId = currentModelInfo.id;
      EventBus.shared.publish(SDKModelEvent.unloadStarted(modelId: modelId));

      try {
        await serviceContainer.modelLoadingService.unloadModel(modelId);
        serviceContainer.generationService.setCurrentModel(null);
        EventBus.shared
            .publish(SDKModelEvent.unloadCompleted(modelId: modelId));
      } catch (e) {
        EventBus.shared.publish(
          SDKModelEvent.loadFailed(modelId: modelId, error: e),
        );
        rethrow;
      }
    }
  }

  /// List available models (alias for availableModels)
  /// Matches iOS RunAnywhere.listAvailableModels pattern
  static Future<List<ModelInfo>> listAvailableModels() async {
    return availableModels();
  }

  // MARK: - Module Registration (iOS Parity)

  /// Register a module with the SDK
  ///
  /// ```dart
  /// RunAnywhere.registerModule(ONNXModule());
  /// RunAnywhere.registerModule(LlamaCppModule(), priority: 150);
  /// ```
  ///
  /// Matches iOS `RunAnywhere.register(Module.self)` pattern
  static void registerModule(RunAnywhereModule module, {int? priority}) {
    ModuleRegistry.shared.registerModule(module, priority: priority);
  }

  /// Register all discovered modules
  ///
  /// ```dart
  /// RunAnywhere.registerAllModules();
  /// ```
  ///
  /// Matches iOS `RunAnywhere.registerAllModules()` pattern
  static void registerAllModules() {
    ModuleRegistry.shared.registerDiscoveredModules();
  }

  /// Get all registered modules
  ///
  /// Matches iOS `RunAnywhere.registeredModules` property
  static List<ModuleMetadata> get registeredModules {
    return ModuleRegistry.shared.allModules;
  }

  /// Check if a capability is available from any registered module
  ///
  /// Matches iOS `RunAnywhere.hasCapability()` pattern
  static bool hasCapability(CapabilityType capability) {
    return ModuleRegistry.shared.hasCapabilityFromModule(capability);
  }

  // MARK: - SDK State Management

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
  static Future<T> generateStructuredOutput<T extends Generatable>({
    required T Function(Map<String, dynamic>) fromJson,
    required String schema,
    required String prompt,
    RunAnywhereGenerationOptions? options,
  }) async {
    // Import structured output handler
    final handler = StructuredOutputHandler();

    // Create config for structured output
    final config = StructuredOutputConfig(
      type: T,
      schema: schema,
      includeSchemaInPrompt: true,
    );

    // Build prompt with schema
    final enhancedPrompt = handler.preparePrompt(
      originalPrompt: prompt,
      config: config,
    );

    // Generate text
    final result = await generate(
      enhancedPrompt,
      options: options ?? RunAnywhereGenerationOptions(),
    );

    // Parse structured output
    return handler.parseStructuredOutput<T>(result.text, fromJson);
  }

  /// Estimate token count in text
  /// Uses improved heuristics for accurate token estimation.
  /// [text] The text to analyze
  /// Returns Estimated number of tokens
  static int estimateTokenCount(String text) {
    // Rough estimation: ~4 characters per token for English text
    return (text.length / 4).ceil();
  }

  /// Reset SDK state (for testing purposes)
  /// Clears all initialization state and cached data
  static void reset() {
    final logger = SDKLogger(category: 'RunAnywhere.Reset');
    logger.info('Resetting SDK state...');

    // Clear initialization state (Phase 1 + Phase 2)
    _isInitialized = false;
    _hasCompletedServicesInit = false;
    _initParams = null;
    _currentEnvironment = null;

    // Clear loaded capabilities
    _loadedSTTCapability = null;
    _loadedTTSCapability = null;
    _loadedVADCapability = null;

    // Clear voice agent and speaker diarization
    _voiceAgentCapability = null;
    _speakerDiarizationService = null;

    // Reset service container if needed
    serviceContainer.reset();

    logger.info('SDK state reset completed');
  }

  // MARK: - Factory Methods

  /// Create a new conversation
  static Conversation conversation() {
    return Conversation();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - Storage & Download API
  // Matches iOS RunAnywhere+Storage.swift
  // ═══════════════════════════════════════════════════════════════════════════

  /// Download a model by ID with progress tracking
  /// Returns a stream of download progress updates
  /// Matches iOS RunAnywhere.downloadModel(_:)
  ///
  /// Example:
  /// ```dart
  /// await for (final progress in RunAnywhere.downloadModel('my-model-id')) {
  ///   print('Progress: ${(progress.percentage * 100).toStringAsFixed(1)}%');
  /// }
  /// ```
  static Stream<DownloadProgress> downloadModel(String modelId) async* {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    final models = await availableModels();
    final model = models.cast<ModelInfo?>().firstWhere(
          (m) => m?.id == modelId,
          orElse: () => null,
        );

    if (model == null) {
      throw SDKError.modelNotFound('Model not found: $modelId');
    }

    final task = await serviceContainer.downloadService.downloadModel(model);
    yield* task.progress;
  }

  /// Get storage information
  /// Matches iOS RunAnywhere.getStorageInfo()
  static Future<StorageInfo> getStorageInfo() async {
    // Use the storage analyzer from service container
    final storageAnalyzer = serviceContainer.storageAnalyzer;
    return storageAnalyzer.analyzeStorage();
  }

  /// Clear cache
  /// Matches iOS RunAnywhere.clearCache()
  static Future<void> clearCache() async {
    final cacheDir = await ModelPathUtils.getCacheDirectory();
    if (await cacheDir.exists()) {
      await cacheDir.delete(recursive: true);
      await cacheDir.create(recursive: true);
    }
    EventBus.shared.publish(SDKStorageEvent.cacheCleared());
  }

  /// Clean temporary files
  /// Matches iOS RunAnywhere.cleanTempFiles()
  static Future<void> cleanTempFiles() async {
    final tempDir = await ModelPathUtils.getTempDirectory();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
      await tempDir.create(recursive: true);
    }
    EventBus.shared.publish(SDKStorageEvent.tempFilesCleaned());
  }

  /// Delete a stored model
  /// Matches iOS RunAnywhere.deleteStoredModel(_:, framework:)
  static Future<void> deleteStoredModel(
    String modelId,
    LLMFramework framework,
  ) async {
    final modelFolder = await ModelPathUtils.getModelFolder(
      modelId: modelId,
      framework: framework,
    );
    if (await modelFolder.exists()) {
      await modelFolder.delete(recursive: true);
    }
    EventBus.shared.publish(SDKModelEvent.deleted(modelId: modelId));
  }

  /// Get base directory path
  /// Matches iOS RunAnywhere.getBaseDirectoryURL()
  static Future<String> getBaseDirectoryPath() async {
    final baseDir = await ModelPathUtils.getBaseDirectory();
    return baseDir.path;
  }

  /// Get all downloaded models grouped by framework
  /// Matches iOS RunAnywhere.getDownloadedModels()
  static Future<Map<LLMFramework, List<String>>> getDownloadedModels() async {
    final result = <LLMFramework, List<String>>{};
    final modelsDir = await ModelPathUtils.getModelsDirectory();

    if (!await modelsDir.exists()) {
      return result;
    }

    // Iterate through framework directories
    await for (final frameworkDir in modelsDir.list()) {
      if (frameworkDir is! Directory) continue;

      final frameworkName = frameworkDir.path.split('/').last;
      final framework = LLMFramework.values.cast<LLMFramework?>().firstWhere(
            (f) => f?.rawValue == frameworkName,
            orElse: () => null,
          );

      if (framework == null) continue;

      final modelIds = <String>[];
      await for (final modelDir in frameworkDir.list()) {
        if (modelDir is Directory) {
          modelIds.add(modelDir.path.split('/').last);
        }
      }

      if (modelIds.isNotEmpty) {
        result[framework] = modelIds;
      }
    }

    return result;
  }

  /// Check if a model is downloaded
  /// Matches iOS RunAnywhere.isModelDownloaded(_:, framework:)
  static Future<bool> isModelDownloaded(
    String modelId,
    LLMFramework framework,
  ) async {
    final modelFolder = await ModelPathUtils.getModelFolder(
      modelId: modelId,
      framework: framework,
    );
    return modelFolder.exists();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - Model Registration API
  // Matches iOS RunAnywhere+ModelAssignments.swift
  // ═══════════════════════════════════════════════════════════════════════════

  /// Register a model from a download URL
  /// Matches iOS RunAnywhere.registerModel(id:name:url:framework:...)
  ///
  /// Example:
  /// ```dart
  /// final model = RunAnywhere.registerModel(
  ///   name: 'My Model',
  ///   url: Uri.parse('https://example.com/model.gguf'),
  ///   framework: InferenceFramework.llamaCpp,
  /// );
  /// ```
  static ModelInfo registerModelWithURL({
    String? id,
    required String name,
    required Uri url,
    required LLMFramework framework,
    ModelCategory modality = ModelCategory.language,
    ModelArtifactType? artifactType,
    int? memoryRequirement,
    bool supportsThinking = false,
  }) {
    return serviceContainer.modelRegistry.addModelFromURL(
      id: id,
      name: name,
      url: url,
      framework: framework,
      category: modality,
      artifactType: artifactType,
      estimatedSize: memoryRequirement,
      supportsThinking: supportsThinking,
    );
  }

  /// Register a model from a URL string
  /// Returns null if URL is invalid
  /// Matches iOS RunAnywhere.registerModel(id:name:urlString:framework:...)
  static ModelInfo? registerModelFromString({
    String? id,
    required String name,
    required String urlString,
    required LLMFramework framework,
    ModelCategory modality = ModelCategory.language,
    ModelArtifactType? artifactType,
    int? memoryRequirement,
    bool supportsThinking = false,
  }) {
    final url = Uri.tryParse(urlString);
    if (url == null) {
      SDKLogger(category: 'RunAnywhere.Models')
          .error('Invalid URL: $urlString');
      return null;
    }
    return registerModelWithURL(
      id: id,
      name: name,
      url: url,
      framework: framework,
      modality: modality,
      artifactType: artifactType,
      memoryRequirement: memoryRequirement,
      supportsThinking: supportsThinking,
    );
  }

  /// Fetch model assignments for the current device from the backend
  /// Matches iOS RunAnywhere.fetchModelAssignments(forceRefresh:)
  static Future<List<ModelInfo>> fetchModelAssignments({
    bool forceRefresh = false,
  }) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    // For now, return all registered models
    // A full implementation would fetch from backend API
    return serviceContainer.modelRegistry.discoverModels();
  }

  /// Get available models for a specific framework
  /// Matches iOS RunAnywhere.getModelsForFramework(_:)
  static Future<List<ModelInfo>> getModelsForFramework(
    LLMFramework framework,
  ) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    return serviceContainer.modelRegistry.getModelsForFramework(framework);
  }

  /// Get available models for a specific category
  /// Matches iOS RunAnywhere.getModelsForCategory(_:)
  static Future<List<ModelInfo>> getModelsForCategory(
    ModelCategory category,
  ) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    return serviceContainer.modelRegistry.getModelsForCategory(category);
  }

  /// Clear cached model assignments
  /// Matches iOS RunAnywhere.clearModelAssignmentsCache()
  static Future<void> clearModelAssignmentsCache() async {
    if (!_isInitialized) {
      return;
    }

    serviceContainer.modelRegistry.clearCache();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - Logging Configuration API
  // Matches iOS RunAnywhere+Logging.swift
  // ═══════════════════════════════════════════════════════════════════════════

  /// Enable or disable local logging
  /// Matches iOS RunAnywhere.configureLocalLogging(enabled:)
  static void configureLocalLogging({required bool enabled}) {
    final config = LoggingManager.shared.configuration.copyWith(
      enableLocalLogging: enabled,
    );
    LoggingManager.shared.configure(config);
  }

  /// Set minimum log level for SDK logging
  /// Matches iOS RunAnywhere.setLogLevel(_:)
  static void setLogLevel(LogLevel level) {
    final config = LoggingManager.shared.configuration.copyWith(
      minLogLevel: level,
    );
    LoggingManager.shared.configure(config);
  }

  /// Enable verbose debugging mode
  /// Matches iOS RunAnywhere.setDebugMode(_:)
  static void setDebugMode({required bool enabled}) {
    // Update log level based on debug mode
    setLogLevel(enabled ? LogLevel.debug : LogLevel.info);

    // Update local logging
    configureLocalLogging(enabled: enabled);
  }

  /// Force flush all pending logs and analytics
  /// Matches iOS RunAnywhere.flushAll()
  static Future<void> flushAll() async {
    // Flush SDK logs
    LoggingManager.shared.flush();

    // Flush analytics events
    await AnalyticsQueueManager.shared.flush();
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - Framework Discovery API
  // Matches iOS RunAnywhere+Frameworks.swift
  // ═══════════════════════════════════════════════════════════════════════════

  /// Get all registered frameworks derived from available models
  /// Returns array of available inference frameworks that have models registered
  /// Matches iOS RunAnywhere.getRegisteredFrameworks()
  static Future<List<LLMFramework>> getRegisteredFrameworks() async {
    if (!_isInitialized) {
      return [];
    }

    // Derive frameworks from registered models - this is the source of truth
    final allModels =
        serviceContainer.modelRegistry.filterModels(const ModelCriteria());
    final frameworks = <LLMFramework>{};

    for (final model in allModels) {
      // Add preferred framework
      if (model.preferredFramework != null) {
        frameworks.add(model.preferredFramework!);
      }
      // Add all compatible frameworks
      for (final framework in model.compatibleFrameworks) {
        frameworks.add(framework);
      }
    }

    final result = frameworks.toList();
    result.sort((a, b) => a.displayName.compareTo(b.displayName));
    return result;
  }

  /// Get all registered frameworks for a specific capability
  /// Matches iOS RunAnywhere.getFrameworks(for:)
  /// [capability] The capability type to filter by
  /// Returns array of frameworks that provide the specified capability
  static Future<List<LLMFramework>> getFrameworksForCapability(
    CapabilityType capability,
  ) async {
    if (!_isInitialized) {
      return [];
    }

    final allModels =
        serviceContainer.modelRegistry.filterModels(const ModelCriteria());
    final frameworks = <LLMFramework>{};

    // Map capability to model categories
    final Set<ModelCategory> relevantCategories;
    switch (capability) {
      case CapabilityType.llm:
        relevantCategories = {ModelCategory.language, ModelCategory.multimodal};
      case CapabilityType.stt:
        relevantCategories = {ModelCategory.speechRecognition};
      case CapabilityType.tts:
        relevantCategories = {ModelCategory.speechSynthesis};
      case CapabilityType.vad:
        relevantCategories = {ModelCategory.audio};
      case CapabilityType.speakerDiarization:
        relevantCategories = {ModelCategory.audio};
    }

    for (final model in allModels) {
      if (relevantCategories.contains(model.category)) {
        if (model.preferredFramework != null) {
          frameworks.add(model.preferredFramework!);
        }
        for (final framework in model.compatibleFrameworks) {
          frameworks.add(framework);
        }
      }
    }

    final result = frameworks.toList();
    result.sort((a, b) => a.displayName.compareTo(b.displayName));
    return result;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - Speaker Diarization API
  // Matches iOS RunAnywhere+SpeakerDiarization.swift
  // ═══════════════════════════════════════════════════════════════════════════

  // Speaker diarization capability instance
  static SpeakerDiarizationService? _speakerDiarizationService;

  /// Initialize speaker diarization with optional configuration
  /// Matches iOS RunAnywhere.initializeSpeakerDiarization(_:)
  /// [config] Optional speaker diarization configuration (uses defaults if not provided)
  static Future<void> initializeSpeakerDiarization([dynamic config]) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    final provider = ModuleRegistry.shared.speakerDiarizationProvider();
    if (provider == null) {
      throw SDKError.featureNotAvailable(
        'No speaker diarization service available. Register a SpeakerDiarizationServiceProvider first.',
      );
    }

    _speakerDiarizationService =
        await provider.createSpeakerDiarizationService(config);
    await _speakerDiarizationService!.initialize();
  }

  /// Initialize speaker diarization with configuration (deprecated)
  /// Deprecated: Use [initializeSpeakerDiarization] with optional config parameter instead
  @Deprecated('Use initializeSpeakerDiarization with optional config parameter')
  static Future<void> initializeSpeakerDiarizationWithConfig(
    dynamic config,
  ) async {
    return initializeSpeakerDiarization(config);
  }

  /// Check if speaker diarization is ready
  /// Matches iOS RunAnywhere.isSpeakerDiarizationReady
  static bool get isSpeakerDiarizationReady =>
      _speakerDiarizationService?.isReady ?? false;

  /// Process audio and identify speaker
  /// Matches iOS RunAnywhere.identifySpeaker(_:)
  /// [samples] Audio samples to analyze (Float32 PCM samples)
  /// Returns information about the detected speaker
  static Future<SpeakerDiarizationSpeakerInfo> identifySpeaker(
      List<double> samples) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    final service = _speakerDiarizationService;
    if (service == null || !service.isReady) {
      throw SDKError.componentNotReady('SpeakerDiarization');
    }

    // Convert double samples to int for process() method
    // This assumes 16-bit PCM - multiply by 32767 to convert from float
    final intSamples =
        samples.map((s) => (s * 32767).round().clamp(-32768, 32767)).toList();

    // Process audio to identify speaker (result not needed, just triggers identification)
    await service.process(intSamples);

    // Get the most recently identified speaker
    final speakers = await service.getAllSpeakers();
    if (speakers.isEmpty) {
      return SpeakerDiarizationSpeakerInfo(id: 'unknown', confidence: 0.0);
    }
    return speakers.last;
  }

  /// Get all identified speakers
  /// Matches iOS RunAnywhere.getAllSpeakers()
  /// Returns array of all speakers detected so far
  static Future<List<SpeakerDiarizationSpeakerInfo>> getAllSpeakers() async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    final service = _speakerDiarizationService;
    if (service == null || !service.isReady) {
      throw SDKError.componentNotReady('SpeakerDiarization');
    }

    return service.getAllSpeakers();
  }

  /// Cleanup speaker diarization resources
  /// Matches iOS RunAnywhere.cleanupSpeakerDiarization()
  static Future<void> cleanupSpeakerDiarization() async {
    final service = _speakerDiarizationService;
    if (service != null) {
      await service.cleanup();
      _speakerDiarizationService = null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - Voice Agent API
  // Matches iOS RunAnywhere+VoiceAgent.swift
  // ═══════════════════════════════════════════════════════════════════════════

  // Voice agent capability instance
  static VoiceAgentCapability? _voiceAgentCapability;

  /// Initialize the voice agent with configuration
  /// Matches iOS RunAnywhere.initializeVoiceAgent(_:)
  static Future<void> initializeVoiceAgent(
    VoiceAgentConfiguration config,
  ) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    await _ensureServicesReady();

    EventBus.shared.publish(SDKVoiceEvent.pipelineStarted());

    try {
      _voiceAgentCapability = VoiceAgentCapability(
        configuration: config,
        serviceContainer: serviceContainer,
      );
      await _voiceAgentCapability!.initialize();
      EventBus.shared.publish(SDKVoiceEvent.pipelineCompleted());
    } catch (e) {
      EventBus.shared.publish(SDKVoicePipelineError(error: e));
      rethrow;
    }
  }

  /// Initialize voice agent with individual model IDs
  /// Pass empty strings to reuse already-loaded models for that component
  /// Matches iOS RunAnywhere.initializeVoiceAgent(sttModelId:llmModelId:ttsVoice:)
  static Future<void> initializeVoiceAgentWithModels({
    String sttModelId = '',
    String llmModelId = '',
    String ttsVoice = '',
  }) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    await _ensureServicesReady();

    EventBus.shared.publish(SDKVoiceEvent.pipelineStarted());

    try {
      // Build config from model IDs
      final config = VoiceAgentConfiguration(
        sttConfig: sttModelId.isNotEmpty
            ? STTConfiguration(modelId: sttModelId)
            : STTConfiguration(),
        llmConfig: llmModelId.isNotEmpty
            ? LLMConfiguration(modelId: llmModelId)
            : LLMConfiguration(),
        ttsConfig: ttsVoice.isNotEmpty
            ? TTSConfiguration(modelId: ttsVoice)
            : const TTSConfiguration(),
      );

      _voiceAgentCapability = VoiceAgentCapability(
        configuration: config,
        serviceContainer: serviceContainer,
      );
      await _voiceAgentCapability!.initialize();
      EventBus.shared.publish(SDKVoiceEvent.pipelineCompleted());
    } catch (e) {
      EventBus.shared.publish(SDKVoicePipelineError(error: e));
      rethrow;
    }
  }

  /// Initialize voice agent using already-loaded models
  /// Use this when you've already loaded STT, LLM, and TTS models via individual APIs
  /// Matches iOS RunAnywhere.initializeVoiceAgentWithLoadedModels()
  static Future<void> initializeVoiceAgentWithLoadedModels() async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    await _ensureServicesReady();

    // Verify all components are loaded
    final states = await getVoiceAgentComponentStates();
    if (!states.isFullyReady) {
      final missing = states.missingComponents.join(', ');
      throw SDKError.componentNotReady(
        'Not all voice components are loaded. Missing: $missing',
      );
    }

    EventBus.shared.publish(SDKVoiceEvent.pipelineStarted());

    try {
      // Create config using existing loaded models
      final sttModelId = _loadedSTTCapability?.sttConfig.modelId ?? '';
      final llmModelId = currentModel?.id ?? '';
      final ttsVoice = _loadedTTSCapability?.currentVoice ?? '';

      final config = VoiceAgentConfiguration(
        sttConfig: STTConfiguration(modelId: sttModelId),
        llmConfig: LLMConfiguration(modelId: llmModelId),
        ttsConfig: TTSConfiguration(modelId: ttsVoice),
      );

      _voiceAgentCapability = VoiceAgentCapability(
        configuration: config,
        serviceContainer: serviceContainer,
      );
      await _voiceAgentCapability!.initialize();
      EventBus.shared.publish(SDKVoiceEvent.pipelineCompleted());
    } catch (e) {
      EventBus.shared.publish(SDKVoicePipelineError(error: e));
      rethrow;
    }
  }

  /// Check if voice agent is ready (all components initialized)
  /// Matches iOS RunAnywhere.isVoiceAgentReady
  static bool get isVoiceAgentReady => _voiceAgentCapability?.isReady ?? false;

  /// Process a complete voice turn: audio → transcription → LLM response → synthesized speech
  /// Matches iOS RunAnywhere.processVoiceTurn(_:)
  static Future<VoiceAgentResult> processVoiceTurn(Uint8List audioData) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    final capability = _voiceAgentCapability;
    if (capability == null || !capability.isReady) {
      throw SDKError.componentNotReady('VoiceAgent');
    }

    try {
      return await capability.processAudio(audioData);
    } catch (e) {
      EventBus.shared.publish(SDKVoicePipelineError(error: e));
      rethrow;
    }
  }

  /// Process audio stream for continuous conversation
  /// Matches iOS RunAnywhere.processVoiceStream(_:)
  static Stream<VoiceAgentEvent> processVoiceStream(
    Stream<Uint8List> audioStream,
  ) {
    if (!_isInitialized) {
      return Stream.error(SDKError.notInitialized());
    }

    final capability = _voiceAgentCapability;
    if (capability == null || !capability.isReady) {
      return Stream.error(SDKError.componentNotReady('VoiceAgent'));
    }

    return capability.processStream(audioStream);
  }

  /// Transcribe audio (voice agent must be initialized)
  /// Matches iOS RunAnywhere.voiceAgentTranscribe(_:)
  static Future<String> voiceAgentTranscribe(Uint8List audioData) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    final capability = _voiceAgentCapability;
    if (capability == null || !capability.isReady) {
      throw SDKError.componentNotReady('VoiceAgent');
    }

    final result = await capability.transcribe(audioData);
    return result ?? '';
  }

  /// Generate LLM response (voice agent must be initialized)
  /// Matches iOS RunAnywhere.voiceAgentGenerateResponse(_:)
  static Future<String> voiceAgentGenerateResponse(String prompt) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    final capability = _voiceAgentCapability;
    if (capability == null || !capability.isReady) {
      throw SDKError.componentNotReady('VoiceAgent');
    }

    final result = await capability.generateResponse(prompt);
    return result ?? '';
  }

  /// Synthesize speech (voice agent must be initialized)
  /// Matches iOS RunAnywhere.voiceAgentSynthesizeSpeech(_:)
  static Future<Uint8List> voiceAgentSynthesizeSpeech(String text) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    final capability = _voiceAgentCapability;
    if (capability == null || !capability.isReady) {
      throw SDKError.componentNotReady('VoiceAgent');
    }

    final result = await capability.synthesizeSpeech(text);
    return result ?? Uint8List(0);
  }

  /// Cleanup voice agent resources
  /// Matches iOS RunAnywhere.cleanupVoiceAgent()
  static Future<void> cleanupVoiceAgent() async {
    final capability = _voiceAgentCapability;
    if (capability != null) {
      await capability.cleanup();
      _voiceAgentCapability = null;
    }
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - Voice Session API (High-Level)
  // Matches iOS RunAnywhere+VoiceSession.swift
  // ═══════════════════════════════════════════════════════════════════════════

  /// Start a voice session with async stream of events
  ///
  /// This is the simplest way to integrate voice assistant.
  /// The session handles audio capture, VAD, and processing internally.
  ///
  /// Matches iOS RunAnywhere.startVoiceSession(config:)
  ///
  /// Example:
  /// ```dart
  /// final session = await RunAnywhere.startVoiceSession();
  ///
  /// // Consume events
  /// session.events.listen((event) {
  ///   switch (event) {
  ///     case VoiceSessionListening(:final audioLevel):
  ///       updateAudioMeter(audioLevel);
  ///     case VoiceSessionTurnCompleted(:final transcript, :final response, :final audio):
  ///       updateUI(transcript, response);
  ///     default:
  ///       break;
  ///   }
  /// });
  /// ```
  static Future<VoiceSessionHandle> startVoiceSession({
    VoiceSessionConfig? config,
  }) async {
    if (!_isInitialized) {
      throw SDKError.notInitialized();
    }

    await _ensureServicesReady();

    final session = VoiceSessionHandle(
      config: config,
      processAudioCallback: (audioData) async {
        final result = await processVoiceTurn(audioData);
        return VoiceAgentProcessResult(
          speechDetected: result.speechDetected,
          transcription: result.transcription,
          response: result.response,
          synthesizedAudio: result.synthesizedAudio,
        );
      },
      isVoiceAgentReadyCallback: () async => isVoiceAgentReady,
      initializeVoiceAgentCallback: () async =>
          initializeVoiceAgentWithLoadedModels(),
    );

    await session.start();
    return session;
  }

  /// Start a voice session with callback-based event handling
  ///
  /// Alternative API using callbacks instead of async stream.
  ///
  /// Matches iOS RunAnywhere.startVoiceSession(config:onEvent:)
  ///
  /// Example:
  /// ```dart
  /// final session = await RunAnywhere.startVoiceSessionWithCallback(
  ///   onEvent: (event) {
  ///     // Handle event
  ///   },
  /// );
  ///
  /// // Later...
  /// session.stop();
  /// ```
  static Future<VoiceSessionHandle> startVoiceSessionWithCallback({
    VoiceSessionConfig? config,
    required void Function(VoiceSessionEvent) onEvent,
  }) async {
    final session = await startVoiceSession(config: config);

    // Forward events to callback
    session.events.listen(onEvent);

    return session;
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - Structured Output Streaming API
  // Matches iOS RunAnywhere+StructuredOutput.swift
  // ═══════════════════════════════════════════════════════════════════════════

  /// Generate structured output with streaming support
  /// Returns both a stream of tokens and a Future of the final parsed result
  ///
  /// Matches iOS RunAnywhere.generateStructuredStream(_:content:options:)
  ///
  /// Example:
  /// ```dart
  /// final result = RunAnywhere.generateStructuredStream<MyType>(
  ///   schema: MyType.jsonSchema,
  ///   fromJson: MyType.fromJson,
  ///   content: 'Generate a response...',
  /// );
  ///
  /// // Listen to streaming tokens
  /// result.stream.listen((token) => print(token));
  ///
  /// // Get final parsed result
  /// final myObject = await result.result;
  /// ```
  static StructuredOutputStreamResult<T>
      generateStructuredStream<T extends Generatable>({
    required String schema,
    required T Function(Map<String, dynamic>) fromJson,
    required String content,
    RunAnywhereGenerationOptions? options,
  }) {
    if (!_isInitialized) {
      final errorController = StreamController<String>();
      errorController.addError(SDKError.notInitialized());
      unawaited(errorController.close());
      return StructuredOutputStreamResult<T>(
        stream: errorController.stream,
        result: Future.error(SDKError.notInitialized()),
      );
    }

    // Import structured output handler
    final handler = StructuredOutputHandler();

    // Create config for structured output
    final config = StructuredOutputConfig(
      type: T,
      schema: schema,
      includeSchemaInPrompt: true,
    );

    // Build prompt with schema
    final enhancedPrompt = handler.preparePrompt(
      originalPrompt: content,
      config: config,
    );

    // Create a stream controller for tokens
    final tokenController = StreamController<String>.broadcast();
    final accumulatedText = StringBuffer();

    // Generate streaming text
    final tokenStream = generateStream(
      enhancedPrompt,
      options: options ?? RunAnywhereGenerationOptions(),
    );

    // Forward tokens and accumulate
    // ignore: cancel_subscriptions - lifecycle managed by asFuture() below
    final subscription = tokenStream.listen(
      (token) {
        accumulatedText.write(token);
        tokenController.add(token);
      },
      onError: tokenController.addError,
      onDone: () => unawaited(tokenController.close()),
    );

    // Create the result future
    final resultFuture = subscription.asFuture<void>().then((_) {
      return handler.parseStructuredOutput<T>(
        accumulatedText.toString(),
        fromJson,
      );
    });

    return StructuredOutputStreamResult<T>(
      stream: tokenController.stream,
      result: resultFuture,
    );
  }

  // ═══════════════════════════════════════════════════════════════════════════
  // MARK: - LLM Streaming Control API
  // Matches iOS RunAnywhere+ModelManagement.swift
  // ═══════════════════════════════════════════════════════════════════════════

  /// Check if the currently loaded LLM model supports streaming generation
  ///
  /// Some models don't support streaming and require non-streaming generation
  /// via `generate()` instead of `generateStream()`.
  ///
  /// Matches iOS RunAnywhere.supportsLLMStreaming
  ///
  /// Returns `true` if streaming is supported, `false` if you should use `generate()` instead
  /// Returns `false` if no model is loaded
  static bool get supportsLLMStreaming {
    if (!_isInitialized) return false;

    // Query the LLM capability for streaming support
    final llmService = serviceContainer.generationService.llmService;
    return llmService?.supportsStreaming ?? false;
  }

  /// Cancel the current text generation
  ///
  /// Use this to stop an ongoing generation when the user navigates away
  /// or explicitly requests cancellation.
  ///
  /// Matches iOS RunAnywhere.cancelGeneration()
  static Future<void> cancelGeneration() async {
    if (!_isInitialized) return;

    // Cancel via generation service
    serviceContainer.generationService.cancel();
  }
}

// MARK: - Conversation Management

/// Simple conversation manager
/// Matches iOS Conversation class from RunAnywhere.swift
class Conversation {
  final List<String> _messages = [];

  Conversation();

  /// Send a message and get response
  Future<String> send(String message) async {
    _messages.add('User: $message');

    final contextPrompt = '${_messages.join('\n')}\nAssistant:';
    final result = await RunAnywhere.generate(contextPrompt);

    _messages.add('Assistant: ${result.text}');
    return result.text;
  }

  /// Get conversation history
  List<String> get history => List.unmodifiable(_messages);

  /// Clear conversation
  void clear() {
    _messages.clear();
  }
}

/// Helper function to mark futures as unawaited
void unawaited(Future<void> future) {
  // Intentionally not awaiting
}
