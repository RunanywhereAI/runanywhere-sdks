/// TTS Handler
///
/// Handles Text-to-Speech processing in the voice pipeline.
/// Matches iOS TTSHandler.swift from Capabilities/Voice/Handlers/
library tts_handler;

import 'dart:async';

import '../../../foundation/logging/sdk_logger.dart';
import '../../../components/tts/tts_service.dart' show TTSService;
import '../../../components/tts/tts_options.dart' show TTSOptions;
import '../../../components/tts/tts_component.dart' show TTSConfiguration;
import '../models/modular_pipeline_event.dart';

/// Handles Text-to-Speech processing in the voice pipeline
/// Matches iOS TTSHandler class from TTSHandler.swift
class TTSHandler {
  final SDKLogger _logger = SDKLogger(category: 'TTSHandler');

  TTSHandler();

  /// Convert text to speech
  Future<void> speakText({
    required String text,
    required TTSService service,
    TTSConfiguration? config,
    required StreamController<ModularPipelineEvent> continuation,
  }) async {
    if (text.isEmpty) {
      _logger.debug('speakText called with empty text, skipping');
      return;
    }

    continuation.add(const TTSStartedEvent());

    final ttsOptions = createTTSOptions(config: config);

    try {
      // Synthesize the text to audio
      final audioData = await service.synthesize(text: text, options: ttsOptions);

      // Emit audio chunk event
      continuation.add(TTSAudioChunkEvent(audioData.toList()));
      continuation.add(const TTSCompletedEvent());

      _logger.info(
        'TTS completed for text: ${text.length > 50 ? '${text.substring(0, 50)}...' : text}',
      );
    } catch (e) {
      _logger.error('TTS failed: $e');
      rethrow;
    }
  }

  /// Create TTS options from configuration
  TTSOptions createTTSOptions({TTSConfiguration? config}) {
    return TTSOptions(
      voice: config?.voice,
      language: config?.language ?? 'en',
      rate: config?.speakingRate ?? 1.0,
      pitch: config?.pitch ?? 1.0,
      volume: config?.volume ?? 1.0,
    );
  }
}
