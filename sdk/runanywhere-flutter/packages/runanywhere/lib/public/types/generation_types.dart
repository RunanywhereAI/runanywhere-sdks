/// Generation Types
///
/// Types for LLM text generation, STT transcription, and TTS synthesis.
/// Mirrors Swift LLMGenerationOptions, LLMGenerationResult, STTOutput, and TTSOutput.
library generation_types;

import 'dart:typed_data';

import 'package:runanywhere/core/models/audio_format.dart';
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/public/types/structured_output_types.dart';

/// Options for LLM text generation
/// Matches Swift's LLMGenerationOptions
class LLMGenerationOptions {
  final int maxTokens;
  final double temperature;
  final double topP;
  final List<String> stopSequences;
  final bool streamingEnabled;
  final InferenceFramework? preferredFramework;
  final String? systemPrompt;
  final StructuredOutputConfig? structuredOutput;

  const LLMGenerationOptions({
    this.maxTokens = 100,
    this.temperature = 0.8,
    this.topP = 1.0,
    this.stopSequences = const [],
    this.streamingEnabled = false,
    this.preferredFramework,
    this.systemPrompt,
    this.structuredOutput,
  });
}

/// Result of LLM text generation
/// Matches Swift's LLMGenerationResult
class LLMGenerationResult {
  final String text;
  final String? thinkingContent;
  final int inputTokens;
  final int tokensUsed;
  final String modelUsed;
  final double latencyMs;
  final String? framework;
  final double tokensPerSecond;
  final double? timeToFirstTokenMs;
  final int thinkingTokens;
  final int responseTokens;
  final Map<String, dynamic>? structuredData;

  const LLMGenerationResult({
    required this.text,
    this.thinkingContent,
    required this.inputTokens,
    required this.tokensUsed,
    required this.modelUsed,
    required this.latencyMs,
    this.framework,
    required this.tokensPerSecond,
    this.timeToFirstTokenMs,
    this.thinkingTokens = 0,
    this.responseTokens = 0,
    this.structuredData,
  });
}

// v2 close-out Phase G-2: `LLMStreamingResult` was DELETED. Callers
// consume `Stream<LLMStreamEvent>` from
// `RunAnywhereSDK.instance.llm.generateStream(...)` directly and derive
// metrics from the terminal event (`isFinal == true`, carries
// `finishReason` + optional `errorMessage`).

/// Options for STT transcription.
///
/// Mirrors Swift's `STTOptions` (10 fields).
class STTOptions {
  /// Language hint (BCP-47, e.g. "en"). Optional — if null, detection is used.
  final String? language;

  /// Whether to auto-detect language from audio.
  final bool detectLanguage;

  /// Whether to add punctuation to the transcribed text.
  final bool enablePunctuation;

  /// Whether to enable speaker diarization.
  final bool enableDiarization;

  /// Maximum number of speakers when diarization is enabled.
  final int maxSpeakers;

  /// Whether to include word-level timestamps.
  final bool enableTimestamps;

  /// Vocabulary filter (custom vocabulary to bias the model).
  final List<String>? vocabularyFilter;

  /// Audio format of the input data.
  final AudioFormat audioFormat;

  /// Sample rate (Hz) of the input audio. Default 16000.
  final int sampleRate;

  /// Preferred inference framework (if multiple are registered).
  final InferenceFramework? preferredFramework;

  const STTOptions({
    this.language,
    this.detectLanguage = false,
    this.enablePunctuation = true,
    this.enableDiarization = false,
    this.maxSpeakers = 0,
    this.enableTimestamps = true,
    this.vocabularyFilter,
    this.audioFormat = AudioFormat.wav,
    this.sampleRate = 16000,
    this.preferredFramework,
  });
}

/// Word-level timestamp returned by STT.
class WordTimestamp {
  /// The word text.
  final String word;

  /// Start time (seconds) within the audio.
  final double startTime;

  /// End time (seconds) within the audio.
  final double endTime;

  /// Confidence for this word (0.0 to 1.0). Optional.
  final double? confidence;

  const WordTimestamp({
    required this.word,
    required this.startTime,
    required this.endTime,
    this.confidence,
  });
}

/// Alternative transcription hypothesis returned by STT (n-best).
class TranscriptionAlternative {
  /// Alternative transcript.
  final String transcript;

  /// Confidence (0.0 to 1.0) for this alternative.
  final double confidence;

  const TranscriptionAlternative({
    required this.transcript,
    required this.confidence,
  });
}

/// Metadata describing the transcription pass.
class TranscriptionMetadata {
  /// Model identifier used for the transcription.
  final String? modelId;

  /// Processing time (seconds, wall-clock).
  final double processingTime;

  /// Audio length (seconds).
  final double audioLength;

  /// Real-time factor: processingTime / audioLength.
  double get realTimeFactor =>
      audioLength > 0 ? processingTime / audioLength : 0.0;

  const TranscriptionMetadata({
    this.modelId,
    required this.processingTime,
    required this.audioLength,
  });
}

/// Partial streaming-transcription result emitted by `transcribeStream`.
///
/// Mirrors Swift's `STTTranscriptionResult` shape.
class STTPartialResult {
  /// Latest transcript snapshot.
  final String transcript;

  /// Confidence (0.0 to 1.0). Optional for partial results.
  final double? confidence;

  /// True when this is the final segment.
  final bool isFinal;

  /// Detected language, if any.
  final String? language;

  /// Word-level timestamps, if available.
  final List<WordTimestamp>? timestamps;

  /// Alternative hypotheses, if available.
  final List<TranscriptionAlternative>? alternatives;

  const STTPartialResult({
    required this.transcript,
    this.confidence,
    this.isFinal = false,
    this.language,
    this.timestamps,
    this.alternatives,
  });
}

