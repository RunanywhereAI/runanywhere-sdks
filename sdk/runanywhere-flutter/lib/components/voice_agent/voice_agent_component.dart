import 'dart:async';
import 'dart:typed_data';
import '../../core/components/base_component.dart';
import '../../core/types/sdk_component.dart';
import '../../core/types/component_state.dart';
import '../../core/protocols/component/component_configuration.dart';
import '../../core/module_registry.dart' show STTOptions, VADService, VADResult;
import '../../public/events/sdk_event.dart';
import '../vad/vad_component.dart';
import '../vad/vad_configuration.dart';
import '../stt/stt_component.dart';
import '../llm/llm_component.dart';
import '../tts/tts_component.dart';

/// Voice Agent Component Configuration
class VoiceAgentConfiguration implements ComponentConfiguration {
  final VADConfiguration vadConfig;
  final STTConfiguration sttConfig;
  final LLMConfiguration llmConfig;
  final TTSConfiguration ttsConfig;

  VoiceAgentConfiguration({
    VADConfiguration? vadConfig,
    STTConfiguration? sttConfig,
    LLMConfiguration? llmConfig,
    TTSConfiguration? ttsConfig,
  })  : vadConfig = vadConfig ?? VADConfiguration(),
        sttConfig = sttConfig ?? STTConfiguration(),
        llmConfig = llmConfig ?? LLMConfiguration(),
        ttsConfig = ttsConfig ?? TTSConfiguration();

  @override
  void validate() {
    vadConfig.validate();
    sttConfig.validate();
    llmConfig.validate();
    ttsConfig.validate();
  }
}

/// Voice Agent Service - wrapper since it doesn't have an external service
class VoiceAgentService {
  VoiceAgentService();
}

/// Voice Agent Component
/// Orchestrates VAD, STT, LLM, and TTS components into a complete voice pipeline
/// Can be used as a complete pipeline or with individual components
class VoiceAgentComponent extends BaseComponent<VoiceAgentService> {
  @override
  SDKComponent get componentType => SDKComponent.voiceAgent;

  final VoiceAgentConfiguration agentParams;

  // Individual components (accessible for custom orchestration)
  VADComponent? vadComponent;
  STTComponent? sttComponent;
  LLMComponent? llmComponent;
  TTSComponent? ttsComponent;

  VoiceAgentComponent({
    required this.agentParams,
    super.serviceContainer,
  }) : super(configuration: agentParams);

  @override
  Future<VoiceAgentService> createService() async {
    // Voice agent doesn't need an external service, it orchestrates other components
    return VoiceAgentService();
  }

  @override
  Future<void> initializeService() async {
    // Initialize all components
    await _initializeComponents();
    eventBus.publish(SDKVoiceEvent.pipelineStarted());
  }

  Future<void> _initializeComponents() async {
    // Initialize VAD (required)
    vadComponent = VADComponent(
      vadConfiguration: agentParams.vadConfig,
      serviceContainer: serviceContainer,
    );
    await vadComponent!.initialize();

    // Initialize STT (required)
    sttComponent = STTComponent(
      sttConfig: agentParams.sttConfig,
      serviceContainer: serviceContainer,
    );
    await sttComponent!.initialize();

    // Initialize LLM (required)
    llmComponent = LLMComponent(
      llmConfig: agentParams.llmConfig,
      serviceContainer: serviceContainer,
    );
    await llmComponent!.initialize();

    // Initialize TTS (required)
    ttsComponent = TTSComponent(
      ttsConfiguration: agentParams.ttsConfig,
      serviceContainer: serviceContainer,
    );
    await ttsComponent!.initialize();
  }

  /// Process audio through the full pipeline
  /// Pipeline: Audio → VAD (detect speech) → STT (transcribe) → LLM (process) → TTS (synthesize)
  Future<VoiceAgentResult> processAudio(Uint8List audioData) async {
    if (state != ComponentState.ready) {
      throw StateError('Voice agent is not ready. Current state: $state');
    }

    try {
      final result = VoiceAgentResult();

      // VAD Processing
      final vad = vadComponent;
      if (vad != null && vad.service != null) {
        final vadResult = await vad.detectSpeech(buffer: audioData);
        result.speechDetected = vadResult.hasSpeech;

        if (!vadResult.hasSpeech) {
          return result; // No speech, return early
        }

        eventBus.publish(SDKVoiceEvent.speechDetected());
      }

      // STT Processing
      final stt = sttComponent;
      if (stt != null && stt.service != null) {
        final sttInput = STTInput(
          audioData: audioData,
          options: STTOptions(),
        );
        final sttResult = await stt.transcribe(sttInput);
        result.transcription = sttResult.transcript;
        eventBus.publish(SDKVoiceEvent.transcriptionFinal(text: sttResult.transcript));
      }

      // LLM Processing
      final llm = llmComponent;
      if (llm != null && llm.service != null && result.transcription != null) {
        final llmInput = LLMInput(
          prompt: result.transcription!,
          options: LLMGenerationOptions(
            maxTokens: agentParams.llmConfig.contextLength,
            temperature: 0.7,
          ),
        );
        final llmResult = await llm.generate(llmInput);
        result.response = llmResult.text;
        eventBus.publish(SDKVoiceEvent.responseGenerated(text: llmResult.text));
      }

      // TTS Processing
      final tts = ttsComponent;
      if (tts != null && tts.service != null && result.response != null) {
        final ttsResult = await tts.synthesize(result.response!);
        result.synthesizedAudio = ttsResult.audioData;
        eventBus.publish(SDKVoiceEvent.audioGenerated(data: result.synthesizedAudio!));
      }

      return result;
    } finally {
      // Processing complete
    }
  }

