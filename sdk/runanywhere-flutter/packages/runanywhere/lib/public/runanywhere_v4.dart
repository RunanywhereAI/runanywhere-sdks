// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_v4.dart — RunAnywhere SDK singleton entry point.
//
// Phase C of the v2 close-out moved the implementation OUT of the
// legacy static `RunAnywhere` class and INTO the capability classes
// under `lib/public/capabilities/`. This singleton now owns the
// lifecycle surface (initialize / reset / version / events /
// environment) and exposes every capability as a lazy property.
//
// Usage:
//   final ra = RunAnywhereSDK.instance;
//   await ra.initialize(environment: SDKEnvironment.development);
//   await ra.llm.load('llama-3-8b');
//   final response = await ra.llm.chat('Hello!');

import 'package:runanywhere/data/network/telemetry_service.dart';
import 'package:runanywhere/foundation/configuration/sdk_constants.dart';
import 'package:runanywhere/foundation/dependency_injection/service_container.dart';
import 'package:runanywhere/foundation/error_types/sdk_error.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/internal/sdk_init.dart';
import 'package:runanywhere/internal/sdk_state.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_auth.dart';
import 'package:runanywhere/native/dart_bridge_device.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart';
import 'package:runanywhere/public/capabilities/runanywhere_downloads.dart';
import 'package:runanywhere/public/capabilities/runanywhere_llm.dart';
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';
import 'package:runanywhere/public/capabilities/runanywhere_rag.dart';
import 'package:runanywhere/public/capabilities/runanywhere_solutions.dart';
import 'package:runanywhere/public/capabilities/runanywhere_stt.dart';
import 'package:runanywhere/public/capabilities/runanywhere_tools.dart';
import 'package:runanywhere/public/capabilities/runanywhere_tts.dart';
import 'package:runanywhere/public/capabilities/runanywhere_vad.dart';
import 'package:runanywhere/public/capabilities/runanywhere_vlm.dart';
import 'package:runanywhere/public/capabilities/runanywhere_voice.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';

/// RunAnywhere SDK entry point.
///
/// Singleton; access via [RunAnywhereSDK.instance]. Capability
/// surfaces are exposed as instance properties (e.g. `instance.llm`,
/// `instance.stt`, `instance.models`). Each capability class owns
/// its own implementation — this singleton is just the lifecycle
/// coordinator + dispatch point.
class RunAnywhereSDK {
  RunAnywhereSDK._();

  /// Shared instance.
  static final RunAnywhereSDK instance = RunAnywhereSDK._();

  // --- Lifecycle -----------------------------------------------------------

  /// True after [initialize] has succeeded.
  bool get isInitialized => SdkState.shared.isInitialized;

  /// True if the SDK is active (initialized + has init params).
  bool get isActive =>
      SdkState.shared.isInitialized && SdkState.shared.initParams != null;

  /// True once Phase 2 (services) initialization has completed. Mirrors
  /// Swift's `areServicesReady`. In Flutter, Phase 2 runs eagerly inside
  /// [initialize] so this returns true alongside [isInitialized] today.
  bool get areServicesReady =>
      SdkState.shared.isInitialized && DartBridge.servicesInitialized;

  /// Cached device id — populated during initialization. Mirrors Swift's
  /// `deviceId: String`.
  String get deviceId =>
      DartBridgeDevice.cachedDeviceId ?? 'unknown-device';

  /// Authenticated user id, or null if not signed in. Mirrors Swift's
  /// `getUserId()`.
  String? get userId => DartBridgeAuth.instance.getUserId();

  /// Authenticated organization id, or null. Mirrors Swift's
  /// `getOrganizationId()`.
  String? get organizationId =>
      DartBridgeAuth.instance.getOrganizationId();

  /// True if the SDK has a valid authentication token.
  bool get isAuthenticated => DartBridgeAuth.instance.isAuthenticated();

  /// True if the device has been registered with the backend. Mirrors
  /// Swift's `isDeviceRegistered()`.
  bool get isDeviceRegistered =>
      DartBridgeDevice.cachedDeviceId != null &&
      DartBridgeDevice.cachedDeviceId!.isNotEmpty;

  /// Awaitable Phase-2 completion. Mirrors Swift's
  /// `completeServicesInitialization()`. In Flutter Phase 2 already
  /// completes synchronously inside [initialize]; this getter exists
  /// for API parity and resolves immediately if initialization is done.
  Future<void> completeServicesInitialization() async {
    if (areServicesReady) return;
    if (!isInitialized) {
      throw SDKError.notInitialized();
    }
  }

  /// Initialization params (apiKey, baseURL, environment) — null
  /// until [initialize] runs.
  SDKInitParams? get initParams => SdkState.shared.initParams;

  /// Current SDK environment (development / staging / production).
  SDKEnvironment? get environment => SdkState.shared.currentEnvironment;

  /// SDK semver string (e.g. "4.0.0").
  String get version => SDKConstants.version;

