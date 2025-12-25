import 'package:runanywhere/data/network/api_client.dart';

/// Development mode network configuration
/// Used when SDK is initialized with `.development` environment
/// Matches iOS DevelopmentNetworkConfig from Data/Network/DevelopmentNetworkConfig.swift
///
/// This consolidates all 3 values needed for development mode:
/// 1. Supabase project URL (base URL for API calls)
/// 2. Supabase anon key (API key / authorization)
/// 3. Build token (validates SDK installation)
///
/// Security Model:
/// - DevelopmentConfig is not committed to main branch
/// - Real values are ONLY in release tags (for distribution)
/// - Token is used ONLY when SDK is in .development mode
/// - Backend validates token via POST /api/v1/devices/register/dev
class DevelopmentNetworkConfig {
  /// Base URL for development API calls (Supabase project URL)
  final Uri baseURL;

  /// API key for development (Supabase anon key)
  final String apiKey;

  /// Build token for SDK validation
  final String buildToken;

  const DevelopmentNetworkConfig._({
    required this.baseURL,
    required this.apiKey,
    required this.buildToken,
  });

  /// Shared development configuration
  /// Returns null if configuration is invalid
  static DevelopmentNetworkConfig? get shared {
    // These values should be provided by DevelopmentConfig
    // In Flutter, this would typically come from a config file or environment
    const supabaseURL = String.fromEnvironment('SUPABASE_URL', defaultValue: '');
    const supabaseAnonKey = String.fromEnvironment('SUPABASE_ANON_KEY', defaultValue: '');
    const buildToken = String.fromEnvironment('BUILD_TOKEN', defaultValue: '');

    if (supabaseURL.isEmpty) {
      return null;
    }

    final url = Uri.tryParse(supabaseURL);
    if (url == null) {
      return null;
    }

    return DevelopmentNetworkConfig._(
      baseURL: url,
      apiKey: supabaseAnonKey,
      buildToken: buildToken,
    );
  }

  /// Create an APIClient configured for development mode
  APIClient createAPIClient() {
    return APIClient(
      baseURL: baseURL,
      apiKey: apiKey,
    );
  }

  /// Check if development configuration is available
  static bool get isAvailable => shared != null;

  /// Get the build token directly (convenience for request bodies)
  static String get token => shared?.buildToken ?? 'invalid_config';

  /// Create with explicit values (for testing)
  factory DevelopmentNetworkConfig.explicit({
    required Uri baseURL,
    required String apiKey,
    required String buildToken,
  }) {
    return DevelopmentNetworkConfig._(
      baseURL: baseURL,
      apiKey: apiKey,
      buildToken: buildToken,
    );
  }
}

/// Configuration for different SDK environments
/// Matches iOS environment-based network configuration
class EnvironmentNetworkConfig {
  /// Development environment configuration
  static DevelopmentNetworkConfig? get development => DevelopmentNetworkConfig.shared;

  /// Staging environment configuration
  /// Uses staging-specific URLs and keys
  static NetworkEnvironmentSettings? get staging {
    const stagingURL = String.fromEnvironment('STAGING_URL', defaultValue: '');
    const stagingKey = String.fromEnvironment('STAGING_API_KEY', defaultValue: '');

    if (stagingURL.isEmpty) return null;

    final url = Uri.tryParse(stagingURL);
    if (url == null) return null;

    return NetworkEnvironmentSettings(
      baseURL: url,
      apiKey: stagingKey,
    );
  }

  /// Production environment configuration
  /// Uses production-specific URLs and keys
  static NetworkEnvironmentSettings? get production {
    const prodURL = String.fromEnvironment('PRODUCTION_URL', defaultValue: '');
    const prodKey = String.fromEnvironment('PRODUCTION_API_KEY', defaultValue: '');

    if (prodURL.isEmpty) return null;

    final url = Uri.tryParse(prodURL);
    if (url == null) return null;

    return NetworkEnvironmentSettings(
      baseURL: url,
      apiKey: prodKey,
    );
  }
}

/// Network settings for a specific environment
class NetworkEnvironmentSettings {
  final Uri baseURL;
  final String apiKey;

  const NetworkEnvironmentSettings({
    required this.baseURL,
    required this.apiKey,
  });
}
