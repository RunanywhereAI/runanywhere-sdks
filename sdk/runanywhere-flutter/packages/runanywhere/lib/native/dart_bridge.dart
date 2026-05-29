// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:ffi';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/sdk_init.pb.dart';
import 'package:runanywhere/native/dart_bridge_auth.dart';
import 'package:runanywhere/native/dart_bridge_device.dart';
import 'package:runanywhere/native/dart_bridge_download.dart';
import 'package:runanywhere/native/dart_bridge_embeddings.dart';
import 'package:runanywhere/native/dart_bridge_events.dart';
import 'package:runanywhere/native/dart_bridge_file_manager.dart';
import 'package:runanywhere/native/dart_bridge_http.dart';
import 'package:runanywhere/native/dart_bridge_llm.dart';
import 'package:runanywhere/native/dart_bridge_lora.dart';
import 'package:runanywhere/native/dart_bridge_model_assignment.dart';
import 'package:runanywhere/native/dart_bridge_model_lifecycle.dart';
import 'package:runanywhere/native/dart_bridge_model_paths.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart';
import 'package:runanywhere/native/dart_bridge_platform.dart';
import 'package:runanywhere/native/dart_bridge_rag.dart';
import 'package:runanywhere/native/dart_bridge_sdk_init.dart';
import 'package:runanywhere/native/dart_bridge_state.dart';
import 'package:runanywhere/native/dart_bridge_storage.dart';
import 'package:runanywhere/native/dart_bridge_stt.dart';
import 'package:runanywhere/native/dart_bridge_telemetry.dart';
import 'package:runanywhere/native/dart_bridge_tts.dart';
import 'package:runanywhere/native/dart_bridge_vad.dart';
import 'package:runanywhere/native/dart_bridge_vlm.dart';
import 'package:runanywhere/native/dart_bridge_voice_agent.dart';
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/native/types/basic_types.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';

/// Central coordinator for all C++ bridges.
///
/// Matches Swift's `CppBridge` pattern exactly:
/// - 2-phase initialization (core sync + services async)
/// - Platform adapter registration (file ops, logging, keychain)
/// - Event callback registration
/// - Module registration coordination
///
/// Usage:
/// ```dart
/// // Phase 1: Core init (sync, ~1-5ms)
/// DartBridge.initialize(SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION);
///
/// // Phase 2: Services init (async, ~100-500ms)
/// await DartBridge.initializeServices();
/// ```
class DartBridge {
  DartBridge._();

  static final _logger = SDKLogger('DartBridge');

  // -------------------------------------------------------------------------
  // State
  // -------------------------------------------------------------------------

  static SDKEnvironment _environment =
      SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
  static bool _isInitialized = false;
  static bool _servicesInitialized = false;
  static DynamicLibrary? _lib;

  // Wired by RunAnywhere.initializeWithParams so capability files can call
  // ensureServicesReady() without importing runanywhere.dart (which imports
  // all capability files — a circular dependency). Null before Phase 1.
  static Future<void> Function()? _ensureServicesReadyHook;

  /// Current environment
  static SDKEnvironment get environment => _environment;

  /// Whether Phase 1 (core) initialization is complete
  static bool get isInitialized => _isInitialized;

  /// Whether Phase 2 (services) initialization is complete
  static bool get servicesInitialized => _servicesInitialized;

  /// Register the Phase-2 readiness hook. Called once by
  /// RunAnywhere.initializeWithParams so capability files can invoke
  /// [ensureServicesReady] without importing runanywhere.dart.
  static void registerEnsureServicesReadyHook(
    Future<void> Function() hook,
  ) {
    _ensureServicesReadyHook = hook;
  }

  /// Await Phase-2 completion before any work that requires services (HTTP,
  /// auth, model-assignment, model-discovery). Mirrors Swift's
  /// `try? await ensureServicesReady()` guard in RunAnywhere+ModelLifecycle.swift
  /// and RunAnywhere+Storage.swift. If Phase 1 has not run, throws
  /// [SDKException.notInitialized]; if the hook is not yet wired (very early
  /// call before initializeWithParams), returns immediately.
  static Future<void> ensureServicesReady() {
    if (!_isInitialized) {
      throw StateError('SDK not initialized');
    }
    final hook = _ensureServicesReadyHook;
    if (hook == null) return Future<void>.value();
    return hook();
  }

  /// Native library reference
  static DynamicLibrary get lib {
    _lib ??= PlatformLoader.load();
    return _lib!;
  }

  // -------------------------------------------------------------------------
  // Phase 1: Core Initialization (Sync)
  // -------------------------------------------------------------------------

