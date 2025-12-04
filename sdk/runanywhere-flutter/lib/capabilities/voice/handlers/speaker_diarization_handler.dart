/// Speaker Diarization Handler for Voice Pipeline
///
/// Handles speaker diarization processing in the voice pipeline.
/// Matches iOS SpeakerDiarizationHandler from Capabilities/Voice/Handlers/SpeakerDiarizationHandler.swift.
library speaker_diarization_handler;

import 'dart:async';

import '../../../components/speaker_diarization/speaker_diarization_component.dart'
    show SpeakerInfo;
import '../../../foundation/logging/sdk_logger.dart';
import '../models/modular_pipeline_event.dart';

/// Protocol for speaker diarization services used by the handler
/// This is the simplified protocol for voice pipeline integration
abstract class HandlerSpeakerDiarizationService {
  /// Process audio samples to identify speaker
  SpeakerInfo processAudio(List<double> samples);

  /// Get all detected speakers
  List<SpeakerInfo> getAllSpeakers();
}

/// Handles speaker diarization processing in the voice pipeline
/// Matches iOS SpeakerDiarizationHandler from Capabilities/Voice/Handlers/SpeakerDiarizationHandler.swift
class SpeakerDiarizationHandler {
  final SDKLogger _logger = SDKLogger(category: 'SpeakerDiarizationHandler');

  /// Creates a new speaker diarization handler
  SpeakerDiarizationHandler();

  /// Detect speaker from audio samples
  /// - Parameters:
  ///   - samples: Audio samples to analyze
  ///   - service: Speaker diarization service
  ///   - sampleRate: Audio sample rate (default 16000)
  /// - Returns: Detected speaker information
  SpeakerInfo detectSpeaker({
    required List<double> samples,
    required HandlerSpeakerDiarizationService service,
    int sampleRate = 16000,
  }) {
    // Process audio to identify speaker
    return service.processAudio(samples);
  }

  /// Handle speaker change detection and notification
  /// - Parameters:
  ///   - previous: Previous speaker (if any)
  ///   - current: Current speaker
  ///   - streamController: Event stream controller to yield events
  void handleSpeakerChange({
    SpeakerInfo? previous,
    required SpeakerInfo current,
    required StreamController<ModularPipelineEvent> streamController,
  }) {
    if (previous?.id != current.id) {
      streamController.add(STTSpeakerChangedEvent(from: previous, to: current));
      _logger.info(
        'Speaker changed from ${previous?.name ?? previous?.id ?? "unknown"} to ${current.name ?? current.id}',
      );
    }
  }

  /// Emit transcript with speaker information
  /// - Parameters:
  ///   - transcript: The transcript text
  ///   - speaker: Speaker information
  ///   - streamController: Event stream controller to yield events
  void emitTranscriptWithSpeaker({
    required String transcript,
    required SpeakerInfo speaker,
    required StreamController<ModularPipelineEvent> streamController,
  }) {
    streamController.add(STTFinalTranscriptWithSpeakerEvent(transcript, speaker));
    _logger.info("Transcript with speaker ${speaker.name ?? speaker.id}: '$transcript'");
  }
}