  /// Event bus for cross-capability SDK events.
  EventBus get events => EventBus.shared;

  /// Initialize the SDK with API key + base URL.
  Future<void> initialize({
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

  /// Initialize with fully-resolved [SDKInitParams].
  ///
  /// Mirrors Swift `RunAnywhere.performCoreInit()` two-phase flow:
  /// - Phase 1: `DartBridge.initialize()` (sync, ~1-5ms)
  /// - Phase 2: async service bridges, device registration, auth
  Future<void> initializeWithParams(SDKInitParams params) async {
    if (SdkState.shared.isInitialized) return;

    final logger = SDKLogger('RunAnywhere.Init');
    EventBus.shared.publish(SDKInitializationStarted());

    try {
      SdkState.shared.currentEnvironment = params.environment;
      SdkState.shared.initParams = params;

      // --- Phase 1: Core init (sync) ---
      DartBridge.initialize(params.environment);
      logger.debug('DartBridge initialized with platform adapter');

      // --- Phase 2: Services init (async) ---
      await DartBridge.initializeServices(
        apiKey: params.apiKey,
        baseURL: params.baseURL.toString(),
        deviceId: DartBridgeDevice.cachedDeviceId,
      );
      logger.debug('Service bridges initialized');

      await DartBridge.modelPaths.setBaseDirectory();

      await ServiceContainer.shared.setupLocalServices(
        apiKey: params.apiKey,
        baseURL: params.baseURL,
        environment: params.environment,
      );

      await registerDeviceIfNeeded(params, logger);
      await authenticateWithBackend(params, logger);

      logger.debug('Initializing model registry...');
      await DartBridgeModelRegistry.instance.initialize();

      // NOTE: Discovery runs lazily on first `models.available()` call
      // so apps have a chance to register their models first.

      SdkState.shared.isInitialized = true;
      logger.info('✅ SDK initialized (${params.environment.description})');
      EventBus.shared.publish(SDKInitializationCompleted());

      TelemetryService.shared.trackSDKInit(
        environment: params.environment.name,
        success: true,
      );
    } catch (e) {
      logger.error('❌ SDK initialization failed: $e');
      SdkState.shared.reset();
      EventBus.shared.publish(SDKInitializationFailed(e));

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

  /// Reset all SDK state; clears registered models, cached
  /// configuration, loaded backends. Useful for tests.
  Future<void> reset() async {
    await TelemetryService.shared.shutdown();

    SdkState.shared.reset();
    DartBridgeModelRegistry.instance.shutdown();
    ServiceContainer.shared.reset();
  }

  // --- Capability surfaces -------------------------------------------------

  /// LLM (text generation) — load, chat, generate, generate-stream, cancel.
  RunAnywhereLLM get llm => RunAnywhereLLM.shared;

  /// STT (speech-to-text) — load, transcribe.
  RunAnywhereSTT get stt => RunAnywhereSTT.shared;

  /// TTS (text-to-speech) — load voice, synthesize, speak.
  RunAnywhereTTS get tts => RunAnywhereTTS.shared;

  /// VAD (voice activity detection) — initialize, detectSpeech, start/stop,
  /// load model. Mirrors Swift's `RunAnywhere+VAD.swift` extension.
  RunAnywhereVAD get vad => RunAnywhereVAD.shared;

  /// VLM (vision-language model) — load, processImage, processImageStream,
  /// describe, askAbout.
  RunAnywhereVLM get vlm => RunAnywhereVLM.shared;

  /// Voice Agent (full STT → LLM → TTS pipeline) — initialize,
  /// cleanup, isReady, eventStream. Symmetric with `llm.generateStream`:
  /// `voice.eventStream()` returns `Stream<VoiceEvent>` and wraps
  /// `VoiceAgentStreamAdapter` internally.
  RunAnywhereVoice get voice => RunAnywhereVoice.shared;

  /// Models registry — list available, refresh from filesystem,
  /// register, register multi-file, update download status, remove.
  RunAnywhereModels get models => RunAnywhereModels.shared;

  /// Downloads — start, delete, storage info, list downloaded.
  RunAnywhereDownloads get downloads => RunAnywhereDownloads.shared;

  /// Tools (LLM function calling) — register, execute, generateWithTools.
  RunAnywhereTools get tools => RunAnywhereTools.shared;

  /// RAG (Retrieval-Augmented Generation) — pipeline lifecycle,
  /// ingest, query, statistics.
  RunAnywhereRAG get rag => RunAnywhereRAG.shared;

  /// Solutions (T4.7/T4.8) — proto/YAML-driven L5 pipeline runtime.
  /// Construct a solution from a typed `SolutionConfig` proto, raw
  /// proto bytes, or YAML sugar; returns a [SolutionHandle] with
  /// start / stop / cancel / feed / closeInput / destroy verbs.
  RunAnywhereSolutions get solutions => RunAnywhereSolutions.shared;
}
