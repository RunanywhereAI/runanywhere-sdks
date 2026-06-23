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

  /// Audio level (0.0 to 1.0) for visualization.
  double audioLevel = 0.0;

  /// Whether speech is currently detected (for pulsing animation).
  bool isSpeechDetected = false;

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

  bool get allModelsLoaded =>
      sttModelState == UiModelLoadState.loaded &&
      llmModelState == UiModelLoadState.loaded &&
      ttsModelState == UiModelLoadState.loaded &&
      vadModelState == UiModelLoadState.loaded;

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
      final llmModelId = sdk.RunAnywhere.llm.currentModelId;
      final sttModelId = sdk.RunAnywhere.stt.currentModelId;
      final ttsVoiceId = sdk.RunAnywhere.tts.currentVoiceId;
      final vadModelId = sdk.RunAnywhere.vad.currentModelId;

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
      if (!sdk.RunAnywhere.voice.isReady) {
        sessionState = UiVoiceSessionState.error;
        errorMessage = 'Please load STT, LLM, TTS, and VAD models first';
        _notify();
        return;
      }

      final voice = sdk.RunAnywhere.voice;
      await voice.initializeWithLoadedModels();

      _eventSubscription = voice.eventStream().listen(
        _handleProtoEvent,
        onError: (Object error) {
          sessionState = UiVoiceSessionState.error;
          errorMessage = 'Voice agent error: $error';
          _notify();
        },
      );

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

    // Release native voice-agent + VAD handles (cross-SDK parity:
    // RunAnywhere.cleanupVoiceAgent() on session end).
    try {
      sdk.RunAnywhere.voice.cleanup();
    } catch (e) {
      debugPrint('Voice cleanup: $e');
    }

    // Commit any assistant response that finished generating but hadn't yet
    // reached PIPELINE_STATE_SPEAKING (where it is normally committed), so a
    // stop in that window doesn't silently drop the turn. Safe from double-add:
    // the subscription is already cancelled, and a committed turn leaves
    // assistantResponse empty.
    _commitAssistantResponse();

    sessionState = UiVoiceSessionState.disconnected;
    currentTranscript = '';
    assistantResponse = '';
    audioLevel = 0.0;
    isSpeechDetected = false;
    _notify();
  }

  /// Dismiss the current error banner.
  void clearError() {
    errorMessage = null;
    _notify();
  }

  // --- Proto event handling ----------------------------------------------------------------

  /// Drive UI state from canonical VoiceEvent proto messages. Turn-completion
  /// aggregation is rebuilt locally from the proto state transitions.
  void _handleProtoEvent(sdk.VoiceEvent event) {
    switch (event.whichPayload()) {
      case sdk.VoiceEvent_Payload.state:
        _handlePipelineState(event.state.current);
        break;

      case sdk.VoiceEvent_Payload.vad:
        final vad = event.vad;
        // VADEvent.type is VADStreamEventKind; start/end ride
        // SPEECH_ACTIVITY with direction on the is_speech bool.
        if (vad.type ==
            sdk.VADStreamEventKind.VAD_STREAM_EVENT_KIND_SPEECH_ACTIVITY) {
          isSpeechDetected = vad.isSpeech;
          if (!vad.isSpeech) {
            sessionState = UiVoiceSessionState.processing;
          }
          _notify();
        }
        break;

      case sdk.VoiceEvent_Payload.speechTurnDetection:
        _handleSpeechTurn(event.speechTurnDetection.kind);
        break;

      case sdk.VoiceEvent_Payload.wakewordDetected:
        sessionState = UiVoiceSessionState.listening;
        isSpeechDetected = false;
        _notify();
        break;

      case sdk.VoiceEvent_Payload.userSaid:
        final text = event.userSaid.text;
        if (text.isNotEmpty) {
          // A new user utterance means the previous assistant reply is done.
          // Commit it as its own bubble BEFORE appending this user turn — the
          // mic-driver / process-turn path doesn't reliably emit
          // agent-response/SPEAKING signals, so without this the next reply's
          // tokens accumulate into the previous reply's buffer and the bubbles
          // merge. Idempotent: a no-op if already committed elsewhere.
          _commitAssistantResponse();
          conversation.add(
            ConversationTurn(
              role: proto.MessageRole.MESSAGE_ROLE_USER,
              text: text,
            ),
          );
        }
        // Clear in-progress transcript so the committed bubble above
        // is not double-rendered.
        currentTranscript = '';
        _notify();
        break;

      case sdk.VoiceEvent_Payload.assistantToken:
        // Streaming per-token for typewriter UX.
        assistantResponse += event.assistantToken.text;
        _notify();
        break;

      case sdk.VoiceEvent_Payload.audio:
        sessionState = UiVoiceSessionState.speaking;
        _notify();
        break;

      case sdk.VoiceEvent_Payload.error:
        sessionState = UiVoiceSessionState.error;
        errorMessage = event.error.message;
        _notify();
        break;

      case sdk.VoiceEvent_Payload.audioLevel:
        audioLevel = event.audioLevel.rms.clamp(0.0, 1.0);
        _notify();
        break;

      case sdk.VoiceEvent_Payload.agentResponseStarted:
        // A new assistant reply is starting — flush any prior uncommitted
        // response into its own turn first, so consecutive replies never merge
        // into one bubble (the next assistant tokens then accumulate fresh).
        _commitAssistantResponse();
        sessionState = UiVoiceSessionState.processing;
        _notify();
        break;

      case sdk.VoiceEvent_Payload.agentResponseCompleted:
        // Canonical end-of-reply: commit the accumulated tokens as their own
        // assistant turn. Idempotent with the SPEAKING-state commit below — the
        // first to fire commits and clears; the other sees an empty buffer.
        _commitAssistantResponse();
        _notify();
        break;

      case sdk.VoiceEvent_Payload.interrupted:
      case sdk.VoiceEvent_Payload.metrics:
      case sdk.VoiceEvent_Payload.componentStateChanged:
      case sdk.VoiceEvent_Payload.sessionError:
      case sdk.VoiceEvent_Payload.sessionStarted:
      case sdk.VoiceEvent_Payload.sessionStopped:
      case sdk.VoiceEvent_Payload.turnLifecycle:
      case sdk.VoiceEvent_Payload.componentProgress:
      case sdk.VoiceEvent_Payload.notSet:
        break;
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

  void _handlePipelineState(sdk.PipelineState state) {
    switch (state) {
      case sdk.PipelineState.PIPELINE_STATE_IDLE:
      case sdk.PipelineState.PIPELINE_STATE_LISTENING:
        sessionState = UiVoiceSessionState.listening;
        _notify();
        break;
      case sdk.PipelineState.PIPELINE_STATE_THINKING:
        sessionState = UiVoiceSessionState.processing;
        _notify();
        break;
      case sdk.PipelineState.PIPELINE_STATE_SPEAKING:
        sessionState = UiVoiceSessionState.speaking;
        // Flush accumulated assistant tokens as a completed turn.
        _commitAssistantResponse();
        _notify();
        break;
      case sdk.PipelineState.PIPELINE_STATE_STOPPED:
        unawaited(stopConversation());
        break;
      default:
        break;
    }
  }

  void _handleSpeechTurn(proto.SpeechTurnDetectionEventKind kind) {
    switch (kind) {
      case proto.SpeechTurnDetectionEventKind
            .SPEECH_TURN_DETECTION_EVENT_KIND_TURN_STARTED:
        isSpeechDetected = true;
        sessionState = UiVoiceSessionState.listening;
        _notify();
        break;
      case proto.SpeechTurnDetectionEventKind
            .SPEECH_TURN_DETECTION_EVENT_KIND_TURN_ENDED:
        isSpeechDetected = false;
        sessionState = UiVoiceSessionState.processing;
        _notify();
        break;
      default:
        break;
    }
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
    // Release the agent on VM teardown (view's dispose), mirroring iOS/Android.
    try {
      sdk.RunAnywhere.voice.cleanup();
    } catch (e) {
      debugPrint('Voice cleanup: $e');
    }
    super.dispose();
  }
}
