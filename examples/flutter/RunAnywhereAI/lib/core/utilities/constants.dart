// Constants (mirroring iOS Constants.swift)
//
// Application-wide constant values.

class Constants {
  Constants._();

  /// App configuration
  static const app = _App();

  /// Storage configuration
  static const storage = _Storage();

  /// Generation configuration
  static const generation = _Generation();

  /// Memory configuration
  static const memory = _Memory();

  /// UI configuration
  static const ui = _UI();
}

class _App {
  const _App();

  String get name => 'RunAnywhereAI';
  String get version => '1.0.0';
  String get bundleId => 'com.runanywhere.ai.demo';
}

class _Storage {
  const _Storage();

  String get modelsDirectory => 'Models';
  String get cacheDirectory => 'Cache';
}

class _Generation {
  const _Generation();

  int get defaultMaxTokens => 150;
  double get defaultTemperature => 0.7;
  double get defaultTopP => 0.95;
  int get defaultTopK => 40;
  double get defaultRepetitionPenalty => 1.1;
}

class _Memory {
  const _Memory();

  /// 1GB minimum required memory
  int get minimumRequiredMemory => 1000000000;

  /// 2GB recommended memory
  int get recommendedMemory => 2000000000;
}

class _UI {
  const _UI();

  /// Maximum width for message bubbles (75% of screen)
  double get messageMaxWidth => 0.75;

  /// Delay before showing typing indicator
  double get typingIndicatorDelay => 0.2;

  /// Delay between streaming tokens
  Duration get streamingTokenDelay => const Duration(milliseconds: 100);
}

/// Keychain keys for secure storage
class KeychainKeys {
  KeychainKeys._();

  static const String apiKey = 'runanywhere_api_key';
  static const String baseURL = 'runanywhere_base_url';
  static const String analyticsLogToLocal = 'analyticsLogToLocal';
  static const String deviceRegistered = 'com.runanywhere.sdk.deviceRegistered';
}

/// UserDefaults keys for preferences
class PreferenceKeys {
  PreferenceKeys._();

  static const String routingPolicy = 'routingPolicy';
  static const String defaultTemperature = 'defaultTemperature';
  static const String defaultMaxTokens = 'defaultMaxTokens';
  static const String useStreaming = 'useStreaming';
}
