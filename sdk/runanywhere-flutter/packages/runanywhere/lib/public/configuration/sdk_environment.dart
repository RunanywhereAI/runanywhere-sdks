import 'package:runanywhere/core/native/rac_native.dart' show RacNative;
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/model_types.pbenum.dart'
    show SDKEnvironment;
import 'package:runanywhere/native/dart_bridge_environment.dart';

export 'package:runanywhere/generated/model_types.pbenum.dart'
    show SDKEnvironment;

extension SDKEnvironmentExtension on SDKEnvironment {
  /// C `rac_environment_t` value (RAC_ENV_DEVELOPMENT / RAC_ENV_PRODUCTION).
  /// Mirrors Swift `cEnvironment`: unknown values map to RAC_ENV_DEVELOPMENT.
  int get _cEnvironment {
    switch (this) {
      case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
        return 0; // RAC_ENV_DEVELOPMENT
      case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
        return 2; // RAC_ENV_PRODUCTION
      default:
        return 0; // RAC_ENV_DEVELOPMENT
    }
  }

  /// Invoke a required `rac_env_*` predicate from commons.
  bool _envPredicate(bool Function(int)? fn, {required String symbol}) {
    if (fn == null) {
      throw UnsupportedError('$symbol is unavailable');
    }
    return fn(_cEnvironment);
  }

  String get description {
    switch (this) {
      case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
        return 'Development Environment';
      case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
        return 'Production Environment';
      default:
        return 'Unspecified Environment';
    }
  }

  /// Check if this is a production environment (uses C++). Mirrors Swift
  /// `isProduction` (SDKEnvironment.swift:73).
  bool get isProduction => _envPredicate(
    RacNative.bindings.rac_env_is_production,
    symbol: 'rac_env_is_production',
  );

  /// Check if this is a testing environment (uses C++).
  bool get isTesting => _envPredicate(
    RacNative.bindings.rac_env_is_testing,
    symbol: 'rac_env_is_testing',
  );

  /// Check if this environment requires a valid backend URL (uses C++).
  bool get requiresBackendURL => _envPredicate(
    RacNative.bindings.rac_env_requires_backend_url,
    symbol: 'rac_env_requires_backend_url',
  );

  bool get isCompatibleWithCurrentBuild {
    switch (this) {
      case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
      case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
        var isDebug = false;
        assert(() {
          isDebug = true;
          return true;
        }());
        return !isDebug;
      default:
        return false;
    }
  }

  static bool get isDebugBuild {
    var isDebug = false;
    assert(() {
      isDebug = true;
      return true;
    }());
    return isDebug;
  }

  LogLevel get defaultLogLevel {
    switch (this) {
      case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
        return LogLevel.LOG_LEVEL_DEBUG;
      case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
        return LogLevel.LOG_LEVEL_WARNING;
      default:
        return LogLevel.LOG_LEVEL_INFO;
    }
  }

  /// Should send telemetry data (production only) — uses C++. Mirrors Swift
  /// `shouldSendTelemetry` (SDKEnvironment.swift:121).
  bool get shouldSendTelemetry => _envPredicate(
    RacNative.bindings.rac_env_should_send_telemetry,
    symbol: 'rac_env_should_send_telemetry',
  );

  /// Should sync with backend (non-development) — uses C++.
  bool get shouldSyncWithBackend => _envPredicate(
    RacNative.bindings.rac_env_should_sync_with_backend,
    symbol: 'rac_env_should_sync_with_backend',
  );

  /// Requires API authentication (non-development) — uses C++.
  bool get requiresAuthentication => _envPredicate(
    RacNative.bindings.rac_env_requires_auth,
    symbol: 'rac_env_requires_auth',
  );
}

class SDKInitParams {
  final String apiKey;
  final Uri baseURL;
  final SDKEnvironment environment;

  SDKInitParams({
    required this.apiKey,
    required this.baseURL,
    this.environment = SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
  }) {
    // Fail-closed on UNSPECIFIED / UNRECOGNIZED: refuse to silently coerce
    // an unknown wire-decoded enum value into DEVELOPMENT (which would
    // disable auth and backend sync).
    if (environment == SDKEnvironment.SDK_ENVIRONMENT_UNSPECIFIED ||
        !SDKEnvironment.values.contains(environment)) {
      throw SDKException.invalidConfiguration(
        'Unknown SDKEnvironment value; refusing to default to DEVELOPMENT',
      );
    }
    final result = DartBridgeEnvironment.instance.validateConfig(
      environment: environment,
      apiKey: apiKey,
      baseURL: baseURL.toString(),
    );
    if (!result.isValid) {
      throw SDKException.validationFailed(
        DartBridgeEnvironment.instance.getValidationErrorMessage(result),
        fieldPath: 'SDKInitParams',
      );
    }
  }

  factory SDKInitParams.fromString({
    required String apiKey,
    required String baseURL,
    SDKEnvironment environment = SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
  }) {
    final uri = Uri.tryParse(baseURL);
    if (uri == null) {
      throw ArgumentError('Invalid base URL: $baseURL');
    }
    return SDKInitParams(
      apiKey: apiKey,
      baseURL: uri,
      environment: environment,
    );
  }

  factory SDKInitParams.forDevelopment({String apiKey = ''}) {
    // Development mode uses local analytics; the backend is reached only
    // through the effective base URL resolved by commons state, so this is a
    // placeholder. Mirrors Swift's `SDKInitParams(forDevelopmentWithAPIKey:)`.
    return SDKInitParams(
      apiKey: apiKey,
      baseURL: Uri.parse('https://dev.runanywhere.local'),
      environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
    );
  }
}
