import 'dart:async';
import 'dart:typed_data';

import '../../core/components/base_component.dart';
import '../../core/types/sdk_component.dart';
import '../../core/types/component_state.dart';
import '../../core/protocols/component/component_configuration.dart';
import '../../core/module_registry.dart' as core
    show ModuleRegistry, SpeakerDiarizationService;
import '../../public/events/component_initialization_event.dart';
import '../stt/stt_component.dart' show STTOutput, WordTimestamp;

export '../../core/module_registry.dart' show SpeakerDiarizationService;

// MARK: - Audio Format

/// Audio format for diarization
enum AudioFormat {
  wav,
  mp3,
  m4a,
  raw,
}

// MARK: - Speaker Diarization Configuration

/// Configuration for Speaker Diarization component
/// Matches iOS SpeakerDiarizationConfiguration from SpeakerDiarizationComponent.swift
class SpeakerDiarizationConfiguration implements ComponentConfiguration {
  /// Model ID (if using ML-based diarization)
  final String? modelId;

  /// Maximum number of speakers to detect
  final int maxSpeakers;

  /// Minimum speech duration in seconds
  final double minSpeechDuration;

  /// Speaker change threshold (0.0 to 1.0)
  final double speakerChangeThreshold;

  /// Whether to enable voice identification
  final bool enableVoiceIdentification;

  /// Window size for processing in seconds
  final double windowSize;

  /// Step size for processing in seconds
  final double stepSize;

  SpeakerDiarizationConfiguration({
    this.modelId,
    this.maxSpeakers = 10,
    this.minSpeechDuration = 0.5,
    this.speakerChangeThreshold = 0.7,
    this.enableVoiceIdentification = false,
    this.windowSize = 2.0,
    this.stepSize = 0.5,
  });

  @override
  void validate() {
    if (maxSpeakers <= 0 || maxSpeakers > 100) {
      throw ArgumentError('Max speakers must be between 1 and 100');
    }
    if (minSpeechDuration <= 0 || minSpeechDuration > 10) {
      throw ArgumentError(
          'Min speech duration must be between 0 and 10 seconds');
    }
    if (speakerChangeThreshold < 0 || speakerChangeThreshold > 1.0) {
      throw ArgumentError('Speaker change threshold must be between 0 and 1');
    }
  }
}

// MARK: - Speaker Diarization Input/Output Models

/// Information about a detected speaker
class SpeakerInfo {
  final String id;
  String? name;
  final double? confidence;
  final List<double>? embedding;

  SpeakerInfo({
    required this.id,
    this.name,
    this.confidence,
    this.embedding,
  });
}

/// Input for Speaker Diarization
/// Matches iOS SpeakerDiarizationInput from SpeakerDiarizationComponent.swift
class SpeakerDiarizationInput implements ComponentInput {
  /// Audio data to diarize
  final Uint8List audioData;

  /// Audio format
  final AudioFormat format;

  /// Optional transcription for labeled output
  final STTOutput? transcription;

  /// Expected number of speakers (if known)
  final int? expectedSpeakers;

  /// Custom options
  final SpeakerDiarizationOptions? options;

  SpeakerDiarizationInput({
    required this.audioData,
    this.format = AudioFormat.wav,
    this.transcription,
    this.expectedSpeakers,
    this.options,
  });

  @override
  void validate() {
    if (audioData.isEmpty) {
      throw ArgumentError('Audio data cannot be empty');
    }
  }
}

/// Output from Speaker Diarization
/// Matches iOS SpeakerDiarizationOutput from SpeakerDiarizationComponent.swift
class SpeakerDiarizationOutput implements ComponentOutput {
  /// Speaker segments
  final List<SpeakerSegment> segments;

  /// Speaker profiles
  final List<SpeakerProfile> speakers;

  /// Labeled transcription (if STT output was provided)
  final LabeledTranscription? labeledTranscription;

  /// Processing metadata
  final DiarizationMetadata metadata;

  /// Timestamp (required by ComponentOutput)
  @override
  final DateTime timestamp;

