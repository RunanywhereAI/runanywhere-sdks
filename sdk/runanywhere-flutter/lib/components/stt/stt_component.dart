import 'dart:async';
import '../../core/components/base_component.dart';
import '../../core/types/sdk_component.dart';
import '../../core/protocols/component/component_configuration.dart';
import '../../core/models/audio_format.dart';
import '../../core/module_registry.dart';
import '../vad/vad_output.dart' show VADOutput;

// Re-export STT types for external consumers
export 'stt_types.dart';

/// Transcription mode for speech-to-text
/// Matches iOS STTMode from STTComponent.swift
enum STTMode {
  /// Batch mode: Record all audio first, then transcribe everything at once
  /// Best for: Short recordings, offline processing, higher accuracy
  batch('batch', 'Batch', 'Record audio, then transcribe all at once'),

  /// Live/Streaming mode: Transcribe audio in real-time as it's recorded
  /// Best for: Live captions, real-time feedback, long recordings
  live('live', 'Live', 'Real-time transcription as you speak');

  final String value;
  final String displayName;
  final String description;

  const STTMode(this.value, this.displayName, this.description);

  static STTMode fromString(String value) {
    return STTMode.values.firstWhere(
      (e) => e.value == value,
      orElse: () => STTMode.batch,
    );
  }
}

/// STT (Speech-to-Text) Component Configuration
/// Matches iOS STTConfiguration from STTComponent.swift
class STTConfiguration implements ComponentConfiguration {
  final String? modelId;
  final String language;
  final int sampleRate;
  final bool enablePunctuation;
  final bool enableDiarization;
  final List<String> vocabularyList;
  final int maxAlternatives;
  final bool enableTimestamps;
  final bool useGPUIfAvailable;

  STTConfiguration({
    this.modelId,
    this.language = 'en-US',
    this.sampleRate = 16000,
    this.enablePunctuation = true,
    this.enableDiarization = false,
    this.vocabularyList = const [],
    this.maxAlternatives = 1,
    this.enableTimestamps = true,
    this.useGPUIfAvailable = true,
  });

  @override
  void validate() {
    if (sampleRate <= 0 || sampleRate > 48000) {
      throw ArgumentError('Sample rate must be between 1 and 48000 Hz');
    }
    if (maxAlternatives <= 0 || maxAlternatives > 10) {
      throw ArgumentError('Max alternatives must be between 1 and 10');
    }
  }
}

/// STT Component Input
/// Matches iOS STTInput from STTComponent.swift
class STTInput implements ComponentInput {
  /// Audio data to transcribe
  final List<int> audioData;

  /// Audio format information
  final AudioFormat format;

  /// Language code override
  final String? language;

  /// Optional VAD output for context
  final VADOutput? vadOutput;

  /// Custom options override
  final STTOptions? options;

  STTInput({
    required this.audioData,
    this.format = AudioFormat.wav,
    this.language,
    this.vadOutput,
    this.options,
  });

  @override
  void validate() {
    if (audioData.isEmpty) {
      throw ArgumentError('STTInput must contain audio data');
    }
  }
}

/// STT Component Output
/// Matches iOS STTOutput from STTComponent.swift
class STTOutput implements ComponentOutput {
  /// Transcribed text
  final String text;

  /// Confidence score (0.0 to 1.0)
  final double confidence;

  /// Word-level timestamps if available
  final List<WordTimestamp>? wordTimestamps;

  /// Detected language if auto-detected
  final String? detectedLanguage;

  /// Alternative transcriptions if available
  final List<TranscriptionAlternative>? alternatives;

  /// Processing metadata
  final TranscriptionMetadata metadata;

  /// Timestamp (required by ComponentOutput)
  @override
  final DateTime timestamp;

