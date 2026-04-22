/// Voice Session Models
///
/// Matches iOS VoiceSession.swift from Capabilities/Voice/Models/
/// and RunAnywhere+VoiceSession.swift from Public/Extensions/
///
/// The whole VoiceSessionEvent hierarchy is `@Deprecated` since v2.1-1,
/// so the in-file self-references (subclass constructors inside the
/// `fromProto` mapper, etc.) all trigger `deprecated_member_use_from_same_package`.
/// Suppressed at file scope because the deprecated-returning shape is
/// the public contract of this file by design — the ENTIRE file will
/// be `git rm`-d in v3's Phase C2.
// ignore_for_file: deprecated_member_use_from_same_package

library voice_session;

import 'dart:typed_data';

import 'package:runanywhere/generated/voice_events.pb.dart'
    show VoiceEvent, VoiceEvent_Payload;
import 'package:runanywhere/generated/voice_events.pbenum.dart'
    show VADEventType, PipelineState;

/// Output from Speech-to-Text transcription
/// Matches Swift STTOutput from Public/Extensions/STT/STTTypes.swift
class STTOutput {
  /// Transcribed text
  final String text;

  /// Confidence score (0.0 to 1.0)
  final double confidence;

  /// Detected language if auto-detected
  final String? detectedLanguage;

  /// Timestamp of the transcription
  final DateTime timestamp;

  const STTOutput({
    required this.text,
    required this.confidence,
    this.detectedLanguage,
    required this.timestamp,
  });
}

/// Events emitted during a voice session.
///
/// **v2.1-1 deprecation (GAP 09 #6)**: This sealed class is now a
/// *derived view* over the canonical `VoiceEvent` proto (codegen'd
/// via protoc_plugin from `idl/voice_events.proto`). The codegen'd
/// type is the single source of truth; this UX-shaped sealed class
/// is kept as a backward-compatibility shim.
///
/// New code should subscribe to the voice agent stream adapter and
/// match on `event.whichPayload()` directly.
///
/// See `docs/migrations/VoiceSessionEvent.md` for the 10-case →
/// 8-payload mapping table and migration guide.
///
/// **v3 Phase A status (shipped)**: the static `fromProto(event)` mapper is
/// FULLY IMPLEMENTED — it switches on `VoiceEvent.whichPayload()` and
/// returns the matching subclass (or null for dropout payloads). See
/// `VoiceSessionEvent.fromProto` below.
///
/// **v3.1 follow-up**: this sealed class (and its `fromProto` mapper) is
/// scheduled for deletion once sample apps migrate off
/// `RunAnywhere.startVoiceSession`. See `docs/v3_phaseC2_scope.md`.
@Deprecated(
  'Use VoiceEvent via VoiceAgentStreamAdapter.stream(). '
  'VoiceSessionEvent is a derived view — see docs/migrations/VoiceSessionEvent.md',
)
sealed class VoiceSessionEvent {
  const VoiceSessionEvent();