  SpeakerDiarizationOutput({
    required this.segments,
    required this.speakers,
    this.labeledTranscription,
    required this.metadata,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Speaker segment
class SpeakerSegment {
  final String speakerId;
  final double startTime;
  final double endTime;
  final double confidence;

  double get duration => endTime - startTime;

  SpeakerSegment({
    required this.speakerId,
    required this.startTime,
    required this.endTime,
    required this.confidence,
  });
}

/// Speaker profile
class SpeakerProfile {
  final String id;
  final List<double>? embedding;
  final double totalSpeakingTime;
  final int segmentCount;
  final String? name;

  SpeakerProfile({
    required this.id,
    this.embedding,
    required this.totalSpeakingTime,
    required this.segmentCount,
    this.name,
  });
}

/// Labeled transcription with speaker information
class LabeledTranscription {
  final List<LabeledSegment> segments;

  LabeledTranscription({required this.segments});

  /// Get full transcript as formatted text
  String get formattedTranscript =>
      segments.map((s) => '[${s.speakerId}]: ${s.text}').join('\n');
}

/// Labeled segment with speaker information
class LabeledSegment {
  final String speakerId;
  final String text;
  final double startTime;
  final double endTime;

  LabeledSegment({
    required this.speakerId,
    required this.text,
    required this.startTime,
    required this.endTime,
  });
}

/// Diarization metadata
class DiarizationMetadata {
  final double processingTime;
  final double audioLength;
  final int speakerCount;
  final String method; // "energy", "ml", "hybrid"

  DiarizationMetadata({
    required this.processingTime,
    required this.audioLength,
    required this.speakerCount,
    required this.method,
  });
}

/// Options for speaker diarization
class SpeakerDiarizationOptions {
  final int maxSpeakers;
  final double minSpeechDuration;
  final double speakerChangeThreshold;

  SpeakerDiarizationOptions({
    this.maxSpeakers = 10,
    this.minSpeechDuration = 0.5,
    this.speakerChangeThreshold = 0.7,
  });
}

/// Errors for Speaker Diarization services
class SpeakerDiarizationError implements Exception {
  final String message;
  final SpeakerDiarizationErrorType type;

  SpeakerDiarizationError(this.message, this.type);

  @override
  String toString() => 'SpeakerDiarizationError: $message';
}

enum SpeakerDiarizationErrorType {
  notInitialized,
  modelNotFound,
  processingFailed,
  audioInvalid,
  tooManySpeakers,
}

// MARK: - Speaker Diarization Component

/// Speaker Diarization Component
/// Matches iOS SpeakerDiarizationComponent from SpeakerDiarizationComponent.swift
class SpeakerDiarizationComponent
    extends BaseComponent<core.SpeakerDiarizationService> {
  @override
  SDKComponent get componentType => SDKComponent.speakerDiarization;

  final SpeakerDiarizationConfiguration diarizationConfig;
  final Map<String, SpeakerProfile> _speakerProfiles = {};

  /// Whether the service is ready for use
  bool get isServiceReady => state == ComponentState.ready;

  SpeakerDiarizationComponent({
    required this.diarizationConfig,
    super.serviceContainer,
  }) : super(configuration: diarizationConfig);

  @override
  Future<core.SpeakerDiarizationService> createService() async {
    // Emit checking event
    eventBus.publish(ComponentInitializationEvent.componentChecking(
      component: componentType,
      modelId: diarizationConfig.modelId,
    ));

    // Check if model needs downloading (for ML-based diarization)
    // Model download support will be added when ML-based providers are available
    if (diarizationConfig.modelId != null) {
      final needsDownload = await _checkNeedsDownload(diarizationConfig.modelId!);
      if (needsDownload) {
        eventBus.publish(ComponentInitializationEvent.componentDownloadRequired(
          component: componentType,
          modelId: diarizationConfig.modelId!,
          sizeBytes: 100000000, // 100MB example
        ));

        await _downloadModel(diarizationConfig.modelId!);
      }
    }

    // Try to get a registered speaker diarization provider
    final provider = core.ModuleRegistry.shared
        .speakerDiarizationProvider(modelId: diarizationConfig.modelId);
    if (provider == null) {
      throw SpeakerDiarizationError(
        'Speaker diarization service requires an external implementation. '
        'Please add a diarization provider as a dependency and register it '
        'with ModuleRegistry.shared.registerSpeakerDiarization(provider).',
        SpeakerDiarizationErrorType.notInitialized,
      );
    }

    final service =
        await provider.createSpeakerDiarizationService(diarizationConfig);
    await service.initialize(modelPath: diarizationConfig.modelId);

    return service;
  }

  @override
  Future<void> initializeService() async {
    // Track initialization
    eventBus.publish(ComponentInitializationEvent.componentInitializing(
      component: componentType,
      modelId: diarizationConfig.modelId,
    ));
    // Service readiness is tracked by base class state
  }

  /// Check if model needs to be downloaded
  /// Currently returns false - will be implemented when ML providers are available
  Future<bool> _checkNeedsDownload(String modelId) async {
    // In real implementation, check if model file exists on disk
    return false;
  }

  Future<void> _downloadModel(String modelId) async {
    eventBus.publish(ComponentInitializationEvent.componentDownloadStarted(
      component: componentType,
      modelId: modelId,
    ));

    // Simulate download
    for (double progress = 0.0; progress <= 1.0; progress += 0.2) {
      eventBus.publish(ComponentInitializationEvent.componentDownloadProgress(
        component: componentType,
        modelId: modelId,
        progress: progress,
      ));
      await Future.delayed(const Duration(milliseconds: 100));
    }

    eventBus.publish(ComponentInitializationEvent.componentDownloadCompleted(
      component: componentType,
      modelId: modelId,
    ));
  }

  @override
  Future<void> performCleanup() async {
    _speakerProfiles.clear();
    await service?.cleanup();
  }

  // MARK: - Public API

  /// Diarize audio to identify speakers
  Future<SpeakerDiarizationOutput> diarize(
    Uint8List audioData, {
    AudioFormat format = AudioFormat.wav,
  }) async {
    ensureReady();

    final input = SpeakerDiarizationInput(audioData: audioData, format: format);
    return process(input);
  }

  /// Diarize with transcription for labeled output
  Future<SpeakerDiarizationOutput> diarizeWithTranscription(
    Uint8List audioData,
    STTOutput transcription, {
    AudioFormat format = AudioFormat.wav,
  }) async {
    ensureReady();

    final input = SpeakerDiarizationInput(
      audioData: audioData,
      format: format,
      transcription: transcription,
    );
    return process(input);
  }

  /// Process diarization input
  Future<SpeakerDiarizationOutput> process(
    SpeakerDiarizationInput input,
  ) async {
    ensureReady();

    final diarizationService = service;
    if (diarizationService == null) {
      throw SpeakerDiarizationError(
        'Speaker diarization service not available',
        SpeakerDiarizationErrorType.notInitialized,
      );
    }

    // Validate input
    input.validate();

    // Track processing time
    final startTime = DateTime.now();

    // Convert audio data to int list for processing
    final audioSamples = input.audioData.toList();

    // Process audio to detect speakers
    await diarizationService.process(audioSamples);

    // Build segments (simple mock - real implementation would use service result)
    final segments = <SpeakerSegment>[];
    const sampleRate = 16000;
    final totalDuration = audioSamples.length / sampleRate;
    var currentTime = 0.0;

    while (currentTime < totalDuration) {
      final endTime = (currentTime + diarizationConfig.windowSize)
          .clamp(0.0, totalDuration);
      segments.add(SpeakerSegment(
        speakerId: 'speaker_1',
        startTime: currentTime,
        endTime: endTime,
        confidence: 0.8,
      ));
      currentTime = endTime;
    }

    // Build speaker profiles
    final speakerIds = segments.map((s) => s.speakerId).toSet();
    final profiles = speakerIds.map((id) {
      final speakerSegments = segments.where((s) => s.speakerId == id);
      final totalTime =
          speakerSegments.fold(0.0, (sum, s) => sum + s.duration);
      return SpeakerProfile(
        id: id,
        embedding: null,
        totalSpeakingTime: totalTime,
        segmentCount: speakerSegments.length,
        name: null,
      );
    }).toList();

    // Store profiles
    for (final profile in profiles) {
      _speakerProfiles[profile.id] = profile;
    }

    // Create labeled transcription if provided
    LabeledTranscription? labeledTranscription;
    if (input.transcription?.wordTimestamps != null) {
      labeledTranscription = _createLabeledTranscription(
        input.transcription!.wordTimestamps!,
        segments,
      );
    }

    final processingTime =
        DateTime.now().difference(startTime).inMilliseconds / 1000.0;

    final metadata = DiarizationMetadata(
      processingTime: processingTime,
      audioLength: totalDuration,
      speakerCount: profiles.length,
      method: diarizationConfig.modelId != null ? 'ml' : 'energy',
    );

    return SpeakerDiarizationOutput(
      segments: segments,
      speakers: profiles,
      labeledTranscription: labeledTranscription,
      metadata: metadata,
    );
  }

  /// Get stored speaker profile
  SpeakerProfile? getSpeakerProfile(String id) {
    return _speakerProfiles[id];
  }

  /// Reset speaker profiles
  void resetProfiles() {
    _speakerProfiles.clear();
  }

  /// Get service for compatibility
  core.SpeakerDiarizationService? getService() {
    return service;
  }

  // MARK: - Private Helpers

  LabeledTranscription _createLabeledTranscription(
    List<WordTimestamp> wordTimestamps,
    List<SpeakerSegment> segments,
  ) {
    final labeledSegments = <LabeledSegment>[];
    var currentText = '';
    var currentSpeaker = '';
    var segmentStart = 0.0;

    for (final word in wordTimestamps) {
      // Find which speaker this word belongs to
      final speaker = segments
              .where((segment) =>
                  word.startTime >= segment.startTime &&
                  word.endTime <= segment.endTime)
              .firstOrNull
              ?.speakerId ??
          'unknown';

      if (speaker != currentSpeaker && currentText.isNotEmpty) {
        // Save previous segment
        labeledSegments.add(LabeledSegment(
          speakerId: currentSpeaker,
          text: currentText.trim(),
          startTime: segmentStart,
          endTime: word.startTime,
        ));
        currentText = '';
        segmentStart = word.startTime;
      }

      currentSpeaker = speaker;
      if (currentText.isEmpty) {
        segmentStart = word.startTime;
      }
      currentText += ' ${word.word}';
    }

    // Add final segment
    if (currentText.isNotEmpty) {
      labeledSegments.add(LabeledSegment(
        speakerId: currentSpeaker,
        text: currentText.trim(),
        startTime: segmentStart,
        endTime: wordTimestamps.last.endTime,
      ));
    }

    return LabeledTranscription(segments: labeledSegments);
  }
}
