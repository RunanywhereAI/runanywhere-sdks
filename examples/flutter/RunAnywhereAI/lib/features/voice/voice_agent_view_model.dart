import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere/runanywhere_protos.dart' as proto;

import 'package:runanywhere_ai/core/models/app_types.dart';

/// One committed conversation turn (user or assistant).
class ConversationTurn {
  final proto.MessageRole role;
  final String text;
  final DateTime timestamp;

  ConversationTurn({
    required this.role,
    required this.text,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// ViewModel for the Voice Assistant (mirrors iOS `VoiceAgentViewModel.swift`).
///
/// Orchestrates the complete STT -> LLM -> TTS pipeline session state machine:
/// the SDK owns the actual orchestration; this ViewModel bridges proto
/// `VoiceEvent`s to UI state. Intentionally NOT built on
/// `VoiceComponentViewModelBase` — it tracks three components at once, a
/// richer pattern than the single-component load/unload base.
class VoiceAgentViewModel extends ChangeNotifier {
  VoiceAgentViewModel();

  // Proto-event subscription owns the active stream; nothing else needs to
  // reach the adapter.
  StreamSubscription<sdk.VoiceEvent>? _eventSubscription;
  sdk.VoiceSession? _session;
  bool _isInitialized = false;
  bool _disposed = false;

  // --- Published session state -------------------------------------------------

  UiVoiceSessionState sessionState = UiVoiceSessionState.disconnected;

  /// Committed conversation turns.
  final List<ConversationTurn> conversation = [];

  /// In-progress transcript from STT.
  String currentTranscript = '';

  /// In-progress assistant response (streamed per token).
  String assistantResponse = '';

  /// Whether speech is currently detected (for pulsing animation).
  bool isSpeechDetected = false;

  /// Microphone activity for the level bars. The voice event grammar reports
  /// speech start/end rather than a continuous level.
  double get micActivity => isSpeechDetected ? 0.9 : 0.15;

  /// Error message to display, or null.
  String? errorMessage;

  // --- Model state ----------------------------------------------------------------

  UiModelLoadState sttModelState = UiModelLoadState.notLoaded;
  UiModelLoadState llmModelState = UiModelLoadState.notLoaded;
  UiModelLoadState ttsModelState = UiModelLoadState.notLoaded;
  UiModelLoadState vadModelState = UiModelLoadState.notLoaded;

  String currentSTTModel = 'Not loaded';
  String currentLLMModel = 'Not loaded';
  String currentTTSModel = 'Not loaded';
  String currentVADModel = 'Not loaded';

  // --- Computed properties (for the view) -------------------------------------------

  // VAD is optional: the voice agent auto-ensures Silero VAD when none is picked.
  bool get allModelsLoaded =>
      sttModelState == UiModelLoadState.loaded &&
      llmModelState == UiModelLoadState.loaded &&
      ttsModelState == UiModelLoadState.loaded;

  bool get isActive =>
      sessionState != UiVoiceSessionState.disconnected &&
      sessionState != UiVoiceSessionState.error;

  bool get isListening =>
      sessionState == UiVoiceSessionState.listening ||
      sessionState == UiVoiceSessionState.connected;

  bool get isProcessing =>
      sessionState == UiVoiceSessionState.processing ||
      sessionState == UiVoiceSessionState.connecting;

  // --- Initialization ------------------------------------------------------------------

  /// Initialize the ViewModel — idempotent.
  Future<void> initialize() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await refreshComponentStates();
  }

  /// Refresh the UI's model readiness state from SDK component state
  /// (useful after model loading in another view / the selection sheet).
  Future<void> refreshComponentStates() async {
    try {
      final state = await sdk.RunAnywhere.models.state();
      final llmModelId =
          state.loaded[proto.ModelCategory.MODEL_CATEGORY_LANGUAGE]?.id;
      final sttModelId = state
          .loaded[proto.ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION]
          ?.id;
      final ttsVoiceId = state
          .loaded[proto.ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS]
          ?.id;
      final vadModelId = state
          .loaded[proto.ModelCategory
              .MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION]
          ?.id;

      sttModelState = sttModelId != null
          ? UiModelLoadState.loaded
          : UiModelLoadState.notLoaded;
      llmModelState = llmModelId != null
          ? UiModelLoadState.loaded
          : UiModelLoadState.notLoaded;
      ttsModelState = ttsVoiceId != null
          ? UiModelLoadState.loaded
          : UiModelLoadState.notLoaded;
      vadModelState = vadModelId != null
          ? UiModelLoadState.loaded
          : UiModelLoadState.notLoaded;

      currentSTTModel = sttModelId ?? 'Not loaded';
      currentLLMModel = llmModelId ?? 'Not loaded';
      currentTTSModel = ttsVoiceId ?? 'Not loaded';
      currentVADModel = vadModelId ?? 'Not loaded';
      _notify();
    } catch (e) {
      debugPrint('Failed to get component states: $e');
    }
  }

  // --- Conversation control ---------------------------------------------------------------

  /// Report a denied microphone permission (the view owns the actual request,
  /// which needs a BuildContext).
  void reportPermissionDenied() {
    sessionState = UiVoiceSessionState.error;
    errorMessage = 'Microphone permission is required for voice assistant';
    _notify();
  }

  /// Start a voice conversation via the SDK voice capability. The SDK owns
  /// the multi-step bootstrap (VAD auto-load + model composition +
  /// initialization); this ViewModel only drives UI state and consumes the
  /// resulting proto event stream.
  Future<void> startConversation() async {
    sessionState = UiVoiceSessionState.connecting;
    errorMessage = null;
    currentTranscript = '';
    assistantResponse = '';
    _notify();

    try {
      if (!allModelsLoaded) {
        sessionState = UiVoiceSessionState.error;
        errorMessage = 'Please load STT, LLM, and TTS models first';
        _notify();
        return;
      }

      final session = await sdk.RunAnywhere.voice.createSession(
        stt: sdk.ModelRef(currentSTTModel),
        llm: sdk.ModelRef(currentLLMModel),
        tts: sdk.ModelRef(currentTTSModel),
      );
      _session = session;

      _eventSubscription = session.events.listen(
        _handleVoiceEvent,
        onError: (Object error) {
          sessionState = UiVoiceSessionState.error;
          errorMessage = 'Voice agent error: $error';
          _notify();
        },
      );
      await session.start();

      sessionState = UiVoiceSessionState.connected;
      _notify();
      debugPrint('Voice session started successfully');
    } catch (e) {
      sessionState = UiVoiceSessionState.error;
      errorMessage = 'Failed to start voice session: $e';
      _notify();
    }
  }

  /// Stop the current voice conversation: cancel the event stream, release
  /// the SDK's voice-agent resources, and reset UI state.
  Future<void> stopConversation() async {
    await _eventSubscription?.cancel();
    _eventSubscription = null;

    try {
      await _session?.close();
    } catch (e) {
      debugPrint('Voice cleanup: $e');
    }
    _session = null;

    // Commit any assistant response that finished generating but hadn't yet
    // reached PIPELINE_STATE_SPEAKING (where it is normally committed), so a
    // stop in that window doesn't silently drop the turn. Safe from double-add:
    // the subscription is already cancelled, and a committed turn leaves
    // assistantResponse empty.
    _commitAssistantResponse();

    sessionState = UiVoiceSessionState.disconnected;
    currentTranscript = '';
    assistantResponse = '';
    isSpeechDetected = false;
    _notify();
  }

  /// Dismiss the current error banner.
  void clearError() {
    errorMessage = null;
    _notify();
  }

  // --- Event handling --------------------------------------------------------

  /// Drive UI state from the SDK's voice event grammar.
  void _handleVoiceEvent(sdk.VoiceEvent event) {
    switch (event) {
      case sdk.VoiceSpeechStarted():
        isSpeechDetected = true;
        sessionState = UiVoiceSessionState.listening;
      case sdk.VoiceSpeechEnded():
        isSpeechDetected = false;
        sessionState = UiVoiceSessionState.processing;
      case sdk.VoiceUserTranscribed(:final text, :final isFinal):
        if (isFinal) {
          if (text.isNotEmpty) {
            // A new user utterance closes the previous assistant reply, so
            // commit it before appending this turn.
            _commitAssistantResponse();
            conversation.add(
              ConversationTurn(
                role: proto.MessageRole.MESSAGE_ROLE_USER,
                text: text,
              ),
            );
          }
          currentTranscript = '';
        } else {
          currentTranscript = text;
        }
      case sdk.VoiceAgentResponse(:final text):
        assistantResponse = text;
      case sdk.VoiceAgentStateChanged(:final state):
        _handleAgentState(state);
      case sdk.VoiceError(:final message, :final recoverable):
        errorMessage = message;
        if (!recoverable) sessionState = UiVoiceSessionState.error;
    }
    _notify();
  }

  void _handleAgentState(sdk.AgentState state) {
    switch (state) {
      case sdk.AgentState.listening:
        sessionState = UiVoiceSessionState.listening;
      case sdk.AgentState.thinking:
        sessionState = UiVoiceSessionState.processing;
      case sdk.AgentState.speaking:
        sessionState = UiVoiceSessionState.speaking;
        // The reply finished generating; commit it as its own bubble.
        _commitAssistantResponse();
    }
  }

  /// Commit the accumulated assistant tokens as a distinct ASSISTANT turn, then
  /// clear the buffer. No-op when empty, so it is safe to call from every
  /// turn-boundary signal (response-started/completed, SPEAKING, stop) without
  /// producing duplicate or merged bubbles.
  void _commitAssistantResponse() {
    if (assistantResponse.isEmpty) return;
    conversation.add(
      ConversationTurn(
        role: proto.MessageRole.MESSAGE_ROLE_ASSISTANT,
        text: assistantResponse,
      ),
    );
    assistantResponse = '';
  }



  // --- Cleanup --------------------------------------------------------------------------------

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_eventSubscription?.cancel());
    _eventSubscription = null;
    // Release the session on VM teardown (view's dispose).
    unawaited(_session?.close());
    _session = null;
    super.dispose();
  }
}