  STTOutput({
    required this.text,
    required this.confidence,
    this.wordTimestamps,
    this.detectedLanguage,
    this.alternatives,
    required this.metadata,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Backward compatibility getter
  String get transcript => text;

  /// Backward compatibility getter
  List<STTSegment> get segments {
    if (wordTimestamps == null) return [];
    return wordTimestamps!
        .map((w) => STTSegment(
              text: w.word,
              startTime: w.startTime,
              endTime: w.endTime,
              confidence: w.confidence,
            ))
        .toList();
  }
}

/// STT Segment (backward compatibility)
class STTSegment {
  final String text;
  final double startTime;
  final double endTime;
  final double confidence;
  final int? speaker;

  STTSegment({
    required this.text,
    required this.startTime,
    required this.endTime,
    required this.confidence,
    this.speaker,
  });
}

/// Word timestamp information
/// Matches iOS WordTimestamp from STTComponent.swift
class WordTimestamp {
  final String word;
  final double startTime;
  final double endTime;
  final double confidence;

  WordTimestamp({
    required this.word,
    required this.startTime,
    required this.endTime,
    required this.confidence,
  });

  Map<String, dynamic> toJson() => {
        'word': word,
        'startTime': startTime,
        'endTime': endTime,
        'confidence': confidence,
      };

  factory WordTimestamp.fromJson(Map<String, dynamic> json) => WordTimestamp(
        word: json['word'] as String,
        startTime: (json['startTime'] as num).toDouble(),
        endTime: (json['endTime'] as num).toDouble(),
        confidence: (json['confidence'] as num).toDouble(),
      );
}

/// Alternative transcription
/// Matches iOS TranscriptionAlternative from STTComponent.swift
class TranscriptionAlternative {
  final String text;
  final double confidence;

  TranscriptionAlternative({
    required this.text,
    required this.confidence,
  });
}

/// Transcription metadata
/// Matches iOS TranscriptionMetadata from STTComponent.swift
class TranscriptionMetadata {
  final String modelId;
  final double processingTime;
  final double audioLength;

  TranscriptionMetadata({
    required this.modelId,
    required this.processingTime,
    required this.audioLength,
  });

  /// Processing time / audio length
  double get realTimeFactor =>
      audioLength > 0 ? processingTime / audioLength : 0;
}

/// Errors for STT services
/// Matches iOS STTError from STTComponent.swift
class STTError implements Exception {
  final String message;
  final STTErrorType type;

  STTError(this.message, this.type);

  @override
  String toString() => 'STTError: $message';

  factory STTError.serviceNotInitialized() =>
      STTError('STT service is not initialized', STTErrorType.serviceNotInitialized);

  factory STTError.transcriptionFailed(String reason) =>
      STTError('Transcription failed: $reason', STTErrorType.transcriptionFailed);

  factory STTError.streamingNotSupported() =>
      STTError('Streaming transcription is not supported', STTErrorType.streamingNotSupported);

  factory STTError.languageNotSupported(String language) =>
      STTError('Language not supported: $language', STTErrorType.languageNotSupported);

  factory STTError.modelNotFound(String model) =>
      STTError('Model not found: $model', STTErrorType.modelNotFound);

  factory STTError.audioFormatNotSupported() =>
      STTError('Audio format is not supported', STTErrorType.audioFormatNotSupported);

  factory STTError.insufficientAudioData() =>
      STTError('Insufficient audio data for transcription', STTErrorType.insufficientAudioData);

  factory STTError.noVoiceServiceAvailable() =>
      STTError('No STT service available for transcription', STTErrorType.noVoiceServiceAvailable);

  factory STTError.microphonePermissionDenied() =>
      STTError('Microphone permission was denied', STTErrorType.microphonePermissionDenied);
}

enum STTErrorType {
  serviceNotInitialized,
  transcriptionFailed,
  streamingNotSupported,
  languageNotSupported,
  modelNotFound,
  audioFormatNotSupported,
  insufficientAudioData,
  noVoiceServiceAvailable,
  audioSessionNotConfigured,
  audioSessionActivationFailed,
  microphonePermissionDenied,
}

/// STT Component
/// Matches iOS STTComponent from STTComponent.swift
class STTComponent extends BaseComponent<STTService> {
  @override
  SDKComponent get componentType => SDKComponent.stt;

  final STTConfiguration sttConfig;
  bool _isModelLoaded = false;
  String? _modelPath;

  STTComponent({
    required this.sttConfig,
    super.serviceContainer,
  }) : super(configuration: sttConfig);

  @override
  Future<STTService> createService() async {
    final provider =
        ModuleRegistry.shared.sttProvider(modelId: sttConfig.modelId);
    if (provider == null) {
      throw STTError(
        'No STT service provider registered. Please register a WhisperKit or other STT implementation.',
        STTErrorType.noVoiceServiceAvailable,
      );
    }

    final service = await provider.createSTTService(sttConfig);
    await service.initialize(modelPath: _modelPath);
    _isModelLoaded = true;

    return service;
  }

  @override
  Future<void> performCleanup() async {
    await service?.cleanup();
    _isModelLoaded = false;
    _modelPath = null;
  }

  // MARK: - Capabilities

  /// Whether the underlying service supports live/streaming transcription
  bool get supportsStreaming => service?.supportsStreaming ?? false;

  /// Get the recommended transcription mode based on service capabilities
  STTMode get recommendedMode => supportsStreaming ? STTMode.live : STTMode.batch;

  /// Check if model is loaded
  bool get isModelLoaded => _isModelLoaded;

  // MARK: - Batch Transcription API

  /// Transcribe audio data in batch mode
  Future<STTOutput> transcribe(
    List<int> audioData, {
    STTOptions? options,
  }) async {
    ensureReady();

    final opts = options ?? STTOptions.defaultOptions();
    final input = STTInput(
      audioData: audioData,
      format: opts.audioFormat,
      language: opts.language,
    );

    return process(input);
  }

  /// Transcribe audio data with simple parameters
  Future<STTOutput> transcribeSimple(
    List<int> audioData, {
    AudioFormat format = AudioFormat.wav,
    String? language,
  }) async {
    ensureReady();

    final input = STTInput(
      audioData: audioData,
      format: format,
      language: language,
    );

    return process(input);
  }

  /// Process STT input
  Future<STTOutput> process(STTInput input) async {
    ensureReady();

    final sttService = service;
    if (sttService == null) {
      throw STTError.serviceNotInitialized();
    }

    // Validate input
    input.validate();

    // Create options from input or use defaults
    final options = input.options ??
        STTOptions(
          language: input.language ?? sttConfig.language,
          detectLanguage: input.language == null,
          enablePunctuation: sttConfig.enablePunctuation,
          enableDiarization: sttConfig.enableDiarization,
          enableTimestamps: sttConfig.enableTimestamps,
          vocabularyFilter: sttConfig.vocabularyList,
          sampleRate: sttConfig.sampleRate,
        );

    // Track processing time
    final startTime = DateTime.now();

    // Perform transcription
    final result = await sttService.transcribe(
      audioData: input.audioData,
      options: options,
    );

    final processingTime =
        DateTime.now().difference(startTime).inMilliseconds / 1000.0;

    // Convert timestamps
    final wordTimestamps = result.timestamps
        ?.map((t) => WordTimestamp(
              word: t.word,
              startTime: t.startTime,
              endTime: t.endTime,
              confidence: t.confidence ?? 0.9,
            ))
        .toList();

    // Convert alternatives
    final alternatives = result.alternatives
        ?.map((a) => TranscriptionAlternative(
              text: a.transcript,
              confidence: a.confidence,
            ))
        .toList();

    // Estimate audio length
    final audioLength = _estimateAudioLength(
      input.audioData.length,
      input.format,
      sttConfig.sampleRate,
    );

    final metadata = TranscriptionMetadata(
      modelId: sttService.currentModel ?? 'unknown',
      processingTime: processingTime,
      audioLength: audioLength,
    );

    return STTOutput(
      text: result.transcript,
      confidence: result.confidence ?? 0.9,
      wordTimestamps: wordTimestamps,
      detectedLanguage: result.language,
      alternatives: alternatives,
      metadata: metadata,
    );
  }

  // MARK: - Live/Streaming Transcription API

  /// Live transcription with real-time partial results
  Stream<String> liveTranscribe(
    Stream<List<int>> audioStream, {
    STTOptions? options,
  }) {
    return streamTranscribe(
      audioStream,
      language: options?.language,
    );
  }

  /// Stream transcription
  Stream<String> streamTranscribe(
    Stream<List<int>> audioStream, {
    String? language,
  }) async* {
    ensureReady();

    final sttService = service;
    if (sttService == null) {
      throw STTError.serviceNotInitialized();
    }

    if (!supportsStreaming) {
      // Fallback to batch mode: collect all audio then transcribe
      final allAudio = <int>[];
      await for (final chunk in audioStream) {
        allAudio.addAll(chunk);
      }

      final result = await transcribeSimple(
        allAudio,
        language: language,
      );

      yield result.text;
      return;
    }

    // TODO: Implement actual streaming when provider supports it
    // For now, fall back to batch mode
    final allAudio = <int>[];
    await for (final chunk in audioStream) {
      allAudio.addAll(chunk);
    }

    final result = await transcribeSimple(
      allAudio,
      language: language,
    );

    yield result.text;
  }

  /// Get service for compatibility
  STTService? getService() {
    return service;
  }

  // MARK: - Private Helpers

  double _estimateAudioLength(int dataSize, AudioFormat format, int sampleRate) {
    // Rough estimation based on format and sample rate
    final int bytesPerSample;
    switch (format) {
      case AudioFormat.pcm:
      case AudioFormat.wav:
        bytesPerSample = 2; // 16-bit PCM
        break;
      case AudioFormat.mp3:
        bytesPerSample = 1; // Compressed
        break;
      default:
        bytesPerSample = 2;
    }

    final samples = dataSize ~/ bytesPerSample;
    return samples / sampleRate;
  }
}