  /// Initialize the core bridge layer.
  ///
  /// This is Phase 1 of 2-phase initialization (matches Swift CppBridge.initialize exactly):
  /// 1. Load native library
  /// 2. Register platform adapter FIRST (file ops, logging, keychain)
  /// 3. Configure C++ logging level (rac_configure_logging)
  /// 4. Drive Phase 1 of SDK init through `rac_sdk_init_phase1_proto`
  ///    (validates inputs + runs `rac_state_initialize` inside commons)
  /// 5. Register events callback (analytics routing)
  /// 6. Initialize telemetry manager
  /// 7. Register device callbacks
  ///
  /// Call this FIRST during SDK init. Must complete before Phase 2.
  ///
  /// [environment] The SDK environment (development/staging/production)
  static void initialize(SDKEnvironment environment) {
    if (_isInitialized) {
      _logger.debug('Already initialized, skipping');
      return;
    }

    _environment = environment;
    _logger.debug('Starting Phase 1 initialization', metadata: {
      'environment': environment.name,
    });

    // Step 1: Load native library
    _lib = PlatformLoader.load();
    _logger.debug('Native library loaded');

    // Step 2: Register platform adapter FIRST (file ops, logging, keychain)
    // C++ needs these callbacks before any other operations
    // Matches Swift: PlatformAdapter.register()
    DartBridgePlatform.register();
    _logger.debug('Platform adapter registered');

    // Step 3: Configure C++ logging level
    // Matches Swift: rac_configure_logging(environment.cEnvironment)
    _configureLogging(environment);
    _logger.debug('C++ logging configured');

    // Step 4: Initialize SDK with configuration (Phase 1 proto-based path)
    // Matches Swift: CppBridge.SdkInit.phase1(...) in
    // sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/Extensions/CppBridge+SdkInit.swift
    // Routes through rac_sdk_init_phase1_proto in commons; supersedes the
    // legacy struct-based rac_sdk_init entry point.
    try {
      DartBridgeSdkInit.phase1(SdkInitPhase1Request(
        environment: _toSdkInitEnvironment(environment),
        // apiKey/baseUrl/deviceId are wired in Phase 2 once they're resolved
        // (Keychain lookup + caller params). Phase 1 only sets the runtime
        // environment + platform/version metadata that commons can derive
        // internally.
      ));
      _logger.debug('SDK Phase 1 (proto) initialized');
    } catch (e) {
      _logger.error('SDK Phase 1 proto init failed: $e');
      rethrow;
    }

    // Step 5: Register events callback (analytics routing)
    // Matches Swift: Events.register()
    DartBridgeEvents.register();
    _logger.debug('Events callback registered');

    // Step 6: Initialize telemetry manager (sync part)
    // Matches Swift: Telemetry.initialize(environment: environment)
    // Note: Full telemetry init with HTTP is in Phase 2
    DartBridgeTelemetry.initializeSync(environment: environment);
    _logger.debug('Telemetry initialized (sync)');

    // Step 7: Register device callbacks
    // Matches Swift: Device.register()
    DartBridgeDevice.registerCallbacks();
    _logger.debug('Device callbacks registered');

    // Step 8: Register file manager I/O callbacks
    DartBridgeFileManager.register();
    _logger.debug('File manager callbacks registered');

    // Step 9: Wire global model registry before any registerModel() calls.
    // Swift's CppBridge.ModelRegistry.shared resolves rac_get_model_registry()
    // lazily; Flutter apps register catalog models immediately after
    // initialize() returns (Phase 1 only).
    DartBridgeModelRegistry.instance.ensureInitialized();
    _logger.debug('Model registry handle wired (Phase 1)');

    _isInitialized = true;
    _logger.info('Phase 1 initialization complete');
  }

  // -------------------------------------------------------------------------
  // Phase 2: Services Initialization (Async)
  // -------------------------------------------------------------------------

