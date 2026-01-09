// ignore_for_file: avoid_classes_with_only_static_members

import 'dart:async';
import 'dart:ffi';

import 'package:runanywhere/public/configuration/sdk_environment.dart';
import '../foundation/logging/sdk_logger.dart';
import 'dart_bridge_auth.dart';
import 'dart_bridge_device.dart';
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
  /// This is Phase 1 of 2-phase initialization (matches Swift exactly):
  /// 1. Load native library
  /// 2. Register platform adapter (file ops, logging, keychain)
  /// 3. Configure C++ logging
  /// 4. Register events callback
  /// 5. Initialize telemetry manager
  /// 6. Register device callbacks
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
    DartBridgePlatform.register();
    _logger.debug('Platform adapter registered');

    // Step 3: Configure C++ logging level
    _configureLogging(environment);
    _logger.debug('C++ logging configured');

    // Step 4: Register events callback (analytics routing)
    DartBridgeEvents.register();
    _logger.debug('Events callback registered');

    // Step 5 & 6: Async initialization (deferred to initializeServices)
    // These require async operations so we defer them to phase 2

    _isInitialized = true;
    _logger.info('Phase 1 initialization complete');
  }

  // -------------------------------------------------------------------------
  // Phase 2: Services Initialization (Async)
  // -------------------------------------------------------------------------

  /// Initialize service bridges.
  ///
  /// This is Phase 2 of 2-phase initialization:
  /// 1. Register model assignment callbacks
  /// 2. Register platform services (Foundation Models, System TTS)
  ///
  /// Call this AFTER Phase 1. Can be called in background.
  static Future<void> initializeServices() async {
    if (!_isInitialized) {
      throw StateError('Must call initialize() before initializeServices()');
    }

    if (_servicesInitialized) {
      _logger.debug('Services already initialized, skipping');
      return;
    }

    _logger.debug('Starting Phase 2 services initialization');

    // Step 1: Register device callbacks (this also caches device ID)
    await DartBridgeDevice.register(environment: _environment);
    _logger.debug('Device callbacks registered');

    // Step 2: Initialize telemetry manager with device ID
    final deviceId = DartBridgeDevice.cachedDeviceId ?? 'unknown-device';
    await DartBridgeTelemetry.initialize(
      environment: _environment,
      deviceId: deviceId,
    );
    _logger.debug('Telemetry manager initialized');

    // Step 3: Model assignment callbacks
    await DartBridgeModelAssignment.register(environment: _environment);
    _logger.debug('Model assignment callbacks registered');

    // Step 4: Platform services (Foundation Models, System TTS)
    await DartBridgePlatformServices.register();
    _logger.debug('Platform services registered');

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
  static DartBridgeLLM get llm => DartBridgeLLM.instance;

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
  static DartBridgeSTT get stt => DartBridgeSTT.instance;

  /// Telemetry bridge
  static DartBridgeTelemetry get telemetry => DartBridgeTelemetry.instance;

  /// TTS bridge
  static DartBridgeTTS get tts => DartBridgeTTS.instance;

  /// VAD bridge
  static DartBridgeVAD get vad => DartBridgeVAD.instance;

  /// Voice agent bridge
  static DartBridgeVoiceAgent get voiceAgent => DartBridgeVoiceAgent.instance;

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
}

/// Log level constants matching rac_log_level_t
abstract class RacLogLevel {
  static const int error = 0;
  static const int warning = 1;
  static const int info = 2;
  static const int debug = 3;
  static const int trace = 4;
}
