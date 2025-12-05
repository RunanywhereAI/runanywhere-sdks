// ignore_for_file: unused_field, unused_import

import 'dart:async';
import 'dart:math' as math;

import '../../../components/speaker_diarization/speaker_diarization_component.dart'
    show SpeakerInfo;
import '../../../foundation/logging/sdk_logger.dart';
import '../handlers/speaker_diarization_handler.dart'
    show HandlerSpeakerDiarizationService;

/// Default implementation of speaker diarization using simple audio features.
///
/// This provides basic speaker tracking functionality without external dependencies.
/// Matches iOS DefaultSpeakerDiarization from Capabilities/Voice/Services/DefaultSpeakerDiarization.swift.
class DefaultSpeakerDiarization implements HandlerSpeakerDiarizationService {
  final SDKLogger _logger = SDKLogger(category: 'DefaultSpeakerDiarization');

  /// Manages detected speakers and their profiles
  final Map<String, SpeakerInfo> _speakers = {};

  /// Current active speaker
  SpeakerInfo? _currentSpeaker;

  /// Speaker change threshold (cosine similarity)
  /// Lowered from 0.7 to 0.5 for better speaker differentiation
  final double speakerChangeThreshold;

  /// Minimum segments before confirming new speaker
  final int minSegmentsForNewSpeaker;

  /// Temporary speaker segments counter
  final Map<String, int> _temporarySpeakerSegments = {};

  /// Next speaker ID counter
  int _nextSpeakerId = 1;

  /// Creates a default speaker diarization service
  /// - Parameters:
  ///   - speakerChangeThreshold: Cosine similarity threshold for speaker change (default: 0.5)
  ///   - minSegmentsForNewSpeaker: Minimum segments before confirming new speaker (default: 2)
  DefaultSpeakerDiarization({
    this.speakerChangeThreshold = 0.5,
    this.minSegmentsForNewSpeaker = 2,
  }) {
    _logger.debug('Initialized default speaker diarization');
  }

  /// Whether the service is ready
  bool get isReady => true;

  /// Initialize the service
  Future<void> initialize() async {
    // No initialization needed for default implementation
  }

  /// Cleanup resources
  Future<void> cleanup() async {
    reset();
  }

  /// Reset the service state
  void reset() {
    _speakers.clear();
    _currentSpeaker = null;
    _temporarySpeakerSegments.clear();
    _nextSpeakerId = 1;
    _logger.debug('Reset speaker diarization state');
  }

  // MARK: - HandlerSpeakerDiarizationService Implementation

  @override
  SpeakerInfo processAudio(List<double> samples) {
    // Create a simple embedding from audio features
    final embedding = _createSimpleEmbedding(samples);

    // Try to match with existing speakers
    final matchedSpeaker = _findMatchingSpeaker(embedding);
    if (matchedSpeaker != null) {
      _currentSpeaker = matchedSpeaker;
      return matchedSpeaker;
    }

    // Create new speaker if no match found
    final newSpeaker = _createNewSpeaker(embedding);
    _currentSpeaker = newSpeaker;
    _logger.info('Detected new speaker: ${newSpeaker.id}');
    return newSpeaker;
  }

  /// Update a speaker's name
  void updateSpeakerName(String speakerId, String name) {
    if (_speakers.containsKey(speakerId)) {
      final speaker = _speakers[speakerId]!;
      _speakers[speakerId] = SpeakerInfo(
        id: speaker.id,
        name: name,
        confidence: speaker.confidence,
        embedding: speaker.embedding,
      );
      _logger.debug('Updated speaker name: $speakerId -> $name');
    }
  }

  @override
  List<SpeakerInfo> getAllSpeakers() {
    return _speakers.values.toList();
  }

  // MARK: - Private Methods

  /// Find speaker that matches the given embedding
  SpeakerInfo? _findMatchingSpeaker(List<double> embedding) {
    SpeakerInfo? bestMatch;
    double bestSimilarity = 0.0;

    for (final speaker in _speakers.values) {
      if (speaker.embedding == null) continue;

      final similarity = _cosineSimilarity(embedding, speaker.embedding!);

      if (similarity > speakerChangeThreshold) {
        if (bestMatch == null || similarity > bestSimilarity) {
          bestMatch = speaker;
          bestSimilarity = similarity;
        }
      }
    }

    return bestMatch;
  }

  /// Create a new speaker profile
  SpeakerInfo _createNewSpeaker(List<double>? embedding) {
    final speakerId = 'speaker_$_nextSpeakerId';
    final speakerNumber = _nextSpeakerId;
    _nextSpeakerId++;

    final speaker = SpeakerInfo(
      id: speakerId,
      name: 'Speaker $speakerNumber',
      confidence: 1.0,
      embedding: embedding,
    );

    _speakers[speakerId] = speaker;
    return speaker;
  }

  /// Calculate cosine similarity between two embeddings
  double _cosineSimilarity(List<double> a, List<double> b) {
    if (a.length != b.length || a.isEmpty) return 0.0;

    double dotProduct = 0.0;
    double normA = 0.0;
    double normB = 0.0;

    for (int i = 0; i < a.length; i++) {
      dotProduct += a[i] * b[i];
      normA += a[i] * a[i];
      normB += b[i] * b[i];
    }

    final denominator = math.sqrt(normA) * math.sqrt(normB);
    return denominator > 0 ? dotProduct / denominator : 0.0;
  }

  /// Create a simple embedding from audio (placeholder for real speaker embedding)
  /// In production, this would use a neural network to generate speaker embeddings
  List<double> _createSimpleEmbedding(List<double> audioBuffer) {
    if (audioBuffer.isEmpty) return List.filled(128, 0.0);

    // Create a simple 128-dimensional "embedding" based on audio statistics
    // This is a placeholder - real speaker embeddings would use neural networks
    final embedding = List<double>.filled(128, 0.0);

    // Calculate some basic audio features
    final chunkSize = audioBuffer.length ~/ 128;
    if (chunkSize == 0) return embedding;

    for (int i = 0; i < math.min(128, audioBuffer.length ~/ chunkSize); i++) {
      final start = i * chunkSize;
      final end = math.min(start + chunkSize, audioBuffer.length);
      final chunk = audioBuffer.sublist(start, end);

      if (chunk.isEmpty) continue;

      // Calculate mean and variance for this chunk
      double mean = 0.0;
      for (final sample in chunk) {
        mean += sample;
      }
      mean /= chunk.length;

      double variance = 0.0;
      for (final sample in chunk) {
        variance += sample * sample;
      }
      variance /= chunk.length;

      embedding[i] = mean + variance;
    }

    // Normalize the embedding
    double norm = 0.0;
    for (final val in embedding) {
      norm += val * val;
    }

    if (norm > 0) {
      final factor = 1.0 / math.sqrt(norm);
      for (int i = 0; i < embedding.length; i++) {
        embedding[i] *= factor;
      }
    }

    return embedding;
  }
}
