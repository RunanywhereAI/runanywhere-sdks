// SPDX-License-Identifier: Apache-2.0
//
// `RunAnywhere.voice` — the full speech-to-speech agent as a session object.

import 'dart:async';

import 'package:runanywhere/features/voice_agent/services/voice_agent_mic_driver.dart';
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/ra_defaults_pool.dart';
import 'package:runanywhere/generated/voice_agent_service.pb.dart'
    show VoiceAgentComposeConfig, VoiceSessionConfig;
import 'package:runanywhere/generated/voice_events.pb.dart' as voice_pb;
import 'package:runanywhere/generated/voice_events.pbenum.dart'
    show PipelineState;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/public/api/internal/model_gate.dart';
import 'package:runanywhere/public/api/namespaces/tts.dart';
import 'package:runanywhere/public/api/types/events.dart';
import 'package:runanywhere/public/api/types/inputs.dart';
import 'package:runanywhere/public/api/types/options.dart';

/// Speech-to-speech agent sessions.
class VoiceApi {
  /// Bind the namespace. Reach it through `RunAnywhere.voice`.
  const VoiceApi();

  /// Build a session over [stt], [llm], and [tts], downloading what is absent.
  ///
  /// ```dart
  /// final s = await RunAnywhere.voice.createSession(
  ///     stt: ModelRef('whisper-tiny'), llm: ModelRef('qwen3-0.6b'),
  ///     tts: ModelRef('piper-en'));
  /// await s.start();
  /// ```
  ///
  /// Throws [SDKException] when a model cannot be fetched, loaded, or wired.
  Future<VoiceSession> createSession({
    required ModelRef stt,
    required ModelRef llm,
    required ModelRef tts,
    VadOptions? vad,
    TurnHandlingOptions? turnHandling,
    LlmOptions? generation,
    bool downloadIfNeeded = true,
  }) async {
    if (!DartBridge.isInitialized) {
      throw SDKException.notInitialized();
    }
    await DartBridge.ensureServicesReady();

    await ModelGate.ensureLoaded(
      modelId: stt.id,
      category: ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
      downloadIfNeeded: downloadIfNeeded,
    );
    await ModelGate.ensureLoaded(
      modelId: llm.id,
      category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
      downloadIfNeeded: downloadIfNeeded,
    );
    await ModelGate.ensureLoaded(
      modelId: tts.id,
      category: ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
      downloadIfNeeded: downloadIfNeeded,
    );
    await _ensureVad(downloadIfNeeded: downloadIfNeeded);

    final config = VoiceAgentComposeConfig(
      sttModelId: stt.id,
      llmModelId: llm.id,
      ttsVoiceId: tts.voice ?? '',
    );
    final turns = turnHandling ?? const TurnHandlingOptions();
    config.sessionConfig = VoiceSessionConfig(
      silenceDurationMs: turns.endpointing.minDelayMs,
      autoPlayTts: true,
      continuousMode: true,
    );
    if (generation != null) {
      config.llmGeneration = generation.toProto();
    }
    await DartBridge.voiceAgent.initializeProto(config);
    return VoiceSession._();
  }

  Future<void> _ensureVad({required bool downloadIfNeeded}) async {
    const category = ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION;
    if (await ModelGate.currentId(category) != null) return;
    const defaultId = RADefaultsVoiceAgent.defaultVadModelId;
    if (defaultId.isEmpty) return;
    try {
      await ModelGate.ensureLoaded(
        modelId: defaultId,
        category: category,
        downloadIfNeeded: downloadIfNeeded,
      );
    } catch (error) {
      // Commons falls back to energy-based endpointing; the session still runs.
      SDKLogger('RunAnywhere.Voice').warning(
        "Default VAD '$defaultId' unavailable: $error",
      );
    }
  }
}

/// A live speech-to-speech conversation.
class VoiceSession {
  VoiceSession._();