/// Result of STT transcription.
///
/// Mirrors Swift's `STTOutput` (rich shape with timestamps, alternatives,
/// metadata). The narrower `text/confidence/durationMs/language` view
/// remains backward-compatible via the same getters.
class STTResult {
  /// The transcribed text.
  final String text;

  /// Confidence score (0.0 to 1.0).
  final double confidence;

  /// Duration of audio processed in milliseconds.
  final int durationMs;

  /// Detected language (if available).
  final String? language;

  /// Word-level timestamps, if requested.
  final List<WordTimestamp>? wordTimestamps;

  /// Alternative hypotheses (n-best), if available.
  final List<TranscriptionAlternative>? alternatives;

  /// Per-pass metadata (modelId, processingTime, audioLength).
  final TranscriptionMetadata? metadata;

  /// Wall-clock timestamp when this result was produced.
  final DateTime? timestamp;

  const STTResult({
    required this.text,
    required this.confidence,
    required this.durationMs,
    this.language,
    this.wordTimestamps,
    this.alternatives,
    this.metadata,
    this.timestamp,
  });

  @override
  String toString() =>
      'STTResult(text: "$text", confidence: $confidence, durationMs: $durationMs, language: $language)';
}

/// Alias matching Swift's `STTOutput` name.
typedef STTOutput = STTResult;

/// Options for TTS synthesis.
///
/// Mirrors Swift's `TTSOptions`.
class TTSOptions {
  /// Voice id to use. If null, the currently-loaded voice is used.
  final String? voice;

  /// Language (BCP-47, e.g. "en-US"). Defaults to "en-US".
  final String language;

  /// Speech rate (0.5 to 2.0; 1.0 is normal).
  final double rate;

  /// Speech pitch (0.5 to 2.0; 1.0 is normal).
  final double pitch;

  /// Speech volume (0.0 to 1.0).
  final double volume;

  /// Audio output format.
  final AudioFormat audioFormat;

  /// Sample rate (Hz). Defaults to 22050 (Piper default).
  final int sampleRate;

  /// Whether the input contains SSML markup.
  final bool useSSML;

  const TTSOptions({
    this.voice,
    this.language = 'en-US',
    this.rate = 1.0,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.audioFormat = AudioFormat.pcm,
    this.sampleRate = 22050,
    this.useSSML = false,
  });
}

/// Phoneme-level timestamp returned by TTS (when supported).
class PhonemeTimestamp {
  /// The phoneme.
  final String phoneme;

  /// Start time (seconds) in the synthesized audio.
  final double startTime;

  /// End time (seconds) in the synthesized audio.
  final double endTime;

  const PhonemeTimestamp({
    required this.phoneme,
    required this.startTime,
    required this.endTime,
  });
}

/// Metadata describing a synthesis pass.
class TTSSynthesisMetadata {
  /// Voice id used for synthesis.
  final String? voice;

  /// Language used.
  final String? language;

  /// Processing time (seconds, wall-clock).
  final double processingTime;

  /// Number of input characters synthesized.
  final int characterCount;

  const TTSSynthesisMetadata({
    this.voice,
    this.language,
    required this.processingTime,
    required this.characterCount,
  });
}

/// Result of TTS synthesis.
///
/// Mirrors Swift's `TTSOutput`. The narrower legacy
/// `samples/sampleRate/durationMs` view remains accessible via the same
/// getters; the new `format`, `phonemeTimestamps`, and `metadata`
/// fields are additive.
class TTSResult {
  /// Audio samples as PCM float data.
  final Float32List samples;

  /// Sample rate in Hz (typically 22050 for Piper).
  final int sampleRate;

  /// Duration of audio in milliseconds.
  final int durationMs;

  /// Audio format that the samples are encoded in.
  final AudioFormat format;

  /// Phoneme-level timestamps, if available.
  final List<PhonemeTimestamp>? phonemeTimestamps;

  /// Per-pass metadata (voice/language/processingTime/characterCount).
  final TTSSynthesisMetadata? metadata;

  /// Wall-clock timestamp when this result was produced.
  final DateTime? timestamp;

  const TTSResult({
    required this.samples,
    required this.sampleRate,
    required this.durationMs,
    this.format = AudioFormat.pcm,
    this.phonemeTimestamps,
    this.metadata,
    this.timestamp,
  });

  /// Duration in seconds.
  double get durationSeconds => durationMs / 1000.0;

  /// Number of audio samples.
  int get numSamples => samples.length;

  /// Audio size (bytes) — convenience matching Swift's `audioSizeBytes`.
  int get audioSizeBytes => samples.lengthInBytes;

  @override
  String toString() =>
      'TTSResult(samples: ${samples.length}, sampleRate: $sampleRate, durationMs: $durationMs)';
}

/// Alias matching Swift's `TTSOutput` name.
typedef TTSOutput = TTSResult;

/// Result returned by `RunAnywhereSDK.instance.tts.speak(...)`.
///
/// Mirrors Swift's `TTSSpeakResult` — a metadata-only view of an
/// already-played synthesis pass.
class TTSSpeakResult {
  /// Duration of the spoken audio (seconds).
  final double duration;

  /// Audio size (bytes).
  final int audioSizeBytes;

  /// Per-pass metadata if available.
  final TTSSynthesisMetadata? metadata;

  const TTSSpeakResult({
    required this.duration,
    required this.audioSizeBytes,
    this.metadata,
  });

  /// Build from a [TTSResult].
  factory TTSSpeakResult.from(TTSResult output) {
    return TTSSpeakResult(
      duration: output.durationSeconds,
      audioSizeBytes: output.audioSizeBytes,
      metadata: output.metadata,
    );
  }
}
