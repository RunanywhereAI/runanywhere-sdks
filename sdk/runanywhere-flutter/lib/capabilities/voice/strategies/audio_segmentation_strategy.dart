/// Audio Segmentation Strategy
///
/// Protocol for audio segmentation strategies.
/// Allows custom implementation while providing default behavior.
/// Matches iOS AudioSegmentationStrategy from Capabilities/Voice/Strategies/AudioSegmentation/AudioSegmentationStrategy.swift.
library audio_segmentation_strategy;

/// Protocol for audio segmentation strategies
/// Allows custom implementation while providing default behavior
/// Matches iOS AudioSegmentationStrategy protocol
abstract class AudioSegmentationStrategy {
  /// Determine if the current audio buffer should be processed
  /// - Parameters:
  ///   - audioBuffer: Current accumulated audio samples
  ///   - sampleRate: Audio sample rate (typically 16000)
  ///   - silenceDuration: How long silence has been detected (seconds)
  ///   - speechDuration: Duration of current speech segment (seconds)
  /// - Returns: True if the buffer should be processed, false to continue accumulating
  bool shouldProcessAudio({
    required List<double> audioBuffer,
    required int sampleRate,
    required double silenceDuration,
    required double speechDuration,
  });

  /// Optional: Reset internal state when speech ends
  void reset();
}

/// Default implementation using simple time-based segmentation
/// Matches iOS DefaultAudioSegmentation from AudioSegmentationStrategy.swift
class DefaultAudioSegmentation implements AudioSegmentationStrategy {
  /// Minimum speech duration before processing (seconds)
  final double minimumSpeechDuration;

  /// Silence duration to consider speech ended (seconds)
  final double silenceThreshold;

  /// Maximum speech duration before forced processing (seconds)
  final double maximumSpeechDuration;

  /// Creates a default audio segmentation strategy
  /// - Parameters:
  ///   - minimumSpeechDuration: Minimum speech duration before processing (default: 3.0 seconds for better diarization)
  ///   - silenceThreshold: Silence duration to consider speech ended (default: 1.5 seconds for phrase completion)
  ///   - maximumSpeechDuration: Maximum speech duration before forced processing (default: 15.0 seconds)
  const DefaultAudioSegmentation({
    this.minimumSpeechDuration = 3.0, // Increased from 1.0 for better diarization
    this.silenceThreshold = 1.5, // Slightly longer for phrase completion
    this.maximumSpeechDuration = 15.0, // Force processing after 15 seconds
  });

  @override
  bool shouldProcessAudio({
    required List<double> audioBuffer,
    required int sampleRate,
    required double silenceDuration,
    required double speechDuration,
  }) {
    // Don't process very short audio
    if (speechDuration < minimumSpeechDuration) {
      return false;
    }

    // Process if we have sufficient silence indicating phrase end
    if (silenceDuration >= silenceThreshold) {
      return true;
    }

    // Force processing if speech is too long
    if (speechDuration >= maximumSpeechDuration) {
      return true;
    }

    return false;
  }

  @override
  void reset() {
    // No internal state in default implementation
  }
}

/// Smart segmentation that tries to detect complete phrases
/// Can be provided by app developers for custom behavior
/// Matches iOS SmartPhraseSegmentation from AudioSegmentationStrategy.swift
class SmartPhraseSegmentation implements AudioSegmentationStrategy {
  /// Minimum phrase length in seconds
  final double minimumPhraseLength;

  /// Optimal phrase length for best accuracy
  final double optimalPhraseLength;

  /// Extended silence for phrase boundaries
  final double phraseEndSilence;

  /// Brief pause threshold (for breathing/thinking)
  final double briefPauseThreshold;

  /// Creates a smart phrase segmentation strategy
  /// - Parameters:
  ///   - minimumPhraseLength: Minimum phrase length (default: 3.0 seconds)
  ///   - optimalPhraseLength: Optimal phrase length for best accuracy (default: 8.0 seconds)
  ///   - phraseEndSilence: Extended silence for phrase boundaries (default: 2.0 seconds)
  ///   - briefPauseThreshold: Brief pause threshold for breathing/thinking (default: 0.5 seconds)
  const SmartPhraseSegmentation({
    this.minimumPhraseLength = 3.0,
    this.optimalPhraseLength = 8.0,
    this.phraseEndSilence = 2.0,
    this.briefPauseThreshold = 0.5,
  });

  @override
  bool shouldProcessAudio({
    required List<double> audioBuffer,
    required int sampleRate,
    required double silenceDuration,
    required double speechDuration,
  }) {
    // Never process very short segments
    if (speechDuration < minimumPhraseLength) {
      return false;
    }

    // For optimal length, be more lenient with silence threshold
    if (speechDuration >= optimalPhraseLength) {
      return silenceDuration >= briefPauseThreshold * 2;
    }

    // For longer segments, require extended silence for phrase boundary
    if (speechDuration >= minimumPhraseLength) {
      return silenceDuration >= phraseEndSilence;
    }

    // Force processing for very long segments
    if (speechDuration >= 15.0) {
      return true;
    }

    return false;
  }

  @override
  void reset() {
    // No internal state needed
  }
}
