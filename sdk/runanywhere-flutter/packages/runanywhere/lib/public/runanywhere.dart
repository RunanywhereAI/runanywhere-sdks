// SPDX-License-Identifier: Apache-2.0
//
// runanywhere.dart — RunAnywhere SDK static entry point.
//
// Usage:
//   await RunAnywhere.initialize(
//     environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
//   );
//   await RunAnywhere.llm.load('llama-3-8b');
//   final response = await RunAnywhere.llm.chat('Hello!');

import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/adapters/http_client_adapter.dart';
import 'package:runanywhere/foundation/constants/sdk_constants.dart';
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/download_service.pb.dart'
    show DownloadProgress;
import 'package:runanywhere/generated/llm_options.pb.dart'
    show LLMGenerationOptions, LLMGenerationResult;
import 'package:runanywhere/generated/llm_service.pb.dart'
    show LLMGenerateRequest, LLMStreamEvent;
import 'package:runanywhere/generated/model_types.pb.dart'
    show
        CurrentModelRequest,
        CurrentModelResult,
        ModelInfo,
        ModelLoadRequest,
        ModelLoadResult,
        ModelUnloadRequest,
        ModelUnloadResult;
import 'package:runanywhere/generated/model_types.pbenum.dart'
    show ModelCategory;
import 'package:runanywhere/generated/rag.pb.dart'
    show
        RAGConfiguration,
        RAGDocument,
        RAGQueryOptions,
        RAGResult,
        RAGStatistics;
import 'package:runanywhere/generated/sdk_events.pb.dart' as sdk_events_pb;
import 'package:runanywhere/generated/sdk_events.pbenum.dart' show SDKComponent;
import 'package:runanywhere/generated/sdk_init.pb.dart' show SdkInitResult;
import 'package:runanywhere/generated/structured_output.pb.dart'
    show
        JSONSchema,
        StructuredOutputOptions,
        StructuredOutputResult,
        StructuredOutputStreamEvent;
import 'package:runanywhere/generated/stt_options.pb.dart'
    show STTOptions, STTOutput, STTPartialResult;
import 'package:runanywhere/generated/tool_calling.pb.dart'
    show
        ToolCall,
        ToolCallingOptions,
        ToolCallingResult,
        ToolDefinition,
        ToolResult;
import 'package:runanywhere/generated/tts_options.pb.dart'
    show TTSOptions, TTSOutput, TTSSpeakResult, TTSVoiceInfo;
import 'package:runanywhere/generated/voice_events.pb.dart' show VoiceEvent;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_auth.dart';
import 'package:runanywhere/native/dart_bridge_device.dart';
import 'package:runanywhere/native/dart_bridge_environment.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart';
import 'package:runanywhere/native/dart_bridge_sdk_init.dart';
import 'package:runanywhere/native/dart_bridge_telemetry.dart';
import 'package:runanywhere/public/capabilities/runanywhere_downloads.dart';
import 'package:runanywhere/public/capabilities/runanywhere_embeddings.dart';
import 'package:runanywhere/public/capabilities/runanywhere_hybrid.dart';
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
import 'package:runanywhere/public/configuration/sdk_environment.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/extensions/runanywhere_structured_output.dart';

/// RunAnywhere SDK entry point.
///
/// Static namespace matching Swift's `enum RunAnywhere` public surface.
///
/// Each capability class owns its own implementation. This type only
/// coordinates lifecycle, state, events, and cross-SDK flat forwarding methods.
abstract final class RunAnywhere {
  // --- Lifecycle -----------------------------------------------------------

  /// True after [initialize] has succeeded. Sourced from the C++ commons
  /// (`rac_state_is_initialized`); Dart does not maintain a parallel flag.
  static bool get isInitialized => DartBridge.isInitialized;

  /// True if the SDK is active (initialized + has init params in commons).
  static bool get isActive =>
      DartBridge.isInitialized && _cachedInitParams != null;

  /// True once Phase 2 (services) initialization has completed. Mirrors
  /// Swift's `areServicesReady`. Phase 2 is detached from [initialize] —
  /// callers needing it ready should `await completeServicesInitialization()`.
  static bool get areServicesReady =>
      DartBridge.isInitialized && DartBridge.servicesInitialized;

  /// True once Phase 2 HTTP/auth setup succeeded. Tracked separately from
  /// [areServicesReady] so an SDK that initialized offline (no connectivity)
  /// can still report `areServicesReady=true` (local models stay usable)
  /// while leaving this latch `false` for the next [ensureServicesReady]
  /// call to retry via `rac_sdk_retry_http_proto`. Mirrors Swift's
  /// `hasCompletedHTTPSetup` (RunAnywhere.swift:35) and Kotlin's
  /// `_hasCompletedHTTPSetup` (RunAnywhere.kt:121).
  static bool get hasCompletedHTTPSetup => _hasCompletedHTTPSetup;

