/// Modular Pipeline Events
///
/// Events emitted during voice pipeline processing.
/// Matches iOS ModularPipelineEvent from the VoiceAgent handlers.
library modular_pipeline_event;

import '../../../components/speaker_diarization/speaker_diarization_component.dart'
    show SpeakerInfo;

/// Events emitted by the modular voice pipeline
/// Matches iOS ModularPipelineEvent from VoiceAgent handlers
sealed class ModularPipelineEvent {
  const ModularPipelineEvent();
}

// MARK: - VAD Events

/// VAD started listening
class VADStartedEvent extends ModularPipelineEvent {
  const VADStartedEvent();
}

/// VAD detected speech activity
class VADSpeechDetectedEvent extends ModularPipelineEvent {
  const VADSpeechDetectedEvent();
}

/// VAD detected silence (speech ended)
class VADSilenceDetectedEvent extends ModularPipelineEvent {
  const VADSilenceDetectedEvent();
}

// MARK: - STT Events

/// STT started transcribing
class STTStartedEvent extends ModularPipelineEvent {
  const STTStartedEvent();
}

/// STT partial transcript (during streaming)
class STTPartialTranscriptEvent extends ModularPipelineEvent {
  final String text;
  const STTPartialTranscriptEvent(this.text);
}

/// STT final transcript
class STTFinalTranscriptEvent extends ModularPipelineEvent {
  final String text;
  const STTFinalTranscriptEvent(this.text);
}

/// STT final transcript with speaker information
class STTFinalTranscriptWithSpeakerEvent extends ModularPipelineEvent {
  final String text;
  final SpeakerInfo speaker;
  const STTFinalTranscriptWithSpeakerEvent(this.text, this.speaker);
}

/// STT speaker changed detection
class STTSpeakerChangedEvent extends ModularPipelineEvent {
  final SpeakerInfo? from;
  final SpeakerInfo to;
  const STTSpeakerChangedEvent({required this.from, required this.to});
}

// MARK: - LLM Events

/// LLM started thinking/processing
class LLMThinkingEvent extends ModularPipelineEvent {
  const LLMThinkingEvent();
}

/// LLM streaming started
class LLMStreamStartedEvent extends ModularPipelineEvent {
  const LLMStreamStartedEvent();
}

/// LLM streaming token received
class LLMStreamTokenEvent extends ModularPipelineEvent {
  final String token;
  const LLMStreamTokenEvent(this.token);
}

/// LLM final response
class LLMFinalResponseEvent extends ModularPipelineEvent {
  final String response;
  const LLMFinalResponseEvent(this.response);
}

// MARK: - TTS Events

/// TTS synthesis started
class TTSStartedEvent extends ModularPipelineEvent {
  const TTSStartedEvent();
}

/// TTS audio chunk ready (for streaming)
class TTSAudioChunkEvent extends ModularPipelineEvent {
  final List<int> audioData;
  const TTSAudioChunkEvent(this.audioData);
}

/// TTS synthesis completed
class TTSCompletedEvent extends ModularPipelineEvent {
  const TTSCompletedEvent();
}

// MARK: - Pipeline Events

/// Pipeline error occurred
class PipelineErrorEvent extends ModularPipelineEvent {
  final Object error;
  final String? context;
  const PipelineErrorEvent(this.error, {this.context});
}

/// Pipeline completed
class PipelineCompletedEvent extends ModularPipelineEvent {
  const PipelineCompletedEvent();
}

/// Extension for convenient event creation
extension ModularPipelineEventFactories on ModularPipelineEvent {
  // VAD
  static const vadStarted = VADStartedEvent();
  static const vadSpeechDetected = VADSpeechDetectedEvent();
  static const vadSilenceDetected = VADSilenceDetectedEvent();

  // STT
  static const sttStarted = STTStartedEvent();
  static STTPartialTranscriptEvent sttPartialTranscript(String text) =>
      STTPartialTranscriptEvent(text);
  static STTFinalTranscriptEvent sttFinalTranscript(String text) =>
      STTFinalTranscriptEvent(text);
  static STTFinalTranscriptWithSpeakerEvent sttFinalTranscriptWithSpeaker(
    String text,
    SpeakerInfo speaker,
  ) =>
      STTFinalTranscriptWithSpeakerEvent(text, speaker);
  static STTSpeakerChangedEvent sttSpeakerChanged({
    SpeakerInfo? from,
    required SpeakerInfo to,
  }) =>
      STTSpeakerChangedEvent(from: from, to: to);

  // LLM
  static const llmThinking = LLMThinkingEvent();
  static const llmStreamStarted = LLMStreamStartedEvent();
  static LLMStreamTokenEvent llmStreamToken(String token) =>
      LLMStreamTokenEvent(token);
  static LLMFinalResponseEvent llmFinalResponse(String response) =>
      LLMFinalResponseEvent(response);

  // TTS
  static const ttsStarted = TTSStartedEvent();
  static TTSAudioChunkEvent ttsAudioChunk(List<int> data) =>
      TTSAudioChunkEvent(data);
  static const ttsCompleted = TTSCompletedEvent();

  // Pipeline
  static PipelineErrorEvent pipelineError(Object error, {String? context}) =>
      PipelineErrorEvent(error, context: context);
  static const pipelineCompleted = PipelineCompletedEvent();
}
