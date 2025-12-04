/// STT Handler
///
/// Handles Speech-to-Text processing in the voice pipeline.
/// Matches iOS STTHandler.swift from Capabilities/Voice/Handlers/
library stt_handler;

import 'dart:async';
import 'dart:typed_data';

import '../../../foundation/logging/sdk_logger.dart';
import '../../../core/module_registry.dart' show STTService;
import '../../../components/stt/stt_component.dart' show STTOptions;
import '../../../components/speaker_diarization/speaker_diarization_component.dart'
    show SpeakerInfo;
import '../models/modular_pipeline_event.dart';

/// Result from STT processing
/// Matches iOS STTResult from STTHandler.swift
class STTResult {
  final String text;
  final List<STTSegment> segments;
  final String? language;
  final double confidence;
  final double duration;
  final List<STTAlternative> alternatives;

  STTResult({
    required this.text,
    this.segments = const [],
    this.language,
    required this.confidence,
    required this.duration,
    this.alternatives = const [],
  });
}

/// STT Segment with timing
class STTSegment {
  final String text;
  final double startTime;
  final double endTime;
  final double confidence;

  STTSegment({
    required this.text,
    required this.startTime,
    required this.endTime,
    required this.confidence,
  });
}

/// Alternative transcription
class STTAlternative {
  final String text;
  final double confidence;

  STTAlternative({
    required this.text,
    required this.confidence,
  });
}

/// Speaker Diarization Service Protocol
/// Matches iOS SpeakerDiarizationService protocol from STTHandler.swift
abstract class SpeakerDiarizationService {
  /// Process audio samples to identify speaker
  SpeakerInfo processAudio(List<double> samples);

  /// Get all detected speakers
  List<SpeakerInfo> getAllSpeakers();
}

/// Handles Speech-to-Text processing in the voice pipeline
/// Matches iOS STTHandler class from STTHandler.swift
class STTHandler {
  final SDKLogger _logger = SDKLogger(category: 'STTHandler');

  STTHandler();

  /// Transcribe audio samples to text
  Future<String> transcribeAudio({
    required List<double> samples,
    required STTService service,
    required STTOptions options,
    SpeakerDiarizationService? speakerDiarization,
    required StreamController<ModularPipelineEvent> continuation,
  }) async {
    if (samples.isEmpty) {
      _logger.debug('transcribeAudio called with empty samples, skipping');
      return '';
    }

    _logger.debug('Starting transcription with ${samples.length} samples');

    // Calculate audio length assuming 16kHz sample rate
    final audioLength = samples.length / 16000.0;

    final startTime = DateTime.now();

    try {
      // Get transcription result
      final result = await _performTranscription(
        samples: samples,
        service: service,
        options: options,
      );

      final endTime = DateTime.now();
      final duration = endTime.difference(startTime).inMilliseconds / 1000.0;

      final transcript = result.text;
      _logger.info('STT transcription result: \'$transcript\'');

      if (transcript.isNotEmpty) {
        // Track metrics
        final wordCount = transcript.split(' ').length;
        final confidence = result.confidence;

        _logger.debug(
          'Transcription stats: duration=${duration}s, words=$wordCount, '
          'confidence=$confidence, audioLength=${audioLength}s',
        );

        // Handle speaker diarization if available
        if (speakerDiarization != null && options.enableDiarization) {
          _handleSpeakerDiarization(
            samples: samples,
            transcript: transcript,
            service: speakerDiarization,
            continuation: continuation,
          );
        } else {
          // Regular transcript without speaker info
          continuation.add(STTFinalTranscriptEvent(transcript));
        }

        return transcript;
      } else {
        _logger.warning('STT returned empty transcript');
        return '';
      }
    } catch (e) {
      _logger.error('STT transcription failed: $e');
      rethrow;
    }
  }

  /// Perform the actual transcription
  Future<STTResult> _performTranscription({
    required List<double> samples,
    required STTService service,
    required STTOptions options,
  }) async {
    // Convert double array to byte data for STT service
    _logger.debug('Converting ${samples.length} float samples to Data');
    final audioData = _convertAudioFormat(samples);
    _logger.debug('Calling STT.transcribe with ${audioData.length} bytes');

    final result = await service.transcribe(
      audioData: audioData,
      options: options,
    );

    // Convert STTTranscriptionResult to STTResult
    final segments = result.timestamps
            ?.map((timestamp) => STTSegment(
                  text: timestamp.word,
                  startTime: timestamp.startTime,
                  endTime: timestamp.endTime,
                  confidence: timestamp.confidence ?? 0.95,
                ))
            .toList() ??
        [];

    final alternatives = result.alternatives
            ?.map((alt) => STTAlternative(
                  text: alt.transcript,
                  confidence: alt.confidence,
                ))
            .toList() ??
        [];

    return STTResult(
      text: result.transcript,
      segments: segments,
      language: result.language,
      confidence: result.confidence ?? 0.95,
      duration: segments.isNotEmpty ? segments.last.endTime : 0,
      alternatives: alternatives,
    );
  }

  /// Convert float samples to byte data
  List<int> _convertAudioFormat(List<double> samples) {
    // Convert to Float32List then to bytes
    final float32List = Float32List.fromList(
      samples.map((s) => s.toDouble()).toList(),
    );
    return float32List.buffer.asUint8List().toList();
  }

  /// Handle speaker diarization for the transcript
  void _handleSpeakerDiarization({
    required List<double> samples,
    required String transcript,
    required SpeakerDiarizationService service,
    required StreamController<ModularPipelineEvent> continuation,
  }) {
    // Process audio to identify speaker
    final speaker = service.processAudio(samples);

    // Get all speakers to check if speaker changed
    final allSpeakers = service.getAllSpeakers();
    final previousSpeaker =
        allSpeakers.length > 1 ? allSpeakers[allSpeakers.length - 2] : null;

    if (previousSpeaker?.id != speaker.id) {
      continuation.add(STTSpeakerChangedEvent(
        from: previousSpeaker,
        to: speaker,
      ));
    }

    // Emit transcript with speaker info
    continuation.add(STTFinalTranscriptWithSpeakerEvent(transcript, speaker));
    _logger.info(
      'Transcript with speaker ${speaker.name ?? speaker.id}: \'$transcript\'',
    );
  }
}
