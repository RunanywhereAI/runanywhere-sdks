import 'dart:typed_data';
import '../../core/models/audio_format.dart';
import '../../core/protocols/component/component_configuration.dart';

/// Output from Text-to-Speech (conforms to ComponentOutput protocol)
/// Matches iOS TTSOutput struct from TTSComponent.swift
class TTSOutput implements ComponentOutput {
  /// Synthesized audio data
  final Uint8List audioData;

  /// Audio format of the output
  final AudioFormat format;

  /// Duration of the audio in seconds
  final double duration;

  /// Phoneme timestamps if available
  final List<PhonemeTimestamp>? phonemeTimestamps;

  /// Processing metadata
  final SynthesisMetadata metadata;

  /// Timestamp (required by ComponentOutput)
  @override
  final DateTime timestamp;

  TTSOutput({
    required this.audioData,
    required this.format,
    required this.duration,
    this.phonemeTimestamps,
    required this.metadata,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Synthesis metadata
/// Matches iOS SynthesisMetadata struct from TTSComponent.swift
class SynthesisMetadata {
  final String voice;
  final String language;
  final double processingTime;
  final int characterCount;
  final double charactersPerSecond;

  SynthesisMetadata({
    required this.voice,
    required this.language,
    required this.processingTime,
    required this.characterCount,
  }) : charactersPerSecond = processingTime > 0
           ? characterCount / processingTime
           : 0;
}

/// Phoneme timestamp information
/// Matches iOS PhonemeTimestamp struct from TTSComponent.swift
class PhonemeTimestamp {
  final String phoneme;
  final double startTime;
  final double endTime;

  PhonemeTimestamp({
    required this.phoneme,
    required this.startTime,
    required this.endTime,
  });
}
