/// Voice Agent Types
///
/// Types for voice agent operations.
/// Matches Swift VoiceAgentTypes.swift from Public/Extensions/VoiceAgent/
library voice_agent_types;

// MARK: - Component Load State

/// State of a voice agent component
sealed class ComponentLoadState {
  const ComponentLoadState();

  /// Component is not loaded
  const factory ComponentLoadState.notLoaded() = ComponentLoadStateNotLoaded;

  /// Component is loaded with the given model ID
  const factory ComponentLoadState.loaded({required String modelId}) =
      ComponentLoadStateLoaded;
}

/// Component not loaded state
class ComponentLoadStateNotLoaded extends ComponentLoadState {
  const ComponentLoadStateNotLoaded();
}

/// Component loaded state
class ComponentLoadStateLoaded extends ComponentLoadState {
  /// ID of the loaded model
  final String modelId;

  const ComponentLoadStateLoaded({required this.modelId});
}

// MARK: - Voice Agent Component States

/// States of all voice agent components (STT, LLM, TTS)
///
/// Matches Swift VoiceAgentComponentStates from VoiceAgentTypes.swift
class VoiceAgentComponentStates {
  /// Speech-to-Text component state
  final ComponentLoadState stt;

  /// Large Language Model component state
  final ComponentLoadState llm;

  /// Text-to-Speech component state
  final ComponentLoadState tts;

  const VoiceAgentComponentStates({
    this.stt = const ComponentLoadState.notLoaded(),
    this.llm = const ComponentLoadState.notLoaded(),
    this.tts = const ComponentLoadState.notLoaded(),
  });

  /// Check if all components are loaded
  bool get isFullyReady =>
      stt is ComponentLoadStateLoaded &&
      llm is ComponentLoadStateLoaded &&
      tts is ComponentLoadStateLoaded;

  /// Check if any component is loaded
  bool get hasAnyLoaded =>
      stt is ComponentLoadStateLoaded ||
      llm is ComponentLoadStateLoaded ||
      tts is ComponentLoadStateLoaded;

  @override
  String toString() {
    String stateToString(ComponentLoadState state) {
      if (state is ComponentLoadStateLoaded) {
        return 'loaded(${state.modelId})';
      }
      return 'notLoaded';
    }

    return 'VoiceAgentComponentStates('
        'stt: ${stateToString(stt)}, '
        'llm: ${stateToString(llm)}, '
        'tts: ${stateToString(tts)})';
  }
}
