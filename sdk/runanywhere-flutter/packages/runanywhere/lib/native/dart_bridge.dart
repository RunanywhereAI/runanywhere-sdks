// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:ffi';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/public/configuration/sdk_environment.dart';
import '../foundation/configuration/sdk_constants.dart';
import '../foundation/logging/sdk_logger.dart';
import 'dart_bridge_auth.dart' hide RacSdkConfigStruct;
import 'dart_bridge_device.dart';
import 'dart_bridge_environment.dart' show RacSdkConfigStruct;
import 'dart_bridge_download.dart';
import 'dart_bridge_events.dart';
import 'dart_bridge_http.dart';
import 'dart_bridge_llm.dart';
import 'dart_bridge_model_assignment.dart';
import 'dart_bridge_model_paths.dart';
import 'dart_bridge_model_registry.dart';
import 'dart_bridge_platform.dart';
import 'dart_bridge_platform_services.dart';
import 'dart_bridge_state.dart';
import 'dart_bridge_storage.dart';
import 'dart_bridge_stt.dart';
import 'dart_bridge_telemetry.dart';
import 'dart_bridge_tts.dart';
import 'dart_bridge_vad.dart';
import 'dart_bridge_voice_agent.dart';
import 'platform_loader.dart';

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
/// DartBridge.initialize(SDKEnvironment.production);
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

  static SDKEnvironment _environment = SDKEnvironment.development;
  static bool _isInitialized = false;
  static bool _servicesInitialized = false;
  static DynamicLibrary? _lib;

  /// Current environment
  static SDKEnvironment get environment => _environment;

  /// Whether Phase 1 (core) initialization is complete
  static bool get isInitialized => _isInitialized;

  /// Whether Phase 2 (services) initialization is complete
  static bool get servicesInitialized => _servicesInitialized;

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
  /// 4. Initialize SDK config (rac_sdk_init) - sets platform, version
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

    // Step 4: Initialize SDK with configuration
    // Matches Swift: rac_sdk_init(&sdkConfig) in CppBridge.State.initialize()
    // This is CRITICAL - the LlamaCPP backend needs this to be set
    _initializeSdkConfig(environment);
    _logger.debug('SDK config initialized');

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

    // Step 2: Initialize C++ state with credentials
    // Matches Swift: CppBridge.State.initialize(environment:apiKey:baseURL:deviceId:)
    await DartBridgeState.instance.initialize(
      environment: _environment,
      apiKey: apiKey,
      baseURL: baseURL,
      deviceId: effectiveDeviceId,
    );
    _logger.debug('C++ state initialized');

    // Step 3: Initialize service bridges
    // Matches Swift: CppBridge.initializeServices()

    // Step 3a: Model assignment callbacks
    await DartBridgeModelAssignment.register(environment: _environment);
    _logger.debug('Model assignment callbacks registered');

    // Step 3b: Platform services (Foundation Models, System TTS)
    await DartBridgePlatformServices.register();
    _logger.debug('Platform services registered');

    // Step 4: Flush telemetry (if any queued events)
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
  static void shutdown() {
    if (!_isInitialized) {
      _logger.debug('Not initialized, nothing to shutdown');
      return;
    }

    _logger.debug('Shutting down DartBridge');

    // Shutdown in reverse order of initialization
    DartBridgeTelemetry.shutdown();
    DartBridgeEvents.unregister();

    _isInitialized = false;
    _servicesInitialized = false;

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

  /// Platform bridge
  static DartBridgePlatform get platform => DartBridgePlatform.instance;

  /// Platform services bridge
  static DartBridgePlatformServices get platformServices =>
      DartBridgePlatformServices.instance;

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

  /// Voice agent bridge
  static DartBridgeVoiceAgent get voiceAgent => DartBridgeVoiceAgent.shared;

  // -------------------------------------------------------------------------
  // Private Helpers
  // -------------------------------------------------------------------------

  /// Configure C++ logging based on environment
  static void _configureLogging(SDKEnvironment environment) {
    int logLevel;
    switch (environment) {
      case SDKEnvironment.development:
        logLevel = RacLogLevel.debug;
        break;
      case SDKEnvironment.staging:
        logLevel = RacLogLevel.info;
        break;
      case SDKEnvironment.production:
        logLevel = RacLogLevel.warning;
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

  /// Initialize SDK configuration in C++ (matches Swift's rac_sdk_init call)
  /// This is critical for the LlamaCPP backend to function correctly.
  static void _initializeSdkConfig(SDKEnvironment environment) {
    try {
      final sdkInit = lib.lookupFunction<
          Int32 Function(Pointer<RacSdkConfigStruct>),
          int Function(Pointer<RacSdkConfigStruct>)>('rac_sdk_init');

      final config = calloc<RacSdkConfigStruct>();
      final platformPtr = 'flutter'.toNativeUtf8();
      final sdkVersionPtr = SDKConstants.version.toNativeUtf8();

      try {
        config.ref.environment = _environmentToInt(environment);
        config.ref.apiKey = nullptr; // Set later if available
        config.ref.baseURL = nullptr; // Set later if available
        config.ref.deviceId = nullptr; // Set later if available
        config.ref.platform = platformPtr;
        config.ref.sdkVersion = sdkVersionPtr;

        final result = sdkInit(config);
        if (result != 0) {
          _logger.warning('rac_sdk_init returned: $result');
        }
      } finally {
        calloc.free(platformPtr);
        calloc.free(sdkVersionPtr);
        calloc.free(config);
      }
    } catch (e) {
      _logger.debug('rac_sdk_init not available: $e');
    }
  }

  /// Convert environment to C int value
  static int _environmentToInt(SDKEnvironment env) {
    switch (env) {
      case SDKEnvironment.development:
        return 0;
      case SDKEnvironment.staging:
        return 1;
      case SDKEnvironment.production:
        return 2;
    }
  }
}

/// Log level constants matching rac_log_level_t
abstract class RacLogLevel {
  static const int error = 0;
  static const int warning = 1;
  static const int info = 2;
  static const int debug = 3;
  static const int trace = 4;
}
