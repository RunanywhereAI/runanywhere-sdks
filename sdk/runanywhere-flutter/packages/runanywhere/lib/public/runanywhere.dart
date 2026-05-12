// SPDX-License-Identifier: Apache-2.0
//
// runanywhere.dart — RunAnywhere SDK singleton entry point.
//
// Usage:
//   final ra = RunAnywhereSDK.instance;
//   await ra.initialize(environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT);
//   await ra.llm.load('llama-3-8b');
//   final response = await ra.llm.chat('Hello!');

import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/adapters/http_client_adapter.dart';
import 'package:runanywhere/foundation/constants/sdk_constants.dart';
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/llm_options.pb.dart'
    show LLMGenerationOptions, LLMGenerationResult;
import 'package:runanywhere/generated/llm_service.pb.dart' show LLMStreamEvent;
import 'package:runanywhere/generated/model_types.pb.dart'
    show
        CurrentModelRequest,
        CurrentModelResult,
        ModelInfo,
        ModelLoadRequest,
        ModelLoadResult,
        ModelUnloadRequest,
        ModelUnloadResult;
import 'package:runanywhere/generated/sdk_events.pb.dart' as sdk_events_pb;
import 'package:runanywhere/generated/sdk_events.pbenum.dart' show SDKComponent;
import 'package:runanywhere/generated/stt_options.pb.dart'
    show STTOptions, STTOutput, STTPartialResult;
import 'package:runanywhere/generated/tts_options.pb.dart'
    show TTSOptions, TTSOutput, TTSSpeakResult, TTSVoiceInfo;
