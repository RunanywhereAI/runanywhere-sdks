/// Voice Session Models
///
/// Matches iOS VoiceSession.swift from Capabilities/Voice/Models/
library voice_session;

import '../../../features/stt/stt_capability.dart' show STTOutput;

/// Configuration for a voice session
/// Matches iOS VoiceSessionConfig from VoiceSession.swift
class VoiceSessionConfig {
  /// Whether to enable speech-to-text transcription
  final bool enableTranscription;

  /// Whether to enable LLM processing
  final bool enableLLM;

  /// Whether to enable text-to-speech
  final bool enableTTS;

  /// Language code for the session
  final String language;

  const VoiceSessionConfig({
    this.enableTranscription = true,
    this.enableLLM = false,
    this.enableTTS = false,
    this.language = 'en',
  });

  /// Create a copy with modified values
  VoiceSessionConfig copyWith({
    bool? enableTranscription,
    bool? enableLLM,
    bool? enableTTS,
    String? language,
  }) {
    return VoiceSessionConfig(
      enableTranscription: enableTranscription ?? this.enableTranscription,
      enableLLM: enableLLM ?? this.enableLLM,
      enableTTS: enableTTS ?? this.enableTTS,
      language: language ?? this.language,
    );
  }
}

/// Voice session state
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

/// Voice session state tracking
/// Matches iOS VoiceSession from VoiceSession.swift
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
