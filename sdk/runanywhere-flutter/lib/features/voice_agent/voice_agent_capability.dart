import 'dart:async';
import 'dart:typed_data';
import '../../core/capabilities_base/base_capability.dart';
import '../../core/types/sdk_component.dart';
import '../../core/types/component_state.dart';
import '../../core/protocols/component/component_configuration.dart';
import '../../public/events/sdk_event.dart';
import '../vad/vad_capability.dart';
import '../vad/vad_configuration.dart';
import '../stt/stt_capability.dart';
import '../llm/llm_capability.dart';
import '../tts/tts_capability.dart';

/// Voice Agent Component Configuration
/// Matches iOS VoiceAgentConfiguration from VoiceAgentComponent.swift
class VoiceAgentConfiguration implements ComponentConfiguration {
  /// Voice agent doesn't have its own model - it orchestrates other components
  String? get modelId => null;

  /// Sub-component configurations
  final VADConfiguration vadConfig;
  final STTConfiguration sttConfig;
  final LLMConfiguration llmConfig;
  final TTSConfiguration ttsConfig;

  VoiceAgentConfiguration({
    VADConfiguration? vadConfig,
    STTConfiguration? sttConfig,
    LLMConfiguration? llmConfig,
    TTSConfiguration? ttsConfig,
  })  : vadConfig = vadConfig ?? const VADConfiguration(),
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

/// Voice Agent Capability
/// Orchestrates VAD, STT, LLM, and TTS capabilities into a complete voice pipeline
/// Can be used as a complete pipeline or with individual capabilities
/// Matches iOS VoiceAgentCapability from VoiceAgentCapability.swift
class VoiceAgentCapability extends BaseCapability<VoiceAgentService> {
  @override
  SDKComponent get componentType => SDKComponent.voiceAgent;

  /// Voice agent configuration (named to match iOS)
  VoiceAgentConfiguration get voiceAgentConfiguration =>
      configuration as VoiceAgentConfiguration;

  /// Private processing flag to prevent concurrent operations (matches iOS isProcessing)
  bool _isProcessing = false;

  /// Check if currently processing audio
  bool get isProcessing => _isProcessing;

  // Individual capabilities (accessible for custom orchestration)
  VADCapability? vadCapability;
  STTCapability? sttCapability;
  LLMCapability? llmCapability;
  TTSCapability? ttsCapability;

  VoiceAgentCapability({
    required VoiceAgentConfiguration configuration,
    super.serviceContainer,
  }) : super(configuration: configuration);

  @override
  Future<VoiceAgentService> createService() async {
    // Voice agent doesn't need an external service, it orchestrates other components
    return VoiceAgentService();
  }

  @override
  Future<void> initializeService() async {
    // Initialize all capabilities
    await _initializeCapabilities();
    eventBus.publish(SDKVoiceEvent.pipelineStarted());
  }

  Future<void> _initializeCapabilities() async {
    final config = voiceAgentConfiguration;

    try {
      // Initialize VAD (required)
      vadCapability = VADCapability(
        vadConfiguration: config.vadConfig,
        serviceContainer: serviceContainer,
      );
      await vadCapability!.initialize();

      // Initialize STT (required)
      sttCapability = STTCapability(
        sttConfig: config.sttConfig,
        serviceContainer: serviceContainer,
      );
      await sttCapability!.initialize();

      // Initialize LLM (required)
      llmCapability = LLMCapability(
        llmConfig: config.llmConfig,
        serviceContainer: serviceContainer,
      );
      await llmCapability!.initialize();

      // Initialize TTS (required)
      ttsCapability = TTSCapability(
        ttsConfiguration: config.ttsConfig,
        serviceContainer: serviceContainer,
      );
      await ttsCapability!.initialize();
    } catch (e) {
      // Cleanup any partially initialized capabilities to prevent resource leaks
      await _cleanupPartialInitialization();
      rethrow;
    }
  }

  /// Clean up any capabilities that were initialized before a failure
  Future<void> _cleanupPartialInitialization() async {
    await vadCapability?.cleanup();
    await sttCapability?.cleanup();
    await llmCapability?.cleanup();
    await ttsCapability?.cleanup();

    vadCapability = null;
    sttCapability = null;
    llmCapability = null;
    ttsCapability = null;
  }