  /// Cached device id — populated during initialization. Mirrors Swift's
  /// `deviceId: String`.
  static String get deviceId =>
      DartBridgeDevice.cachedDeviceId ?? 'unknown-device';

  /// Authenticated user id, or null if not signed in. Mirrors Swift's
  /// `getUserId()`.
  static String? get userId => DartBridgeAuth.instance.getUserId();

  /// Authenticated organization id, or null. Mirrors Swift's
  /// `getOrganizationId()`.
  static String? get organizationId =>
      DartBridgeAuth.instance.getOrganizationId();

  /// True if the SDK has a valid authentication token.
  static bool get isAuthenticated => DartBridgeAuth.instance.isAuthenticated();

  /// True if the device has been registered with the backend. Mirrors
  /// Swift's `isDeviceRegistered()`.
  static bool get isDeviceRegistered =>
      DartBridgeDevice.instance.isDeviceRegistered();

  /// Awaitable Phase-2 completion. Mirrors Swift's
  /// `completeServicesInitialization()`. [initialize] detaches Phase 2
  /// (platform service wiring plus commons-owned init orchestration) and stores
  /// the resulting Future in [_servicesInitFuture]; concurrent callers share
  /// that single Future so the work runs at most once.
  /// Returns immediately once Phase 2 has resolved. Throws
  /// [SDKException.notInitialized] if Phase 1 never ran.
  static Future<void> completeServicesInitialization() {
    if (!isInitialized) {
      throw SDKException.notInitialized();
    }
    return _servicesInitFuture ?? Future<void>.value();
  }

  /// One-call "wait until everything is ready" entry point. Three paths let an
  /// offline-first Phase 2 (services ready, HTTP/auth deferred in commons)
  /// retry HTTP setup without re-running the full step list.
  ///
  ///  - Fast path: services ready + HTTP configured → return (O(1)).
  ///  - Recovery path: services ready but HTTP failed (offline init) →
  ///    retry HTTP via `rac_sdk_retry_http_proto` without re-running Phase 2.
  ///  - Cold start path: services not ready → await the in-flight Phase-2
  ///    future (or a fresh one if Phase 2 hasn't started yet).
  ///
  /// Concurrent callers share the same Phase-2 future, so the work executes
  /// at most once.
  static Future<void> ensureServicesReady() async {
    if (!isInitialized) {
      throw SDKException.notInitialized();
    }
    // Fast path — services ready + HTTP/auth done.
    if (areServicesReady && _hasCompletedHTTPSetup) return;
    // Recovery path — services ready, HTTP/auth failed (offline init).
    if (areServicesReady && !_hasCompletedHTTPSetup) {
      await _retryHTTPSetup();
      return;
    }
    // Cold start path — Phase 1 done but Phase 2 still running (or never
    // dispatched). Await the in-flight future; concurrent callers share it.
    await (_servicesInitFuture ?? Future<void>.value());
  }

  /// Initialization params (apiKey, baseURL, environment) — null
  /// until [initialize] runs. Cached from the most recent
  /// `initializeWithParams` call so callers can introspect what was
  /// resolved (commons stores the canonical values too via
  /// `rac_state_*`).
  static SDKInitParams? get initParams => _cachedInitParams;

  /// Current SDK environment. Sourced from `DartBridge` which mirrors
  /// commons' canonical environment.
  static SDKEnvironment? get environment =>
      DartBridge.isInitialized ? DartBridge.environment : null;

  // Cached params from the most recent successful initializeWithParams.
  // The canonical source is commons (rac_state_*); this is a lightweight
  // Dart accessor for callers that want the original Uri / apiKey shape.
  static SDKInitParams? _cachedInitParams;

  // One-shot Dart-only compatibility flag: startup downloaded-model discovery
  // is owned by commons Phase 2; legacy callers still use runDiscoveryIfNeeded()
  // as a readiness guard before listing registry contents.
  static bool _hasRunDiscovery = false;

  // Latched HTTP/auth completion flag — see [hasCompletedHTTPSetup]. Phase 2
  // sets this from the C++ `SdkInitResult.http_configured` snapshot;
  // [_retryHTTPSetup] re-latches on a successful `rac_sdk_retry_http_proto`
  // round-trip so subsequent `ensureServicesReady()` calls short-circuit.
  static bool _hasCompletedHTTPSetup = false;

  // Shared Phase-2 future. Mirrors Swift's `_servicesInitTask`. Stored at
  // detach time inside [initializeWithParams]; replayed by
  // [completeServicesInitialization]. Dart's single-threaded event loop
  // makes the check-and-set atomic, so no explicit lock is needed (unlike
  // Swift which uses `_servicesInitLock: DispatchQueue`).
  static Future<void>? _servicesInitFuture;

