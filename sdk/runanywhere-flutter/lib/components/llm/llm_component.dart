import 'dart:async';
import '../../core/components/base_component.dart';
import '../../core/types/sdk_component.dart';
import '../../core/protocols/component/component_configuration.dart';
import '../../core/module_registry.dart' as core
    show ModuleRegistry, LLMService, LLMGenerationOptions;
import '../../core/models/common.dart' show LLMFramework, QuantizationLevel;
import '../../public/models/conversation.dart';

export '../../public/models/conversation.dart';
export '../../core/models/common.dart' show LLMFramework, QuantizationLevel;

/// LLM (Language Model) Component Configuration
/// Matches iOS LLMConfiguration from LLMComponent.swift
class LLMConfiguration implements ComponentConfiguration {
  /// Model ID
  final String? modelId;

  // Model loading parameters
  final int contextLength;
  final bool useGPUIfAvailable;
  final QuantizationLevel? quantizationLevel;
  final int cacheSize; // Token cache size in MB
  final String? preloadContext; // Optional system prompt to preload

  // Default generation parameters
  final double temperature;
  final int maxTokens;
  final String? systemPrompt;
  final bool streamingEnabled;
  final LLMFramework? preferredFramework;

  LLMConfiguration({
    this.modelId,
    this.contextLength = 2048,
    this.useGPUIfAvailable = true,
    this.quantizationLevel,
    this.cacheSize = 100,
    this.preloadContext,
    this.temperature = 0.7,
    this.maxTokens = 100,
    String? systemPrompt,
    this.streamingEnabled = true,
    this.preferredFramework,
  }) : systemPrompt = systemPrompt ?? preloadContext;

  @override
  void validate() {
    if (contextLength <= 0 || contextLength > 32768) {
      throw ArgumentError('Context length must be between 1 and 32768');
    }
    if (cacheSize < 0 || cacheSize > 1000) {
      throw ArgumentError('Cache size must be between 0 and 1000 MB');
    }
    if (temperature < 0 || temperature > 2.0) {
      throw ArgumentError('Temperature must be between 0 and 2.0');
    }
    if (maxTokens <= 0 || maxTokens > contextLength) {
      throw ArgumentError('Max tokens must be between 1 and context length');
    }
  }
}

/// LLM Component Input
/// Matches iOS LLMInput from LLMComponent.swift
class LLMInput implements ComponentInput {
  /// Messages in the conversation
  final List<Message> messages;

  /// Optional system prompt override
  final String? systemPrompt;

  /// Optional context for conversation
  final Context? context;

  /// Optional generation options override
  final LLMGenerationOptions? options;

  LLMInput({
    required this.messages,
    this.systemPrompt,
    this.context,
    this.options,
  });

  /// Convenience initializer for single prompt
  factory LLMInput.fromPrompt(String prompt, {String? systemPrompt}) {
    return LLMInput(
      messages: [Message.user(prompt)],
      systemPrompt: systemPrompt,
    );
  }

  @override
  void validate() {
    if (messages.isEmpty) {
      throw ArgumentError('LLMInput must contain at least one message');
    }
  }
}

/// LLM Component Output
/// Matches iOS LLMOutput from LLMComponent.swift
class LLMOutput implements ComponentOutput {
  /// Generated text
  final String text;

  /// Token usage statistics
  final TokenUsage tokenUsage;

  /// Generation metadata
  final GenerationMetadata metadata;

  /// Finish reason
  final FinishReason finishReason;

  /// Timestamp (required by ComponentOutput)
  @override
  final DateTime timestamp;

