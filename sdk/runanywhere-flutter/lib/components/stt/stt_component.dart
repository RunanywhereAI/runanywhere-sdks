import '../../core/components/base_component.dart';
import '../../core/types/sdk_component.dart';
import '../../core/protocols/component/component_configuration.dart';
import '../../core/module_registry.dart';

/// STT (Speech-to-Text) Component Configuration
class STTConfiguration implements ComponentConfiguration {
  final String? modelId;
  final String language;
  final int sampleRate;
  final bool enablePunctuation;

  STTConfiguration({
    this.modelId,
    this.language = 'en',
    this.sampleRate = 16000,
    this.enablePunctuation = true,
  });

  @override
  void validate() {
    if (sampleRate <= 0) {
      throw ArgumentError('Sample rate must be positive');
    }
  }
}

/// STT Component Input
class STTInput implements ComponentInput {
  final List<int> audioData;
  final STTOptions options;

  STTInput({
    required this.audioData,
    required this.options,
  });

  @override
  void validate() {
    if (audioData.isEmpty) {
      throw ArgumentError('Audio data cannot be empty');
    }
  }
}

/// STT Component Output
class STTOutput implements ComponentOutput {
  final String transcript;
  final double confidence;
  final List<STTSegment> segments;
  @override
  final DateTime timestamp;

  STTOutput({
    required this.transcript,
    required this.confidence,
    required this.segments,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// STT Segment
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

/// STT Component
class STTComponent extends BaseComponent<STTService> {
  @override
  SDKComponent get componentType => SDKComponent.stt;

  final STTConfiguration sttConfig;

  STTComponent({
    required this.sttConfig,
    super.serviceContainer,
  }) : super(configuration: sttConfig);

  @override
  Future<STTService> createService() async {
    final provider = ModuleRegistry.shared.sttProvider(modelId: sttConfig.modelId);
    if (provider == null) {
      throw StateError('No STT provider available');
    }
    return await provider.createSTTService(sttConfig);
  }

  /// Transcribe audio
  Future<STTOutput> transcribe(STTInput input) async {
    ensureReady();
    final service = this.service;
    if (service == null) {
      throw StateError('STT service not initialized');
    }

    final result = await service.transcribe(
      audioData: input.audioData,
      options: input.options,
    );

    return STTOutput(
      transcript: result.transcript,
      confidence: result.confidence,
      segments: [],
      timestamp: DateTime.now(),
    );
  }
}

