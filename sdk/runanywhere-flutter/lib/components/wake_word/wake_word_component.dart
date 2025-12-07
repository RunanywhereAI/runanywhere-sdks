import 'dart:async';
import 'dart:typed_data';

import '../../core/components/base_component.dart';
import '../../core/types/sdk_component.dart';
import '../../core/protocols/component/component_configuration.dart';
import '../../core/module_registry.dart' as core
    show ModuleRegistry, WakeWordService;
import '../../public/events/component_initialization_event.dart';

export '../../core/module_registry.dart' show WakeWordService;

// MARK: - Wake Word Configuration

/// Configuration for Wake Word Detection component
/// Matches iOS WakeWordConfiguration from WakeWordComponent.swift
class WakeWordConfiguration implements ComponentConfiguration {
  /// Model ID (if using ML-based detection)
  final String? modelId;

  /// Wake words to detect
  final List<String> wakeWords;

  /// Detection sensitivity (0.0 to 1.0)
  final double sensitivity;

  /// Audio buffer size
  final int bufferSize;

  /// Sample rate
  final int sampleRate;

  /// Confidence threshold for detection
  final double confidenceThreshold;

  /// Whether to continue listening after detection
  final bool continuousListening;

  WakeWordConfiguration({
    this.modelId,
    this.wakeWords = const ['Hey Siri', 'OK Google'],
    this.sensitivity = 0.5,
    this.bufferSize = 16000,
    this.sampleRate = 16000,
    this.confidenceThreshold = 0.7,
    this.continuousListening = true,
  });

  @override
  void validate() {
    if (wakeWords.isEmpty) {
      throw ArgumentError('At least one wake word must be specified');
    }
    if (sensitivity < 0 || sensitivity > 1) {
      throw ArgumentError('Sensitivity must be between 0 and 1');
    }
    if (confidenceThreshold < 0 || confidenceThreshold > 1) {
      throw ArgumentError('Confidence threshold must be between 0 and 1');
    }
  }
}

// MARK: - Wake Word Input/Output Models

/// Input for Wake Word Detection
/// Matches iOS WakeWordInput from WakeWordComponent.swift
class WakeWordInput implements ComponentInput {
  /// Audio buffer to process
  final Float32List audioBuffer;

  /// Optional timestamp
  final double? timestamp;

  WakeWordInput({
    required this.audioBuffer,
    this.timestamp,
  });

  @override
  void validate() {
    if (audioBuffer.isEmpty) {
      throw ArgumentError('Audio buffer cannot be empty');
    }
  }
}

/// Output from Wake Word Detection
/// Matches iOS WakeWordOutput from WakeWordComponent.swift
class WakeWordOutput implements ComponentOutput {
  /// Whether a wake word was detected
  final bool detected;

  /// Detected wake word (if any)
  final String? wakeWord;

  /// Confidence score (0.0 to 1.0)
  final double confidence;

  /// Detection metadata
  final WakeWordMetadata metadata;

  /// Timestamp (required by ComponentOutput)
  @override
  final DateTime timestamp;

