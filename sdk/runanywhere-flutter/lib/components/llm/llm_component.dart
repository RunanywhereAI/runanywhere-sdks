import '../../core/components/base_component.dart';
import '../../core/types/sdk_component.dart';
import '../../core/protocols/component/component_configuration.dart';
import '../../core/module_registry.dart' as core show ModuleRegistry, LLMService, LLMGenerationOptions;

/// LLM (Language Model) Component Configuration
class LLMConfiguration implements ComponentConfiguration {
  final String? modelId;
  final int contextLength;
  final bool useGPUIfAvailable;
  final String? quantizationLevel;

  LLMConfiguration({
    this.modelId,
    this.contextLength = 2048,
    this.useGPUIfAvailable = true,
    this.quantizationLevel,
  });

  @override
  void validate() {
    if (contextLength <= 0) {
      throw ArgumentError('Context length must be positive');
    }
  }
}

/// LLM Component Input
class LLMInput implements ComponentInput {
  final String prompt;
  final LLMGenerationOptions options;

  LLMInput({
    required this.prompt,
    required this.options,
  });

  @override
  void validate() {
    if (prompt.isEmpty) {
      throw ArgumentError('Prompt cannot be empty');
    }
  }
}

/// LLM Component Output
class LLMOutput implements ComponentOutput {
  final String text;
  final int tokensUsed;
  final int latencyMs;
  @override
  final DateTime timestamp;

  LLMOutput({
    required this.text,
    required this.tokensUsed,
    required this.latencyMs,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// LLM Generation Options
class LLMGenerationOptions {
  final int maxTokens;
  final double temperature;
  final String? systemPrompt;

  LLMGenerationOptions({
    this.maxTokens = 500,
    this.temperature = 0.7,
    this.systemPrompt,
  });
}

/// LLM Component
class LLMComponent extends BaseComponent<core.LLMService> {
  @override
  SDKComponent get componentType => SDKComponent.llm;

  final LLMConfiguration llmConfig;

  LLMComponent({
    required this.llmConfig,
    super.serviceContainer,
  }) : super(configuration: llmConfig);

  @override
  Future<core.LLMService> createService() async {
    final provider = core.ModuleRegistry.shared.llmProvider(modelId: llmConfig.modelId);
    if (provider == null) {
      throw StateError('No LLM provider available');
    }
    return await provider.createLLMService(llmConfig);
  }

  /// Generate text
  Future<LLMOutput> generate(LLMInput input) async {
    ensureReady();
    final service = this.service;
    if (service == null) {
      throw StateError('LLM service not initialized');
    }

    final result = await service.generate(
      prompt: input.prompt,
      options: core.LLMGenerationOptions(
        maxTokens: input.options.maxTokens,
        temperature: input.options.temperature,
      ),
    );

    return LLMOutput(
      text: result.text,
      tokensUsed: 0, // TODO: Get from result
      latencyMs: 0, // TODO: Get from result
      timestamp: DateTime.now(),
    );
  }

  /// Generate text stream
  Stream<String> generateStream(LLMInput input) {
    ensureReady();
    final service = this.service;
    if (service == null) {
      throw StateError('LLM service not initialized');
    }

    return service.generateStream(
      prompt: input.prompt,
      options: core.LLMGenerationOptions(
        maxTokens: input.options.maxTokens,
        temperature: input.options.temperature,
      ),
    );
  }
}

