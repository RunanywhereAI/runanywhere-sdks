import 'package:runanywhere/public/configuration/sdk_environment.dart';

export 'package:runanywhere/public/configuration/sdk_environment.dart'
    show SDKEnvironment;

/// HTTP Service Configuration
///
/// Matches React Native HTTPServiceConfig interface.
class HTTPServiceConfig {
  /// Base URL for API requests
  final String baseURL;

  /// API key for authentication
  final String apiKey;

  /// SDK environment
  final SDKEnvironment environment;

  /// Request timeout in milliseconds
  final int timeoutMs;

  const HTTPServiceConfig({
    required this.baseURL,
    required this.apiKey,
    this.environment = SDKEnvironment.production,
    this.timeoutMs = defaultTimeoutMs,
  });

  /// Default timeout in milliseconds
  static const int defaultTimeoutMs = 30000;
}

/// Development (Supabase) Configuration
///
/// Matches React Native DevModeConfig interface.
class DevModeConfig {
  /// Supabase project URL
  final String supabaseURL;

  /// Supabase anon key
  final String supabaseKey;

  const DevModeConfig({
    required this.supabaseURL,
    required this.supabaseKey,
  });
}

/// Network configuration options for SDK initialization
///
/// Matches React Native NetworkConfig interface.
class NetworkConfig {
  /// Base URL for API requests
  /// - Production: Railway endpoint (e.g., "https://api.runanywhere.ai")
  /// - Development: Can be left empty if supabase config is provided
  final String? baseURL;

  /// API key for authentication
  /// - Production: RunAnywhere API key
  /// - Development: Build token
  final String apiKey;

  /// SDK environment
  final SDKEnvironment environment;

  /// Supabase configuration for development mode
  /// When provided in development mode, SDK makes calls directly to Supabase
  final SupabaseNetworkConfig? supabase;

  /// Request timeout in milliseconds
  final int timeoutMs;

  const NetworkConfig({
    this.baseURL,
    required this.apiKey,
    this.environment = SDKEnvironment.production,
    this.supabase,
    this.timeoutMs = defaultTimeoutMs,
  });

  /// Default production base URL
  static const String defaultBaseURL = 'https://api.runanywhere.ai';

  /// Default timeout in milliseconds
  static const int defaultTimeoutMs = 30000;
}

/// Supabase network configuration
class SupabaseNetworkConfig {
  /// Supabase project URL
  final String url;

  /// Supabase anon key
  final String anonKey;

  const SupabaseNetworkConfig({
    required this.url,
    required this.anonKey,
  });
}

/// Create network configuration from SDK init options
///
/// Matches React Native createNetworkConfig function.
NetworkConfig createNetworkConfig({
  required String apiKey,
  String? baseURL,
  String? environmentStr,
  SDKEnvironment? environment,
  String? supabaseURL,
  String? supabaseKey,
  int? timeoutMs,
}) {
  // Map string environment to enum if provided
  SDKEnvironment env = environment ?? SDKEnvironment.production;
  if (environmentStr != null) {
    switch (environmentStr.toLowerCase()) {
      case 'development':
        env = SDKEnvironment.development;
        break;
      case 'staging':
        env = SDKEnvironment.staging;
        break;
      case 'production':
        env = SDKEnvironment.production;
        break;
    }
  }

  // Build supabase config if provided
  final supabase = supabaseURL != null && supabaseKey != null
      ? SupabaseNetworkConfig(
          url: supabaseURL,
          anonKey: supabaseKey,
        )
      : null;

  return NetworkConfig(
    baseURL: baseURL ?? NetworkConfig.defaultBaseURL,
    apiKey: apiKey,
    environment: env,
    supabase: supabase,
    timeoutMs: timeoutMs ?? NetworkConfig.defaultTimeoutMs,
  );
}

/// Get environment name string
String getEnvironmentName(SDKEnvironment env) {
  switch (env) {
    case SDKEnvironment.development:
      return 'development';
    case SDKEnvironment.staging:
      return 'staging';
    case SDKEnvironment.production:
      return 'production';
  }
}

/// Check if environment is development
bool isDevelopment(SDKEnvironment env) {
  return env == SDKEnvironment.development;
}

/// Check if environment is production
bool isProduction(SDKEnvironment env) {
  return env == SDKEnvironment.production;
}

/// Check if environment is staging
bool isStaging(SDKEnvironment env) {
  return env == SDKEnvironment.staging;
}
