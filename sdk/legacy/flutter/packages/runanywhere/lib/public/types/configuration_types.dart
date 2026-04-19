/// Configuration Types
///
/// Types for SDK configuration.
library configuration_types;

/// Supabase configuration for development mode
class SupabaseConfig {
  final Uri projectURL;
  final String anonKey;

  const SupabaseConfig({
    required this.projectURL,
    required this.anonKey,
  });
}
