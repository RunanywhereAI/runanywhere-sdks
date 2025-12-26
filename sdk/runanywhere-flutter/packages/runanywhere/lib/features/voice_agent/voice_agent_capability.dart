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
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
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
  final SDKLogger logger = SDKLogger(category: 'VoiceAgentCapability');

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
    logger.info('🔧 Initializing voice agent capabilities...');
    logger.info(
        '📋 Config: STT=${config.sttConfig.modelId}, LLM=${config.llmConfig.modelId}, TTS=${config.ttsConfig.modelId}');

    try {
      // Initialize VAD (optional - we bypass it in processAudio anyway)
      logger.info('🎯 Initializing VAD...');
      vadCapability = VADCapability(
        vadConfiguration: config.vadConfig,
        serviceContainer: serviceContainer,
      );
      await vadCapability!.initialize();
      logger.info('✅ VAD initialized (but will be bypassed in favor of STT)');

      // Initialize STT (required)
      logger.info(
          '🎤 Initializing STT with model: ${config.sttConfig.modelId}...');
      sttCapability = STTCapability(
        sttConfig: config.sttConfig,
        serviceContainer: serviceContainer,
      );
      await sttCapability!.initialize();
      logger.info(
          '✅ STT initialized: ready=${sttCapability!.isReady}, service=${sttCapability!.service != null}');

      // Initialize LLM (required)
      logger.info(
          '🧠 Initializing LLM with model: ${config.llmConfig.modelId}...');
      llmCapability = LLMCapability(
        llmConfig: config.llmConfig,
        serviceContainer: serviceContainer,
      );
      await llmCapability!.initialize();
      logger.info(
          '✅ LLM initialized: ready=${llmCapability!.isReady}, service=${llmCapability!.service != null}');

      // Initialize TTS (required)
      logger.info(
          '🔊 Initializing TTS with model: ${config.ttsConfig.modelId}...');
      ttsCapability = TTSCapability(
        ttsConfiguration: config.ttsConfig,
        serviceContainer: serviceContainer,
      );
      await ttsCapability!.initialize();
      logger.info(
          '✅ TTS initialized: ready=${ttsCapability!.isReady}, service=${ttsCapability!.service != null}');

      logger.info('✅ All voice agent capabilities initialized successfully');
    } catch (e) {
      logger.error('❌ Failed to initialize capabilities: $e');
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
  /// Pipeline: Audio → STT (transcribe) → LLM (process) → TTS (synthesize)
  /// Note: VAD is bypassed - VoiceSessionHandle already performs audio level detection,
  /// and STT will return empty text if no speech is present.
  /// Matches iOS processAudio from VoiceAgentComponent.swift
  Future<VoiceAgentResult> processAudio(Uint8List audioData) async {
    if (state != ComponentState.ready) {
      throw StateError('Voice agent is not ready. Current state: $state');
    }

    // Prevent concurrent processing (matches iOS pattern)
    _isProcessing = true;
    logger.info(
        '🔄 VoiceAgent: Processing ${audioData.length} bytes of audio...');

    try {
      final result = VoiceAgentResult();

      // Skip VAD - VoiceSessionHandle already detected speech via audio level.
      // Let STT determine if there's meaningful speech by checking if transcription is empty.
      // This is more reliable than VAD which can be overly restrictive.
      result.speechDetected = true; // Assume speech until STT proves otherwise
      logger.info(
          '📍 Bypassing VAD (VoiceSessionHandle already detected speech via audio level)');

      // STT Processing
      final stt = sttCapability;
      if (stt != null && stt.service != null) {
        logger
            .info('🎤 STT: Transcribing ${audioData.length} bytes of audio...');
        final sttResult = await stt.transcribe(audioData.toList());
        result.transcription = sttResult.text;
        logger.info(
            '🎤 STT result: "${sttResult.text}" (${sttResult.text.length} chars)');

        // If STT returns empty, no meaningful speech was detected
        if (sttResult.text.trim().isEmpty) {
          logger.info(
              '🔇 STT returned empty transcription - no meaningful speech detected');
          result.speechDetected = false;
          return result;
        }

        eventBus.publish(SDKVoiceEvent.speechDetected());
        eventBus
            .publish(SDKVoiceEvent.transcriptionFinal(text: sttResult.text));
      } else {
        logger.error('❌ STT not available! Cannot transcribe audio.');
        result.speechDetected = false;
        return result;
      }

      // LLM Processing
      final llm = llmCapability;
      if (llm != null && llm.service != null && result.transcription != null) {
        logger
            .info('🧠 LLM: Generating response for: "${result.transcription}"');
        final llmResult = await llm.generate(result.transcription!);
        result.response = llmResult.text;
        final previewLen =
            llmResult.text.length > 50 ? 50 : llmResult.text.length;
        logger.info(
            '🧠 LLM result: "${llmResult.text.substring(0, previewLen)}${llmResult.text.length > 50 ? "..." : ""}" (${llmResult.text.length} chars)');
        eventBus.publish(SDKVoiceEvent.responseGenerated(text: llmResult.text));
      } else {
        logger.warning('⚠️ LLM not available or no transcription to process');
      }

      // TTS Processing
      final tts = ttsCapability;
      if (tts != null && tts.service != null && result.response != null) {
        logger.info('🔊 TTS: Synthesizing speech for response...');
        final ttsResult = await tts.synthesize(result.response!);
        result.synthesizedAudio = ttsResult.audioData;
        logger.info(
            '🔊 TTS result: ${ttsResult.audioData.length} bytes of audio');
        eventBus.publish(
            SDKVoiceEvent.audioGenerated(data: result.synthesizedAudio!));
      } else {
        logger.warning('⚠️ TTS not available or no response to synthesize');
      }

      final transcriptPreview = result.transcription ?? '(null)';
      final responsePreview = result.response != null
          ? result.response!.substring(
              0, (result.response!.length > 30 ? 30 : result.response!.length))
          : '(null)';
      logger.info(
          '✅ VoiceAgent: Pipeline complete - speechDetected=${result.speechDetected}, transcription="$transcriptPreview", response="$responsePreview..."');
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
