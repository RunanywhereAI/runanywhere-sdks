/// LLM Handler for Voice Pipeline
///
/// Handles Language Model processing in the voice pipeline.
/// Matches iOS VoiceLLMHandler.swift from Capabilities/Voice/Handlers/
library llm_handler;

import 'dart:async';

import '../../../foundation/logging/sdk_logger.dart';
import '../../../core/module_registry.dart' show LLMService, LLMGenerationOptions;
import '../../../components/llm/llm_component.dart' show LLMConfiguration;
import '../../../components/tts/tts_component.dart' show TTSConfiguration;
import '../../../components/tts/tts_options.dart' show TTSOptions;
import '../models/modular_pipeline_event.dart';
import 'streaming_tts_handler.dart';

/// Handles Language Model processing in the voice pipeline
/// Matches iOS VoiceLLMHandler class from LLMHandler.swift
class VoiceLLMHandler {
  final SDKLogger _logger = SDKLogger(category: 'LLMHandler');

  VoiceLLMHandler();

  /// Process transcript through LLM
  Future<String> processWithLLM({
    required String transcript,
    LLMService? llmService,
    LLMConfiguration? config,
    StreamingTTSHandler? streamingTTSHandler,
    required bool ttsEnabled,
    TTSConfiguration? ttsConfig,
    required StreamController<ModularPipelineEvent> continuation,
  }) async {
    continuation.add(const LLMThinkingEvent());

    final options = LLMGenerationOptions(
      maxTokens: config?.maxTokens ?? 100,
      temperature: config?.temperature ?? 0.7,
      preferredFramework: config?.preferredFramework,
      systemPrompt: config?.systemPrompt,
    );

    // Check if streaming is enabled (prefer streaming for voice pipelines)
    final useStreaming = config?.streamingEnabled ?? true;

    if (useStreaming && llmService != null && llmService.isReady) {
      // Use streaming for real-time responses
      return await _streamGenerate(
        transcript: transcript,
        llmService: llmService,
        options: options,
        streamingTTSHandler: streamingTTSHandler,
        ttsEnabled: ttsEnabled,
        ttsConfig: ttsConfig,
        continuation: continuation,
      );
    } else {
      // Fall back to non-streaming generation
      return await _generateNonStreaming(
        transcript: transcript,
        llmService: llmService,
        options: options,
        continuation: continuation,
      );
    }
  }

  /// Stream-based generation with real-time TTS
  Future<String> _streamGenerate({
    required String transcript,
    required LLMService llmService,
    required LLMGenerationOptions options,
    StreamingTTSHandler? streamingTTSHandler,
    required bool ttsEnabled,
    TTSConfiguration? ttsConfig,
    required StreamController<ModularPipelineEvent> continuation,
  }) async {
    _logger.debug('Using streaming LLM service for real-time generation');

    // Reset streaming TTS handler for new response
    streamingTTSHandler?.reset();

    var responseContent = ''; // Content without thinking
    var firstTokenReceived = false;

    // Note: Thinking content parsing would be implemented here
    // For now, we treat all tokens as content

    await for (final token in llmService.generateStream(
      prompt: transcript,
      options: options,
    )) {
      if (!firstTokenReceived) {
        firstTokenReceived = true;
        continuation.add(const LLMStreamStartedEvent());
      }

      responseContent += token;
      continuation.add(LLMStreamTokenEvent(token));

      // Process token for streaming TTS if enabled
      if (ttsEnabled && streamingTTSHandler != null) {
        final ttsOptions = TTSOptions(
          voice: ttsConfig?.voice,
          language: ttsConfig?.language ?? 'en',
          rate: ttsConfig?.speakingRate ?? 1.0,
          pitch: ttsConfig?.pitch ?? 1.0,
          volume: ttsConfig?.volume ?? 1.0,
        );
        await streamingTTSHandler.processToken(
          token,
          options: ttsOptions,
          continuation: continuation,
        );
      }
    }

    // Flush any remaining text in TTS buffer
    if (ttsEnabled && streamingTTSHandler != null) {
      final ttsOptions = TTSOptions(
        voice: ttsConfig?.voice,
        language: ttsConfig?.language ?? 'en',
        rate: ttsConfig?.speakingRate ?? 1.0,
        pitch: ttsConfig?.pitch ?? 1.0,
        volume: ttsConfig?.volume ?? 1.0,
      );
      await streamingTTSHandler.flushRemaining(
        options: ttsOptions,
        continuation: continuation,
      );
    }

    final finalResponse = responseContent;
    continuation.add(LLMFinalResponseEvent(finalResponse));
    return finalResponse;
  }

  /// Non-streaming generation fallback
  Future<String> _generateNonStreaming({
    required String transcript,
    LLMService? llmService,
    required LLMGenerationOptions options,
    required StreamController<ModularPipelineEvent> continuation,
  }) async {
    String response;

    if (llmService != null && llmService.isReady) {
      // Use the provided LLM service if it's ready
      _logger.debug('Using initialized LLM service for generation');
      final result = await llmService.generate(
        prompt: transcript,
        options: options,
      );
      response = result.text;
    } else {
      // Return empty if no service available
      _logger.warning('No LLM service available for generation');
      response = '';
    }

    continuation.add(LLMFinalResponseEvent(response));
    return response;
  }
}
