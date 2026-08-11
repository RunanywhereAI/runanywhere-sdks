import 'dart:math' as math;
import 'dart:typed_data';

import 'package:runanywhere/runanywhere.dart' as sdk;
import 'package:runanywhere_ai/features/benchmarks/benchmark_runner.dart';
import 'package:runanywhere_ai/features/benchmarks/benchmark_types.dart';

/// Benchmarks STT transcription with deterministic synthetic audio inputs.
///
/// Mirrors iOS `STTBenchmarkProvider.swift` + `SyntheticInputGenerator`:
/// silent and sine-wave PCM Int16 mono buffers are generated in code (no
/// bundled audio asset) so results are reproducible.
class STTBenchmarkProvider implements BenchmarkScenarioProvider {
  static const int _sampleRate = 16000;

  @override
  BenchmarkCategory get category => BenchmarkCategory.stt;

  @override
  List<BenchmarkScenario> scenarios() => const [
        BenchmarkScenario(
          name: 'Silent 2s',
          category: BenchmarkCategory.stt,
          parameters: {'type': 'silent'},
        ),
        BenchmarkScenario(
          name: 'Sine Tone 3s',
          category: BenchmarkCategory.stt,
          parameters: {'type': 'sine'},
        ),
      ];

  @override
  Future<BenchmarkMetrics> execute(
    BenchmarkScenario scenario,
    sdk.ModelInfo model,
  ) async {
    final metrics = BenchmarkMetrics();

    // Load
    final loadStopwatch = Stopwatch()..start();
    await sdk.RunAnywhere.models.load(model.id);
    metrics.loadTimeMs = loadStopwatch.elapsedMicroseconds / 1000.0;

    try {
      // Generate audio
      final Uint8List audioData;
      final double audioDuration;
      if (scenario.parameters?['type'] == 'silent') {
        audioDuration = 2.0;
        audioData = _silentAudio(durationSeconds: audioDuration);
      } else {
        audioDuration = 3.0;
        audioData = _sineWaveAudio(durationSeconds: audioDuration);
      }

      // Transcribe raw PCM Int16 mono @ 16 kHz. Audio properties live on the
      // SDK-built STTAudioSource; the SDK detects the encoding from the bytes.
      final benchStopwatch = Stopwatch()..start();
      final result = await sdk.RunAnywhere.stt.transcribe(
        sdk.AudioInput.pcm16(audioData),
      );
      final elapsedMs = benchStopwatch.elapsedMicroseconds / 1000.0;
      metrics.endToEndLatencyMs = elapsedMs;

      metrics.audioLengthSeconds = audioDuration;
      // Commons owns transcribed duration (STTResult.durationMs). Never fall back
      // to the fixture length — omit RTF when the engine did not report duration.
      if (result.durationMs > 0) {
        metrics.realTimeFactor = elapsedMs / result.durationMs;
      }

      // memoryDeltaBytes stays 0: no portable Dart available-memory probe.
      return metrics;
    } finally {
      try {
        await sdk.RunAnywhere.models.unloadAll(
          sdk.ModelCategory.MODEL_CATEGORY_SPEECH_RECOGNITION,
        );
      } catch (_) {
        // Best-effort cleanup.
      }
    }
  }

  /// Silent PCM Int16 mono audio buffer.
  static Uint8List _silentAudio({
    required double durationSeconds,
    int sampleRate = _sampleRate,
  }) {
    final sampleCount = (durationSeconds * sampleRate).round();
    return Uint8List(sampleCount * 2);
  }

  /// Sine-wave PCM Int16 little-endian mono audio buffer.
  /// Explicit input/fixture synthesis only — not model-output math.
  static Uint8List _sineWaveAudio({
    required double durationSeconds,
    double frequencyHz = 440.0,
    int sampleRate = _sampleRate,
  }) {
    final sampleCount = (durationSeconds * sampleRate).round();
    final bytes = ByteData(sampleCount * 2);
    // Fixture amplitude (Int16.max / 2), matching iOS SyntheticInputGenerator.
    const amplitude = 32767 / 2;
    for (var i = 0; i < sampleCount; i++) {
      final time = i / sampleRate;
      final value =
          (math.sin(2.0 * math.pi * frequencyHz * time) * amplitude).round();
      bytes.setInt16(i * 2, value, Endian.little);
    }
    return bytes.buffer.asUint8List();
  }
}