  /// Initialize service bridges.
  ///
  /// This is Phase 2 of 2-phase initialization (matches Swift completeServicesInitialization):
  /// 1. Setup HTTP transport (if needed)
  /// 2. Initialize C++ state (rac_state_initialize with apiKey, baseURL, deviceId)
  /// 3. Initialize service bridges (ModelAssignment, Platform)
  /// 4. Model paths base directory (done in RunAnywhere.initializeWithParams)
  /// 5. Device registration (if needed)
  /// 6. Flush telemetry
  ///
  /// Call this AFTER Phase 1. Can be called in background.
  ///
  /// [apiKey] API key for production/staging
  /// [baseURL] Backend URL for production/staging
  /// [deviceId] Device identifier
  static Future<void> initializeServices({
    String? apiKey,
    String? baseURL,
    String? deviceId,
  }) async {
    if (!_isInitialized) {
      throw StateError('Must call initialize() before initializeServices()');
    }

    if (_servicesInitialized) {
      _logger.debug('Services already initialized, skipping');
      return;
    }

    _logger.debug('Starting Phase 2 services initialization');

    // Step 1: Get device ID if not provided
    final effectiveDeviceId =
        deviceId ?? DartBridgeDevice.cachedDeviceId ?? 'unknown-device';

    // Step 2: HTTP transport — configure C++ HTTP layer BEFORE phase2 so that
    // rac_sdk_init_phase2_proto's device-registration POST has a live transport.
    // Mirrors Swift Step 1 in _performServicesInitialization(): setupHTTP runs
    // before CppBridge.SdkInit.phase2() (RunAnywhere.swift:266-279 → :287).
    if (!DartBridgeHTTP.instance.isConfigured) {
      try {
        await DartBridgeHTTP.instance.configure(
          environment: _environment,
          apiKey: apiKey,
          baseURL: baseURL,
        );
        _logger.debug('HTTP transport configured');
      } catch (e) {
        _logger.warning('HTTP setup failed (offline?): $e');
      }
    }

    // Step 3: Initialize C++ state with credentials
    // Matches Swift: CppBridge.State.initialize(environment:apiKey:baseURL:deviceId:)
    await DartBridgeState.instance.initialize(
      environment: _environment,
      apiKey: apiKey,
      baseURL: baseURL,
      deviceId: effectiveDeviceId,
    );
    _logger.debug('C++ state initialized');

    // Step 4: Drive the canonical Phase 2 step-list inside commons. HTTP is
    // now configured so device-registration completes in a single round-trip.
    // Matches Swift Step 3: CppBridge.SdkInit.phase2() (RunAnywhere.swift:287).
    // Soft failures (offline mode, missing creds) come back as
    // success=true + warning; hard failures throw.
    try {
      final result = DartBridgeSdkInit.phase2(SdkInitPhase2Request());
      _logger.debug('SDK Phase 2 (proto) complete', metadata: {
        'httpConfigured': result.httpConfigured,
        'deviceRegistered': result.deviceRegistered,
        'linkedModelsCount': result.linkedModelsCount,
        'durationMs': result.durationMs.toInt(),
        if (result.hasWarning()) 'warning': result.warning,
      });
    } catch (e) {
      // Non-fatal: services init may still succeed via the per-bridge
      // registrations below even when the C++ step-list reports an error.
      _logger.warning('SDK Phase 2 proto error: $e');
    }

    // Step 5: Initialize service bridges
    // Matches Swift: CppBridge.initializeServices()

    // Step 5a: Model assignment callbacks
    // Only auto-fetch in staging/production, not development
    final shouldAutoFetch =
        _environment != SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
    await DartBridgeModelAssignment.register(
      environment: _environment,
      autoFetch: shouldAutoFetch,
    );
    _logger.debug(
        'Model assignment callbacks registered (autoFetch: $shouldAutoFetch)');

    // Step 5b: Platform services (Foundation Models, System TTS)
    await DartBridgePlatform.registerServices();
    _logger.debug('Platform services registered');

    // Step 6: Flush telemetry (if any queued events)
    // Matches Swift: CppBridge.Telemetry.flush()
    DartBridgeTelemetry.flush();
    _logger.debug('Telemetry flushed');

    _servicesInitialized = true;
    _logger.info('Phase 2 services initialization complete');
  }

  // -------------------------------------------------------------------------
  // Shutdown
  // -------------------------------------------------------------------------

  /// Shutdown all bridges and release resources.
  ///
  /// Async because per-modality component destroy() paths must complete
  /// before Telemetry/Events teardown so commons-side handles created via
  /// the lifecycle ABIs (and legacy `getHandle()`-based paths like
  /// TTS `listVoicesProto`, `synthesizeProto`, `synthesizeStreamProto`)
  /// do not leak across `RunAnywhere.reset()` -> `initialize()` cycles.
  ///
  /// Mirrors Swift `CppBridge.shutdown()`
  /// (`sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/Bridge/CppBridge.swift:176`):
  /// destroys AI components (LLM -> STT -> TTS -> VAD -> VoiceAgent -> VLM)
  /// sequentially BEFORE Telemetry + Events teardown.
  static Future<void> shutdown() async {
    if (!_isInitialized) {
      _logger.debug('Not initialized, nothing to shutdown');
      return;
    }

    _logger.debug('Shutting down DartBridge');

    // Destroy per-modality component handles FIRST so commons-side state
    // is released while Telemetry/Events are still wired (mirrors Swift's
    // CppBridge.shutdown() order at CppBridge.swift:181-186). Each destroy()
    // is best-effort and swallows its own errors internally.
    DartBridgeLLM.shared.destroy();
    DartBridgeSTT.shared.destroy();
    DartBridgeTTS.shared.destroy();
    DartBridgeVAD.shared.destroy();
    DartBridgeVoiceAgent.shared.destroy();
    DartBridgeVLM.shared.destroy();

    // Shutdown in reverse order of initialization
    DartBridgeTelemetry.shutdown();
    DartBridgeEvents.unregister();

    _isInitialized = false;
    _servicesInitialized = false;
    _ensureServicesReadyHook = null;

    _logger.info('DartBridge shutdown complete');
  }