  final StreamController<VoiceEvent> _events =
      StreamController<VoiceEvent>.broadcast();
  final TtsApi _tts = TtsApi();
  final StringBuffer _reply = StringBuffer();

  VoiceAgentMicDriver? _driver;
  StreamSubscription<voice_pb.VoiceEvent>? _subscription;
  bool _speaking = false;
  bool _closed = false;

  /// Everything the session observes: transcripts, state changes, and errors.
  ///
  /// Subscribing does not open the microphone; only [start] does.
  Stream<VoiceEvent> get events => _events.stream;

  /// Open the microphone and begin the turn loop.
  ///
  /// Throws [SDKException] when the session is closed or capture is refused.
  Future<void> start() async {
    if (_closed) {
      throw SDKException.invalidState('Voice session is closed');
    }
    if (_driver != null) return;
    final driver = VoiceAgentMicDriver();
    _driver = driver;
    _subscription = driver.events.listen(
      _forward,
      onError: (Object error) => _events.add(
        VoiceError('$error', recoverable: true),
      ),
    );
    await driver.start();
    _events.add(const VoiceAgentStateChanged(AgentState.listening));
  }

  /// Speak [text] now, outside the turn loop.
  ///
  /// Throws [SDKException] when synthesis or playback fails.
  Future<void> say(String text) async {
    if (_closed) {
      throw SDKException.invalidState('Voice session is closed');
    }
    _events.add(const VoiceAgentStateChanged(AgentState.speaking));
    await _tts.speak(text);
    _events.add(const VoiceAgentStateChanged(AgentState.listening));
  }

  /// Stop the agent mid-utterance.
  Future<void> interrupt() async {
    await _tts.stop();
    _events.add(const VoiceAgentStateChanged(AgentState.listening));
  }

  /// Release the microphone, the pipeline, and the event stream.
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    await _subscription?.cancel();
    _subscription = null;
    await _driver?.stop();
    _driver = null;
    await _tts.stop();
    DartBridge.voiceAgent.cleanup();
    await _events.close();
  }

  void _forward(voice_pb.VoiceEvent event) {
    if (_events.isClosed) return;
    if (event.hasUserSaid()) {
      _events.add(
        VoiceUserTranscribed(
          event.userSaid.text,
          isFinal: event.userSaid.isFinal,
        ),
      );
      return;
    }
    if (event.hasAssistantToken()) {
      _reply.write(event.assistantToken.text);
      _events.add(VoiceAgentResponse(_reply.toString()));
      if (event.assistantToken.isFinal) _reply.clear();
      return;
    }
    if (event.hasVad()) {
      final speaking = event.vad.isSpeech;
      if (speaking != _speaking) {
        _speaking = speaking;
        _events.add(
          speaking ? const VoiceSpeechStarted() : const VoiceSpeechEnded(),
        );
      }
      return;
    }
    if (event.hasState()) {
      final mapped = _agentState(event.state.current);
      if (mapped != null) _events.add(VoiceAgentStateChanged(mapped));
      return;
    }
    if (event.hasError()) {
      _events.add(
        VoiceError(
          event.error.message,
          recoverable: event.error.isRecoverable,
        ),
      );
    }
  }

  static AgentState? _agentState(PipelineState state) {
    switch (state) {
      case PipelineState.PIPELINE_STATE_LISTENING:
      case PipelineState.PIPELINE_STATE_WAITING_WAKEWORD:
      case PipelineState.PIPELINE_STATE_IDLE:
        return AgentState.listening;
      case PipelineState.PIPELINE_STATE_THINKING:
      case PipelineState.PIPELINE_STATE_PROCESSING_SPEECH:
      case PipelineState.PIPELINE_STATE_GENERATING_RESPONSE:
        return AgentState.thinking;
      case PipelineState.PIPELINE_STATE_SPEAKING:
      case PipelineState.PIPELINE_STATE_PLAYING_TTS:
        return AgentState.speaking;
      default:
        return null;
    }
  }
}