  LLMOutput({
    required this.text,
    required this.tokenUsage,
    required this.metadata,
    required this.finishReason,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  /// Convenience getters for backward compatibility
  int get tokensUsed => tokenUsage.totalTokens;
  int get latencyMs => (metadata.generationTime * 1000).round();
}

// LLMGenerationOptions is now defined in module_registry.dart (canonical location)
// Re-export for convenient access from llm_component
typedef LLMGenerationOptions = core.LLMGenerationOptions;

/// Errors for LLM services
/// Matches iOS LLMServiceError from LLMComponent.swift
class LLMServiceError implements Exception {
  final String message;
  final LLMErrorType type;

  LLMServiceError(this.message, this.type);

  @override
  String toString() => 'LLMServiceError: $message';
}

enum LLMErrorType {
  notInitialized,
  modelNotFound,
  generationFailed,
  streamingNotSupported,
  contextLengthExceeded,
  invalidOptions,
}

/// LLM Component
/// Matches iOS LLMComponent from LLMComponent.swift
class LLMComponent extends BaseComponent<core.LLMService> {
  @override
  SDKComponent get componentType => SDKComponent.llm;

  final LLMConfiguration llmConfig;
  Context? _conversationContext;
  bool _isModelLoaded = false;
  String? _modelPath;

  LLMComponent({
    required this.llmConfig,
    super.serviceContainer,
  }) : super(configuration: llmConfig) {
    // Preload context if provided
    if (llmConfig.preloadContext != null) {
      _conversationContext = Context(systemPrompt: llmConfig.preloadContext);
    }
  }

  @override
  Future<core.LLMService> createService() async {
    final provider =
        core.ModuleRegistry.shared.llmProvider(modelId: llmConfig.modelId);
    if (provider == null) {
      throw LLMServiceError(
        'No LLM service provider registered. Please add llama.cpp or another LLM implementation as a dependency and register it with ModuleRegistry.shared.registerLLM(provider).',
        LLMErrorType.notInitialized,
      );
    }

    final service = await provider.createLLMService(llmConfig);
    await service.initialize(modelPath: _modelPath);
    _isModelLoaded = true;

    return service;
  }

  @override
  Future<void> performCleanup() async {
    await service?.cleanup();
    _isModelLoaded = false;
    _modelPath = null;
    _conversationContext = null;
  }

  /// Generate text from a simple prompt
  Future<LLMOutput> generate(String prompt, {String? systemPrompt}) async {
    ensureReady();
    final input = LLMInput(
      messages: [Message.user(prompt)],
      systemPrompt: systemPrompt,
    );
    return process(input);
  }

  /// Generate with conversation history
  Future<LLMOutput> generateWithHistory(
    List<Message> messages, {
    String? systemPrompt,
  }) async {
    ensureReady();
    final input = LLMInput(messages: messages, systemPrompt: systemPrompt);
    return process(input);
  }

  /// Process LLM input
  Future<LLMOutput> process(LLMInput input) async {
    ensureReady();

    final llmService = service;
    if (llmService == null) {
      throw LLMServiceError(
        'LLM service not available',
        LLMErrorType.notInitialized,
      );
    }

    // Validate input
    input.validate();

    // Use provided options or create from configuration
    final options = input.options ??
        LLMGenerationOptions(
          maxTokens: llmConfig.maxTokens,
          temperature: llmConfig.temperature,
          streamingEnabled: llmConfig.streamingEnabled,
          preferredFramework: llmConfig.preferredFramework,
        );

    // Build prompt
    final prompt = _buildPrompt(
      input.messages,
      systemPrompt: input.systemPrompt ?? llmConfig.systemPrompt,
    );

    // Track generation time
    final startTime = DateTime.now();

    // Generate response
    final result = await llmService.generate(
      prompt: prompt,
      options: options,
    );

    final generationTime =
        DateTime.now().difference(startTime).inMilliseconds / 1000.0;

    // Calculate tokens (rough estimate - real implementation would get from service)
    final promptTokens = prompt.length ~/ 4;
    final completionTokens = result.text.length ~/ 4;
    final tokensPerSecond =
        generationTime > 0 ? completionTokens / generationTime : 0.0;

    // Create output
    return LLMOutput(
      text: result.text,
      tokenUsage: TokenUsage(
        promptTokens: promptTokens,
        completionTokens: completionTokens,
      ),
      metadata: GenerationMetadata(
        modelId: llmConfig.modelId ?? 'unknown',
        temperature: options.temperature,
        generationTime: generationTime,
        tokensPerSecond: tokensPerSecond,
      ),
      finishReason: FinishReason.completed,
    );
  }

  /// Stream generation
  Stream<String> streamGenerate(String prompt, {String? systemPrompt}) {
    ensureReady();
    final llmService = service;
    if (llmService == null) {
      throw LLMServiceError(
        'LLM service not available',
        LLMErrorType.notInitialized,
      );
    }

    final options = LLMGenerationOptions(
      maxTokens: llmConfig.maxTokens,
      temperature: llmConfig.temperature,
      streamingEnabled: true,
      preferredFramework: llmConfig.preferredFramework,
    );

    final fullPrompt = _buildPrompt(
      [Message.user(prompt)],
      systemPrompt: systemPrompt ?? llmConfig.systemPrompt,
    );

    return llmService.generateStream(
      prompt: fullPrompt,
      options: options,
    );
  }

  /// Get current conversation context
  Context? get conversationContext => _conversationContext;

  /// Update conversation context
  void updateContext(Context context) {
    _conversationContext = context;
  }

  /// Clear conversation context
  void clearContext() {
    _conversationContext = _conversationContext?.cleared();
  }

  /// Get service for compatibility
  core.LLMService? getService() {
    return service;
  }

  /// Check if model is loaded
  bool get isModelLoaded => _isModelLoaded;

  // MARK: - Private Helpers

  String _buildPrompt(List<Message> messages, {String? systemPrompt}) {
    final buffer = StringBuffer();

    // Add system prompt first if available
    if (systemPrompt != null && systemPrompt.isNotEmpty) {
      buffer.writeln(systemPrompt);
      buffer.writeln();
    }

    // Add messages without role markers - let the service handle formatting
    for (final message in messages) {
      buffer.writeln(message.content);
    }

    return buffer.toString().trim();
  }
}
