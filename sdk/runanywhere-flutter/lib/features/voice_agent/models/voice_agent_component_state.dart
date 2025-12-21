import 'package:runanywhere/public/events/sdk_event.dart';
import 'package:uuid/uuid.dart';

/// Represents the loading state of a single model/voice component
/// Matches iOS ComponentLoadState from Features/VoiceAgent/Models/VoiceAgentComponentState.swift
sealed class ComponentLoadState {
  const ComponentLoadState();

  /// Component is not loaded
  static const ComponentLoadState notLoaded = NotLoadedState();

  /// Component is currently loading
  static const ComponentLoadState loading = LoadingState();

  /// Component is loaded with a specific model/voice
  const factory ComponentLoadState.loaded({required String modelId}) =
      LoadedState;

  /// Component failed to load with an error
  const factory ComponentLoadState.error(String message) = ErrorState;

  /// Whether the component is currently loaded and ready to use
  bool get isLoaded => this is LoadedState;

  /// Whether the component is currently loading
  bool get isLoading => this is LoadingState;

  /// Get the model ID if loaded
  String? get modelId {
    if (this is LoadedState) {
      return (this as LoadedState).modelId;
    }
    return null;
  }
}

class NotLoadedState extends ComponentLoadState {
  const NotLoadedState();
}

class LoadingState extends ComponentLoadState {
  const LoadingState();
}

class LoadedState extends ComponentLoadState {
  @override
  final String modelId;
  const LoadedState({required this.modelId});
}

class ErrorState extends ComponentLoadState {
  final String message;
  const ErrorState(this.message);
}

/// Unified state of all voice agent components
/// Use this to track which models are loaded and ready for the voice pipeline
/// Matches iOS VoiceAgentComponentStates from Features/VoiceAgent/Models/VoiceAgentComponentState.swift
class VoiceAgentComponentStates {
  /// Speech-to-Text component state
  final ComponentLoadState stt;

  /// Large Language Model component state
  final ComponentLoadState llm;

  /// Text-to-Speech component state
  final ComponentLoadState tts;

  const VoiceAgentComponentStates({
    this.stt = ComponentLoadState.notLoaded,
    this.llm = ComponentLoadState.notLoaded,
    this.tts = ComponentLoadState.notLoaded,
  });

  /// Whether all components are loaded and the voice agent is ready to use
  bool get isFullyReady => stt.isLoaded && llm.isLoaded && tts.isLoaded;

  /// Whether any component is currently loading
  bool get isAnyLoading => stt.isLoading || llm.isLoading || tts.isLoading;

  /// Get a summary of which components are missing
  List<String> get missingComponents {
    final missing = <String>[];
    if (!stt.isLoaded) missing.add('STT');
    if (!llm.isLoaded) missing.add('LLM');
    if (!tts.isLoaded) missing.add('TTS');
    return missing;
  }

  /// Create a copy with modified states
  VoiceAgentComponentStates copyWith({
    ComponentLoadState? stt,
    ComponentLoadState? llm,
    ComponentLoadState? tts,
  }) {
    return VoiceAgentComponentStates(
      stt: stt ?? this.stt,
      llm: llm ?? this.llm,
      tts: tts ?? this.tts,
    );
  }
}

/// Event emitted when any voice agent component state changes
/// Apps can subscribe to this for reactive UI updates
/// Matches iOS VoiceAgentStateEvent from Features/VoiceAgent/Models/VoiceAgentComponentState.swift
sealed class VoiceAgentStateEvent implements SDKEvent {
  const VoiceAgentStateEvent();

  static VoiceAgentStateEvent sttStateChanged(ComponentLoadState state) =>
      STTStateChangedEvent(state);
  static VoiceAgentStateEvent llmStateChanged(ComponentLoadState state) =>
      LLMStateChangedEvent(state);
  static VoiceAgentStateEvent ttsStateChanged(ComponentLoadState state) =>
      TTSStateChangedEvent(state);
  static const VoiceAgentStateEvent allComponentsReady =
      AllComponentsReadyEvent();
}

/// Mixin for VoiceAgentStateEvent to provide SDKEvent defaults
mixin _VoiceAgentStateEventDefaults implements SDKEvent {
  static const _uuid = Uuid();

  @override
  String get id => _uuid.v4();

  @override
  DateTime get timestamp => DateTime.now();

  @override
  String? get sessionId => null;

  @override
  EventDestination get destination => EventDestination.publicOnly;
}

class STTStateChangedEvent extends VoiceAgentStateEvent
    with _VoiceAgentStateEventDefaults {
  final ComponentLoadState state;
  const STTStateChangedEvent(this.state);

  @override
  String get type => 'voice_agent_stt_state_changed';

  @override
  EventCategory get category => EventCategory.voice;

  @override
  Map<String, String> get properties => {
        'component': 'stt',
        'state': _stateString(state),
      };

  String _stateString(ComponentLoadState state) {
    switch (state) {
      case NotLoadedState():
        return 'not_loaded';
      case LoadingState():
        return 'loading';
      case LoadedState(modelId: final id):
        return 'loaded:$id';
      case ErrorState(message: final msg):
        return 'error:$msg';
    }
  }
}

class LLMStateChangedEvent extends VoiceAgentStateEvent
    with _VoiceAgentStateEventDefaults {
  final ComponentLoadState state;
  const LLMStateChangedEvent(this.state);

  @override
  String get type => 'voice_agent_llm_state_changed';

  @override
  EventCategory get category => EventCategory.voice;

  @override
  Map<String, String> get properties => {
        'component': 'llm',
        'state': _stateString(state),
      };

  String _stateString(ComponentLoadState state) {
    switch (state) {
      case NotLoadedState():
        return 'not_loaded';
      case LoadingState():
        return 'loading';
      case LoadedState(modelId: final id):
        return 'loaded:$id';
      case ErrorState(message: final msg):
        return 'error:$msg';
    }
  }
}

class TTSStateChangedEvent extends VoiceAgentStateEvent
    with _VoiceAgentStateEventDefaults {
  final ComponentLoadState state;
  const TTSStateChangedEvent(this.state);

  @override
  String get type => 'voice_agent_tts_state_changed';

  @override
  EventCategory get category => EventCategory.voice;

  @override
  Map<String, String> get properties => {
        'component': 'tts',
        'state': _stateString(state),
      };

  String _stateString(ComponentLoadState state) {
    switch (state) {
      case NotLoadedState():
        return 'not_loaded';
      case LoadingState():
        return 'loading';
      case LoadedState(modelId: final id):
        return 'loaded:$id';
      case ErrorState(message: final msg):
        return 'error:$msg';
    }
  }
}

class AllComponentsReadyEvent extends VoiceAgentStateEvent
    with _VoiceAgentStateEventDefaults {
  const AllComponentsReadyEvent();

  @override
  String get type => 'voice_agent_all_components_ready';

  @override
  EventCategory get category => EventCategory.voice;

  @override
  Map<String, String> get properties => {'ready': 'true'};
}