  // -------------------------------------------------------------------------
  // Bridge Extensions (static accessors matching Swift pattern)
  // -------------------------------------------------------------------------

  /// Authentication bridge
  static DartBridgeAuth get auth => DartBridgeAuth.instance;

  /// Device bridge
  static DartBridgeDevice get device => DartBridgeDevice.instance;

  /// Download bridge
  static DartBridgeDownload get download => DartBridgeDownload.instance;

  /// Events bridge
  static DartBridgeEvents get events => DartBridgeEvents.instance;

  /// HTTP bridge
  static DartBridgeHTTP get http => DartBridgeHTTP.instance;

  /// Embeddings bridge
  static DartBridgeEmbeddings get embeddings => DartBridgeEmbeddings.shared;

  /// LLM bridge
  static DartBridgeLLM get llm => DartBridgeLLM.shared;

  /// Model assignment bridge
  static DartBridgeModelAssignment get modelAssignment =>
      DartBridgeModelAssignment.instance;

  /// Model paths bridge
  static DartBridgeModelPaths get modelPaths => DartBridgeModelPaths.instance;

  /// Model registry bridge
  static DartBridgeModelRegistry get modelRegistry =>
      DartBridgeModelRegistry.instance;

  /// Model lifecycle bridge
  static DartBridgeModelLifecycle get modelLifecycle =>
      DartBridgeModelLifecycle.instance;

  /// Platform bridge (also exposes Foundation Models / System TTS/STT
  /// availability callbacks via `DartBridgePlatform.registerServices()`).
  static DartBridgePlatform get platform => DartBridgePlatform.instance;

  /// State bridge
  static DartBridgeState get state => DartBridgeState.instance;

  /// Storage bridge
  static DartBridgeStorage get storage => DartBridgeStorage.instance;

  /// STT bridge
  static DartBridgeSTT get stt => DartBridgeSTT.shared;

  /// Telemetry bridge
  static DartBridgeTelemetry get telemetry => DartBridgeTelemetry.instance;

  /// TTS bridge
  static DartBridgeTTS get tts => DartBridgeTTS.shared;

  /// VAD bridge
  static DartBridgeVAD get vad => DartBridgeVAD.shared;

  /// VLM bridge
  static DartBridgeVLM get vlm => DartBridgeVLM.shared;

  /// Voice agent bridge
  static DartBridgeVoiceAgent get voiceAgent => DartBridgeVoiceAgent.shared;

  /// RAG pipeline bridge
  static DartBridgeRAG get rag => DartBridgeRAG.shared;

  /// LoRA adapter bridge
  static DartBridgeLora get lora => DartBridgeLora.shared;

  /// LoRA registry bridge
  static DartBridgeLoraRegistry get loraRegistry =>
      DartBridgeLoraRegistry.shared;

  // -------------------------------------------------------------------------
  // Private Helpers
  // -------------------------------------------------------------------------

  /// Configure C++ logging based on environment.
  ///
  /// Uses canonical `RacLogLevel` values from `basic_types.dart` matching
  /// `rac_log_level_t` in commons (`include/rac/core/rac_types.h`):
  /// `trace=0, debug=1, info=2, warning=3, error=4, fatal=5`.
  static void _configureLogging(SDKEnvironment environment) {
    int logLevel;
    switch (environment) {
      case SDKEnvironment.SDK_ENVIRONMENT_STAGING:
        logLevel = RacLogLevel.info;
        break;
      case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
        logLevel = RacLogLevel.warning;
        break;
      case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
      default:
        logLevel = RacLogLevel.debug;
        break;
    }

    try {
      final configureLogging =
          lib.lookupFunction<Void Function(Int32), void Function(int)>(
              'rac_configure_logging');
      configureLogging(logLevel);
    } catch (e) {
      _logger.warning('Failed to configure C++ logging: $e');
    }
  }

  /// Map the public Dart [SDKEnvironment] to the proto-generated
  /// [SdkInitEnvironment] consumed by `rac_sdk_init_phase1_proto`. Mirrors
  /// Swift's `CppBridge.SdkInit.mapEnvironment`.
  static SdkInitEnvironment _toSdkInitEnvironment(SDKEnvironment env) {
    switch (env) {
      case SDKEnvironment.SDK_ENVIRONMENT_STAGING:
        return SdkInitEnvironment.SDK_INIT_ENVIRONMENT_STAGING;
      case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
        return SdkInitEnvironment.SDK_INIT_ENVIRONMENT_PRODUCTION;
      case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
      default:
        return SdkInitEnvironment.SDK_INIT_ENVIRONMENT_DEVELOPMENT;
    }
  }
}
