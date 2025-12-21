/// Voice Session Models
///
/// Matches iOS VoiceSession.swift from Capabilities/Voice/Models/
/// and RunAnywhere+VoiceSession.swift from Public/Extensions/
library voice_session;

import 'dart:typed_data';
import '../../../features/stt/stt_capability.dart' show STTOutput;

/// Events emitted during a voice session
/// Matches iOS VoiceSessionEvent from RunAnywhere+VoiceSession.swift
sealed class VoiceSessionEvent {
  const VoiceSessionEvent();
}

/// Session started and ready
class VoiceSessionStarted extends VoiceSessionEvent {
  const VoiceSessionStarted();
}

/// Listening for speech with current audio level (0.0 - 1.0)
class VoiceSessionListening extends VoiceSessionEvent {
  final double audioLevel;
  const VoiceSessionListening({required this.audioLevel});
}

/// Speech detected, started accumulating audio
class VoiceSessionSpeechStarted extends VoiceSessionEvent {
  const VoiceSessionSpeechStarted();
}

/// Speech ended, processing audio
class VoiceSessionProcessing extends VoiceSessionEvent {
  const VoiceSessionProcessing();
}

/// Got transcription from STT
class VoiceSessionTranscribed extends VoiceSessionEvent {
  final String text;
  const VoiceSessionTranscribed({required this.text});
}

/// Got response from LLM
class VoiceSessionResponded extends VoiceSessionEvent {
  final String text;
  const VoiceSessionResponded({required this.text});
}

/// Playing TTS audio
class VoiceSessionSpeaking extends VoiceSessionEvent {
  const VoiceSessionSpeaking();
}

/// Complete turn result
class VoiceSessionTurnCompleted extends VoiceSessionEvent {
  final String transcript;
  final String response;
  final Uint8List? audio;
  const VoiceSessionTurnCompleted({
    required this.transcript,
    required this.response,
    this.audio,
  });
}

/// Session stopped
class VoiceSessionStopped extends VoiceSessionEvent {
  const VoiceSessionStopped();
}

/// Error occurred
class VoiceSessionError extends VoiceSessionEvent {
  final String message;
  const VoiceSessionError({required this.message});
}

/// Configuration for voice session behavior
/// Matches iOS VoiceSessionConfig from RunAnywhere+VoiceSession.swift
class VoiceSessionConfig {
  /// Silence duration (seconds) before processing speech
  final double silenceDuration;

  /// Minimum audio level to detect speech (0.0 - 1.0)
  final double speechThreshold;

  /// Whether to auto-play TTS response
  final bool autoPlayTTS;

  /// Whether to auto-resume listening after TTS playback
  final bool continuousMode;

  const VoiceSessionConfig({
    this.silenceDuration = 1.5,
    this.speechThreshold = 0.1,
    this.autoPlayTTS = true,
    this.continuousMode = true,
  });

  /// Default configuration
  static const VoiceSessionConfig defaultConfig = VoiceSessionConfig();

  /// Create a copy with modified values
  VoiceSessionConfig copyWith({
    double? silenceDuration,
    double? speechThreshold,
    bool? autoPlayTTS,
    bool? continuousMode,
  }) {
    return VoiceSessionConfig(
      silenceDuration: silenceDuration ?? this.silenceDuration,
      speechThreshold: speechThreshold ?? this.speechThreshold,
      autoPlayTTS: autoPlayTTS ?? this.autoPlayTTS,
      continuousMode: continuousMode ?? this.continuousMode,
    );
  }
}

/// Voice session errors
/// Matches iOS VoiceSessionError from RunAnywhere+VoiceSession.swift
class VoiceSessionException implements Exception {
  final VoiceSessionErrorType type;
  final String message;

  const VoiceSessionException(this.type, this.message);

  @override
  String toString() => message;
}

enum VoiceSessionErrorType {
  microphonePermissionDenied,
  notReady,
  alreadyRunning,
}

/// Voice session state (for internal tracking)
/// Matches iOS VoiceSessionState from VoiceSession.swift
enum VoiceSessionState {
  idle('idle'),
  listening('listening'),
  processing('processing'),
  speaking('speaking'),
  ended('ended'),
  error('error');

  final String value;
  const VoiceSessionState(this.value);

  static VoiceSessionState fromString(String value) {
    return VoiceSessionState.values.firstWhere(
      (e) => e.value == value,
      orElse: () => VoiceSessionState.idle,
    );
  }
}

/// Voice session state tracking (for internal use)
class VoiceSession {
  /// Unique session identifier
  final String id;

  /// Session configuration
  final VoiceSessionConfig configuration;

  /// Current session state
  VoiceSessionState state;

  /// Transcripts collected during this session
  final List<STTOutput> transcripts;

  /// When the session started
  DateTime? startTime;

  /// When the session ended
  DateTime? endTime;

  VoiceSession({
    required this.id,
    required this.configuration,
    this.state = VoiceSessionState.idle,
    List<STTOutput>? transcripts,
    this.startTime,
    this.endTime,
  }) : transcripts = transcripts ?? [];

  /// Calculate the session duration
  Duration? get duration {
    if (startTime == null) return null;
    final end = endTime ?? DateTime.now();
    return end.difference(startTime!);
  }

  /// Check if the session is active
  bool get isActive =>
      state == VoiceSessionState.listening ||
      state == VoiceSessionState.processing ||
      state == VoiceSessionState.speaking;

  /// Create a copy with modified values
  VoiceSession copyWith({
    String? id,
    VoiceSessionConfig? configuration,
    VoiceSessionState? state,
    List<STTOutput>? transcripts,
    DateTime? startTime,
    DateTime? endTime,
  }) {
    return VoiceSession(
      id: id ?? this.id,
      configuration: configuration ?? this.configuration,
      state: state ?? this.state,
      transcripts: transcripts ?? List.from(this.transcripts),
      startTime: startTime ?? this.startTime,
      endTime: endTime ?? this.endTime,
    );
  }
}
