import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../../core/capabilities_base/base_capability.dart';
import '../../core/types/sdk_component.dart';
import '../../core/protocols/component/component_configuration.dart';
import '../../core/models/audio_format.dart';
import '../../core/module_registry.dart' hide TTSService, TTSOptions;
import '../../foundation/dependency_injection/service_container.dart';
import 'tts_service.dart';
import 'tts_options.dart';
import 'tts_output.dart';
import 'system_tts_service.dart';

/// TTS (Text-to-Speech) Component Configuration
/// Matches iOS TTSConfiguration from TTSComponent.swift
class TTSConfiguration
    implements ComponentConfiguration, ComponentInitParameters {
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
  /// Text to synthesize (optional if SSML is provided)
  final String? text;

  /// Optional SSML markup (overrides text if provided)
  final String? ssml;

  /// Voice ID override
  final String? voiceId;

  /// Language override
  final String? language;

  /// Custom options override
  final TTSOptions? options;

  TTSInput({
    this.text,
    this.ssml,
    this.voiceId,
    this.language,
    this.options,
  });

  @override
  void validate() {
    if ((text == null || text!.isEmpty) && ssml == null) {
      throw ArgumentError('TTSInput must contain either text or SSML');
    }
  }
}

/// TTS Capability
/// Matches iOS TTSCapability from TTSCapability.swift
class TTSCapability extends BaseCapability<TTSService> {
  @override
  SDKComponent get componentType => SDKComponent.tts;

  final TTSConfiguration ttsConfiguration;
  String? currentVoice;
  String? _modelPath;

  /// Whether a voice/model is currently loaded
  bool _isVoiceLoaded = false;

  TTSCapability({
    required this.ttsConfiguration,
    super.serviceContainer,
  })  : currentVoice = ttsConfiguration.voice,
        super(configuration: ttsConfiguration);

  /// Whether a voice/model is currently loaded.
  /// Matches iOS TTSCapability.isVoiceLoaded property.
  bool get isVoiceLoaded => _isVoiceLoaded && service != null;

  /// Alias for isVoiceLoaded to match ModelLoadableCapability pattern.
  /// Matches iOS TTSCapability.isModelLoaded property.
  bool get isModelLoaded => isVoiceLoaded;

  /// Currently loaded voice ID.
  /// Matches iOS TTSCapability.currentVoiceId property.
  String? get currentVoiceId => currentVoice;

  /// Alias for currentVoiceId to match ModelLoadableCapability pattern.
  /// Matches iOS TTSCapability.currentModelId property.
  String? get currentModelId => currentVoiceId;

  /// Load a voice by ID.
  /// Matches iOS TTSCapability.loadVoice(_:) method.
  ///
  /// [voiceId] - The voice identifier to load.
  Future<void> loadVoice(String voiceId) async {
    currentVoice = voiceId;
    _isVoiceLoaded = true;
  }

  /// Load a model by ID (alias for loadVoice for parity with other capabilities).
  /// Matches iOS TTSCapability.loadModel(_:) method.
  ///
  /// [modelId] - The model/voice identifier to load.
  Future<void> loadModel(String modelId) async {
    await loadVoice(modelId);
  }

  /// Unload the currently loaded voice/model.
  /// Matches iOS TTSCapability.unload() method.
  Future<void> unload() async {
    currentVoice = null;
    _isVoiceLoaded = false;
  }