  /// Process audio stream for continuous conversation
  Stream<VoiceAgentEvent> processStream(Stream<Uint8List> audioStream) async* {
    await for (final audioData in audioStream) {
      try {
        final result = await processAudio(audioData);
        yield VoiceAgentEvent.processed(result);
      } catch (e) {
        yield VoiceAgentEvent.error(e);
      }
    }
  }

  // MARK: - Individual Component Access

  /// Process only through VAD
  Future<bool> detectVoiceActivity(Uint8List audioData) async {
    final vad = vadComponent;
    if (vad == null || vad.service == null) {
      return true; // Assume speech if VAD not available
    }
    final result = await vad.detectSpeech(buffer: audioData);
    return result.hasSpeech;
  }

  /// Process only through STT
  Future<String?> transcribe(Uint8List audioData) async {
    final stt = sttComponent;
    if (stt == null || stt.service == null) {
      return null;
    }
    final result = await stt.transcribe(
      STTInput(audioData: audioData, options: STTOptions()),
    );
    return result.transcript;
  }

  /// Process only through LLM
  Future<String?> generateResponse(String prompt) async {
    final llm = llmComponent;
    if (llm == null || llm.service == null) {
      return null;
    }
    final result = await llm.generate(
      LLMInput(
        prompt: prompt,
        options: LLMGenerationOptions(
          maxTokens: agentParams.llmConfig.contextLength,
          temperature: 0.7,
        ),
      ),
    );
    return result.text;
  }

  /// Process only through TTS
  Future<Uint8List?> synthesizeSpeech(String text) async {
    final tts = ttsComponent;
    if (tts == null || tts.service == null) {
      return null;
    }
    final result = await tts.synthesize(text);
    return result.audioData;
  }

  // MARK: - Cleanup

  @override
  Future<void> performCleanup() async {
    await vadComponent?.cleanup();
    await sttComponent?.cleanup();
    await llmComponent?.cleanup();
    await ttsComponent?.cleanup();

    vadComponent = null;
    sttComponent = null;
    llmComponent = null;
    ttsComponent = null;
  }
}

// MARK: - Voice Agent Result

/// Result from voice agent processing
class VoiceAgentResult {
  bool speechDetected;
  String? transcription;
  String? response;
  Uint8List? synthesizedAudio;

  VoiceAgentResult({
    this.speechDetected = false,
    this.transcription,
    this.response,
    this.synthesizedAudio,
  });
}

// MARK: - Voice Agent Events

/// Events emitted by the voice agent
abstract class VoiceAgentEvent {
  static VoiceAgentEvent processed(VoiceAgentResult result) =>
      VoiceAgentProcessed(result);
  static VoiceAgentEvent vadTriggered(bool isSpeech) =>
      VoiceAgentVADTriggered(isSpeech);
  static VoiceAgentEvent transcriptionAvailable(String text) =>
      VoiceAgentTranscriptionAvailable(text);
  static VoiceAgentEvent responseGenerated(String text) =>
      VoiceAgentResponseGenerated(text);
  static VoiceAgentEvent audioSynthesized(Uint8List data) =>
      VoiceAgentAudioSynthesized(data);
  static VoiceAgentEvent error(Object error) => VoiceAgentError(error);
}

class VoiceAgentProcessed extends VoiceAgentEvent {
  final VoiceAgentResult result;
  VoiceAgentProcessed(this.result);
}

class VoiceAgentVADTriggered extends VoiceAgentEvent {
  final bool isSpeech;
  VoiceAgentVADTriggered(this.isSpeech);
}

class VoiceAgentTranscriptionAvailable extends VoiceAgentEvent {
  final String text;
  VoiceAgentTranscriptionAvailable(this.text);
}

class VoiceAgentResponseGenerated extends VoiceAgentEvent {
  final String text;
  VoiceAgentResponseGenerated(this.text);
}

class VoiceAgentAudioSynthesized extends VoiceAgentEvent {
  final Uint8List data;
  VoiceAgentAudioSynthesized(this.data);
}

class VoiceAgentError extends VoiceAgentEvent {
  final Object error;
  VoiceAgentError(this.error);
}
