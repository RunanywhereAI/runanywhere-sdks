import 'sdk_environment.dart';

/// SDK Initialization Parameters
/// Similar to Swift SDK's SDKInitParams
class SDKInitParams {
  final String apiKey;
  final Uri baseURL;
  final SDKEnvironment environment;
  final SupabaseConfig? supabaseConfig;

  SDKInitParams({
    required this.apiKey,
    required this.baseURL,
    required this.environment,
    this.supabaseConfig,
  });

  /// Create from string URL
  factory SDKInitParams.fromString({
    required String apiKey,
    required String baseURL,
    required SDKEnvironment environment,
    SupabaseConfig? supabaseConfig,
  }) {
    return SDKInitParams(
      apiKey: apiKey,
      baseURL: Uri.parse(baseURL),
      environment: environment,
      supabaseConfig: supabaseConfig,
    );
  }
}

/// Supabase Configuration for development mode
class SupabaseConfig {
  final Uri projectURL;
  final String anonKey;

  SupabaseConfig({required this.projectURL, required this.anonKey});
}
