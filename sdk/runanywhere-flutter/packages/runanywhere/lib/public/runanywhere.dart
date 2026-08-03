// SPDX-License-Identifier: Apache-2.0
//
// runanywhere.dart — RunAnywhere SDK entry point (public API v3).
//
// The whole public surface is this type plus its capability namespaces. One
// verb has exactly one name and one shape; everything else lives behind the
// namespaces or is internal.

import 'dart:async';

import 'package:runanywhere/adapters/http_client_adapter.dart';
import 'package:runanywhere/foundation/constants/sdk_constants.dart';
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/ra_defaults_pool.dart';
import 'package:runanywhere/generated/sdk_init.pb.dart' show SdkInitResult;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_device.dart';
import 'package:runanywhere/native/dart_bridge_hf_auth.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart';
import 'package:runanywhere/native/dart_bridge_sdk_init.dart';
import 'package:runanywhere/native/dart_bridge_state.dart';
import 'package:runanywhere/native/dart_bridge_telemetry.dart';
import 'package:runanywhere/public/api/internal/sdk_event_mapper.dart';
import 'package:runanywhere/public/api/namespaces/embeddings.dart';
import 'package:runanywhere/public/api/namespaces/llm.dart';
import 'package:runanywhere/public/api/namespaces/media.dart';
import 'package:runanywhere/public/api/namespaces/models.dart';
import 'package:runanywhere/public/api/namespaces/rag.dart';
import 'package:runanywhere/public/api/namespaces/stt.dart';
import 'package:runanywhere/public/api/namespaces/tts.dart';
import 'package:runanywhere/public/api/namespaces/vad.dart';
import 'package:runanywhere/public/api/namespaces/vlm.dart';
import 'package:runanywhere/public/api/namespaces/voice.dart';
import 'package:runanywhere/public/api/types/events.dart';
import 'package:runanywhere/public/capabilities/runanywhere_cua.dart';
import 'package:runanywhere/public/capabilities/runanywhere_hybrid.dart';
import 'package:runanywhere/public/capabilities/runanywhere_solutions.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';
import 'package:runanywhere/public/events/event_bus.dart';

/// RunAnywhere SDK entry point.
abstract final class RunAnywhere {
  // --- Core ----------------------------------------------------------------

  /// Bring the SDK up: platform adapters, native load, auth, device
  /// registration, catalog, and telemetry.
  ///
  /// A null [apiKey] runs keyless local mode; a null [baseUrl] uses the
  /// default control plane for [environment]. Remote work continues in the
  /// background after the call returns, so there is no second phase.
  ///
  /// Throws [SDKException] when the native core cannot start or the
  /// configuration is rejected.
  static Future<void> initialize({
    String? apiKey,
    String? baseUrl,
    SDKEnvironment environment = SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
  }) {
    final existing = _initializationFuture;
    if (existing != null) return existing;

    final resetInProgress = _resetFuture;
    final operation = () async {
      if (resetInProgress != null) await resetInProgress;
      await _initialize(_resolveParams(apiKey, baseUrl, environment));
    }();
    _initializationFuture = operation;
    unawaited(_clearWhenSettled(operation, () => _initializationFuture, () {
      _initializationFuture = null;
    }));
    return operation;
  }

  /// Tear everything down: unload models, close sessions, clear state.
  static Future<void> reset() {
    final existing = _resetFuture;
    if (existing != null) return existing;

    DartBridge.beginShutdown();
    final initializationInProgress = _initializationFuture;
    if (identical(_initializationFuture, initializationInProgress)) {
      _initializationFuture = null;
    }
    final operation = () async {
      if (initializationInProgress != null) {
        try {
          await initializationInProgress;
        } catch (_) {
          // Initialization owns its rollback; teardown still runs.
        }
      }
      final servicesInProgress = _remoteServicesFuture;
      if (servicesInProgress != null) {
        try {
          await servicesInProgress;
        } catch (_) {
          // Remote setup is best-effort; teardown still runs.
        }
      }
      await _reset();
    }();
    _resetFuture = operation;
    unawaited(_clearWhenSettled(operation, () => _resetFuture, () {
      _resetFuture = null;
    }));
    return operation;
  }

  /// True once local inference is usable.
  static bool get isReady => DartBridge.isInitialized && _localServicesReady;

  /// SDK semver string.
  static String get version => SDKConstants.version;

