/// Component Types
///
/// Core type definitions for component models.
/// Matches Swift ComponentTypes.swift from Core/Types/
library component_types;

import 'package:runanywhere/core/types/model_types.dart';

// MARK: - Component Protocols

/// Protocol for component configuration and initialization
///
/// All component configurations (LLM, STT, TTS, VAD, etc.) implement this.
/// Provides common properties needed for model selection and framework preference.
abstract class ComponentConfiguration {
  /// Model identifier (optional - uses default if not specified)
  String? get modelId;

  /// Preferred inference framework for this component (optional)
  InferenceFramework? get preferredFramework => null;

  /// Validates the configuration
  void validate();
}

/// Protocol for component output data
abstract class ComponentOutput {
  DateTime get timestamp;
}

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