  /// Process audio through the full pipeline
  /// Pipeline: Audio → VAD (detect speech) → STT (transcribe) → LLM (process) → TTS (synthesize)
  /// Matches iOS processAudio from VoiceAgentComponent.swift
  Future<VoiceAgentResult> processAudio(Uint8List audioData) async {
    if (state != ComponentState.ready) {
      throw StateError('Voice agent is not ready. Current state: $state');
    }

    // Prevent concurrent processing (matches iOS pattern)
    _isProcessing = true;

    try {
      final result = VoiceAgentResult();

      // VAD Processing
      final vad = vadCapability;
      if (vad != null && vad.service != null) {
        final vadResult = await vad.detectSpeech(buffer: audioData);
        result.speechDetected = vadResult.hasSpeech;

        if (!vadResult.hasSpeech) {
          return result; // No speech, return early
        }

        eventBus.publish(SDKVoiceEvent.speechDetected());
      }

      // STT Processing
      final stt = sttCapability;
      if (stt != null && stt.service != null) {
        final sttResult = await stt.transcribe(audioData.toList());
        result.transcription = sttResult.text;
        eventBus
            .publish(SDKVoiceEvent.transcriptionFinal(text: sttResult.text));
      }

      // LLM Processing
      final llm = llmCapability;
      if (llm != null && llm.service != null && result.transcription != null) {
        final llmResult = await llm.generate(result.transcription!);
        result.response = llmResult.text;
        eventBus.publish(SDKVoiceEvent.responseGenerated(text: llmResult.text));
      }

      // TTS Processing
      final tts = ttsCapability;
      if (tts != null && tts.service != null && result.response != null) {
        final ttsResult = await tts.synthesize(result.response!);
        result.synthesizedAudio = ttsResult.audioData;
        eventBus.publish(
            SDKVoiceEvent.audioGenerated(data: result.synthesizedAudio!));
      }

      return result;
    } finally {
      // Always reset processing flag (matches iOS defer pattern)
      _isProcessing = false;
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

  // MARK: - Individual Capability Access

  /// Process only through VAD
  Future<bool> detectVoiceActivity(Uint8List audioData) async {
    final vad = vadCapability;
    if (vad == null || vad.service == null) {
      return true; // Assume speech if VAD not available
    }
    final result = await vad.detectSpeech(buffer: audioData);
    return result.hasSpeech;
  }

  /// Process only through STT
  Future<String?> transcribe(Uint8List audioData) async {
    final stt = sttCapability;
    if (stt == null || stt.service == null) {
      return null;
    }
    final result = await stt.transcribe(audioData.toList());
    return result.text;
  }

  /// Process only through LLM
  Future<String?> generateResponse(String prompt) async {
    final llm = llmCapability;
    if (llm == null || llm.service == null) {
      return null;
    }
    final result = await llm.generate(prompt);
    return result.text;
  }

  /// Process only through TTS
  Future<Uint8List?> synthesizeSpeech(String text) async {
    final tts = ttsCapability;
    if (tts == null || tts.service == null) {
      return null;
    }
    final result = await tts.synthesize(text);
    return result.audioData;
  }

  // MARK: - Cleanup

  @override
  Future<void> performCleanup() async {
    await vadCapability?.cleanup();
    await sttCapability?.cleanup();
    await llmCapability?.cleanup();
    await ttsCapability?.cleanup();

    vadCapability = null;
    sttCapability = null;
    llmCapability = null;
    ttsCapability = null;
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

// MARK: - Component Load State

/// State of a voice agent component
/// Matches iOS ComponentLoadState from RunAnywhere+VoiceAgent.swift
sealed class ComponentLoadState {
  const ComponentLoadState();

  /// Component is not loaded
  static const ComponentLoadState notLoaded = NotLoadedState();

  /// Component is currently loading
  static const ComponentLoadState loading = LoadingState();

  /// Component is loaded with a specific model/voice
  const factory ComponentLoadState.loaded({required String modelId}) =
      LoadedState;

  /// Component failed to load
  const factory ComponentLoadState.failed({required Object error}) =
      FailedState;
}

class NotLoadedState extends ComponentLoadState {
  const NotLoadedState();
}

class LoadingState extends ComponentLoadState {
  const LoadingState();
}

class LoadedState extends ComponentLoadState {
  final String modelId;
  const LoadedState({required this.modelId});
}

class FailedState extends ComponentLoadState {
  final Object error;
  const FailedState({required this.error});
}

/// State of all voice agent components
/// Matches iOS VoiceAgentComponentStates from RunAnywhere+VoiceAgent.swift
class VoiceAgentComponentStates {
  /// STT component state
  final ComponentLoadState stt;

  /// LLM component state
  final ComponentLoadState llm;

  /// TTS component state
  final ComponentLoadState tts;

  VoiceAgentComponentStates({
    this.stt = ComponentLoadState.notLoaded,
    this.llm = ComponentLoadState.notLoaded,
    this.tts = ComponentLoadState.notLoaded,
  });

  /// Check if all components are loaded
  bool get isFullyReady =>
      stt is LoadedState && llm is LoadedState && tts is LoadedState;

  /// Check if any component is loading
  bool get isLoading =>
      stt is LoadingState || llm is LoadingState || tts is LoadingState;

  /// Get list of components that are not ready
  List<String> get notReadyComponents {
    final notReady = <String>[];
    if (stt is! LoadedState) notReady.add('STT');
    if (llm is! LoadedState) notReady.add('LLM');
    if (tts is! LoadedState) notReady.add('TTS');
    return notReady;
  }
}