  /// Stable per-install device identifier.
  ///
  /// Throws [SDKException] before [initialize] has run.
  static String get deviceId {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized(
        'Device ID is unavailable before RunAnywhere.initialize().',
      );
    }
    final value = DartBridgeDevice.cachedDeviceId;
    if (value == null || value.isEmpty) {
      throw StateError('Device ID was not resolved during initialization');
    }
    return value;
  }

  /// Lifecycle, model, and error breadcrumbs.
  static Stream<SdkEvent> get events => EventBus.shared.allEvents
      .map(SdkEventMapper.map)
      .where((event) => event != null)
      .cast<SdkEvent>();

  // --- Capability namespaces ----------------------------------------------

  /// Text generation, tool calling, and structured output.
  static LlmApi get llm => const LlmApi();

  /// Vision-language generation.
  static VlmApi get vlm => const VlmApi();

  /// Speech-to-text transcription.
  static SttApi get stt => const SttApi();

  /// Text-to-speech synthesis and playback.
  static TtsApi get tts => _tts;

  /// Voice-activity detection.
  static VadApi get vad => const VadApi();

  /// Text embedding.
  static EmbeddingsApi get embeddings => const EmbeddingsApi();

  /// Cross-encoder reranking.
  static RerankApi get rerank => const RerankApi();

  /// Diffusion image generation.
  static ImagesApi get images => const ImagesApi();

  /// Speaker diarization.
  static DiarizationApi get diarization => const DiarizationApi();

  /// Semantic image segmentation.
  static SegmentationApi get segmentation => const SegmentationApi();

  /// Speech-to-speech agent sessions.
  static VoiceApi get voice => const VoiceApi();

  /// Retrieval-augmented generation sessions.
  static RagApi get rag => const RagApi();

  /// The model registry.
  static ModelsApi get models => const ModelsApi();

  /// LoRA adapters applied on top of the loaded model.
  static LoraApi get lora => const LoraApi();

  /// Computer-use-agent scaffold — stateless, model-agnostic `systemPrompt` +
  /// `parseAction` over a model profile (Fara1.5 built in). Pair with [vlm]
  /// for inference; the app owns screenshot capture, action execution, and the
  /// agent loop.
  static RunAnywhereCUA get cua => RunAnywhereCUA.shared;

  // --- Beyond the v3 spec --------------------------------------------------
  //
  // The two namespaces below have no v3 spec entry but back shipped features
  // with no other public path. They stay until the spec covers them.

  /// Proto/YAML-driven pipeline runtime.
  static RunAnywhereSolutions get solutions => RunAnywhereSolutions.shared;

  /// On-device/cloud speech routing.
  static RunAnywhereHybrid get hybrid => RunAnywhereHybrid.shared;

  /// Supply a Hugging Face bearer token so private model repos can be fetched.
  ///
  /// Pass an empty string to clear it; pass null to fall back to the
  /// `HF_TOKEN` environment variable.
  static void setHfToken(String? token) => DartBridgeHfAuth.setHfToken(token);

  // --- Internals -----------------------------------------------------------

  static final TtsApi _tts = TtsApi();

  static SDKInitParams? _cachedInitParams;
  static bool _localServicesReady = false;
  static bool _hasCompletedHttpSetup = false;
  static bool _httpSetupApplicable = true;
  static Future<void>? _initializationFuture;
  static Future<void>? _remoteServicesFuture;
  static Future<void>? _resetFuture;

  static SDKInitParams _resolveParams(
    String? apiKey,
    String? baseUrl,
    SDKEnvironment environment,
  ) {
    final key = (apiKey ?? '').trim();
    final url = (baseUrl ?? '').trim();
    if (url.isEmpty) {
      // Commons resolves the baked control-plane URL for the environment; the
      // development placeholder keeps its validated shape.
      return SDKInitParams(
        apiKey: key,
        baseURL: Uri.parse(RADefaultsEnvironment.developmentPlaceholderUrl),
        environment: environment,
      );
    }
    final parsed = Uri.tryParse(url);
    if (parsed == null) {
      throw SDKException.validationFailed(
        'Invalid base URL: $url',
        fieldPath: 'RunAnywhere.initialize.baseUrl',
      );
    }
    return SDKInitParams(
      apiKey: key,
      baseURL: parsed,
      environment: environment,
    );
  }

  static Future<void> _initialize(SDKInitParams params) async {
    if (DartBridge.isInitialized) return;

    final logger = SDKLogger('RunAnywhere.Init');
    try {
      _cachedInitParams = params;
      final deviceId = await DartBridgeDevice.instance.getDeviceId();

      // The telemetry sink must exist before core init: commons emits
      // initialization events during it and a null sink drops them.
      DartBridgeTelemetry.attachSinkPhase1(
        environment: params.environment,
        deviceId: deviceId,
      );

      DartBridge.initialize(
        params.environment,
        apiKey: params.apiKey,
        baseURL: params.baseURL.toString(),
        deviceId: deviceId,
      );
      DartBridge.registerEnsureServicesReadyHook(_ensureServicesReady);
      await DartBridge.modelPaths.setBaseDirectory();

      await _startLocalServices(params, deviceId);
      _localServicesReady = true;

      // Remote setup (auth, device registration, assignment fetch) retries in
      // the background; local inference does not wait for the network.
      final remote = _dispatchRemoteServices(params, deviceId, logger);
      unawaited(
        remote.catchError((Object _, StackTrace _) {
          logger.warning('Remote service setup failed (non-critical)');
        }),
      );
    } catch (_) {
      logger.error('SDK initialization failed');
      await DartBridge.shutdown();
      _cachedInitParams = null;
      _localServicesReady = false;
      _hasCompletedHttpSetup = false;
      _httpSetupApplicable = true;
      _remoteServicesFuture = null;
      rethrow;
    }
  }

  /// HTTP client, telemetry, and the registry handle — everything a caller
  /// needs before registering models or running local inference.
  static Future<void> _startLocalServices(
    SDKInitParams params,
    String deviceId,
  ) async {
    final effectiveBaseURL =
        DartBridgeState.instance.baseURL ?? params.baseURL.toString();
    HTTPClientAdapter.shared.configure(
      baseURL: effectiveBaseURL,
      apiKey: params.apiKey,
      environment: params.environment,
    );
    DartBridgeTelemetry.initializeSync(environment: params.environment);
    await DartBridgeTelemetry.initialize(
      environment: params.environment,
      deviceId: deviceId,
      baseURL: HTTPClientAdapter.shared.isConfigured
          ? params.baseURL.toString()
          : null,
    );
    await DartBridgeModelRegistry.instance.initialize();
  }

  static Future<void> _dispatchRemoteServices(
    SDKInitParams params,
    String deviceId,
    SDKLogger logger,
  ) {
    final future = _runRemoteServices(params, deviceId, logger);
    _remoteServicesFuture = future;
    unawaited(_clearWhenSettled(future, () => _remoteServicesFuture, () {
      _remoteServicesFuture = null;
    }));
    return future;
  }

  static Future<void> _runRemoteServices(
    SDKInitParams params,
    String deviceId,
    SDKLogger logger,
  ) async {
    final result = await DartBridge.initializeServices(
      apiKey: params.apiKey,
      baseURL: params.baseURL.toString(),
      deviceId: deviceId,
      forceRefreshAssignments: false,
      flushTelemetry: true,
      discoverDownloadedModels: true,
      rescanLocalModels: true,
    );
    _hasCompletedHttpSetup = _isHttpSetupComplete(result);
    _httpSetupApplicable = result?.httpApplicable ?? true;
    logger.info('Remote services ready (${params.environment.description})');
  }

  /// Readiness gate the capability layer reaches through
  /// `DartBridge.ensureServicesReady()`.
  static Future<void> _ensureServicesReady() async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    if (DartBridge.servicesInitialized &&
        (_hasCompletedHttpSetup || !_httpSetupApplicable)) {
      return;
    }
    if (DartBridge.servicesInitialized &&
        !_hasCompletedHttpSetup &&
        _httpSetupApplicable) {
      _retryHttpSetup();
      return;
    }
    final inFlight = _remoteServicesFuture;
    if (inFlight != null) {
      await inFlight;
      return;
    }
    final params = _cachedInitParams;
    if (params == null) {
      throw SDKException.notInitialized();
    }
    await _dispatchRemoteServices(
      params,
      await DartBridgeDevice.instance.getDeviceId(),
      SDKLogger('RunAnywhere.Services'),
    );
  }

  static bool _isHttpSetupComplete(SdkInitResult? result) {
    if (result == null) return false;
    if (result.hasHasCompletedHttpSetup()) {
      return result.hasCompletedHttpSetup;
    }
    return result.httpConfigured;
  }

  static void _retryHttpSetup() {
    final logger = SDKLogger('RunAnywhere.HTTPRetry');
    try {
      final proto = DartBridgeSdkInit.retryHTTP();
      _hasCompletedHttpSetup = _isHttpSetupComplete(proto);
      _httpSetupApplicable = proto.httpApplicable;
    } catch (_) {
      logger.debug('HTTP retry failed');
    }
  }

  static Future<void> _reset() async {
    DartBridgeTelemetry.flush();
    DartBridge.modelLifecycle.reset();
    _localServicesReady = false;
    _hasCompletedHttpSetup = false;
    _httpSetupApplicable = true;
    _cachedInitParams = null;
    _remoteServicesFuture = null;
    DartBridgeModelRegistry.instance.shutdown();
    // Shut the bridge down last so telemetry, registry, and HTTP can flush
    // against a still-initialized native side.
    await DartBridge.shutdown();
  }

  static Future<void> _clearWhenSettled(
    Future<void> operation,
    Future<void>? Function() read,
    void Function() clear,
  ) => operation.then<void>(
    (_) {
      if (identical(read(), operation)) clear();
    },
    onError: (Object _, StackTrace _) {
      if (identical(read(), operation)) clear();
    },
  );
}
