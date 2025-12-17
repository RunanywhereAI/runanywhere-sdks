/// SDK Environment mode - determines how data is handled
enum SDKEnvironment {
  /// Development/testing mode - may use local data, verbose logging
  development,

  /// Staging mode - testing with real services
  staging,

  /// Production mode - live environment
  production,
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
      this == SDKEnvironment.development ||
      this == SDKEnvironment.staging;

  /// Should send telemetry data
  bool get shouldSendTelemetry => this == SDKEnvironment.production;

  /// Should use mock data sources
  bool get useMockData => this == SDKEnvironment.development;

  /// Should sync with backend
  bool get shouldSyncWithBackend => this != SDKEnvironment.development;

  /// Requires API authentication
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
  static SupabaseConfig? configuration(SDKEnvironment environment) {
    switch (environment) {
      case SDKEnvironment.development:
        return SupabaseConfig(
          projectURL: Uri.parse('https://fhtgjtxuoikwwouxqzrn.supabase.co'),
          anonKey: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZodGdqdHh1b2lrd3dvdXhxenJuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjExOTkwNzIsImV4cCI6MjA3Njc3NTA3Mn0.aIssX-t8CIqt8zoctNhMS8fm3wtH-DzsQiy9FunqD9E',
        );
      case SDKEnvironment.staging:
      case SDKEnvironment.production:
        return null;
    }
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
  SupabaseConfig? get supabaseConfig => SupabaseConfig.configuration(environment);

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
}
