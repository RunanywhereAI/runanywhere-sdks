import 'dart:async';
import 'dart:typed_data';
import '../../core/components/base_component.dart';
import '../../core/types/sdk_component.dart';
import '../../core/protocols/component/component_configuration.dart';
import '../../core/models/audio_format.dart';
import '../../core/module_registry.dart' hide TTSService, TTSOptions;
import 'tts_service.dart';
import 'tts_options.dart';
import 'tts_output.dart';
import 'system_tts_service.dart';

/// TTS (Text-to-Speech) Component Configuration
/// Matches iOS TTSConfiguration from TTSComponent.swift
class TTSConfiguration implements ComponentConfiguration, ComponentInitParameters {
  @override
  String get componentType => SDKComponent.tts.value;

  @override
  final String? modelId;

  // TTS-specific parameters
  final String voice;
  final String language;
  final double speakingRate; // 0.5 to 2.0
  final double pitch; // 0.5 to 2.0
  final double volume; // 0.0 to 1.0
  final AudioFormat audioFormat;
  final bool useNeuralVoice;
  final bool enableSSML;

  TTSConfiguration({
    this.modelId,
    this.voice = 'system',
    this.language = 'en-US',
    this.speakingRate = 1.0,
    this.pitch = 1.0,
    this.volume = 1.0,
    this.audioFormat = AudioFormat.pcm,
    this.useNeuralVoice = true,
    this.enableSSML = false,
  });

  @override
  void validate() {
    if (speakingRate < 0.5 || speakingRate > 2.0) {
      throw ArgumentError('Speaking rate must be between 0.5 and 2.0');
    }
    if (pitch < 0.5 || pitch > 2.0) {
      throw ArgumentError('Pitch must be between 0.5 and 2.0');
    }
    if (volume < 0.0 || volume > 1.0) {
      throw ArgumentError('Volume must be between 0.0 and 1.0');
    }
  }
}

/// Input for Text-to-Speech (conforms to ComponentInput protocol)
/// Matches iOS TTSInput from TTSComponent.swift
class TTSInput implements ComponentInput {
  /// Text to synthesize
  final String text;

  /// Optional SSML markup (overrides text if provided)
  final String? ssml;

  /// Voice ID override
  final String? voiceId;

  /// Language override
  final String? language;

  /// Custom options override
  final TTSOptions? options;

  TTSInput({
    required this.text,
    this.ssml,
    this.voiceId,
    this.language,
    this.options,
  });

  @override
  void validate() {
    if (text.isEmpty && ssml == null) {
      throw ArgumentError('TTSInput must contain either text or SSML');
    }
  }
}

/// TTS Component
/// Matches iOS TTSComponent from TTSComponent.swift
class TTSComponent extends BaseComponent<TTSService> {
  @override
  SDKComponent get componentType => SDKComponent.tts;

  final TTSConfiguration ttsConfiguration;
  String? currentVoice;

  TTSComponent({
    required this.ttsConfiguration,
    super.serviceContainer,
  })  : currentVoice = ttsConfiguration.voice,
        super(configuration: ttsConfiguration);

  @override
  Future<TTSService> createService() async {
    final modelId = ttsConfiguration.voice;

    // Try to get a registered TTS provider from central registry
    final provider = ModuleRegistry.shared.ttsProvider(modelId: modelId);

    TTSService ttsService;

    if (provider != null) {
      // Use registered provider (e.g., ONNX TTS or other providers)
      final service = await provider.createTTSService(ttsConfiguration);
      if (service is! TTSService) {
        throw StateError('Provider returned invalid service type');
      }
      ttsService = service;
    } else {
      // Fallback to system TTS
      ttsService = SystemTTSService();
      await ttsService.initialize();
    }

    return ttsService;
  }

  @override
  Future<void> initializeService() async {
    final service = this.service;
    if (service == null) return;

    await service.initialize();
  }

  // MARK: - Public API

  /// Synthesize speech from text
  Future<TTSOutput> synthesize(
    String text, {
    String? voice,
    String? language,
  }) async {
    ensureReady();

    final input = TTSInput(
      text: text,
      voiceId: voice,
      language: language,
    );
    return await process(input);
  }