  /// SDK semver string (e.g. "4.0.0").
  static String get version => SDKConstants.version;

  /// Event bus for cross-capability SDK events.
  static EventBus get events => EventBus.shared;

  /// Initialize the SDK with API key + base URL.
  static Future<void> initialize({
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
  /// - Phase 1 (awaited): synchronous core init (~1–5 ms) — register
  ///   platform adapter, configure logging, run `rac_state_initialize`,
  ///   wire events / device / telemetry / file-manager callbacks.
  ///   Completes before this method returns. Phase 1 failures throw to
  ///   the caller.
  /// - Phase 2 (detached): local service setup (HTTP/telemetry/model
  ///   registry) + background services (device registration + auth).
  ///   Mirrors Swift's `Task.detached(priority: .userInitiated)`. The
  ///   resulting Future is stored in [_servicesInitFuture] so concurrent
  ///   callers of [completeServicesInitialization] share it. Failures
  ///   are non-critical — they are swallowed at the detach site (logged
  ///   as warnings) but still observable to anyone awaiting
  ///   [completeServicesInitialization] directly.
  static Future<void> initializeWithParams(SDKInitParams params) async {
    if (DartBridge.isInitialized) return;

    final logger = SDKLogger('RunAnywhere.Init');
    // C++ commons auto-emits INITIALIZATION_STAGE_STARTED via
    // `event_publisher.cpp:531`; Dart does not re-emit a duplicate.

    try {
      _cachedInitParams = params;

      final phase1DeviceId = await DartBridgeDevice.instance.getDeviceId();

      // --- Phase 1: Core init (sync after Flutter async device-id lookup) ---
      // Phase-1 failures (invalid env, library load) propagate to the
      // caller via the surrounding try / rethrow.
      DartBridge.initialize(
        params.environment,
        apiKey: params.apiKey,
        baseURL: params.baseURL.toString(),
        deviceId: phase1DeviceId,
      );
      DartBridge.registerEnsureServicesReadyHook(ensureServicesReady);

      logger.info(
        'Phase 1 complete (${params.environment.description}); '
        'Phase 2 dispatched in background',
      );

      // --- Phase 2: Detached background services ---
      // Mirrors Swift `Task.detached(priority: .userInitiated) { ... }`.
      // Store the Future first so concurrent callers of
      // `completeServicesInitialization()` see it before the detach
      // wrapper might observe a failure. Phase 2 errors are swallowed
      // here (non-critical) but still observable to direct awaiters.
      final phase2 = _runPhase2(params, logger);
      _servicesInitFuture = phase2;
      unawaited(
        phase2.catchError((Object error, StackTrace _) {
          logger.warning('Phase 2 failed (non-critical): $error');
        }),
      );
    } catch (e) {
      logger.error('SDK initialization failed: $e');
      _cachedInitParams = null;
      _hasRunDiscovery = false;
      _hasCompletedHTTPSetup = false;
      _servicesInitFuture = null;
      // Commons auto-emits INITIALIZATION_STAGE_FAILED via
      // `event_publisher.cpp:557`; failure telemetry flows through
      // structured errors. Dart does not re-emit a duplicate.
      rethrow;
    }
  }

  /// Platform-owned Phase 2 setup plus the commons deterministic init step-list.
  /// Runs detached from [initializeWithParams] so the caller's
  /// `await initialize()` returns after Phase 1 and the platform device-id
  /// lookup needed to populate the commons init contract.
  static Future<void> _runPhase2(SDKInitParams params, SDKLogger logger) async {
    // Step 1: Configure the shared HTTP client. Mirrors Swift's inlined
    // HTTP setup inside `RunAnywhere.performCoreInit()` (no DI container).
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

    // Step 2: Model-paths base directory. Commons Phase 2 performs downloaded
    // model discovery, so the path root must exist before the proto call.
    await DartBridge.modelPaths.setBaseDirectory();

    // Step 3: Telemetry sink setup. The flush itself is now owned by commons
    // Phase 2 via rac_events_flush_telemetry_sink.
    DartBridgeTelemetry.initializeSync(environment: params.environment);
    final telemetryDeviceId = await DartBridgeDevice.instance.getDeviceId();
    await DartBridgeTelemetry.initialize(
      environment: params.environment,
      deviceId: telemetryDeviceId,
      baseURL: HTTPClientAdapter.shared.isConfigured
          ? params.baseURL.toString()
          : null,
    );

    // Step 4: Global model registry handle.
    await DartBridgeModelRegistry.instance.initialize();

    // Commons auto-emits the INITIALIZATION_STAGE_COMPLETED SDKEvent from the
    // C++ init path (`event_publisher.cpp:544`) and the destination router
    // forwards it to the registered telemetry sink, so Dart does not emit it.

    // Step 5: Commons-owned deterministic Phase 2 orchestration: auth via the
    // registered HTTP transport, device registration with build token, model
    // assignment fetch, telemetry flush, and downloaded-model discovery.
    final phase2Result = await DartBridge.initializeServices(
      apiKey: params.apiKey,
      baseURL: params.baseURL.toString(),
      deviceId: telemetryDeviceId,
      buildToken:
          params.environment == SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT
          ? DartBridgeDevConfig.buildToken
          : null,
      forceRefreshAssignments: false,
      flushTelemetry: true,
      discoverDownloadedModels: true,
      rescanLocalModels: true,
    );

    _hasCompletedHTTPSetup = _isHTTPSetupComplete(phase2Result);
    if (phase2Result?.success == true) {
      _hasRunDiscovery = true;
    }

    logger.info('Phase 2 complete (${params.environment.description})');
  }

  /// Latched HTTP setup status from the generated commons init result.
  static bool _isHTTPSetupComplete(SdkInitResult? result) {
    if (result == null) return false;
    if (result.hasHasCompletedHttpSetup()) {
      return result.hasCompletedHttpSetup;
    }
    return result.httpConfigured;
  }

  /// Retry HTTP/auth after an offline initialization. The retry orchestration
  /// lives in commons behind `rac_sdk_retry_http_proto`; Dart only latches the
  /// generated result. Failures are logged and swallowed so the next call can
  /// retry again.
  static Future<void> _retryHTTPSetup() async {
    final logger = SDKLogger('RunAnywhere.HTTPRetry');

    try {
      final proto = DartBridgeSdkInit.retryHTTP();
      _hasCompletedHTTPSetup = _isHTTPSetupComplete(proto);
      if (proto.hasWarning()) {
        logger.debug('HTTP retry warning: ${proto.warning}');
      }
      if (_hasCompletedHTTPSetup) {
        logger.info('HTTP/Auth setup succeeded on retry');
      } else {
        logger.debug('HTTP/Auth retry still missing usable config');
      }
    } catch (e) {
      logger.debug('HTTP retry proto failed: $e');
    }
  }

  /// Compatibility hook for callers that previously triggered one-shot
  /// downloaded-model discovery before listing. Startup discovery now runs in
  /// commons Phase 2, so this only waits for Phase 2 once.
  static Future<void> runDiscoveryIfNeeded() async {
    if (_hasRunDiscovery) return;
    final logger = SDKLogger('RunAnywhere.Discovery');
    try {
      await completeServicesInitialization();
    } catch (e) {
      logger.debug('Phase 2 discovery readiness wait failed: $e');
    }
    _hasRunDiscovery = true;
  }

  /// Reset all SDK state; clears registered models, cached
  /// configuration, loaded backends. Useful for tests.
  ///
  /// Mirrors Swift `RunAnywhere.reset()`: this is the symmetric counterpart
  /// of [initializeWithParams]. Calling reset() and then a subsequent
  /// initialize(...) MUST run a fresh Phase 1 + Phase 2 against the new
  /// params, so reset must clear the bridge's `_isInitialized` flag —
  /// otherwise [initializeWithParams] short-circuits at
  /// `if (DartBridge.isInitialized) return;` and the SDK stays in a
  /// half-reset state (Dart caches empty, native bridge still marked
  /// initialized).
  static Future<void> reset() async {
    DartBridgeTelemetry.flush();

    DartBridge.modelLifecycle.reset();
    _hasRunDiscovery = false;
    _hasCompletedHTTPSetup = false;
    _cachedInitParams = null;
    _servicesInitFuture = null;
    DartBridgeModelRegistry.instance.shutdown();
    HTTPClientAdapter.shared.resetForTesting();
    // Tear down the bridge LAST so dependents (telemetry/registry/HTTP)
    // can flush against a still-initialized native side. Mirrors Swift's
    // `await CppBridge.shutdown()` ordering inside `RunAnywhere.reset()`.
    unawaited(DartBridge.shutdown());
  }

  // --- Capability surfaces -------------------------------------------------

  /// LLM (text generation) — load, chat, generate, generate-stream, cancel.
  static RunAnywhereLLM get llm => RunAnywhereLLM.shared;

  /// STT (speech-to-text) — load, transcribe.
  static RunAnywhereSTT get stt => RunAnywhereSTT.shared;

  /// TTS (text-to-speech) — load voice, synthesize, speak.
  static RunAnywhereTTS get tts => RunAnywhereTTS.shared;

  /// VAD (voice activity detection) — initialize, detectSpeech, start/stop,
  /// load model. Mirrors Swift's `RunAnywhere+VAD.swift` extension.
  static RunAnywhereVAD get vad => RunAnywhereVAD.shared;

  /// VLM (vision-language model) — load, processImage, processImageStream,
  /// describe, askAbout.
  static RunAnywhereVLM get vlm => RunAnywhereVLM.shared;

  /// VisionLanguage namespace (Swift parity). Identical to [vlm].
  static RunAnywhereVLM get visionLanguage => RunAnywhereVLM.shared;

  /// Voice Agent (full STT → LLM → TTS pipeline) — initialize,
  /// cleanup, isReady, eventStream. Symmetric with `llm.generateStream`:
  /// `voice.eventStream()` returns `Stream<VoiceEvent>` and wraps
  /// `VoiceAgentStreamAdapter` internally.
  static RunAnywhereVoice get voice => RunAnywhereVoice.shared;

  /// Models registry — list available, refresh from filesystem,
  /// register, register multi-file, update download status, remove.
  static RunAnywhereModels get models => RunAnywhereModels.shared;

  /// Model/component lifecycle — generated proto load/unload/current/snapshot.
  static RunAnywhereModelLifecycle get modelLifecycle =>
      RunAnywhereModelLifecycle.shared;

  /// Downloads — start, delete, storage info, list downloaded.
  static RunAnywhereDownloads get downloads => RunAnywhereDownloads.shared;

  /// Tools (LLM function calling) — register, execute, generateWithTools.
  static RunAnywhereTools get tools => RunAnywhereTools.shared;

  /// RAG (Retrieval-Augmented Generation) — pipeline lifecycle,
  /// ingest, query, statistics.
  static RunAnywhereRAG get rag => RunAnywhereRAG.shared;

  /// Solutions (T4.7/T4.8) — proto/YAML-driven L5 pipeline runtime.
  /// Construct a solution from a typed `SolutionConfig` proto, raw
  /// proto bytes, or YAML sugar; returns a [SolutionHandle] with
  /// start / stop / cancel / feed / closeInput / destroy verbs.
  static RunAnywhereSolutions get solutions => RunAnywhereSolutions.shared;

  // Diffusion (image generation) is intentionally NOT exposed on the public
  // `RunAnywhere` namespace until the cross-SDK v2 contract for image
  // generation lands (proto-backed lifecycle stream/cancel/capabilities ABIs
  // across Swift/Kotlin/RN/Web). Removed under swift-parity-002-followup-flutter
  // to keep the Swift-as-reference public surface coherent. The implementation
  // in `public/capabilities/runanywhere_diffusion.dart` is retained for the
  // day the contract is settled.

  /// Embeddings — load an embeddings model and generate embedding vectors.
  static RunAnywhereEmbeddings get embeddings => RunAnywhereEmbeddings.shared;

  /// Runtime plugin loader (parity with Swift `RunAnywhere.PluginLoader`).
  static RunAnywherePluginLoaderCapability get pluginLoader =>
      RunAnywherePluginLoaderCapability.shared;

  /// LoRA (Low-Rank Adaptation) capability — load, remove, register,
  /// query loaded/registered adapters. Canonical §3 namespace.
  static RunAnywhereLoRACapability get lora => RunAnywhereLoRACapability.shared;

  /// Hybrid STT router — per-request dispatch between an on-device (offline,
  /// sherpa) and a cloud (online, cloud) speech service. Vends the router
  /// factory, the cloud-backend registry, the device-state installer, and
  /// cloud plugin registration. Mirrors Kotlin `RACRouter` /
  /// Swift `HybridSTTRouter`. STT-only today.
  static RunAnywhereHybrid get hybrid => RunAnywhereHybrid.shared;

  // -- Flat aliases for cross-SDK portability (canonical §0 — RN/Web/Swift use
  //    flat method names; Flutter additionally exposes them so portable
  //    code reads identically across SDKs).

  /// Flat alias for `llm.load(modelId)`.
  static Future<void> loadLLMModel(String modelId) =>
      RunAnywhereLLM.shared.load(modelId);

  /// Flat alias for `llm.unload()`.
  static Future<void> unloadLLMModel() => RunAnywhereLLM.shared.unload();

  /// Flat alias for `stt.load(modelId)`.
  static Future<void> loadSTTModel(String modelId) =>
      RunAnywhereSTT.shared.load(modelId);

  /// Flat alias for `stt.unload()`.
  static Future<void> unloadSTTModel() => RunAnywhereSTT.shared.unload();

  /// Flat alias for `tts.loadVoice(voiceId)` — the canonical TTS load.
  static Future<void> loadTTSVoice(String voiceId) =>
      RunAnywhereTTS.shared.loadVoice(voiceId);

  /// Flat alias for `tts.unloadVoice()`.
  static Future<void> unloadTTSVoice() => RunAnywhereTTS.shared.unloadVoice();

  /// Flat alias for `vlm.load(modelId)`.
  static Future<void> loadVLMModel(String modelId) =>
      RunAnywhereVLM.shared.load(modelId);

  /// Flat alias for `vlm.unload()`.
  static Future<void> unloadVLMModel() => RunAnywhereVLM.shared.unload();

  /// Flat alias for `vad.loadModel(modelId)`.
  static Future<void> loadVADModel(String modelId) =>
      RunAnywhereVAD.shared.loadModel(modelId);

  /// Flat alias for `vad.unloadModel()`.
  static Future<void> unloadVADModel() => RunAnywhereVAD.shared.unloadModel();

  /// Flat alias for `models.refreshModelRegistry()`.
  static Future<void> refreshModelRegistry() =>
      RunAnywhereModels.shared.refreshModelRegistry();

  /// Proto-backed model lifecycle load. Matches the universal
  /// `RunAnywhere.loadModel(request)` name on Swift, Kotlin, RN, and Web.
  static Future<ModelLoadResult> loadModel(ModelLoadRequest request) =>
      RunAnywhereModelLifecycle.shared.load(request);

  /// Proto-backed model lifecycle unload. Matches the universal
  /// `RunAnywhere.unloadModel(request)` name on Swift, Kotlin, RN, and Web.
  static Future<ModelUnloadResult> unloadModel(ModelUnloadRequest request) =>
      RunAnywhereModelLifecycle.shared.unload(request);

  /// Polymorphic load — dispatch on [ModelInfo.category]. Drop-in replacement
  /// for the per-capability `llm.load` / `stt.load` / `tts.loadVoice` /
  /// `vlm.load` / `vad.loadModel` switch ladders that example view-models
  /// otherwise hand-roll. Named `loadModelByInfo` to avoid collision with the
  /// proto-backed [loadModel] overload (Dart has no method overloading).
  static Future<void> loadModelByInfo(ModelInfo model) =>
      RunAnywhereModels.shared.loadModel(model);

  /// Polymorphic unload — dispatch on [ModelInfo.category]. Named
  /// `unloadModelByInfo` to avoid collision with the proto-backed [unloadModel].
  static Future<void> unloadModelByInfo(ModelInfo model) =>
      RunAnywhereModels.shared.unloadModel(model);

  /// Proto-backed current-model query.
  static Future<CurrentModelResult> currentModel([
    CurrentModelRequest? request,
  ]) => RunAnywhereModelLifecycle.shared.current(request);

  /// Full [ModelInfo] for the model currently loaded under [category], or
  /// `null` when nothing is loaded for it.
  static Future<ModelInfo?> modelInfoForCategory(ModelCategory category) =>
      RunAnywhereModelLifecycle.shared.modelInfoForCategory(category);

  /// Proto-backed component lifecycle snapshot.
  static sdk_events_pb.ComponentLifecycleSnapshot? componentLifecycleSnapshot(
    SDKComponent component,
  ) => RunAnywhereModelLifecycle.shared.componentSnapshot(component);

  // --- Canonical flat methods (§3-§10 of spec) --------------------------------

  /// Canonical flat method — cancel any in-flight LLM generation.
  /// Mirrors Swift / RN / Web `RunAnywhere.cancelGeneration()`.
  static void cancelGeneration() => RunAnywhereLLM.shared.cancelGeneration();

  /// True when an LLM model is currently loaded. Mirrors Swift's
  /// `isLLMModelLoaded: Bool` property.
  static bool get isLLMModelLoaded => RunAnywhereLLM.shared.isLoaded;

  /// Currently-loaded LLM model info, or null.
  static Future<ModelInfo?> get currentLLMModel =>
      RunAnywhereLLM.shared.currentModel();

  /// True when an STT model is currently loaded.
  static bool get isSTTModelLoaded => RunAnywhereSTT.shared.isLoaded;

  /// True when a TTS voice is currently loaded.
  static bool get isTTSVoiceLoaded => RunAnywhereTTS.shared.isLoaded;

  /// True when a VAD model is currently loaded.
  static bool get isVADModelLoaded => RunAnywhereVAD.shared.isModelLoaded;

  /// Flat alias — transcribe audio to proto [STTOutput].
  /// Mirrors Swift / RN / Web `RunAnywhere.transcribe(audio:options:)`.
  static Future<STTOutput> transcribe(Uint8List audio, [STTOptions? options]) =>
      RunAnywhereSTT.shared.transcribe(audio, options);

  /// Flat streaming alias — real FFI-backed streaming STT.
  /// Mirrors Swift / RN / Web `RunAnywhere.transcribeStream`.
  static Stream<STTPartialResult> transcribeStream(
    Uint8List audio, {
    STTOptions? options,
  }) => RunAnywhereSTT.shared.transcribeStream(audio, options: options);

  /// Flat chunk-feed streaming alias — session-based stream-in / stream-out
  /// transcription; the native session owns endpointing. Mirrors Swift
  /// `RunAnywhere.transcribeStream(audio: AsyncStream<Data>)`.
  static Stream<STTPartialResult> transcribeStreamSession(
    Stream<Uint8List> audio, {
    STTOptions? options,
  }) => RunAnywhereSTT.shared.transcribeStreamSession(audio, options: options);

  /// Flat alias — synthesize text to proto [TTSOutput].
  /// Mirrors Swift / RN / Web `RunAnywhere.synthesize(text:options:)`.
  static Future<TTSOutput> synthesize(String text, [TTSOptions? options]) =>
      RunAnywhereTTS.shared.synthesize(text, options);

  /// Flat alias — speak text and return proto [TTSSpeakResult].
  /// Mirrors Swift `RunAnywhere.speak(text:options:)`.
  static Future<TTSSpeakResult> speak(String text, [TTSOptions? options]) =>
      RunAnywhereTTS.shared.speak(text, options);

  /// Flat alias — stop any in-flight synthesis.
  static Future<void> stopSynthesis() => RunAnywhereTTS.shared.stopSynthesis();

  /// Flat alias — list available TTS voices as [TTSVoiceInfo] proto objects.
  /// Mirrors Swift `RunAnywhere.availableTTSVoices()`.
  static Future<List<TTSVoiceInfo>> availableTTSVoices() async {
    final voiceIds = await RunAnywhereTTS.shared.availableVoices();
    return voiceIds.map((id) => TTSVoiceInfo(id: id, displayName: id)).toList();
  }

  /// Flat alias for loading a TTS model (distinct from loading a TTS voice).
  /// Mirrors Swift `RunAnywhere.loadTTSModel(modelId:)`.
  static Future<void> loadTTSModel(String modelId) => loadTTSVoice(modelId);

  /// Flat alias for unloading the active TTS model.
  static Future<void> unloadTTSModel() => unloadTTSVoice();

  /// Flat generate — canonical cross-SDK positional signature.
  /// Mirrors Swift / RN / Web `RunAnywhere.generate(prompt:options:)`.
  static Future<LLMGenerationResult> generate(
    String prompt, [
    LLMGenerationOptions? options,
  ]) => RunAnywhereLLM.shared.generate(prompt, options);

  /// Flat generated-proto LLM request.
  static Future<LLMGenerationResult> generateRequest(
    LLMGenerateRequest request,
  ) => RunAnywhereLLM.shared.generateRequest(request);

  /// Flat streaming generate.
  /// Mirrors Swift / RN / Web `RunAnywhere.generateStream(prompt:options:)`.
  static Stream<LLMStreamEvent> generateStream(
    String prompt, [
    LLMGenerationOptions? options,
  ]) => RunAnywhereLLM.shared.generateStream(prompt, options);

  /// Flat generated-proto streaming LLM request.
  static Stream<LLMStreamEvent> generateStreamRequest(
    LLMGenerateRequest request,
  ) => RunAnywhereLLM.shared.generateStreamRequest(request);

  /// Extract structured output from raw model text using a typed schema.
  static StructuredOutputResult extractStructuredOutput({
    required String text,
    required JSONSchema schema,
  }) =>
      RunAnywhereLLM.shared.extractStructuredOutput(text: text, schema: schema);

  /// Generate structured output using commons orchestration.
  static Future<StructuredOutputResult> generateStructured({
    required String prompt,
    required JSONSchema schema,
    LLMGenerationOptions? options,
  }) => RunAnywhereStructuredOutput.generateStructured(
    prompt: prompt,
    schema: schema,
    options: options,
  );

  /// Stream structured output events.
  static Stream<StructuredOutputStreamEvent> generateStructuredStream({
    required String prompt,
    required JSONSchema schema,
    LLMGenerationOptions? options,
  }) => RunAnywhereStructuredOutput.generateStructuredStream(
    prompt: prompt,
    schema: schema,
    options: options,
  );

  /// Generate raw LLM text with a structured-output configuration.
  static Future<LLMGenerationResult> generateWithStructuredOutput({
    required String prompt,
    required StructuredOutputOptions structuredOutput,
    LLMGenerationOptions? options,
  }) => RunAnywhereStructuredOutput.generateWithStructuredOutput(
    prompt: prompt,
    structuredOutput: structuredOutput,
    options: options,
  );

  /// Register a tool executor.
  static void registerTool(ToolDefinition definition, ToolExecutor executor) =>
      RunAnywhereTools.shared.registerTool(definition, executor);

  /// Register a typed generated-proto tool executor.
  static void registerTypedTool(
    ToolDefinition definition,
    TypedToolExecutor executor,
  ) => RunAnywhereTools.shared.registerTypedTool(definition, executor);

  /// Unregister a tool by name.
  static void unregisterTool(String toolName) =>
      RunAnywhereTools.shared.unregisterTool(toolName);

  /// Registered tool definitions.
  static List<ToolDefinition> getRegisteredTools() =>
      RunAnywhereTools.shared.getRegisteredTools();

  /// Clear all registered tools.
  static void clearTools() => RunAnywhereTools.shared.clearTools();

  /// Execute a tool call manually.
  static Future<ToolResult> executeTool(ToolCall toolCall) =>
      RunAnywhereTools.shared.execute(toolCall);

  /// Generate with tool calling support.
  static Future<ToolCallingResult> generateWithTools(
    String prompt, {
    ToolCallingOptions? options,
  }) => RunAnywhereTools.shared.generateWithTools(prompt, options: options);

  /// Continue generation after a manual tool result.
  static Future<ToolCallingResult> continueWithToolResult(
    String originalPrompt,
    ToolResult toolResult, {
    ToolCallingOptions? options,
  }) => RunAnywhereTools.shared.continueWithToolResult(
    originalPrompt,
    toolResult,
    options: options,
  );

  /// RAG lifecycle-resolution helper.
  static Future<RAGConfiguration> ragResolvedConfiguration({
    required ModelInfo embeddingModel,
    required ModelInfo llmModel,
    RAGConfiguration? baseConfiguration,
  }) => RunAnywhereRAG.shared.ragResolvedConfiguration(
    embeddingModel: embeddingModel,
    llmModel: llmModel,
    baseConfiguration: baseConfiguration,
  );

  /// Create a RAG pipeline from generated config.
  static Future<void> ragCreatePipeline(RAGConfiguration config) =>
      RunAnywhereRAG.shared.ragCreatePipeline(config);

  /// Create a RAG pipeline from registry models.
  static Future<void> ragCreatePipelineForModels({
    required ModelInfo embeddingModel,
    required ModelInfo llmModel,
    RAGConfiguration? baseConfiguration,
  }) => RunAnywhereRAG.shared.ragCreatePipelineForModels(
    embeddingModel: embeddingModel,
    llmModel: llmModel,
    baseConfiguration: baseConfiguration,
  );

  /// Destroy the RAG pipeline.
  static Future<void> ragDestroyPipeline() =>
      RunAnywhereRAG.shared.ragDestroyPipeline();

  /// Ingest a generated-proto RAG document.
  static Future<RAGStatistics> ragIngest(RAGDocument document) =>
      RunAnywhereRAG.shared.ragIngest(document);

  /// Add a batch of generated-proto RAG documents.
  static Future<void> ragAddDocumentsBatch(List<RAGDocument> documents) =>
      RunAnywhereRAG.shared.ragAddDocumentsBatch(documents);

  /// RAG document count.
  static Future<int> ragGetDocumentCount() =>
      RunAnywhereRAG.shared.ragGetDocumentCount();

  /// RAG document count convenience getter.
  static Future<int> get ragDocumentCount =>
      RunAnywhereRAG.shared.ragDocumentCount;

  /// RAG statistics.
  static Future<RAGStatistics> ragGetStatistics() =>
      RunAnywhereRAG.shared.ragGetStatistics();

  /// Clear RAG documents.
  static Future<void> ragClearDocuments() =>
      RunAnywhereRAG.shared.ragClearDocuments();

  /// Query the RAG pipeline.
  static Future<RAGResult> ragQuery(RAGQueryOptions options) =>
      RunAnywhereRAG.shared.ragQuery(options);

  /// Download a registered model by id. Drains the commons-backed progress
  /// stream, forwarding each event to [onProgress], and returns the terminal
  /// [DownloadProgress] on completion.
  ///
  /// Mirrors Swift `RunAnywhere.downloadModel(_:onProgress:) async throws ->
  /// RADownloadProgress`: callers await the final result and observe progress
  /// via the optional callback — they do not need to manage the stream
  /// themselves. Throws [SDKException] on failure or cancellation.
  static Future<DownloadProgress> downloadModel(
    String modelId, {
    Future<void> Function(DownloadProgress)? onProgress,
  }) async {
    DownloadProgress? last;
    await for (final progress in RunAnywhereDownloads.shared.start(modelId)) {
      last = progress;
      if (onProgress != null) {
        await onProgress(progress);
      }
    }
    return last ??
        DownloadProgress(
          modelId: modelId,
          errorMessage: 'No progress events received for model: $modelId',
        );
  }

  /// Flat streaming voice agent events.
  /// Mirrors Swift `RunAnywhere.streamVoiceAgent()`.
  static Stream<VoiceEvent> streamVoiceAgent() =>
      RunAnywhereVoice.shared.eventStream();
}
