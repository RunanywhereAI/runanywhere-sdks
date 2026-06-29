// Constants (mirroring iOS Constants.swift)
//
// Application-wide constant values.

/// Default backend config, supplied at build time via --dart-define so no
/// secret is committed (mirrors the Android example's gitignored
/// local.properties → BuildConfig.RUNANYWHERE_API_KEY / _BASE_URL). Empty when
/// not provided, in which case the app falls back to the SDK's dev defaults.
///
///   flutter run \
///     --dart-define=RUNANYWHERE_API_KEY=runa_prod_... \
///     --dart-define=RUNANYWHERE_BASE_URL=https://...up.railway.app
class DefaultConfig {
  DefaultConfig._();

  static const String runanywhereApiKey =
      String.fromEnvironment('RUNANYWHERE_API_KEY');
  static const String runanywhereBaseUrl =
      String.fromEnvironment('RUNANYWHERE_BASE_URL');
}

/// Keychain keys for secure storage
class KeychainKeys {
  KeychainKeys._();

  static const String apiKey = 'runanywhere_api_key';
  static const String baseURL = 'runanywhere_base_url';
  static const String analyticsLogToLocal = 'analyticsLogToLocal';
}

/// UserDefaults keys for preferences
class PreferenceKeys {
  PreferenceKeys._();

  static const String defaultTemperature = 'defaultTemperature';
  static const String defaultMaxTokens = 'defaultMaxTokens';
  static const String defaultSystemPrompt = 'defaultSystemPrompt';
  static const String useStreaming = 'useStreaming';
  static const String thinkingModeEnabled = 'thinkingModeEnabled';
  static const String toolCallingEnabled = 'toolCallingEnabled';
  static const String deviceRegistered = 'com.runanywhere.sdk.deviceRegistered';
}

/// Default system prompt applied across every chat surface (main Chat + NPU
/// Chat) when the user has not set their own in Settings. A concrete persona
/// keeps small on-device models anchored as a conversational assistant.
const String kDefaultSystemPrompt =
    'You are a helpful, friendly AI assistant. Answer the user clearly and '
    'concisely.';
