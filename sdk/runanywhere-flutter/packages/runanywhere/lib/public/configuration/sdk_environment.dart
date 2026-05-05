import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/model_types.pbenum.dart'
    show SDKEnvironment;
import 'package:runanywhere/native/dart_bridge_dev_config.dart';

export 'package:runanywhere/generated/model_types.pbenum.dart'
    show SDKEnvironment;

extension SDKEnvironmentExtension on SDKEnvironment {
  String get description {
    switch (this) {
      case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
        return 'Development Environment';
      case SDKEnvironment.SDK_ENVIRONMENT_STAGING:
        return 'Staging Environment';
      case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
        return 'Production Environment';
      default:
        return 'Development Environment';
    }
  }

  bool get isProduction => this == SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION;

  bool get isTesting =>
      this == SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT ||
      this == SDKEnvironment.SDK_ENVIRONMENT_STAGING;

  bool get requiresBackendURL =>
      this != SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;

  bool get isCompatibleWithCurrentBuild {
    switch (this) {
      case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
      case SDKEnvironment.SDK_ENVIRONMENT_STAGING:
        return true;
      case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
        var isDebug = false;
        assert(() {
          isDebug = true;
          return true;
        }());
        return !isDebug;
      default:
        return true;
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
        return LogLevel.debug;
      case SDKEnvironment.SDK_ENVIRONMENT_STAGING:
        return LogLevel.info;
      case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
        return LogLevel.warning;
      default:
        return LogLevel.debug;
    }
  }

  bool get shouldSendTelemetry =>
      this == SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION;

  bool get useMockData => this == SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;

  bool get shouldSyncWithBackend =>
      this != SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;

  bool get requiresAuthentication =>
      this != SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
}

class SupabaseConfig {
  final Uri projectURL;
  final String anonKey;

  SupabaseConfig({
    required this.projectURL,
    required this.anonKey,
  });

  static SupabaseConfig? configuration(SDKEnvironment environment) {
    switch (environment) {
      case SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT:
        final supabaseUrl = DartBridgeDevConfig.supabaseURL;
        final supabaseKey = DartBridgeDevConfig.supabaseKey;

        if (supabaseUrl == null ||
            supabaseUrl.isEmpty ||
            supabaseKey == null ||
            supabaseKey.isEmpty ||
            _looksLikePlaceholder(supabaseUrl) ||
            _looksLikePlaceholder(supabaseKey)) {
          return null;
        }

        final uri = Uri.tryParse(supabaseUrl);
        if (uri == null ||
            !uri.hasScheme ||
            (uri.scheme != 'http' && uri.scheme != 'https') ||
            uri.host.isEmpty) {
          return null;
        }

        return SupabaseConfig(projectURL: uri, anonKey: supabaseKey);
      default:
        return null;
    }
  }

  static bool _looksLikePlaceholder(String value) {
    return RegExp(r'YOUR_|<your|REPLACE_ME|PLACEHOLDER', caseSensitive: false)
        .hasMatch(value);
  }
}

class SDKInitParams {
  final String apiKey;
  final Uri baseURL;
  final SDKEnvironment environment;

  SupabaseConfig? get supabaseConfig =>
      SupabaseConfig.configuration(environment);

  SDKInitParams({
    required this.apiKey,
    required this.baseURL,
    this.environment = SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION,
  });

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
    final supabaseConfig = SupabaseConfig.configuration(
      SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
    );
    return SDKInitParams(
      apiKey: apiKey,
      baseURL: supabaseConfig?.projectURL ?? Uri.parse('http://localhost'),
      environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
    );
  }
}
