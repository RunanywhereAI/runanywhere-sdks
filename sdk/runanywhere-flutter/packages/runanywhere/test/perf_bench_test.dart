import 'package:flutter_test/flutter_test.dart';

import 'fixtures/streaming_proto_fixtures.dart';

void main() {
  group('perf_bench (dart)', () {
    test('decodes generated proto frames and emits deltas', () {
      final result = decodePerfBenchFixture(
        buildPerfBenchFixture(),
        receivedAtNs: <int>[1100, 2200, 3500, 4700, 5900],
      );

      expect(result.count, greaterThan(0),
          reason: 'expected >0 events decoded');
      expect(result.nonEmpty, greaterThan(0),
          reason: 'expected >0 non-empty deltas');
    });

    test('p50 delta below 1ms (1_000_000 ns)', () {
      final result = decodePerfBenchFixture(
        buildPerfBenchFixture(),
        receivedAtNs: <int>[1100, 2200, 3500, 4700, 5900],
      );
      final p50 = p50NonZeroDeltas(result.deltas);

      expect(
        p50,
        isNotNull,
        reason: 'no non-zero deltas — producer not emitting metrics arm?',
      );
      expect(
        p50!,
        lessThan(1000000),
        reason: 'p50 latency $p50 ns exceeds 1ms threshold',
      );
    });
  });
}