  WakeWordOutput({
    required this.detected,
    this.wakeWord,
    required this.confidence,
    required this.metadata,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Wake word detection metadata
class WakeWordMetadata {
  final double processingTime;
  final int bufferSize;
  final int sampleRate;

  WakeWordMetadata({
    required this.processingTime,
    required this.bufferSize,
    required this.sampleRate,
  });
}

/// Errors for Wake Word services
class WakeWordError implements Exception {
  final String message;
  final WakeWordErrorType type;

  WakeWordError(this.message, this.type);

  @override
  String toString() => 'WakeWordError: $message';
}

enum WakeWordErrorType {
  notInitialized,
  modelNotFound,
  processingFailed,
  audioInvalid,
  notListening,
}

// MARK: - Wake Word Component

/// Wake Word Detection Component
/// Matches iOS WakeWordComponent from WakeWordComponent.swift
class WakeWordComponent extends BaseComponent<core.WakeWordService> {
  @override
  SDKComponent get componentType => SDKComponent.wakeWord;

  final WakeWordConfiguration wakeWordConfig;
  bool _isDetectingInternal = false;
  bool _isListeningInternal = false;

  /// Whether detection is currently active
  bool get isDetecting => _isDetectingInternal;

  WakeWordComponent({
    required this.wakeWordConfig,
    super.serviceContainer,
  }) : super(configuration: wakeWordConfig);

  @override
  Future<core.WakeWordService> createService() async {
    // Emit model checking event
    eventBus.publish(ComponentInitializationEvent.componentChecking(
      component: componentType,
      modelId: wakeWordConfig.modelId,
    ));

    // Try to get a registered wake word provider from central registry
    final provider = core.ModuleRegistry.shared.wakeWordProvider(
      modelId: wakeWordConfig.modelId,
    );

    if (provider == null) {
      throw WakeWordError(
        'Wake word detection service requires an external implementation. '
        'Please add a wake word provider as a dependency and register it '
        'with ModuleRegistry.shared.registerWakeWord(provider).',
        WakeWordErrorType.notInitialized,
      );
    }

    final service = await provider.createWakeWordService(wakeWordConfig);
    await service.initialize(modelPath: wakeWordConfig.modelId);

    return service;
  }

  @override
  Future<void> initializeService() async {
    eventBus.publish(ComponentInitializationEvent.componentInitializing(
      component: componentType,
      modelId: wakeWordConfig.modelId,
    ));
  }

  @override
  Future<void> performCleanup() async {
    await service?.cleanup();
    _isDetectingInternal = false;
    _isListeningInternal = false;
  }

  // MARK: - Public API

  /// Start listening for wake words
  Future<void> startListening() async {
    ensureReady();

    final wakeWordService = service;
    if (wakeWordService == null) {
      throw WakeWordError(
        'Wake word service not available',
        WakeWordErrorType.notInitialized,
      );
    }

    // Start listening would typically be handled by the native service
    // For now we just track state
    _isListeningInternal = true;
    _isDetectingInternal = true;
  }

  /// Stop listening for wake words
  Future<void> stopListening() async {
    final wakeWordService = service;
    if (wakeWordService == null) return;

    _isListeningInternal = false;
    _isDetectingInternal = false;
  }

  /// Process audio input for wake word detection
  Future<WakeWordOutput> process(WakeWordInput input) async {
    ensureReady();

    final wakeWordService = service;
    if (wakeWordService == null) {
      throw WakeWordError(
        'Wake word service not available',
        WakeWordErrorType.notInitialized,
      );
    }

    // Validate input
    input.validate();

    // Track processing time
    final startTime = DateTime.now();

    // Process audio buffer
    final detected = await wakeWordService.detect(
      input.audioBuffer.buffer.asUint8List().toList(),
    );

    final processingTime =
        DateTime.now().difference(startTime).inMilliseconds / 1000.0;

    // Create output
    return WakeWordOutput(
      detected: detected,
      wakeWord: detected ? wakeWordConfig.wakeWords.first : null,
      confidence: detected ? wakeWordConfig.confidenceThreshold : 0.0,
      metadata: WakeWordMetadata(
        processingTime: processingTime,
        bufferSize: input.audioBuffer.length,
        sampleRate: wakeWordConfig.sampleRate,
      ),
    );
  }

  /// Process audio data in simpler format (List<int>)
  Future<WakeWordOutput> processAudio(List<int> audioData) async {
    final floatBuffer = Float32List.fromList(
      audioData.map((e) => e.toDouble() / 32768.0).toList(),
    );
    return process(WakeWordInput(audioBuffer: floatBuffer));
  }

  /// Check if currently listening
  bool get isListening => _isListeningInternal && service != null;

  /// Get service for compatibility
  core.WakeWordService? getService() {
    return service;
  }
}
