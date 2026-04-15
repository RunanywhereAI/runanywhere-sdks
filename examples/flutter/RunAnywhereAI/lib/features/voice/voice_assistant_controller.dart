import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere/capabilities/voice/models/voice_session.dart';

enum VoiceSessionState {
  idle,
  connecting,
  listening,
  processing,
  speaking,
  error,
}

class VoiceAssistantState {
  const VoiceAssistantState({
    this.sessionState = VoiceSessionState.idle,
    this.conversation = const [],
    this.audioLevel = 0.0,
    this.sttReady = false,
    this.llmReady = false,
    this.ttsReady = false,
    this.errorMessage,
  });

  final VoiceSessionState sessionState;
  final List<ConversationTurn> conversation;
  final double audioLevel;
  final bool sttReady;
  final bool llmReady;
  final bool ttsReady;
  final String? errorMessage;

  bool get allModelsReady => sttReady && llmReady && ttsReady;
  bool get isActive => sessionState != VoiceSessionState.idle &&
      sessionState != VoiceSessionState.error;

  VoiceAssistantState copyWith({
    VoiceSessionState? sessionState,
    List<ConversationTurn>? conversation,
    double? audioLevel,
    bool? sttReady,
    bool? llmReady,
    bool? ttsReady,
    String? errorMessage,
    bool clearError = false,
  }) {
    return VoiceAssistantState(
      sessionState: sessionState ?? this.sessionState,
      conversation: conversation ?? this.conversation,
      audioLevel: audioLevel ?? this.audioLevel,
      sttReady: sttReady ?? this.sttReady,
      llmReady: llmReady ?? this.llmReady,
      ttsReady: ttsReady ?? this.ttsReady,
      errorMessage: clearError ? null : (errorMessage ?? this.errorMessage),
    );
  }
}

class ConversationTurn {
  const ConversationTurn({
    required this.role,
    required this.text,
    required this.timestamp,
  });

  final ConversationRole role;
  final String text;
  final DateTime timestamp;
}

enum ConversationRole { user, assistant }

final voiceAssistantControllerProvider =
    NotifierProvider<VoiceAssistantController, VoiceAssistantState>(
  VoiceAssistantController.new,
);

class VoiceAssistantController extends Notifier<VoiceAssistantState> {
  StreamSubscription<VoiceSessionEvent>? _eventSub;

  @override
  VoiceAssistantState build() {
    ref.onDispose(_cleanup);
    _syncModels();
    return const VoiceAssistantState();
  }

  void _syncModels() {
    state = state.copyWith(
      sttReady: sdk.RunAnywhere.isSTTModelLoaded,
      llmReady: sdk.RunAnywhere.isModelLoaded,
      ttsReady: sdk.RunAnywhere.isTTSVoiceLoaded,
    );
  }

  Future<void> toggleSession() async {
    if (state.isActive) {
      await _stopSession();
    } else {
      await _startSession();
    }
  }

  Future<void> _startSession() async {
    if (!state.allModelsReady) {
      state = state.copyWith(
        errorMessage: 'Load STT, LLM, and TTS models first',
      );
      return;
    }

    state = state.copyWith(
      sessionState: VoiceSessionState.connecting,
      clearError: true,
    );

    try {
      final session = await sdk.RunAnywhere.startVoiceSession();
      _eventSub = session.events.listen(_handleEvent);
      state = state.copyWith(sessionState: VoiceSessionState.listening);
    } on Exception catch (e) {
      state = state.copyWith(
        sessionState: VoiceSessionState.error,
        errorMessage: e.toString(),
      );
    }
  }

  Future<void> _stopSession() async {
    await _eventSub?.cancel();
    _eventSub = null;
    state = state.copyWith(sessionState: VoiceSessionState.idle);
  }

  void _handleEvent(VoiceSessionEvent event) {
    switch (event) {
      case VoiceSessionStarted():
        state = state.copyWith(sessionState: VoiceSessionState.listening);
      case VoiceSessionListening(audioLevel: final level):
        state = state.copyWith(
          sessionState: VoiceSessionState.listening,
          audioLevel: level,
        );
      case VoiceSessionSpeechStarted():
        state = state.copyWith(sessionState: VoiceSessionState.listening);
      case VoiceSessionProcessing():
        state = state.copyWith(sessionState: VoiceSessionState.processing);
      case VoiceSessionTranscribed(text: final text):
        state = state.copyWith(
          sessionState: VoiceSessionState.processing,
          conversation: [
            ...state.conversation,
            ConversationTurn(
              role: ConversationRole.user,
              text: text,
              timestamp: DateTime.now(),
            ),
          ],
        );
      case VoiceSessionResponded(text: final text):
        state = state.copyWith(
          conversation: [
            ...state.conversation,
            ConversationTurn(
              role: ConversationRole.assistant,
              text: text,
              timestamp: DateTime.now(),
            ),
          ],
        );
      case VoiceSessionSpeaking():
        state = state.copyWith(sessionState: VoiceSessionState.speaking);
      case VoiceSessionTurnCompleted():
        state = state.copyWith(sessionState: VoiceSessionState.listening);
      case VoiceSessionError(message: final msg):
        state = state.copyWith(
          sessionState: VoiceSessionState.error,
          errorMessage: msg,
        );
      case VoiceSessionStopped():
        state = state.copyWith(sessionState: VoiceSessionState.idle);
    }
  }

  void _cleanup() {
    _eventSub?.cancel();
  }
}
