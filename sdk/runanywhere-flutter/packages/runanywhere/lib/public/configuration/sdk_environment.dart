import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/model_types.pbenum.dart' as pb;
import 'package:runanywhere/native/dart_bridge_dev_config.dart';

/// SDK Environment mode — determines how data is handled.
///
/// GAP 01 Phase 4: `toProto()` / `fromProto()` keep this enum in sync with
/// `runanywhere.v1.SDKEnvironment` in `idl/model_types.proto`. Adding a case
/// requires updating both sides; the CI drift-check enforces freshness of
/// `lib/generated/model_types.pbenum.dart`.
enum SDKEnvironment {
  /// Development/testing mode — may use local data, verbose logging.
  development,

  /// Staging mode — testing with real services.
  staging,

  /// Production mode — live environment.
  production;

  /// Convert to the IDL-generated Wire enum.
  pb.SDKEnvironment toProto() {
    switch (this) {
      case SDKEnvironment.development:
        return pb.SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
      case SDKEnvironment.staging:
        return pb.SDKEnvironment.SDK_ENVIRONMENT_STAGING;
      case SDKEnvironment.production:
        return pb.SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION;
    }
  }

  /// Decode from the IDL-generated Wire enum. Unknown → development.
  static SDKEnvironment fromProto(pb.SDKEnvironment proto) {
    if (proto == pb.SDKEnvironment.SDK_ENVIRONMENT_STAGING) {
      return SDKEnvironment.staging;
    }
    if (proto == pb.SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION) {
      return SDKEnvironment.production;
    }
    return SDKEnvironment.development;
  }
}

extension SDKEnvironmentExtension on SDKEnvironment {
  /// Human-readable description
  String get description {
    switch (this) {
      case SDKEnvironment.development:
        return 'Development Environment';
      case SDKEnvironment.staging:
        return 'Staging Environment';
      case SDKEnvironment.production:
        return 'Production Environment';
    }
  }

  /// Check if this is a production environment
  bool get isProduction => this == SDKEnvironment.production;

  /// Check if this is a testing environment
  bool get isTesting =>
      this == SDKEnvironment.development || this == SDKEnvironment.staging;

  /// Check if this environment requires a valid backend URL
  bool get requiresBackendURL => this != SDKEnvironment.development;

  // MARK: - Build Configuration Validation

  /// Check if the current build configuration is compatible with this environment
  /// Production environment is only allowed in Release builds
  bool get isCompatibleWithCurrentBuild {
    switch (this) {
      case SDKEnvironment.development:
      case SDKEnvironment.staging:
        return true;
      case SDKEnvironment.production:
        // In Dart/Flutter, we use kDebugMode or assert() to check debug mode
        // Since there's no #if DEBUG in Dart, we check via assert
        bool isDebug = false;
        assert(() {
          isDebug = true;
          return true;
        }());
        return !isDebug;
    }
  }

  /// Returns true if we're running in a DEBUG build
  static bool get isDebugBuild {
    bool isDebug = false;
    assert(() {
      isDebug = true;
      return true;
    }());
    return isDebug;
  }

  // MARK: - Environment-Specific Settings

  /// Determine logging verbosity based on environment
  LogLevel get defaultLogLevel {
    switch (this) {
      case SDKEnvironment.development:
        return LogLevel.debug;
      case SDKEnvironment.staging:
        return LogLevel.info;
      case SDKEnvironment.production:
        return LogLevel.warning;
    }
  }

  /// Should send telemetry data (production only)
  bool get shouldSendTelemetry => this == SDKEnvironment.production;

  /// Should use mock data sources (development only)
  bool get useMockData => this == SDKEnvironment.development;

  /// Should sync with backend (non-development)
  bool get shouldSyncWithBackend => this != SDKEnvironment.development;

  /// Requires API authentication (non-development)
  bool get requiresAuthentication => this != SDKEnvironment.development;
}

/// Supabase configuration
class SupabaseConfig {
  final Uri projectURL;
  final String anonKey;

  SupabaseConfig({
    required this.projectURL,
    required this.anonKey,
  });

  /// Get configuration for environment
  ///
  /// For development mode, reads from C++ dev config (development_config.cpp).
  /// This ensures credentials are stored in a single git-ignored location.
  static SupabaseConfig? configuration(SDKEnvironment environment) {
    switch (environment) {
      case SDKEnvironment.development:
        // Read from C++ dev config - credentials stored in development_config.cpp (git-ignored)
        final supabaseUrl = DartBridgeDevConfig.supabaseURL;
        final supabaseKey = DartBridgeDevConfig.supabaseKey;

        if (supabaseUrl == null ||
            supabaseUrl.isEmpty ||
            supabaseKey == null ||
            supabaseKey.isEmpty ||
            _looksLikePlaceholder(supabaseUrl) ||
            _looksLikePlaceholder(supabaseKey)) {
          // Dev config not available - this is expected if development_config.cpp
          // hasn't been filled in. Telemetry will be disabled in dev mode.
          return null;
        }

        final uri = Uri.tryParse(supabaseUrl);
        if (uri == null ||
            !uri.hasScheme ||
            (uri.scheme != 'http' && uri.scheme != 'https') ||
            uri.host.isEmpty) {
          return null;
        }

        return SupabaseConfig(
          projectURL: uri,
          anonKey: supabaseKey,
        );
      case SDKEnvironment.staging:
      case SDKEnvironment.production:
        return null;
    }
  }

  static bool _looksLikePlaceholder(String value) {
    return RegExp(r'YOUR_|<your|REPLACE_ME|PLACEHOLDER', caseSensitive: false)
        .hasMatch(value);
  }
}

/// SDK initialization parameters
class SDKInitParams {
  /// API key for authentication
  final String apiKey;

  /// Base URL for API requests
  final Uri baseURL;

  /// Environment mode
  final SDKEnvironment environment;

  /// Supabase configuration (for analytics in dev mode)
  SupabaseConfig? get supabaseConfig =>
      SupabaseConfig.configuration(environment);

  SDKInitParams({
    required this.apiKey,
    required this.baseURL,
    this.environment = SDKEnvironment.production,
  });

  /// Create from string URL
  factory SDKInitParams.fromString({
    required String apiKey,
    required String baseURL,
    SDKEnvironment environment = SDKEnvironment.production,
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

  /// Create development mode parameters
  /// Uses Supabase for analytics, no authentication required
  /// Matches iOS SDKInitParams(forDevelopmentWithAPIKey:)
  factory SDKInitParams.forDevelopment({String apiKey = ''}) {
    final supabaseConfig =
        SupabaseConfig.configuration(SDKEnvironment.development);
    return SDKInitParams(
      apiKey: apiKey,
      baseURL: supabaseConfig?.projectURL ?? Uri.parse('http://localhost'),
      environment: SDKEnvironment.development,
    );
  }
}
