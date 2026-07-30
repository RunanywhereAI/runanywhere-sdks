import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere_ai/features/benchmarks/benchmark_runner.dart';
import 'package:runanywhere_ai/features/benchmarks/benchmark_types.dart';

/// Benchmarks LLM generation with short/medium/long token counts.
///
/// Mirrors iOS `LLMBenchmarkProvider.swift`: load warmup streamed
/// generation aggregated into TTFT / tokens-per-second / prefill / decode
/// throughput unload.
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
      await sdk.RunAnywhere.models.unload(
        sdk.ModelCategory.MODEL_CATEGORY_LANGUAGE,
      );
    } catch (_) {
      // Nothing loaded — fine.
    }

    // Load
    final loadStopwatch = Stopwatch()..start();
    await sdk.RunAnywhere.models.load(model.id);
    metrics.loadTimeMs = loadStopwatch.elapsedMicroseconds / 1000.0;

    try {
      // Warmup: tiny generation drained to the terminal event.
      final warmupStopwatch = Stopwatch()..start();
      final warmupEvents = sdk.RunAnywhere.llm.generateStream(
        'Hello',
        options: sdk.LlmOptions(maxOutputTokens: 5, temperature: 0.0),
      );
      await for (final event in warmupEvents) {
        if (event is sdk.GenerationCompleted) break;
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
      sdk.GenerationResult? result;
      await for (final event in sdk.RunAnywhere.llm.generateStream(
        prompt,
        options: sdk.LlmOptions(
          maxOutputTokens: maxTokens,
          temperature: 0.0,
          systemPrompt: systemPrompt,
        ),
      )) {
        if (event is sdk.GenerationCompleted) result = event.result;
      }
      final wallMs = benchStopwatch.elapsedMicroseconds / 1000.0;

      if (result == null) {
        throw Exception('Generation produced no terminal result');
      }

      metrics.endToEndLatencyMs = wallMs;
      metrics.ttftMs = result.timeToFirstTokenMs > 0
          ? result.timeToFirstTokenMs.toDouble()
          : null;
      metrics.tokensPerSecond =
          result.tokensPerSecond > 0 ? result.tokensPerSecond : null;
      metrics.inputTokens = result.inputTokens > 0 ? result.inputTokens : null;
      metrics.outputTokens =
          result.outputTokens > 0 ? result.outputTokens : null;

      // memoryDeltaBytes stays 0: Dart has no portable available-memory
      // probe (iOS uses os_proc_available_memory).
      return metrics;
    } finally {
      try {
        await sdk.RunAnywhere.models.unload(
          sdk.ModelCategory.MODEL_CATEGORY_LANGUAGE,
        );
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  }
}