  @override
  Future<TTSService> createService() async {
    // Get model info from registry to get the actual model path
    final registry = serviceContainer?.modelRegistry ??
        ServiceContainer.shared.modelRegistry;
    final modelId = ttsConfiguration.modelId;

    debugPrint('[TTSComponent] createService() - modelId: $modelId');

    if (modelId != null) {
      final modelInfo = registry.getModel(modelId);
      debugPrint(
          '[TTSComponent] modelInfo from registry: ${modelInfo != null ? "found" : "NOT FOUND"}');

      if (modelInfo != null && modelInfo.localPath != null) {
        // Use the model's local path (handles nested directories for ONNX)
        // For ONNX models, the path might be a directory containing the .onnx file
        final localPath = modelInfo.localPath!.toFilePath();
        debugPrint('[TTSComponent] localPath from modelInfo: $localPath');

        // Check if it's a directory (ONNX models in nested dirs)
        final pathFile = File(localPath);
        final pathDir = Directory(localPath);

        final dirExists = await pathDir.exists();
        final fileExists = await pathFile.exists();
        debugPrint(
            '[TTSComponent] Path check - dirExists: $dirExists, fileExists: $fileExists');

        if (dirExists) {
          // It's a directory - ONNX models are stored in directories
          // The native backend will find the .onnx file inside
          _modelPath = localPath;
          debugPrint('[TTSComponent] Using directory path: $_modelPath');
        } else if (fileExists) {
          // It's a file - use it directly
          _modelPath = localPath;
          debugPrint('[TTSComponent] Using file path: $_modelPath');
        } else {
          // Path doesn't exist, fallback to modelId
          _modelPath = modelId;
          debugPrint(
              '[TTSComponent] Path not found, falling back to modelId: $_modelPath');
        }
      } else {
        // Fallback: use modelId as path (for built-in models or if not found)
        _modelPath = modelId;
        debugPrint(
            '[TTSComponent] modelInfo.localPath is null, falling back to modelId: $_modelPath');
      }
    } else {
      debugPrint('[TTSComponent] ERROR: modelId is null!');
    }

    debugPrint('[TTSComponent] Final _modelPath: $_modelPath');

    // Try to get a registered TTS provider from central registry
    final provider = ModuleRegistry.shared.ttsProvider(modelId: modelId);
    debugPrint(
        '[TTSComponent] TTS provider from registry: ${provider != null ? "found" : "NOT FOUND"}');

    TTSService ttsService;

    if (provider != null) {
      // Use registered provider (e.g., ONNX TTS or other providers)
      debugPrint('[TTSComponent] Creating TTS service from provider...');
      final service = await provider.createTTSService(ttsConfiguration);
      if (service is! TTSService) {
        throw StateError('Provider returned invalid service type');
      }
      // Initialize with model path
      debugPrint(
          '[TTSComponent] Initializing service with modelPath: $_modelPath');
      await service.initialize(modelPath: _modelPath);
      ttsService = service;
    } else {
      // Fallback to system TTS
      debugPrint('[TTSComponent] No provider, falling back to SystemTTS');
      ttsService = SystemTTSService();
      await ttsService.initialize();
    }

    return ttsService;
  }

  @override
  Future<void> initializeService() async {
    final service = this.service;
    if (service == null) return;

    // Service is already initialized in createService() with the model path
    // Don't call initialize() again as it would clear the loaded model
    // await service.initialize();
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

    // Get text to synthesize (prioritize SSML, then text, then empty string)
    final String textToSynthesize = input.ssml ?? input.text ?? '';

    // Create options from input or use defaults
    final options = input.options ??
        TTSOptions(
          voice: input.voiceId ?? ttsConfiguration.voice,
          language: input.language ?? ttsConfiguration.language,
          rate: ttsConfiguration.speakingRate,
          pitch: ttsConfiguration.pitch,
          volume: ttsConfiguration.volume,
          audioFormat: ttsConfiguration.audioFormat,
          sampleRate:
              ttsConfiguration.audioFormat == AudioFormat.pcm ? 16000 : 44100,
          useSSML: input.ssml != null,
        );

    // Track processing time
    final startTime = DateTime.now();

    // Perform synthesis
    final audioData = await ttsService.synthesize(
      text: textToSynthesize,
      options: options,
    );

    final processingTime =
        DateTime.now().difference(startTime).inMilliseconds / 1000.0;

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

    // Use StreamController to yield chunks as they arrive
    final controller = StreamController<Uint8List>();

    // Start synthesis in background and add chunks to stream as they arrive
    // We intentionally don't await here to allow chunks to be yielded as they arrive
    unawaited(
      ttsService
          .synthesizeStream(
        text: text,
        options: options,
        onChunk: (chunk) {
          controller.add(chunk);
        },
      )
          .then((_) {
        // Close the stream when synthesis is complete
        controller.close();
      }).catchError((error) {
        // Forward errors to the stream
        controller.addError(error);
        controller.close();
      }),
    );

    // Yield chunks as they become available
    await for (final chunk in controller.stream) {
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
