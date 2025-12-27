/// STT (Speech-to-Text) Types
///
/// Matches iOS STT types from STTComponent.swift.
/// These types are defined separately to avoid circular dependencies
/// between module_registry.dart and stt_component.dart.
library stt_types;

import 'package:runanywhere/core/models/audio_format.dart';
import 'package:runanywhere/features/llm/llm_capability.dart' show LLMFramework;

/// Options for speech-to-text transcription
/// Matches iOS STTOptions from STTComponent.swift
class STTOptions {
  /// Language code for transcription
  final String language;

  /// Whether to auto-detect the spoken language
  final bool detectLanguage;

  /// Enable automatic punctuation
  final bool enablePunctuation;

  /// Enable speaker diarization
  final bool enableDiarization;

  /// Maximum number of speakers to identify
  final int? maxSpeakers;

  /// Enable word-level timestamps
  final bool enableTimestamps;

  /// Custom vocabulary words
  final List<String> vocabularyFilter;

  /// Audio format of input data
  final AudioFormat audioFormat;

  /// Sample rate of input audio
  final int sampleRate;

  /// Preferred framework for transcription
  final LLMFramework? preferredFramework;

  STTOptions({
    this.language = 'en',
    this.detectLanguage = false,
    this.enablePunctuation = true,
    this.enableDiarization = false,
    this.maxSpeakers,
    this.enableTimestamps = true,
    this.vocabularyFilter = const [],
    this.audioFormat = AudioFormat.pcm,
    this.sampleRate = 16000,
    this.preferredFramework,
  });

  /// Create default options for a specific language
  factory STTOptions.defaultOptions({String language = 'en'}) {
    return STTOptions(language: language);
  }
}

/// Result from STT service transcription
/// Matches iOS STTTranscriptionResult from STTComponent.swift
class STTTranscriptionResult {
  final String transcript;
  final double? confidence;
  final List<TimestampInfo>? timestamps;
  final String? language;
  final List<AlternativeTranscription>? alternatives;

  STTTranscriptionResult({
    required this.transcript,
    this.confidence,
    this.timestamps,
    this.language,
    this.alternatives,
  });
}

/// Word timestamp information for service layer
/// Matches iOS TimestampInfo from STTComponent.swift
class TimestampInfo {
  final String word;
  final double startTime;
  final double endTime;
  final double? confidence;

  TimestampInfo({
    required this.word,
    required this.startTime,
    required this.endTime,
    this.confidence,
  });
}

/// Alternative transcription for service layer
/// Matches iOS AlternativeTranscription from STTComponent.swift
class AlternativeTranscription {
  final String transcript;
  final double confidence;

  AlternativeTranscription({
    required this.transcript,
    required this.confidence,
  });
}
