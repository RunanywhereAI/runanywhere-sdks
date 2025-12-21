import 'dart:typed_data';

/// Result from voice agent processing
/// Contains all outputs from the voice pipeline: transcription, LLM response, and synthesized audio
/// Matches iOS VoiceAgentResult from Features/VoiceAgent/Models/VoiceAgentResult.swift
class VoiceAgentResult {
  /// Whether speech was detected in the input audio
  bool speechDetected;

  /// Transcribed text from STT
  String? transcription;

  /// Generated response text from LLM
  String? response;

  /// Synthesized audio data from TTS
  Uint8List? synthesizedAudio;

  VoiceAgentResult({
    this.speechDetected = false,
    this.transcription,
    this.response,
    this.synthesizedAudio,
  });

  /// Create from map
  factory VoiceAgentResult.fromJson(Map<String, dynamic> json) {
    return VoiceAgentResult(
      speechDetected: json['speechDetected'] as bool? ?? false,
      transcription: json['transcription'] as String?,
      response: json['response'] as String?,
      synthesizedAudio: json['synthesizedAudio'] != null
          ? Uint8List.fromList((json['synthesizedAudio'] as List).cast<int>())
          : null,
    );
  }

  /// Convert to map
  Map<String, dynamic> toJson() => {
        'speechDetected': speechDetected,
        if (transcription != null) 'transcription': transcription,
        if (response != null) 'response': response,
        if (synthesizedAudio != null)
          'synthesizedAudio': synthesizedAudio!.toList(),
      };
}

/// Events emitted by the voice agent during processing
/// Matches iOS VoiceAgentEvent from Features/VoiceAgent/Models/VoiceAgentResult.swift
sealed class VoiceAgentEvent {
  const VoiceAgentEvent();

  /// Complete processing result
  factory VoiceAgentEvent.processed(VoiceAgentResult result) =
      VoiceAgentProcessedEvent;

  /// VAD triggered (speech detected or ended)
  factory VoiceAgentEvent.vadTriggered(bool speechDetected) =
      VoiceAgentVADTriggeredEvent;

  /// Transcription available from STT
  factory VoiceAgentEvent.transcriptionAvailable(String text) =
      VoiceAgentTranscriptionEvent;

  /// Response generated from LLM
  factory VoiceAgentEvent.responseGenerated(String text) =
      VoiceAgentResponseEvent;

  /// Audio synthesized from TTS
  factory VoiceAgentEvent.audioSynthesized(Uint8List data) =
      VoiceAgentAudioEvent;

  /// Error occurred during processing
  factory VoiceAgentEvent.error(Object error) = VoiceAgentErrorEvent;
}

class VoiceAgentProcessedEvent extends VoiceAgentEvent {
  final VoiceAgentResult result;
  const VoiceAgentProcessedEvent(this.result);
}

class VoiceAgentVADTriggeredEvent extends VoiceAgentEvent {
  final bool speechDetected;
  const VoiceAgentVADTriggeredEvent(this.speechDetected);
}

class VoiceAgentTranscriptionEvent extends VoiceAgentEvent {
  final String text;
  const VoiceAgentTranscriptionEvent(this.text);
}

class VoiceAgentResponseEvent extends VoiceAgentEvent {
  final String text;
  const VoiceAgentResponseEvent(this.text);
}

class VoiceAgentAudioEvent extends VoiceAgentEvent {
  final Uint8List data;
  const VoiceAgentAudioEvent(this.data);
}

class VoiceAgentErrorEvent extends VoiceAgentEvent {
  final Object error;
  const VoiceAgentErrorEvent(this.error);
}