  /// Synthesize with SSML markup
  Future<TTSOutput> synthesizeSSML(
    String ssml, {
    String? voice,
    String? language,
  }) async {
    ensureReady();

    final input = TTSInput(
      text: '',
      ssml: ssml,
      voiceId: voice,
      language: language,
    );
    return await process(input);
  }

  /// Process TTS input
  Future<TTSOutput> process(TTSInput input) async {
    ensureReady();

    final ttsService = service;
    if (ttsService == null) {
      throw StateError('TTS service not available');
    }

    // Validate input
    input.validate();

    // Get text to synthesize
    final textToSynthesize = input.ssml ?? input.text;

    // Create options from input or use defaults
    final options = input.options ??
        TTSOptions(
          voice: input.voiceId ?? ttsConfiguration.voice,
          language: input.language ?? ttsConfiguration.language,
          rate: ttsConfiguration.speakingRate,
          pitch: ttsConfiguration.pitch,
          volume: ttsConfiguration.volume,
          audioFormat: ttsConfiguration.audioFormat,
          sampleRate: ttsConfiguration.audioFormat == AudioFormat.pcm ? 16000 : 44100,
          useSSML: input.ssml != null,
        );

    // Track processing time
    final startTime = DateTime.now();

    // Perform synthesis
    final audioData = await ttsService.synthesize(
      text: textToSynthesize,
      options: options,
    );

    final processingTime = DateTime.now().difference(startTime).inMilliseconds / 1000.0;

    // Calculate audio duration (estimate)
    final duration = _estimateAudioDuration(
      audioData.length,
      ttsConfiguration.audioFormat,
    );

    final metadata = SynthesisMetadata(
      voice: options.voice ?? ttsConfiguration.voice,
      language: options.language,
      processingTime: processingTime,
      characterCount: textToSynthesize.length,
    );

    return TTSOutput(
      audioData: audioData,
      format: ttsConfiguration.audioFormat,
      duration: duration,
      phonemeTimestamps: null, // Would be extracted from service if available
      metadata: metadata,
    );
  }

  /// Stream synthesis for long text
  Stream<Uint8List> streamSynthesize(
    String text, {
    String? voice,
    String? language,
  }) async* {
    ensureReady();

    final ttsService = service;
    if (ttsService == null) {
      throw StateError('TTS service not available');
    }

    final options = TTSOptions(
      voice: voice ?? ttsConfiguration.voice,
      language: language ?? ttsConfiguration.language,
      rate: ttsConfiguration.speakingRate,
      pitch: ttsConfiguration.pitch,
      volume: ttsConfiguration.volume,
      audioFormat: ttsConfiguration.audioFormat,
      sampleRate: 16000,
      useSSML: false,
    );

    // Use a list to collect chunks since we need to yield them
    final chunks = <Uint8List>[];
    await ttsService.synthesizeStream(
      text: text,
      options: options,
      onChunk: (chunk) {
        chunks.add(chunk);
      },
    );

    // Yield all collected chunks
    for (final chunk in chunks) {
      yield chunk;
    }
  }

  /// Get available voices
  List<String> getAvailableVoices() {
    return service?.availableVoices ?? [];
  }

  /// Stop current synthesis
  void stopSynthesis() {
    service?.stop();
  }

  /// Check if currently synthesizing
  bool get isSynthesizing {
    return service?.isSynthesizing ?? false;
  }

  /// Get service for compatibility
  TTSService? getService() {
    return service;
  }

  // MARK: - Cleanup

  @override
  Future<void> performCleanup() async {
    service?.stop();
    await service?.cleanup();
    currentVoice = null;
  }

  // MARK: - Private Helpers

  double _estimateAudioDuration(int dataSize, AudioFormat format) {
    // Rough estimation based on format and typical bitrates
    final int bytesPerSecond;
    switch (format) {
      case AudioFormat.pcm:
      case AudioFormat.wav:
        bytesPerSecond = 32000; // 16-bit PCM at 16kHz
        break;
      case AudioFormat.mp3:
        bytesPerSecond = 16000; // 128kbps MP3
        break;
      default:
        bytesPerSecond = 32000;
    }

    return dataSize / bytesPerSecond;
  }
}