  /// Derive a [VoiceSessionEvent] from the canonical `VoiceEvent`
  /// (proto3 via protoc_plugin, generated from `idl/voice_events.proto`).
  ///
  /// Returns `null` for proto events that don't have a UX-visible
  /// counterpart in the legacy enum (metrics, interrupted, low-level
  /// VAD arms like BARGE_IN/SILENCE, state=THINKING). See
  /// `docs/migrations/VoiceSessionEvent.md` for the full dropout list.
  ///
  /// v3-readiness Phase A6: ported 1:1 from the Swift template at
  /// `sdk/runanywhere-swift/.../VoiceAgentTypes.swift`
  /// `VoiceSessionEvent.from(_:)`.
  static VoiceSessionEvent? fromProto(VoiceEvent event) {
    switch (event.whichPayload()) {
      case VoiceEvent_Payload.userSaid:
        return VoiceSessionTranscribed(text: event.userSaid.text);

      case VoiceEvent_Payload.assistantToken:
        return VoiceSessionResponded(text: event.assistantToken.text);

      case VoiceEvent_Payload.audio:
        return const VoiceSessionSpeaking();

      case VoiceEvent_Payload.vad:
        final vadType = event.vad.type;
        if (vadType == VADEventType.VAD_EVENT_VOICE_START) {
          return const VoiceSessionSpeechStarted();
        } else if (vadType == VADEventType.VAD_EVENT_VOICE_END_OF_UTTERANCE) {
          return const VoiceSessionProcessing();
        }
        // BARGE_IN, SILENCE, UNSPECIFIED have no UX counterpart.
        return null;

      case VoiceEvent_Payload.state:
        final cur = event.state.current;
        if (cur == PipelineState.PIPELINE_STATE_IDLE) {
          return const VoiceSessionStarted();
        } else if (cur == PipelineState.PIPELINE_STATE_LISTENING) {
          return const VoiceSessionListening(audioLevel: 0.0);
        } else if (cur == PipelineState.PIPELINE_STATE_SPEAKING) {
          return const VoiceSessionSpeaking();
        } else if (cur == PipelineState.PIPELINE_STATE_STOPPED) {
          return const VoiceSessionStopped();
        }
        // THINKING, UNSPECIFIED have no UX counterpart.
        return null;

      case VoiceEvent_Payload.error:
        return VoiceSessionError(message: event.error.message);

      case VoiceEvent_Payload.interrupted:
      case VoiceEvent_Payload.metrics:
      case VoiceEvent_Payload.notSet:
        // No legacy UX counterpart. Consumers that need these should
        // read proto events directly via VoiceAgentStreamAdapter.stream().
        return null;
    }
  }
}

/// Session started and ready. v2.1-1: maps from `VoiceEvent.state { current = IDLE }`.
class VoiceSessionStarted extends VoiceSessionEvent {
  const VoiceSessionStarted();
}

/// Listening for speech with current audio level (0.0 - 1.0).
/// v2.1-1: maps from `VoiceEvent.state { current = LISTENING }`; audioLevel
/// is not in the proto and will be 0 when derived.
class VoiceSessionListening extends VoiceSessionEvent {
  final double audioLevel;
  const VoiceSessionListening({required this.audioLevel});
}

/// Speech detected, started accumulating audio.
/// v2.1-1: maps from `VoiceEvent.vad { type = VOICE_START }`.
class VoiceSessionSpeechStarted extends VoiceSessionEvent {
  const VoiceSessionSpeechStarted();
}

/// Speech ended, processing audio.
/// v2.1-1: maps from `VoiceEvent.vad { type = VOICE_END_OF_UTTERANCE }`.
class VoiceSessionProcessing extends VoiceSessionEvent {
  const VoiceSessionProcessing();
}

/// Got transcription from STT.
/// v2.1-1: maps from `VoiceEvent.userSaid { text }`.
class VoiceSessionTranscribed extends VoiceSessionEvent {
  final String text;
  const VoiceSessionTranscribed({required this.text});
}

/// Got response from LLM.
/// v2.1-1: maps from `VoiceEvent.assistantToken { text }`.
class VoiceSessionResponded extends VoiceSessionEvent {
  final String text;
  const VoiceSessionResponded({required this.text});
}

/// Playing TTS audio.
/// v2.1-1: maps from `VoiceEvent.audio { pcm, ... }`.
class VoiceSessionSpeaking extends VoiceSessionEvent {
  const VoiceSessionSpeaking();
}

/// Complete turn result.
///
/// v2.1-1: **CANNOT be derived** from a single `VoiceEvent` — this case
/// aggregates multiple proto events across a turn. Callers needing
/// turn-level aggregation should buffer proto events themselves.
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

/// Session stopped. v2.1-1: maps from `VoiceEvent.state { current = STOPPED }`.
class VoiceSessionStopped extends VoiceSessionEvent {
  const VoiceSessionStopped();
}

/// Error occurred. v2.1-1: maps from `VoiceEvent.error { message }`.
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
  /// Default is 0.03 which is sensitive enough for most microphones.
  /// Increase to 0.1 or higher for noisy environments.
  final double speechThreshold;

  /// Whether to auto-play TTS response
  final bool autoPlayTTS;

  /// Whether to auto-resume listening after TTS playback
  final bool continuousMode;

  const VoiceSessionConfig({
    this.silenceDuration = 1.5,
    this.speechThreshold = 0.03,
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
