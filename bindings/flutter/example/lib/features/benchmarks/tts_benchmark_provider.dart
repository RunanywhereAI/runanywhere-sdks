import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere_ai/features/benchmarks/benchmark_runner.dart';
import 'package:runanywhere_ai/features/benchmarks/benchmark_types.dart';

/// Benchmarks TTS synthesis with short and medium text inputs.
///
/// Mirrors iOS `TTSBenchmarkProvider.swift`: load voice synthesize (not
/// speak — no playback) report latency, produced audio duration, and
/// character throughput unload.
class TTSBenchmarkProvider implements BenchmarkScenarioProvider {
  @override
  BenchmarkCategory get category => BenchmarkCategory.tts;

  @override
  List<BenchmarkScenario> scenarios() => const [
        BenchmarkScenario(
          name: 'Short Text',
          category: BenchmarkCategory.tts,
          parameters: {'length': 'short'},
        ),
        BenchmarkScenario(
          name: 'Medium Text',
          category: BenchmarkCategory.tts,
          parameters: {'length': 'medium'},
        ),
      ];

  @override
  Future<BenchmarkMetrics> execute(
    BenchmarkScenario scenario,
    sdk.ModelInfo model,
  ) async {
    final metrics = BenchmarkMetrics();

    final text = scenario.parameters?['length'] == 'short'
        ? 'Hello, this is a test.'
        : 'The quick brown fox jumps over the lazy dog. Machine learning '
            'models can generate speech from text with remarkable quality '
            'and natural intonation.';

    // Load
    final loadStopwatch = Stopwatch()..start();
    await sdk.RunAnywhere.models.load(model.id);
    metrics.loadTimeMs = loadStopwatch.elapsedMicroseconds / 1000.0;

    try {
      // Synthesize (not speak)
      final benchStopwatch = Stopwatch()..start();
      final result = await sdk.RunAnywhere.tts.synthesize(text);
      metrics.endToEndLatencyMs = benchStopwatch.elapsedMicroseconds / 1000.0;

      // Commons owns audio duration (TTSOutput.duration_ms). Never derive from
      // PCM byte length / sample rate.
      final durationMs = result.durationMs;
      if (durationMs > 0) {
        metrics.audioDurationSeconds = durationMs / 1000.0;
      }
      metrics.charactersProcessed = text.length;

      // memoryDeltaBytes stays 0: no portable Dart available-memory probe.
      return metrics;
    } finally {
      try {
        await sdk.RunAnywhere.models.unloadAll(
          sdk.ModelCategory.MODEL_CATEGORY_SPEECH_SYNTHESIS,
        );
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  }
}
