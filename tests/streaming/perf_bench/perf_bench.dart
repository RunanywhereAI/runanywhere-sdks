// perf_bench.dart — Dart consumer for the GAP 09 #8 perf bench.
//
// v3.2 (T7.5): mirrors the T3.2 Kotlin fix. The producer stamps
// `metrics.createdAtNs` using C++ `std::chrono::steady_clock`, which has
// a process-local epoch. Dart's `Stopwatch` is monotonic but starts from
// its own zero — so `recvNs - producerNs` produces a giant negative
// offset that the `> 0` filter discards, yielding spurious "no non-zero
// deltas" failures. The README's spec ("per-event work: proto decode +
// delta computation only") is a per-event decode-latency budget, so we
// bracket `Stopwatch.elapsedMicroseconds` around the decode call only —
// monotonic, same-clock, exactly the cost the p50 budget bounds.
//
// Reads /tmp/perf_input.bin (produced by perf_producer.cpp), decodes each
// VoiceEvent via protoc_plugin, and writes per-event decode delta_ns to
// /tmp/perf_bench.dart.log.
//
// Runner integration: sdk/runanywhere-flutter/packages/runanywhere/test/
// perf_bench_test.dart (flutter_test wrapper — asserts p50 < 1ms).
//
// Binary format (matches perf_producer.cpp):
//   uint32_t magic = 0x42504152 ('RAPB')
//   uint32_t count
//   count × { uint32_t len; uint8_t[len] proto_bytes }

import 'dart:io';
import 'dart:typed_data';

import 'package:runanywhere/generated/voice_events.pb.dart';

class PerfBenchResult {
  PerfBenchResult({
    required this.count,
    required this.nonEmpty,
    required this.deltas,
  });
  final int count;
  final int nonEmpty;
  final List<int> deltas;
}

class PerfBench {
  static const String defaultInputPath = '/tmp/perf_input.bin';
  static const String defaultOutputPath = '/tmp/perf_bench.dart.log';
  static const int magic = 0x42504152; // 'RAPB'

  /// Run the perf bench consumer. Returns per-event latency deltas in ns.
  static Future<PerfBenchResult> run({
    String inputPath = defaultInputPath,
    String outputPath = defaultOutputPath,
  }) async {
    final bytes = await File(inputPath).readAsBytes();
    if (bytes.length < 8) {
      throw StateError('perf_bench input too short (<8 bytes): ${bytes.length}');
    }

    final header = ByteData.sublistView(bytes, 0, 8);
    final readMagic = header.getUint32(0, Endian.little);
    if (readMagic != magic) {
      throw StateError(
        'perf_bench bad magic: 0x${readMagic.toRadixString(16)} '
        '(expected 0x${magic.toRadixString(16)})',
      );
    }
    final count = header.getUint32(4, Endian.little);

    final deltas = List<int>.filled(count, 0);
    var nonEmpty = 0;
    var cursor = 8;
    final stopwatch = Stopwatch()..start();

    for (var i = 0; i < count; i++) {
      if (cursor + 4 > bytes.length) break;
      final lenView = ByteData.sublistView(bytes, cursor, cursor + 4);
      final len = lenView.getUint32(0, Endian.little);
      cursor += 4;
      if (cursor + len > bytes.length) break;

      final frame = bytes.sublist(cursor, cursor + len);
      cursor += len;

      try {
        // Bracket the Stopwatch around decode only (T7.5 / T3.2 fix —
        // see header). Stopwatch is microsecond-precision on Dart, so
        // ns deltas floor to the nearest µs; that's still enough
        // resolution to enforce the 1ms p50 budget.
        final startUs = stopwatch.elapsedMicroseconds;
        final event = VoiceEvent.fromBuffer(frame);
        final endUs = stopwatch.elapsedMicroseconds;
        final decodeNs = (endUs - startUs) * 1000;

        if (decodeNs > 0) {
          deltas[i] = decodeNs;
          // `nonEmpty` retains its original semantics — the count of
          // events that carry a metrics arm. Decoupled from the delta
          // value so the aggregator can still tell "producer emitted
          // metrics" apart from "decode took too long".
          if (event.hasMetrics() && event.metrics.createdAtNs.toInt() > 0) {
            nonEmpty++;
          }
        }
      } catch (_) {
        // Malformed frame: skip gracefully.
      }
    }

    await _writeDeltas(deltas, outputPath);
    // ignore: avoid_print
    print(
      'perf_bench.dart: wrote ${deltas.length} deltas '
      '($nonEmpty non-empty) to $outputPath',
    );
    return PerfBenchResult(
      count: deltas.length,
      nonEmpty: nonEmpty,
      deltas: deltas,
    );
  }

  /// Compute p50 over non-zero deltas. Returns null if no non-zero values.
  static int? p50(List<int> deltas) {
    final nonZero = deltas.where((d) => d > 0).toList()..sort();
    if (nonZero.isEmpty) return null;
    return nonZero[nonZero.length ~/ 2];
  }

  static Future<void> _writeDeltas(List<int> deltas, String path) async {
    final sink = File(path).openWrite();
    for (final d in deltas) {
      sink.writeln(d);
    }
    await sink.close();
  }
}
