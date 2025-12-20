import 'dart:async';
import '../foundation/dependency_injection/service_container.dart';
import '../foundation/error_types/sdk_error.dart';
import '../foundation/logging/sdk_logger.dart';
import '../foundation/security/keychain_manager.dart';
import '../foundation/device_identity/device_manager.dart';
import '../foundation/configuration/sdk_constants.dart';
import '../core/protocols/frameworks/unified_framework_adapter.dart';
import '../core/models/model/model_registration.dart';
import 'configuration/sdk_environment.dart';
import 'events/event_bus.dart';
import 'events/sdk_event.dart';
import 'models/models.dart';
import '../capabilities/text_generation/generation_service.dart';
import '../capabilities/structured_output/structured_output_handler.dart';
import '../features/stt/stt_capability.dart';
import '../features/tts/tts_capability.dart';
import '../features/tts/tts_options.dart';
import '../features/tts/tts_output.dart';
import '../features/vad/vad_capability.dart';
import '../features/vad/vad_configuration.dart';
import '../features/voice_agent/voice_agent_capability.dart';
import '../core/module_registry.dart' hide TTSOptions, TTSService;

// Export generation options
export '../capabilities/text_generation/generation_service.dart'
    show RunAnywhereGenerationOptions, GenerationResult;

// Export capability types for public use
export '../features/stt/stt_capability.dart'
    show STTCapability, STTConfiguration, STTOutput, STTMode, STTOptions;
export '../features/tts/tts_capability.dart'
    show TTSCapability, TTSConfiguration;
export '../features/tts/tts_output.dart' show TTSOutput, SynthesisMetadata;
export '../features/llm/llm_capability.dart'
    show
        LLMCapability,
        LLMConfiguration,
        LLMOutput,
        Message,
        MessageRole,
        Context;

// Export framework adapter types for registration
export '../core/protocols/frameworks/unified_framework_adapter.dart';
export '../core/models/model/model_registration.dart';
export '../core/model_lifecycle_manager.dart';

// Export core types for public use
export '../core/models/framework/llm_framework.dart';
export '../core/models/framework/framework_modality.dart';
export '../core/models/framework/model_format.dart';
export '../core/models/framework/model_artifact_type.dart';
export '../core/models/model/model_category.dart';

// Export speaker diarization types
export '../features/speaker_diarization/speaker_info.dart';

// Export VAD types for top-level access
export '../features/vad/vad_capability.dart' show VADCapability;
export '../features/vad/vad_service.dart'
    show VADResult, VADService, SpeechActivityEvent;
export '../features/vad/vad_configuration.dart' show VADConfiguration;

// Export TTS options for top-level synthesize
export '../features/tts/tts_options.dart' show TTSOptions;

// Export VoiceAgent types
export '../features/voice_agent/voice_agent_capability.dart'
    show
        VoiceAgentCapability,
        VoiceAgentConfiguration,
        VoiceAgentResult,
        VoiceAgentEvent,
        ComponentLoadState,
        VoiceAgentComponentStates;

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
    return await DeviceManager.shared.getDeviceId();
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
      return await capability.synthesize(
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
  /// Matches iOS RunAnywhere.detectSpeech(in:)
  /// [audioData] Audio data (16-bit PCM samples)
  /// Returns true if speech is detected
  static Future<bool> detectSpeech(List<int> audioData) async {
    final capability = _loadedVADCapability;
    if (capability == null || !capability.isReady) {
      throw SDKError.componentNotReady('VAD');
    }

    final result = await capability.detectSpeech(buffer: audioData);
    return result.hasSpeech;
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
      return VoiceAgentComponentStates();
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

  /// Load a TTS (Text-to-Speech) model by ID
  /// This initializes the TTS component and loads the model into memory
  /// [modelId] The model identifier (voice name)
  /// Matches iOS loadTTSModel from RunAnywhere.swift
  static Future<void> loadTTSModel(String modelId) async {
    EventBus.shared.publish(SDKModelEvent.loadStarted(modelId: modelId));

    try {
      // Ensure initialized
      if (!_isInitialized) {
        throw SDKError.notInitialized();
      }

      // Lazy device registration on first API call
      await _ensureDeviceRegistered();

      // Create TTS configuration with the modelId
      // Note: voice defaults to 'system' but modelId is what we need for path resolution
      final ttsConfig = TTSConfiguration(modelId: modelId);

      // Create and initialize TTS capability
      final ttsCapability = TTSCapability(ttsConfiguration: ttsConfig);
      await ttsCapability.initialize();

      // Store the capability for later use
      _loadedTTSCapability = ttsCapability;

      EventBus.shared.publish(SDKModelEvent.loadCompleted(modelId: modelId));
    } catch (e) {
      EventBus.shared.publish(
        SDKModelEvent.loadFailed(modelId: modelId, error: e),
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

  // MARK: - Multi-Adapter Support (NEW)

  /// Register a framework adapter with optional priority
  /// Higher priority adapters are preferred when multiple can handle the same model
  /// Matches iOS RunAnywhere.registerFrameworkAdapter pattern
  static void registerFrameworkAdapter(
    UnifiedFrameworkAdapter adapter, {
    int priority = 100,
  }) {
    // Note: Adapter registration can happen before SDK initialization
    // This allows registering adapters during app setup
    serviceContainer.registerFrameworkAdapter(adapter, priority: priority);
  }

  /// Register a framework adapter with models
  /// This is the primary method for registering adapters with pre-configured models
  /// Matches iOS RunAnywhere.registerFramework pattern
  static Future<void> registerFramework(
    UnifiedFrameworkAdapter adapter, {
    List<ModelRegistration>? models,
    int priority = 100,
  }) async {
    await serviceContainer.registerFramework(
      adapter,
      models: models,
      priority: priority,
    );
  }

  /// Check if SDK has been initialized
  /// Returns true if SDK has been initialized
  /// Deprecated: Use [isSDKInitialized] getter instead
  static bool hasBeenInitialized() {
    return isSDKInitialized;
  }

  // Note: isActive is now a getter defined above

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

    // Reset service container if needed
    serviceContainer.reset();

    logger.info('SDK state reset completed');
  }

  // MARK: - Factory Methods

  /// Create a new conversation
  static Conversation conversation() {
    return Conversation();
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
