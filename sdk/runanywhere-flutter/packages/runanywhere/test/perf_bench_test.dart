// perf_bench_test.dart — flutter_test runner for GAP 09 #8 p50 benchmark.
//
// v3.1: asserts p50 < 1ms (Dart's Stopwatch precision is µs, so the
// threshold is effectively "under 1 ms to the nearest µs").
//
// Pre-condition: /tmp/perf_input.bin must exist.
//
// To run:
//   cmake --build build/macos-release --target perf_producer && \
//   ./build/macos-release/tests/streaming/perf_bench/perf_producer && \
//   cd sdk/runanywhere-flutter/packages/runanywhere && flutter test test/perf_bench_test.dart

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../../tests/streaming/perf_bench/perf_bench.dart';

void main() {
  group('perf_bench (dart)', () {
    setUpAll(() {
      if (!File(PerfBench.defaultInputPath).existsSync()) {
        fail(
          'perf_bench input missing at ${PerfBench.defaultInputPath}. Run: '
          'cmake --build build/macos-release --target perf_producer && '
          './build/macos-release/tests/streaming/perf_bench/perf_producer',
        );
      }
    });

    test('decodes proto and emits deltas', () async {
      final result = await PerfBench.run();
      expect(result.count, greaterThan(0), reason: 'expected >0 events decoded');
      expect(result.nonEmpty, greaterThan(0), reason: 'expected >0 non-empty deltas');
    });

    test('p50 delta below 1ms (1_000_000 ns)', () async {
      final result = await PerfBench.run();
      final p50 = PerfBench.p50(result.deltas);
      expect(
        p50,
        isNotNull,
        reason: 'no non-zero deltas — producer not emitting metrics arm?',
      );
      expect(
        p50!,
        lessThan(1000000),
        reason: 'p50 latency $p50 ns exceeds 1ms threshold (GAP 09 #8)',
      );
    });
  });
}
