/// Streaming TTS Handler
///
/// Handles progressive TTS for streaming text generation.
/// Matches iOS StreamingTTSHandler.swift from Capabilities/Voice/Operations/
library streaming_tts_handler;

import 'dart:async';

import '../../../foundation/logging/sdk_logger.dart';
import '../../../components/tts/tts_service.dart' show TTSService;
import '../../../components/tts/tts_options.dart' show TTSOptions;
import '../../../components/tts/tts_component.dart' show TTSConfiguration;
import '../models/modular_pipeline_event.dart';

/// Handles progressive TTS for streaming text generation
/// Speaks complete sentences as they become available during streaming
/// Matches iOS StreamingTTSHandler class from StreamingTTSOperation.swift
class StreamingTTSHandler {
  final TTSService ttsService;
  final SDKLogger _logger = SDKLogger(category: 'StreamingTTSHandler');

  // State tracking
  String _spokenText = '';
  String _pendingBuffer = '';

  // Configuration
  static const _sentenceDelimiters = ['.', '!', '?'];
  static const _minSentenceLength = 3; // Minimum characters for a valid sentence

  StreamingTTSHandler({required this.ttsService});

  /// Reset the handler for a new streaming session
  void reset() {
    _spokenText = '';
    _pendingBuffer = '';
    _logger.debug('StreamingTTS handler reset');
  }

  /// Process a new token from the streaming response
  /// Returns true if TTS was triggered
  Future<bool> processToken(
    String token, {
    TTSOptions? options,
    StreamController<ModularPipelineEvent>? continuation,
  }) async {
    // Add token to pending buffer
    _pendingBuffer += token;

    // Check for complete sentences
    final sentences = _extractCompleteSentences();

    if (sentences.isNotEmpty) {
      // Speak the complete sentences
      for (final sentence in sentences) {
        await _speakSentence(
          sentence,
          options: options,
          continuation: continuation,
        );
      }
      return true;
    }

    return false;
  }

  /// Extract complete sentences from the pending buffer
  List<String> _extractCompleteSentences() {
    final completeSentences = <String>[];

    var currentIndex = 0;
    while (currentIndex < _pendingBuffer.length) {
      // Find next delimiter
      int? delimiterIndex;
      for (final delimiter in _sentenceDelimiters) {
        final index = _pendingBuffer.indexOf(delimiter, currentIndex);
        if (index != -1 && (delimiterIndex == null || index < delimiterIndex)) {
          delimiterIndex = index;
        }
      }

      if (delimiterIndex != null) {
        final sentenceEndIndex = delimiterIndex + 1;
        final sentence = _pendingBuffer.substring(currentIndex, sentenceEndIndex);

        // Check if this sentence is new (not already spoken)
        final fullTextSoFar = _spokenText + sentence;
        if (!_spokenText.endsWith(sentence) &&
            sentence.length >= _minSentenceLength) {
          completeSentences.add(sentence.trim());
          _spokenText = fullTextSoFar;
        }

        currentIndex = sentenceEndIndex;
      } else {
        // No more delimiters found
        break;
      }
    }

    // Update pending buffer to only contain unprocessed text
    if (currentIndex < _pendingBuffer.length) {
      _pendingBuffer = _pendingBuffer.substring(currentIndex);
    } else {
      _pendingBuffer = '';
    }

    return completeSentences;
  }

  /// Speak a single sentence
  Future<void> _speakSentence(
    String sentence, {
    TTSOptions? options,
    StreamController<ModularPipelineEvent>? continuation,
  }) async {
    if (sentence.isEmpty) return;

    _logger.debug('Speaking sentence: $sentence');
    continuation?.add(const TTSStartedEvent());

    try {
      final ttsOptions = options ??
          TTSOptions(
            voice: 'system',
            language: 'en',
            rate: 1.0,
            pitch: 1.0,
            volume: 1.0,
          );
      final audioData =
          await ttsService.synthesize(text: sentence, options: ttsOptions);
      continuation?.add(TTSAudioChunkEvent(audioData.toList()));
      continuation?.add(const TTSCompletedEvent());
    } catch (e) {
      _logger.error('TTS failed for sentence: $e');
    }
  }

  /// Speak any remaining text in the buffer (call at end of streaming)
  Future<void> flushRemaining({
    TTSOptions? options,
    StreamController<ModularPipelineEvent>? continuation,
  }) async {
    if (_pendingBuffer.isEmpty) return;

    final remainingText = _pendingBuffer.trim();
    _pendingBuffer = '';

    if (remainingText.isNotEmpty && !_spokenText.contains(remainingText)) {
      await _speakSentence(
        remainingText,
        options: options,
        continuation: continuation,
      );
    }
  }

  /// Process streaming text with default TTS options from config
  Future<void> processStreamingText(
    String text, {
    TTSConfiguration? config,
    StreamController<ModularPipelineEvent>? continuation,
  }) async {
    final options = TTSOptions(
      voice: config?.voice,
      language: config?.language ?? 'en',
      rate: config?.speakingRate ?? 1.0,
      pitch: config?.pitch ?? 1.0,
      volume: config?.volume ?? 1.0,
    );

    await processToken(text, options: options, continuation: continuation);
  }
}
