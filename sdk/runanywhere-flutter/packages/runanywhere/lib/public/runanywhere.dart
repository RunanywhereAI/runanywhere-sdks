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

import 'package:fixnum/fixnum.dart' show Int64;

import 'package:runanywhere/adapters/http_client_adapter.dart';
import 'package:runanywhere/foundation/constants/sdk_constants.dart';
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/download_service.pb.dart'
    show DownloadProgress, DownloadState;
import 'package:runanywhere/generated/errors.pbenum.dart'
    show ErrorCategory, ErrorCode;
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
    show InferenceFramework, ModelCategory;
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
import 'package:runanywhere/generated/storage_types.pb.dart'
    show StorageDeleteRequest, StorageDeleteResult;
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
    show TTSOptions, TTSOutput, TTSSpeakResult;
import 'package:runanywhere/generated/voice_events.pb.dart' show VoiceEvent;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_auth.dart';
import 'package:runanywhere/native/dart_bridge_device.dart';
import 'package:runanywhere/native/dart_bridge_environment.dart';
import 'package:runanywhere/native/dart_bridge_events.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart';
import 'package:runanywhere/native/dart_bridge_sdk_init.dart';
import 'package:runanywhere/native/dart_bridge_telemetry.dart';
import 'package:runanywhere/native/type_conversions/model_types_cpp_bridge.dart'
    show ProtoInferenceFrameworkCppBridge;
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
import 'package:runanywhere/public/extensions/runanywhere_storage.dart';
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
  /// `completeServicesInitialization()` (RunAnywhere.swift:255-273):
  /// concurrent callers share the in-flight Future so the step list runs at
  /// most once, and a FAILED Phase 2 is cleared so the next call rebuilds a
  /// fresh one (retry) instead of replaying the stored failure forever.
  /// Throws [SDKException.notInitialized] if Phase 1 never ran.
  static Future<void> completeServicesInitialization() {
    if (!isInitialized) {
      throw SDKException.notInitialized();
    }
    if (areServicesReady) {
      return Future<void>.value();
    }
    final existing = _servicesInitFuture;
    if (existing != null) {
      return existing;
    }
    final params = _cachedInitParams;
    if (params == null) {
      throw SDKException.notInitialized();
    }
    return _dispatchPhase2(params, SDKLogger('RunAnywhere.Services'));
  }

  /// Start (or restart) Phase 2 and store the shared Future. The Future is
  /// cleared on completion — success is then gated by [areServicesReady],
  /// and failure clearing is what makes [completeServicesInitialization]
  /// retryable, mirroring Swift's clear-on-both-paths
  /// (RunAnywhere.swift:267-273).
  static Future<void> _dispatchPhase2(SDKInitParams params, SDKLogger logger) {
    final future = _runPhase2(params, logger);
    _servicesInitFuture = future;
    unawaited(
      future.then<void>(
        (_) {
          if (identical(_servicesInitFuture, future)) {
            _servicesInitFuture = null;
          }
        },
        onError: (Object _, StackTrace _) {
          if (identical(_servicesInitFuture, future)) {
            _servicesInitFuture = null;
          }
        },
      ),
    );
    return future;
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
  // Internal Phase-2 readiness gate. Swift's `ensureServicesReady` is
  // `internal` (RunAnywhere.swift:336); capability files reach it through
  // `DartBridge.ensureServicesReady()` (the registered hook), not this class.
  static Future<void> _ensureServicesReady() async {
    if (!isInitialized) {
      throw SDKException.notInitialized();
    }
    // Fast path — services ready + HTTP/auth done, OR HTTP setup does not
    // apply to this configuration (nothing to retry — avoids re-attempting
    // HTTP on every guarded call when offline). Mirrors Swift's
    // `readiness.http || !readiness.applicable` (RunAnywhere.swift:344).
    if (areServicesReady && (_hasCompletedHTTPSetup || !_httpSetupApplicable)) {
      return;
    }
    // Recovery path — services ready, HTTP/auth failed (offline init) and a
    // retry can actually succeed.
    if (areServicesReady && !_hasCompletedHTTPSetup && _httpSetupApplicable) {
      await _retryHTTPSetup();
      return;
    }
    // Cold start path — Phase 1 done but Phase 2 still running, never
    // dispatched, or cleared after a failure. completeServicesInitialization
    // shares the in-flight Future or rebuilds a fresh one.
    await completeServicesInitialization();
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

  // Latched HTTP/auth completion flag — see [hasCompletedHTTPSetup]. Phase 2
  // sets this from the C++ `SdkInitResult.http_configured` snapshot;
  // [_retryHTTPSetup] re-latches on a successful `rac_sdk_retry_http_proto`
  // round-trip so subsequent `ensureServicesReady()` calls short-circuit.
  static bool _hasCompletedHTTPSetup = false;

  // Whether HTTP setup applies to this configuration at all. Phase 2 latches
  // it from `SdkInitResult.http_applicable` (sdk_init.proto field 11) — false
  // means commons decided there is nothing to retry (e.g. dev mode with no
  // usable credentials), so [_ensureServicesReady] must NOT re-attempt HTTP
  // on every guarded call (that was the offline per-call stall). Mirrors
  // Swift's `httpSetupApplicable` (RunAnywhere.swift:328, :344).
  static bool _httpSetupApplicable = true;

  // Shared Phase-2 future. Mirrors Swift's `_servicesInitTask`. Stored at
  // detach time inside [initializeWithParams]; replayed by
  // [completeServicesInitialization]. Dart's single-threaded event loop
  // makes the check-and-set atomic, so no explicit lock is needed (unlike
  // Swift which uses `_servicesInitLock: DispatchQueue`).
  static Future<void>? _servicesInitFuture;

  /// SDK semver string (e.g. "0.19.13").
  static String get version => SDKConstants.version;

  /// Event bus for cross-capability SDK events.
  static EventBus get events => EventBus.shared;

  // -- Imperative SDK-event surface (Swift RunAnywhere+SDKEvents.swift:17-35).
  //    Dart consumers should prefer [events]; these entry points are retained
  //    for cross-SDK parity (Kotlin's primary event API, documented RN surface).

  /// Subscribe a handler to the canonical native SDK event stream.
  /// Cancel the returned subscription to unsubscribe.
  static StreamSubscription<sdk_events_pb.SDKEvent> subscribeSDKEvents(
    void Function(sdk_events_pb.SDKEvent event) handler,
  ) => DartBridgeEvents.instance.subscribe(handler);

  /// Cancel a subscription returned by [subscribeSDKEvents]. Name parity
  /// with Swift `RunAnywhere.unsubscribeSDKEvents(_:)`.
  static Future<void> unsubscribeSDKEvents(
    StreamSubscription<sdk_events_pb.SDKEvent> subscription,
  ) => subscription.cancel();

  /// Publish an event through the commons router
  /// (`rac_sdk_event_publish_proto`). Returns false when the native
  /// publish path is unavailable.
  static Future<bool> publishSDKEvent(sdk_events_pb.SDKEvent event) =>
      DartBridgeEvents.instance.publish(event);

  /// Poll one queued SDK event (`rac_sdk_event_poll`), or null when the
  /// queue is empty.
  static Future<sdk_events_pb.SDKEvent?> pollSDKEvent() =>
      DartBridgeEvents.instance.poll();

  /// Publish a structured failure event (`rac_sdk_event_publish_failure`).
  static Future<bool> publishSDKFailure({
    required int errorCode,
    required String message,
    required String component,
    required String operation,
    bool recoverable = false,
  }) => DartBridgeEvents.instance.publishFailure(
    errorCode: errorCode,
    message: message,
    component: component,
    operation: operation,
    recoverable: recoverable,
  );

  /// Consume a token stream into one aggregated [LLMGenerationResult].
  ///
  /// Matches Swift `RunAnywhere.aggregateStream(prompt:events:onToken:)`
  /// (RunAnywhere+TextGeneration.swift:129): concatenates `event.token`
  /// text, counts tokens, computes TTFT/throughput from timestamps, and
  /// prefers the backend's terminal aggregate result (text + metrics) when
  /// the final event carries one. The `framework` field resolves from the
  /// loaded LLM model's analytics key so callers stay aligned with the
  /// registry's canonical framework label.
  ///
  /// [onToken] receives the aggregated transcript so far (suitable for
  /// live UI updates) for each non-empty token.
  static Future<LLMGenerationResult> aggregateStream({
    required String prompt,
    required Stream<LLMStreamEvent> events,
    Future<void> Function(String aggregated)? onToken,
  }) async {
    var fullResponse = '';
    var tokenCount = 0;
    DateTime? firstTokenTime;
    final startTime = DateTime.now();
    var finishReason = '';
    var terminalError = '';
    LLMStreamEvent? finalEvent;

    await for (final event in events) {
      if (event.token.isNotEmpty) {
        firstTokenTime ??= DateTime.now();
        fullResponse += event.token;
        tokenCount++;
        if (onToken != null) {
          await onToken(fullResponse);
        }
      }
      if (event.isFinal) {
        finalEvent = event;
        finishReason = event.finishReason;
        terminalError = event.errorMessage;
        break;
      }
    }

    final totalLatencyMs =
        DateTime.now().difference(startTime).inMicroseconds / 1000.0;
    final ttftMs = firstTokenTime == null
        ? null
        : firstTokenTime.difference(startTime).inMicroseconds / 1000.0;

    final snapshot = await RunAnywhereModelLifecycle.shared.current(
      CurrentModelRequest(category: ModelCategory.MODEL_CATEGORY_LANGUAGE),
    );
    final modelId = snapshot.found ? snapshot.modelId : '';
    final framework = snapshot.found
        ? snapshot.model.framework.analyticsKey
        : InferenceFramework.INFERENCE_FRAMEWORK_UNKNOWN.analyticsKey;

    // Prefer the backend's terminal aggregate result when the final event
    // carries one, matching Swift/Web; otherwise fall back to the locally
    // concatenated text / wall-clock metrics.
    final finalResult = (finalEvent != null && finalEvent.hasResult())
        ? finalEvent.result
        : null;
    final inputTokens =
        finalResult?.promptTokens ??
        (prompt.length ~/ 4 > 0 ? prompt.length ~/ 4 : 1);
    final completionTokens = finalResult?.completionTokens ?? tokenCount;
    final result = LLMGenerationResult(
      text: finalResult?.text ?? fullResponse,
      inputTokens: inputTokens,
      tokensGenerated: completionTokens,
      responseTokens: completionTokens,
      totalTokens: finalResult?.totalTokens ?? (inputTokens + completionTokens),
      modelUsed: modelId,
      generationTimeMs: finalResult?.totalTimeMs.toDouble() ?? totalLatencyMs,
      framework: framework,
      promptEvalTimeMs: finalResult?.promptEvalTimeMs ?? Int64.ZERO,
      decodeTimeMs: finalResult?.decodeTimeMs ?? Int64.ZERO,
      tokensPerSecond:
          finalResult?.tokensPerSecond ??
          (totalLatencyMs > 0 ? tokenCount / (totalLatencyMs / 1000.0) : 0),
    );
    if (finalResult != null && finalResult.hasThinkingContent()) {
      result.thinkingContent = finalResult.thinkingContent;
    }
    final ttft = finalResult?.timeToFirstTokenMs.toDouble() ?? ttftMs;
    if (ttft != null) {
      result.ttftMs = ttft;
    }
    if (finishReason.isNotEmpty) result.finishReason = finishReason;
    if (terminalError.isNotEmpty) result.errorMessage = terminalError;
    return result;
  }

  /// Initialize the SDK with API key + base URL.
  static Future<void> initialize({
    String? apiKey,
    String? baseURL,
    SDKEnvironment environment = SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
  }) async {
    final SDKInitParams params;

    if (environment == SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT) {
      // Development mode ignores any caller-supplied baseURL and always uses
      // the dev placeholder / Supabase-derived URL. Mirrors Swift
      // RunAnywhere.swift:125-127 (`SDKInitParams(forDevelopmentWithAPIKey:)`).
      params = SDKInitParams.forDevelopment(apiKey: apiKey ?? '');
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
      DartBridge.registerEnsureServicesReadyHook(_ensureServicesReady);

      // Configure the C++ model-paths base directory as part of Phase 1 —
      // BEFORE initialize() returns and any registerModel() call runs — so
      // rac_model_registry_save() can reconcile entries against on-disk
      // folders inline. Mirrors Swift RunAnywhere.swift:186-195 (which sets
      // it before the Phase-1 proto); deferring this to detached Phase 2
      // raced app-side registerModel() calls against an unset base dir.
      await DartBridge.modelPaths.setBaseDirectory();

      logger.info(
        'Phase 1 complete (${params.environment.description}); '
        'Phase 2 dispatched in background',
      );

      // --- Phase 2: Detached background services ---
      // Mirrors Swift `Task.detached(priority: .userInitiated) { ... }`.
      // _dispatchPhase2 stores the Future first so concurrent callers of
      // `completeServicesInitialization()` see it before the detach
      // wrapper might observe a failure, and clears it on failure so the
      // next call retries. Phase 2 errors are swallowed here
      // (non-critical) but still observable to direct awaiters.
      final phase2 = _dispatchPhase2(params, logger);
      unawaited(
        phase2.catchError((Object error, StackTrace _) {
          logger.warning('Phase 2 failed (non-critical): $error');
        }),
      );
    } catch (e) {
      logger.error('SDK initialization failed: $e');
      _cachedInitParams = null;
      _hasCompletedHTTPSetup = false;
      _httpSetupApplicable = true;
      _servicesInitFuture = null;
      // Commons auto-emits INITIALIZATION_STAGE_FAILED from
      // rac_sdk_init_phase1_proto (sdk_init.cpp); failure telemetry flows
      // through structured errors. Dart does not re-emit a duplicate.
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

    // Step 2 (moved to Phase 1): the model-paths base directory is now set
    // inside [initializeWithParams] before it returns — see the Swift
    // ordering rationale there. Commons Phase 2 downloaded-model discovery
    // still observes the configured root.

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

    // Commons auto-emits the INITIALIZATION_STAGE_COMPLETED SDKEvent (with a
    // duration_ms property) from rac_sdk_init_phase1_proto and the destination
    // router forwards it to the registered telemetry sink, so Dart does not
    // emit it.

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
    _httpSetupApplicable = phase2Result?.httpApplicable ?? true;

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
      _httpSetupApplicable = proto.httpApplicable;
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
    _hasCompletedHTTPSetup = false;
    _httpSetupApplicable = true;
    _cachedInitParams = null;
    _servicesInitFuture = null;
    DartBridgeModelRegistry.instance.shutdown();
    HTTPClientAdapter.shared.resetForTesting();
    // Tear down the bridge LAST so dependents (telemetry/registry/HTTP)
    // can flush against a still-initialized native side, and AWAIT it so a
    // `reset(); initialize()` sequence cannot race the still-true
    // `_isInitialized` short-circuit. Mirrors Swift's
    // `await CppBridge.shutdown()` (RunAnywhere.swift:109).
    await DartBridge.shutdown();
  }

  // --- Capability surfaces -------------------------------------------------
  //
  // The flat `RunAnywhere.*` static methods are the canonical surface — they
  // mirror the Swift SDK (the cross-SDK source of truth) one-to-one. The
  // capability objects below are ergonomic accessors over the same
  // implementations; prefer the flat methods when porting code between SDKs.

  /// LLM (text generation) — load, chat, generate, generate-stream, cancel.
  static RunAnywhereLLM get llm => RunAnywhereLLM.shared;

  /// STT (speech-to-text) — load, transcribe.
  static RunAnywhereSTT get stt => RunAnywhereSTT.shared;

  /// TTS (text-to-speech) — load voice, synthesize, speak.
  static RunAnywhereTTS get tts => RunAnywhereTTS.shared;

  /// VAD (voice activity detection) — detectVoiceActivity, streamVAD,
  /// reset, load model. Mirrors Swift's `RunAnywhere+VAD.swift` extension.
  static RunAnywhereVAD get vad => RunAnywhereVAD.shared;

  /// VLM (vision-language model) — load, processImage, processImageStream.
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

  /// Flat alias — transcribe audio to proto [STTOutput].
  /// Mirrors Swift / RN / Web `RunAnywhere.transcribe(audio:options:)`.
  static Future<STTOutput> transcribe(Uint8List audio, [STTOptions? options]) =>
      RunAnywhereSTT.shared.transcribe(audio, options);

  /// Flat chunk-feed streaming — session-based stream-in / stream-out
  /// transcription; the native session owns endpointing. Mirrors Swift
  /// `RunAnywhere.transcribeStream(audio: AsyncStream<Data>)`
  /// (RunAnywhere+STT.swift:50).
  static Stream<STTPartialResult> transcribeStream(
    Stream<Uint8List> audio, {
    STTOptions? options,
  }) => RunAnywhereSTT.shared.transcribeStream(audio, options: options);

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

  /// Flat storage delete request. Mirrors Swift `RunAnywhere.deleteStorage`.
  static Future<StorageDeleteResult> deleteStorage(
    StorageDeleteRequest request,
  ) => RunAnywhereStorage.deleteStorage(request);

  /// Flat temp cleanup helper. Mirrors Swift `RunAnywhere.cleanTempFiles`.
  static Future<void> cleanTempFiles() => RunAnywhereStorage.cleanTempFiles();

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

    // Mirror Swift `reportDownloadProgress`: terminal FAILED / CANCELLED
    // states throw structured SDKExceptions instead of returning the
    // failure progress to the caller.
    final terminal = last;
    if (terminal == null) {
      throw SDKException.make(
        code: ErrorCode.ERROR_CODE_DOWNLOAD_FAILED,
        message: 'No progress events received for model: $modelId',
        category: ErrorCategory.ERROR_CATEGORY_NETWORK,
      );
    }
    switch (terminal.state) {
      case DownloadState.DOWNLOAD_STATE_FAILED:
        throw SDKException.make(
          code: ErrorCode.ERROR_CODE_DOWNLOAD_FAILED,
          message: terminal.errorMessage.isEmpty
              ? 'Download failed'
              : terminal.errorMessage,
          category: ErrorCategory.ERROR_CATEGORY_NETWORK,
        );
      case DownloadState.DOWNLOAD_STATE_CANCELLED:
        throw SDKException.make(
          code: ErrorCode.ERROR_CODE_CANCELLED,
          message: 'Download cancelled',
          category: ErrorCategory.ERROR_CATEGORY_NETWORK,
        );
      default:
        return terminal;
    }
  }

  /// Flat streaming voice agent events.
  /// Mirrors Swift `RunAnywhere.streamVoiceAgent()`.
  static Stream<VoiceEvent> streamVoiceAgent() =>
      RunAnywhereVoice.shared.eventStream();
}
