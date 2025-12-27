/// Voice Capability Service
///
/// Main capability coordinator for voice processing using the component system.
/// Matches iOS VoiceCapabilityService.swift from Capabilities/Voice/Services/
library voice_capability_service;

import 'dart:async';
import 'dart:typed_data';

import 'package:runanywhere/capabilities/voice/services/voice_session_manager.dart';
import 'package:runanywhere/core/module_registry.dart'
    show ModuleRegistry, STTService, LLMService;
import 'package:runanywhere/features/llm/llm_capability.dart'
    show LLMConfiguration;
import 'package:runanywhere/features/stt/stt_capability.dart'
    show STTConfiguration;
import 'package:runanywhere/features/tts/models/tts_configuration.dart'
    show TTSConfiguration;
import 'package:runanywhere/features/tts/protocol/tts_service.dart'
    show TTSService;
import 'package:runanywhere/features/vad/vad_configuration.dart'
    show VADConfiguration;
import 'package:runanywhere/features/voice_agent/voice_agent_capability.dart';
import 'package:runanywhere/foundation/dependency_injection/service_container.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';

/// Voice audio chunk for streaming
class VoiceAudioChunk {
  final Uint8List data;
  final Duration timestamp;

  VoiceAudioChunk({required this.data, required this.timestamp});
}

/// Main capability coordinator for voice processing using the component system
/// Matches iOS VoiceCapabilityService class from VoiceCapabilityService.swift
class VoiceCapabilityService {
  final SDKLogger _logger = SDKLogger(category: 'VoiceCapabilityService');

  // Services
  final VoiceSessionManager _sessionManager;

  // State
  bool _isInitialized = false;

  // Active voice agents
  final Map<String, VoiceAgentCapability> _activeAgents = {};

  VoiceCapabilityService() : _sessionManager = VoiceSessionManager();

  /// Initialize the voice capability
  Future<void> initialize() async {
    if (_isInitialized) {
      _logger.debug('Voice capability already initialized');
      return;
    }

    _logger.info('Initializing voice capability');

    // Initialize sub-services
    await _sessionManager.initialize();

    _isInitialized = true;
    _logger.info('Voice capability initialized successfully');
  }

  /// Create a voice agent with the given parameters
  Future<VoiceAgentCapability> createVoiceAgent({
    VADConfiguration? vadParams,
    STTConfiguration? sttParams,
    LLMConfiguration? llmParams,
    TTSConfiguration? ttsParams,
  }) async {
    _logger.debug('Creating voice agent with custom parameters');

    // Create agent configuration (all components are required, use defaults if not provided)
    final agentConfig = VoiceAgentConfiguration(
      vadConfig: vadParams ?? const VADConfiguration(),
      sttConfig: sttParams ?? STTConfiguration(),
      llmConfig: llmParams ?? LLMConfiguration(),
      ttsConfig: ttsParams ?? const TTSConfiguration(),
    );

    // Create and initialize agent
    final agent = VoiceAgentCapability(
      configuration: agentConfig,
      serviceContainer: ServiceContainer.shared,
    );

    await agent.initialize();

    // Track agent
    final agentId = DateTime.now().millisecondsSinceEpoch.toString();
    _activeAgents[agentId] = agent;

    return agent;
  }

  /// Create a full voice pipeline with all components
  Future<VoiceAgentCapability> createFullPipeline({
    String? sttModelId,
    String? llmModelId,
  }) async {
    return createVoiceAgent(
      vadParams: const VADConfiguration(),
      sttParams: STTConfiguration(modelId: sttModelId),
      llmParams: LLMConfiguration(modelId: llmModelId),
      ttsParams: const TTSConfiguration(),
    );
  }

  /// Process voice with a custom pipeline configuration
  Stream<VoiceAgentEvent> processVoice({
    required Stream<VoiceAudioChunk> audioStream,
    VADConfiguration? vadParams,
    STTConfiguration? sttParams,
    LLMConfiguration? llmParams,
    TTSConfiguration? ttsParams,
  }) async* {
    try {
      // Create agent
      final agent = await createVoiceAgent(
        vadParams: vadParams,
        sttParams: sttParams,
        llmParams: llmParams,
        ttsParams: ttsParams,
      );

      // Convert audio chunks to Data stream
      final dataStream = audioStream.map((chunk) => chunk.data);

      // Process through agent
      await for (final event in agent.processStream(dataStream)) {
        yield event;
      }
    } catch (e) {
      yield VoiceAgentEvent.error(e);
    }
  }

  /// Find voice service for a specific model
  Future<STTService?> findVoiceService({String? modelId}) async {
    // Check if any active agent has STT with the specified model
    for (final agent in _activeAgents.values) {
      final stt = agent.sttCapability?.getService();
      if (stt != null) {
        return stt;
      }
    }

    // Fallback: try to create via provider
    final provider = ModuleRegistry.shared.sttProvider(modelId: modelId);
    if (provider == null) {
      _logger.warning('No STT provider available for model: $modelId');
      return null;
    }

    try {
      final config = STTConfiguration(
        modelId: modelId,
        language: 'en',
        sampleRate: 16000,
      );
      final service = await provider.createSTTService(config);
      return service;
    } catch (e) {
      _logger.error('Failed to create STT service: $e');
      return null;
    }
  }

  /// Find LLM service for a specific model
  Future<LLMService?> findLLMService({String? modelId}) async {
    // Check if any active agent has LLM with the specified model
    for (final agent in _activeAgents.values) {
      final llm = agent.llmCapability?.getService();
      if (llm != null) {
        return llm;
      }
    }
    return null;
  }

  /// Find TTS service
  Future<TTSService?> findTTSService() async {
    // Check if any active agent has TTS
    for (final agent in _activeAgents.values) {
      final tts = agent.ttsCapability?.getService();
      if (tts != null) {
        return tts;
      }
    }
    return null;
  }

  /// Get the session manager
  VoiceSessionManager get sessionManager => _sessionManager;

  /// Clean up all active agents
  Future<void> cleanup() async {
    for (final agent in _activeAgents.values) {
      await agent.cleanup();
    }
    _activeAgents.clear();
    _isInitialized = false;
  }
}

// MARK: - Backward Compatibility

extension VoiceCapabilityServiceBackwardCompat on VoiceCapabilityService {
  /// Create a voice pipeline using the new architecture
  Future<VoiceAgentCapability> createPipeline({
    VADConfiguration? vadParams,
    STTConfiguration? sttParams,
    LLMConfiguration? llmParams,
    TTSConfiguration? ttsParams,
  }) async {
    // Use the new VoiceAgent component which is the modern pipeline
    return createVoiceAgent(
      vadParams: vadParams,
      sttParams: sttParams,
      llmParams: llmParams,
      ttsParams: ttsParams,
    );
  }
}