import 'package:runanywhere/generated/voice_events.pb.dart' show VoiceEvent;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_auth.dart';
import 'package:runanywhere/native/dart_bridge_device.dart';
import 'package:runanywhere/native/dart_bridge_events.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart';
import 'package:runanywhere/native/dart_bridge_telemetry.dart';
import 'package:runanywhere/public/capabilities/runanywhere_diffusion.dart';
import 'package:runanywhere/public/capabilities/runanywhere_downloads.dart';
import 'package:runanywhere/public/capabilities/runanywhere_embeddings.dart';
import 'package:runanywhere/public/capabilities/runanywhere_hardware.dart';
import 'package:runanywhere/public/capabilities/runanywhere_llm.dart';
import 'package:runanywhere/public/capabilities/runanywhere_lora.dart';
import 'package:runanywhere/public/capabilities/runanywhere_model_lifecycle.dart';
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';
import 'package:runanywhere/public/capabilities/runanywhere_plugin_loader.dart';
import 'package:runanywhere/public/capabilities/runanywhere_rag.dart';
import 'package:runanywhere/public/capabilities/runanywhere_solutions.dart';
import 'package:runanywhere/public/capabilities/runanywhere_stt.dart';
import 'package:runanywhere/public/capabilities/runanywhere_tools.dart';
import 'package:runanywhere/public/capabilities/runanywhere_tts.dart';
import 'package:runanywhere/public/capabilities/runanywhere_vad.dart';
import 'package:runanywhere/public/capabilities/runanywhere_vlm.dart';
import 'package:runanywhere/public/capabilities/runanywhere_voice.dart';
import 'package:runanywhere/public/capabilities/runanywhere_voice_agent.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';
import 'package:runanywhere/public/events/event_bus.dart';

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

  /// True after [initialize] has succeeded. Sourced from the C++ commons
  /// (`rac_state_is_initialized`); Dart does not maintain a parallel flag.
  bool get isInitialized => DartBridge.isInitialized;

  /// True if the SDK is active (initialized + has init params in commons).
  bool get isActive => DartBridge.isInitialized && _cachedInitParams != null;

  /// True once Phase 2 (services) initialization has completed. Mirrors
  /// Swift's `areServicesReady`. In Flutter, Phase 2 runs eagerly inside
  /// [initialize] so this returns true alongside [isInitialized] today.
  bool get areServicesReady =>
      DartBridge.isInitialized && DartBridge.servicesInitialized;

  /// Cached device id — populated during initialization. Mirrors Swift's
  /// `deviceId: String`.
  String get deviceId => DartBridgeDevice.cachedDeviceId ?? 'unknown-device';

  /// Authenticated user id, or null if not signed in. Mirrors Swift's
  /// `getUserId()`.
  String? get userId => DartBridgeAuth.instance.getUserId();

  /// Authenticated organization id, or null. Mirrors Swift's
  /// `getOrganizationId()`.
  String? get organizationId => DartBridgeAuth.instance.getOrganizationId();

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
      throw SDKException.notInitialized();
    }
  }

  /// Initialization params (apiKey, baseURL, environment) — null
  /// until [initialize] runs. Cached from the most recent
  /// `initializeWithParams` call so callers can introspect what was
  /// resolved (commons stores the canonical values too via
  /// `rac_state_*`).
  SDKInitParams? get initParams => _cachedInitParams;

  /// Current SDK environment. Sourced from `DartBridge` which mirrors
  /// commons' canonical environment.
  SDKEnvironment? get environment =>
      DartBridge.isInitialized ? DartBridge.environment : null;

  // Cached params from the most recent successful initializeWithParams.
  // The canonical source is commons (rac_state_*); this is a lightweight
  // Dart accessor for callers that want the original Uri / apiKey shape.
  SDKInitParams? _cachedInitParams;

  // One-shot Dart-only flag: has the lazy filesystem discovery pass run?
  // Anything cross-platform (initialized / environment / params) lives in
  // commons and is read through DartBridge. Only Dart scheduling state
  // belongs here.
  bool _hasRunDiscovery = false;

  /// SDK semver string (e.g. "4.0.0").
  String get version => SDKConstants.version;

  /// Event bus for cross-capability SDK events.
  EventBus get events => EventBus.shared;

  /// Canonical generated-proto SDK event stream from commons.
  Stream<sdk_events_pb.SDKEvent> get sdkEvents => DartBridgeEvents.eventStream;

  /// Initialize the SDK with API key + base URL.
  Future<void> initialize({
    String? apiKey,
    String? baseURL,
    SDKEnvironment environment = SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
  }) async {
    final SDKInitParams params;

    if (environment == SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT) {
      if (baseURL == null || baseURL.isEmpty) {
        params = SDKInitParams.forDevelopment(apiKey: apiKey ?? '');
      } else {
        final uri = Uri.tryParse(baseURL);
        if (uri == null) {
          throw SDKException.validationFailed('Invalid base URL: $baseURL');
        }
        params = SDKInitParams(
          apiKey: apiKey ?? '',
          baseURL: uri,
          environment: environment,
        );
      }
    } else {
      if (apiKey == null || apiKey.isEmpty) {
        throw SDKException.validationFailed(
          'API key is required for ${environment.description} mode',
        );
      }
      if (baseURL == null || baseURL.isEmpty) {
        throw SDKException.validationFailed(
          'Base URL is required for ${environment.description} mode',
        );
      }
      final uri = Uri.tryParse(baseURL);
      if (uri == null) {
        throw SDKException.validationFailed('Invalid base URL: $baseURL');
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
  /// - Phase 1: Core init (sync, ~1-5ms) + local service setup (async,
  ///   no network) — completes before this method returns.
  /// - Phase 2: Device registration + authentication — fired in the
  ///   background (fire-and-forget), matching the iOS `Task.detached`
  ///   pattern. Network failures are non-critical; offline inference
  ///   still works.
  Future<void> initializeWithParams(SDKInitParams params) async {
    if (DartBridge.isInitialized) return;

    final logger = SDKLogger('RunAnywhere.Init');
    // C++ commons auto-emits INITIALIZATION_STAGE_STARTED via
    // `event_publisher.cpp:531`; Dart does not re-emit a duplicate.

    try {
      _cachedInitParams = params;

      // --- Phase 1: Core init (sync) ---
      DartBridge.initialize(params.environment);

      // --- Local service setup (async, no network) ---
      await DartBridge.initializeServices(
        apiKey: params.apiKey,
        baseURL: params.baseURL.toString(),
        deviceId: DartBridgeDevice.cachedDeviceId,
      );

      await DartBridge.modelPaths.setBaseDirectory();

      // Configure the shared HTTP client. Mirrors Swift's inlined HTTP
      // setup inside `RunAnywhere.performCoreInit()` (no DI container).
      HTTPClientAdapter.shared.configure(
        baseURL: params.baseURL.toString(),
        apiKey: params.apiKey,
        environment: params.environment,
      );
      if (params.environment == SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT) {
        final supabaseConfig = SupabaseConfig.configuration(params.environment);
        if (supabaseConfig != null) {
          HTTPClientAdapter.shared.configureDev(
            supabaseURL: supabaseConfig.projectURL.toString(),
            supabaseKey: supabaseConfig.anonKey,
          );
        }
      }

      // Commons-owned telemetry: sync init + async device-info wiring.
      DartBridgeTelemetry.initializeSync(environment: params.environment);
      final telemetryDeviceId = await DartBridgeDevice.instance.getDeviceId();
      await DartBridgeTelemetry.initialize(
        environment: params.environment,
        deviceId: telemetryDeviceId,
        baseURL: HTTPClientAdapter.shared.isConfigured
            ? params.baseURL.toString()
            : null,
      );

      await DartBridgeModelRegistry.instance.initialize();

      logger.info('SDK initialized (${params.environment.description})');

      // Commons auto-emits RAC_EVENT_SDK_INITIALIZED and the
      // INITIALIZATION_STAGE_COMPLETED SDKEvent from the C++ init path
      // (`event_publisher.cpp:544`), so Dart does not re-emit duplicates.
      unawaited(DartBridgeTelemetry.instance.emitSDKInitialized(
        durationMs: 0,
        environment: params.environment.name,
      ));

      // --- Phase 2: Background services (network, fire-and-forget) ---
      // Mirrors iOS `Task.detached { completeServicesInitialization() }`.
      // Failures are non-critical; offline inference still works.
      unawaited(_completeBackgroundServices(params, logger));
    } catch (e) {
      logger.error('SDK initialization failed: $e');
      _cachedInitParams = null;
      _hasRunDiscovery = false;
      // Commons auto-emits INITIALIZATION_STAGE_FAILED via
      // `event_publisher.cpp:557`; failure telemetry flows through
      // structured errors. Dart does not re-emit a duplicate.
      rethrow;
    }
  }

  /// Phase 2 background services — device registration + authentication.
  /// Runs after [initializeWithParams] returns. Failures are logged but
  /// never surface to the caller.
  Future<void> _completeBackgroundServices(
    SDKInitParams params,
    SDKLogger logger,
  ) async {
    try {
      await _registerDeviceIfNeeded(params, logger);
      await _authenticateWithBackend(params, logger);
      logger.debug('Background services completed');
    } catch (e) {
      logger.warning('Background services failed (non-critical): $e');
    }
  }

  /// Register device with backend. Mirrors Swift
  /// `CppBridge.Device.registerIfNeeded(environment:)`. The C++ device
  /// manager owns gating (skip-on-development, already-registered
  /// short-circuit). Dart's only job is to install the HTTP/secure
  /// callbacks and invoke the C ABI; failures are logged and swallowed
  /// so offline inference still works.
  Future<void> _registerDeviceIfNeeded(
    SDKInitParams params,
    SDKLogger logger,
  ) async {
    try {
      await DartBridgeDevice.register(
        environment: params.environment,
        baseURL: params.baseURL.toString(),
      );
      await DartBridgeDevice.instance.registerIfNeeded();
      logger.debug('Device registration check completed');
    } catch (e) {
      logger.warning('Device registration failed (non-critical): $e');
    }
  }

  /// Authenticate with backend. Mirrors Swift
  /// `CppBridge.Auth.authenticate(apiKey:)`. The commons auth manager
  /// owns environment / placeholder / URL gating; if commons rejects
  /// the config it returns a non-success result and we just log it.
  /// On success we forward the access token to `HTTPClientAdapter` so
  /// subsequent requests carry it.
  Future<void> _authenticateWithBackend(
    SDKInitParams params,
    SDKLogger logger,
  ) async {
    try {
      await DartBridgeAuth.initialize(
        environment: params.environment,
        baseURL: params.baseURL.toString(),
      );

      final deviceId = await DartBridgeDevice.instance.getDeviceId();
      final result = await DartBridgeAuth.instance.authenticate(
        apiKey: params.apiKey,
        deviceId: deviceId,
      );

      if (result.isSuccess) {
        logger.info('Authenticated for ${params.environment.description}');
        final token = result.data?.accessToken;
        if (token != null) {
          HTTPClientAdapter.shared.setToken(token);
        }
      } else {
        logger.debug(
          'Authentication skipped or failed: ${result.error}',
          metadata: {'environment': params.environment.name},
        );
      }
    } catch (e) {
      logger.warning(
        'Authentication error (non-critical): $e',
        metadata: {'environment': params.environment.name},
      );
    }
  }

  /// One-shot filesystem discovery of downloaded models. Called lazily
  /// on first `models.available()` so apps can register their catalog
  /// first. Safe to call repeatedly — the [_hasRunDiscovery] flag
  /// short-circuits after the first successful pass.
  Future<void> runDiscoveryIfNeeded() async {
    if (_hasRunDiscovery) return;
    final logger = SDKLogger('RunAnywhere.Discovery');
    final result =
        await DartBridgeModelRegistry.instance.discoverDownloadedModels();
    if (result.discoveredModels.isNotEmpty) {
      logger.info(
        'Discovered ${result.discoveredModels.length} downloaded models',
      );
    }
    _hasRunDiscovery = true;
  }

  /// Reset all SDK state; clears registered models, cached
  /// configuration, loaded backends. Useful for tests.
  Future<void> reset() async {
    DartBridgeTelemetry.flush();

    DartBridge.modelLifecycle.reset();
    _hasRunDiscovery = false;
    _cachedInitParams = null;
    DartBridgeModelRegistry.instance.shutdown();
    HTTPClientAdapter.shared.resetForTesting();
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

  /// VisionLanguage namespace (Swift parity). Identical to [vlm].
  RunAnywhereVLM get visionLanguage => RunAnywhereVLM.shared;

  /// Voice Agent (full STT → LLM → TTS pipeline) — initialize,
  /// cleanup, isReady, eventStream. Symmetric with `llm.generateStream`:
  /// `voice.eventStream()` returns `Stream<VoiceEvent>` and wraps
  /// `VoiceAgentStreamAdapter` internally.
  RunAnywhereVoice get voice => RunAnywhereVoice.shared;

  /// Models registry — list available, refresh from filesystem,
  /// register, register multi-file, update download status, remove.
  RunAnywhereModels get models => RunAnywhereModels.shared;

  /// Model/component lifecycle — generated proto load/unload/current/snapshot.
  RunAnywhereModelLifecycle get modelLifecycle =>
      RunAnywhereModelLifecycle.shared;

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

  /// Voice Agent namespace (parity with Swift `RunAnywhere.VoiceAgent`).
  /// Wraps `voice` with VoiceAgent-themed aliases.
  RunAnywhereVoiceAgent get voiceAgent => RunAnywhereVoiceAgent.shared;

  /// Diffusion (image generation). Calls the `rac_diffusion_*` C ABI;
  /// surfaces `featureNotAvailable` only when commons indicates so.
  RunAnywhereDiffusion get diffusion => RunAnywhereDiffusion.shared;

  /// Embeddings — load an embeddings model and generate embedding vectors.
  RunAnywhereEmbeddings get embeddings => RunAnywhereEmbeddings.shared;

  /// Runtime plugin loader (parity with Swift `RunAnywhere.PluginLoader`).
  RunAnywherePluginLoaderCapability get pluginLoader =>
      RunAnywherePluginLoaderCapability.shared;

  /// LoRA (Low-Rank Adaptation) capability — load, remove, register,
  /// query loaded/registered adapters. Canonical §3 namespace.
  RunAnywhereLoRACapability get lora => RunAnywhereLoRACapability.shared;

  /// Hardware profile (chip, NPU presence, acceleration mode).
  /// Canonical §14 namespace.
  RunAnywhereHardware get hardware => RunAnywhereHardware.shared;

  // -- Flat aliases for cross-SDK portability (canonical §0 — RN/Web/Swift use
  //    flat method names; Flutter additionally exposes them so portable
  //    code reads identically across SDKs).

  /// Flat alias for `llm.load(modelId)`.
  Future<void> loadLLMModel(String modelId) =>
      RunAnywhereLLM.shared.load(modelId);

  /// Flat alias for `llm.unload()`.
  Future<void> unloadLLMModel() => RunAnywhereLLM.shared.unload();

  /// Flat alias for `stt.load(modelId)`.
  Future<void> loadSTTModel(String modelId) =>
      RunAnywhereSTT.shared.load(modelId);

  /// Flat alias for `stt.unload()`.
  Future<void> unloadSTTModel() => RunAnywhereSTT.shared.unload();

  /// Flat alias for `tts.loadVoice(voiceId)` — the canonical TTS load.
  Future<void> loadTTSVoice(String voiceId) =>
      RunAnywhereTTS.shared.loadVoice(voiceId);

  /// Flat alias for `tts.unloadVoice()`.
  Future<void> unloadTTSVoice() => RunAnywhereTTS.shared.unloadVoice();

  /// Flat alias for `vlm.load(modelId)`.
  Future<void> loadVLMModel(String modelId) =>
      RunAnywhereVLM.shared.load(modelId);

  /// Flat alias for `vlm.unload()`.
  Future<void> unloadVLMModel() => RunAnywhereVLM.shared.unload();

  /// Flat alias for `vad.loadModel(modelId)`.
  Future<void> loadVADModel(String modelId) =>
      RunAnywhereVAD.shared.loadModel(modelId);

  /// Flat alias for `vad.unloadModel()`.
  Future<void> unloadVADModel() => RunAnywhereVAD.shared.unloadModel();

  /// Flat alias for `models.refreshModelRegistry()`.
  Future<void> refreshModelRegistry() =>
      RunAnywhereModels.shared.refreshModelRegistry();

  /// Proto-backed model lifecycle load.
  Future<ModelLoadResult> loadModelLifecycle(ModelLoadRequest request) =>
      RunAnywhereModelLifecycle.shared.load(request);

  /// Proto-backed model lifecycle unload.
  Future<ModelUnloadResult> unloadModelLifecycle(ModelUnloadRequest request) =>
      RunAnywhereModelLifecycle.shared.unload(request);

  /// Proto-backed current-model query.
  Future<CurrentModelResult> currentModel([CurrentModelRequest? request]) =>
      RunAnywhereModelLifecycle.shared.current(request);

  /// Proto-backed component lifecycle snapshot.
  sdk_events_pb.ComponentLifecycleSnapshot? componentLifecycleSnapshot(
    SDKComponent component,
  ) =>
      RunAnywhereModelLifecycle.shared.componentSnapshot(component);

  // --- Canonical flat methods (§3-§10 of spec) --------------------------------

  /// Canonical flat method — cancel any in-flight LLM generation.
  /// Mirrors Swift / RN / Web `RunAnywhere.cancelGeneration()`.
  Future<void> cancelGeneration() async =>
      RunAnywhereLLM.shared.cancelGeneration();

  /// True when an LLM model is currently loaded. Mirrors Swift's
  /// `isLLMModelLoaded: Bool` property.
  bool get isLLMModelLoaded => RunAnywhereLLM.shared.isLoaded;

  /// Currently-loaded LLM model info, or null.
  Future<ModelInfo?> get currentLLMModel =>
      RunAnywhereLLM.shared.currentModel();

  /// True when an STT model is currently loaded.
  bool get isSTTModelLoaded => RunAnywhereSTT.shared.isLoaded;

  /// True when a TTS voice is currently loaded.
  bool get isTTSVoiceLoaded => RunAnywhereTTS.shared.isLoaded;

  /// True when a VAD model is currently loaded.
  bool get isVADModelLoaded => RunAnywhereVAD.shared.isModelLoaded;

  /// Flat alias — transcribe audio to proto [STTOutput].
  /// Mirrors Swift / RN / Web `RunAnywhere.transcribe(audio:options:)`.
  Future<STTOutput> transcribe(Uint8List audio, [STTOptions? options]) =>
      RunAnywhereSTT.shared.transcribe(audio, options);

  /// Flat streaming alias — real FFI-backed streaming STT.
  /// Mirrors Swift / RN / Web `RunAnywhere.transcribeStream`.
  Stream<STTPartialResult> transcribeStream(Uint8List audio,
          {STTOptions? options}) =>
      RunAnywhereSTT.shared.transcribeStream(audio, options: options);

  /// Flat alias — synthesize text to proto [TTSOutput].
  /// Mirrors Swift / RN / Web `RunAnywhere.synthesize(text:options:)`.
  Future<TTSOutput> synthesize(String text, [TTSOptions? options]) =>
      RunAnywhereTTS.shared.synthesize(text, options);

  /// Flat alias — speak text and return proto [TTSSpeakResult].
  /// Mirrors Swift `RunAnywhere.speak(text:options:)`.
  Future<TTSSpeakResult> speak(String text, [TTSOptions? options]) =>
      RunAnywhereTTS.shared.speak(text, options);

  /// Flat alias — stop any in-flight synthesis.
  Future<void> stopSynthesis() => RunAnywhereTTS.shared.stopSynthesis();

  /// Flat alias — list available TTS voices as [TTSVoiceInfo] proto objects.
  /// Mirrors Swift `RunAnywhere.availableTTSVoices()`.
  Future<List<TTSVoiceInfo>> availableTTSVoices() async {
    final voiceIds = await RunAnywhereTTS.shared.availableVoices();
    return voiceIds.map((id) => TTSVoiceInfo(id: id, displayName: id)).toList();
  }

  /// Flat alias for loading a TTS model (distinct from loading a TTS voice).
  /// Mirrors Swift `RunAnywhere.loadTTSModel(modelId:)`.
  Future<void> loadTTSModel(String modelId) => loadTTSVoice(modelId);

  /// Flat alias for unloading the active TTS model.
  Future<void> unloadTTSModel() => unloadTTSVoice();

  /// Flat generate — canonical cross-SDK positional signature.
  /// Mirrors Swift / RN / Web `RunAnywhere.generate(prompt:options:)`.
  Future<LLMGenerationResult> generate(
    String prompt, [
    LLMGenerationOptions? options,
  ]) =>
      RunAnywhereLLM.shared.generate(prompt, options);

  /// Flat streaming generate.
  /// Mirrors Swift / RN / Web `RunAnywhere.generateStream(prompt:options:)`.
  Stream<LLMStreamEvent> generateStream(
    String prompt, [
    LLMGenerationOptions? options,
  ]) =>
      RunAnywhereLLM.shared.generateStream(prompt, options);

  /// Flat streaming voice agent events.
  /// Mirrors Swift `RunAnywhere.streamVoiceAgent()`.
  Stream<VoiceEvent> streamVoiceAgent() =>
      RunAnywhereVoice.shared.eventStream();
}
