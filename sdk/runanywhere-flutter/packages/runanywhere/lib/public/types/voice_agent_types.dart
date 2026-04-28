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

  /// Component is currently loading.
  const factory ComponentLoadState.loading() = ComponentLoadStateLoading;

  /// Component is loaded with the given model ID
  const factory ComponentLoadState.loaded({required String modelId}) =
      ComponentLoadStateLoaded;

  /// Component failed to load with an error message.
  const factory ComponentLoadState.error(String message) =
      ComponentLoadStateError;
}

/// Component not loaded state
class ComponentLoadStateNotLoaded extends ComponentLoadState {
  const ComponentLoadStateNotLoaded();
}

/// Component is currently loading.
class ComponentLoadStateLoading extends ComponentLoadState {
  const ComponentLoadStateLoading();
}

/// Component loaded state
class ComponentLoadStateLoaded extends ComponentLoadState {
  /// ID of the loaded model
  final String modelId;

  const ComponentLoadStateLoaded({required this.modelId});
}

/// Component encountered a load error.
class ComponentLoadStateError extends ComponentLoadState {
  /// Failure reason / message.
  final String message;

  const ComponentLoadStateError(this.message);
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

  /// True if any component is currently loading.
  bool get isAnyLoading =>
      stt is ComponentLoadStateLoading ||
      llm is ComponentLoadStateLoading ||
      tts is ComponentLoadStateLoading;

  /// Names of components that are not yet loaded.
  List<String> get missingComponents {
    final missing = <String>[];
    if (stt is! ComponentLoadStateLoaded) missing.add('stt');
    if (llm is! ComponentLoadStateLoaded) missing.add('llm');
    if (tts is! ComponentLoadStateLoaded) missing.add('tts');
    return missing;
  }

  @override
  String toString() {
    String stateToString(ComponentLoadState state) {
      if (state is ComponentLoadStateLoaded) {
        return 'loaded(${state.modelId})';
      }
      if (state is ComponentLoadStateLoading) return 'loading';
      if (state is ComponentLoadStateError) return 'error(${state.message})';
      return 'notLoaded';
    }

    return 'VoiceAgentComponentStates('
        'stt: ${stateToString(stt)}, '
        'llm: ${stateToString(llm)}, '
        'tts: ${stateToString(tts)})';
  }
}
