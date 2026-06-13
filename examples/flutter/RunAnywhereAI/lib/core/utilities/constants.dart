// Constants (mirroring iOS Constants.swift)
//
// Application-wide constant values.

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
