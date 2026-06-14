import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere_ai/features/benchmarks/benchmark_runner.dart';
import 'package:runanywhere_ai/features/benchmarks/benchmark_types.dart';

/// Benchmarks LLM generation with short/medium/long token counts.
///
/// Mirrors iOS `LLMBenchmarkProvider.swift`: load → warmup → streamed
/// generation aggregated into TTFT / tokens-per-second / prefill / decode
/// throughput → unload.
class LLMBenchmarkProvider implements BenchmarkScenarioProvider {
  @override
  BenchmarkCategory get category => BenchmarkCategory.llm;

  @override
  List<BenchmarkScenario> scenarios() => const [
        BenchmarkScenario(
          name: 'Short (50 tokens)',
          category: BenchmarkCategory.llm,
          parameters: {'maxTokens': '50'},
        ),
        BenchmarkScenario(
          name: 'Medium (256 tokens)',
          category: BenchmarkCategory.llm,
          parameters: {'maxTokens': '256'},
        ),
        BenchmarkScenario(
          name: 'Long (512 tokens)',
          category: BenchmarkCategory.llm,
          parameters: {'maxTokens': '512'},
        ),
      ];

  @override
  Future<BenchmarkMetrics> execute(
    BenchmarkScenario scenario,
    sdk.ModelInfo model,
  ) async {
    final maxTokens =
        int.tryParse(scenario.parameters?['maxTokens'] ?? '') ?? 512;
    final metrics = BenchmarkMetrics();

    // Ensure clean state: unload any LLM left over from Chat or a previous
    // run (mirrors iOS pre-unload).
    try {
      await sdk.RunAnywhere.llm.unload();
    } catch (_) {
      // Nothing loaded — fine.
    }

    // Load
    final loadStopwatch = Stopwatch()..start();
    await sdk.RunAnywhere.llm.load(model.id);
    metrics.loadTimeMs = loadStopwatch.elapsedMicroseconds / 1000.0;

    try {
      // Warmup: tiny generation drained to the terminal event.
      final warmupStopwatch = Stopwatch()..start();
      final warmupEvents = sdk.RunAnywhere.llm.generateStream(
        'Hello',
        sdk.LLMGenerationOptions(maxTokens: 5, temperature: 0.0),
      );
      await for (final event in warmupEvents) {
        if (event.isFinal) break;
      }
      metrics.warmupTimeMs = warmupStopwatch.elapsedMicroseconds / 1000.0;

      // Benchmark
      const systemPrompt =
          'You are a helpful assistant. Always give extremely detailed, '
          'thorough responses. Never stop early. Use the full response '
          'length available to you. Elaborate on every point with examples '
          'and explanations.';
      const prompt =
          'Write a very long and detailed explanation of how neural networks '
          'work, covering perceptrons, activation functions, '
          'backpropagation, gradient descent, loss functions, convolutional '
          'layers, recurrent layers, transformers, attention mechanisms, and '
          'training procedures. Be as thorough as possible.';

      final benchStopwatch = Stopwatch()..start();
      final result = await sdk.RunAnywhere.aggregateStream(
        prompt: prompt,
        events: sdk.RunAnywhere.llm.generateStream(
          prompt,
          sdk.LLMGenerationOptions(
            maxTokens: maxTokens,
            temperature: 0.0,
            systemPrompt: systemPrompt,
          ),
        ),
      );
      final wallMs = benchStopwatch.elapsedMicroseconds / 1000.0;

      if (result.errorMessage.isNotEmpty) {
        throw Exception(result.errorMessage);
      }

      final generationMs =
          result.generationTimeMs > 0 ? result.generationTimeMs : wallMs;
      metrics.endToEndLatencyMs = generationMs;
      metrics.ttftMs = result.ttftMs > 0 ? result.ttftMs : null;
      metrics.tokensPerSecond =
          result.tokensPerSecond > 0 ? result.tokensPerSecond : null;
      metrics.inputTokens = result.inputTokens > 0 ? result.inputTokens : null;
      metrics.outputTokens =
          result.tokensGenerated > 0 ? result.tokensGenerated : null;

      final decodeTimeMs = result.decodeTimeMs.toInt();
      if (decodeTimeMs > 0 && result.tokensGenerated > 0) {
        metrics.decodeTokensPerSecond =
            result.tokensGenerated / (decodeTimeMs / 1000.0);
      }
      final promptEvalTimeMs = result.promptEvalTimeMs.toInt();
      if (promptEvalTimeMs > 0 && result.inputTokens > 0) {
        metrics.prefillTokensPerSecond =
            result.inputTokens / (promptEvalTimeMs / 1000.0);
      }

      // memoryDeltaBytes stays 0: Dart has no portable available-memory
      // probe (iOS uses os_proc_available_memory).
      return metrics;
    } finally {
      try {
        await sdk.RunAnywhere.llm.unload();
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  }
}
