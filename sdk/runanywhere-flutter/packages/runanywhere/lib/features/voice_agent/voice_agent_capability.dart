import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/core/capabilities_base/base_capability.dart';
import 'package:runanywhere/core/protocols/component/component_configuration.dart';
import 'package:runanywhere/core/types/component_state.dart';
import 'package:runanywhere/core/types/sdk_component.dart';
import 'package:runanywhere/features/llm/llm_capability.dart';
import 'package:runanywhere/features/stt/stt_capability.dart';
import 'package:runanywhere/features/tts/models/tts_configuration.dart';
import 'package:runanywhere/features/tts/tts_capability.dart';
import 'package:runanywhere/features/vad/vad_capability.dart';
import 'package:runanywhere/features/vad/vad_configuration.dart';
import 'package:runanywhere/features/voice_agent/models/voice_agent_result.dart';
import 'package:runanywhere/public/events/sdk_event.dart';

export 'models/voice_agent_component_state.dart';
export 'models/voice_agent_result.dart';

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
        ttsConfig = ttsConfig ?? const TTSConfiguration();

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
