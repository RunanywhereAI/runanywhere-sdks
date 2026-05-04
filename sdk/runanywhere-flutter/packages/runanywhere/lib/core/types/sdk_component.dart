library component_types;

// MARK: - SDK Component Enum

/// SDK component types for identification.
///
/// This enum consolidates what was previously `CapabilityType` and provides
/// a unified type for all AI capabilities in the SDK.
///
/// ## Usage
///
/// ```dart
/// // Check what capabilities a module provides
/// final capabilities = MyModule.capabilities;
/// if (capabilities.contains(SDKComponent.llm)) {
///   // Module provides LLM services
/// }
/// ```
enum SDKComponent {
  llm('LLM', 'Language Model', 'llm'),
  stt('STT', 'Speech to Text', 'stt'),
  vlm('VLM', 'Vision Language Model', 'vlm'),
  tts('TTS', 'Text to Speech', 'tts'),
  vad('VAD', 'Voice Activity Detection', 'vad'),
  voice('VOICE', 'Voice Agent', 'voice'),
  embedding('EMBEDDING', 'Embedding', 'embedding');

  final String rawValue;
  final String displayName;
  final String analyticsKey;

  const SDKComponent(this.rawValue, this.displayName, this.analyticsKey);

  static SDKComponent? fromRawValue(String value) {
    return SDKComponent.values.cast<SDKComponent?>().firstWhere(
          (c) => c?.rawValue == value || c?.analyticsKey == value.toLowerCase(),
          orElse: () => null,
        );
  }
}
