import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:runanywhere/core/capabilities_base/base_capability.dart';
import 'package:runanywhere/core/module_registry.dart' hide TTSService;
import 'package:runanywhere/core/types/sdk_component.dart';
import 'package:runanywhere/features/tts/models/tts_configuration.dart';
import 'package:runanywhere/features/tts/models/tts_input.dart';
import 'package:runanywhere/features/tts/protocol/tts_service.dart';
import 'package:runanywhere/features/tts/system_tts_service.dart';
import 'package:runanywhere/features/tts/tts_output.dart';
import 'package:runanywhere/foundation/dependency_injection/service_container.dart';
import 'package:runanywhere/infrastructure/analytics/services/tts_analytics_service.dart';

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

  /// Analytics service for tracking synthesis operations.
  /// Matches iOS TTSCapability.analyticsService
  final TTSAnalyticsService _analyticsService;

  TTSCapability({
    required this.ttsConfiguration,
    super.serviceContainer,
    TTSAnalyticsService? analyticsService,
  })  : currentVoice = ttsConfiguration.voice,
        _analyticsService = analyticsService ?? TTSAnalyticsService(),
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
      // Initialize with configuration
      debugPrint(
          '[TTSComponent] Initializing service with modelPath: $_modelPath');
      // Create a configuration with the model path for initialization
      final initConfig = ttsConfiguration.copyWith(modelId: _modelPath);
      await service.initialize(initConfig);
      ttsService = service;
    } else {
      // Fallback to system TTS
      debugPrint('[TTSComponent] No provider, falling back to SystemTTS');
      ttsService = SystemTTSService();
      await ttsService.initialize(ttsConfiguration);
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
    return process(input);
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
    return process(input);
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

    final text = input.text ?? input.ssml ?? '';
    final voiceId = input.voiceId ?? currentVoice ?? 'default';

    // Start synthesis tracking (matches iOS pattern)
    final synthesisId = _analyticsService.startSynthesis(
      text: text,
      voice: voiceId,
      framework: ttsService.inferenceFramework,
    );

    // Perform synthesis using the service protocol
    final TTSOutput output;
    try {
      output = await ttsService.synthesize(input);
    } catch (e) {
      _analyticsService.trackSynthesisFailed(
        synthesisId: synthesisId,
        errorMessage: e.toString(),
      );
      rethrow;
    }

    // Complete synthesis tracking (matches iOS pattern)
    _analyticsService.completeSynthesis(
      synthesisId: synthesisId,
      audioDurationMs: output.duration * 1000,
      audioSizeBytes: output.audioData.length,
    );

    return output;
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

    final input = TTSInput(
      text: text,
      voiceId: voice,
      language: language,
    );

    // Call the service's synthesizeStream method which returns a Stream
    await for (final chunk in ttsService.synthesizeStream(input)) {
      yield chunk;
    }
  }

  /// Get available voices
  Future<List<TTSVoice>> getAvailableVoices() async {
    final ttsService = service;
    if (ttsService == null) {
      return [];
    }
    return ttsService.getAvailableVoices();
  }

  /// Get service for compatibility
  TTSService? getService() {
    return service;
  }

  /// Stop current synthesis.
  /// Matches iOS TTSCapability.stop() method.
  Future<void> stop() async {
    await service?.stop();
  }

  /// Whether currently synthesizing.
  /// Matches iOS TTSCapability.isSynthesizing property.
  bool get isSynthesizing => service?.isSynthesizing ?? false;

  // MARK: - Analytics

  /// Get current TTS analytics metrics.
  /// Matches iOS TTSCapability.getAnalyticsMetrics().
  TTSMetrics getAnalyticsMetrics() {
    return _analyticsService.getMetrics();
  }

  // MARK: - Cleanup

  @override
  Future<void> performCleanup() async {
    await service?.cleanup();
    currentVoice = null;
  }
}
