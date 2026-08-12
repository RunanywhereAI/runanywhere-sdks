import 'package:flutter_test/flutter_test.dart';

import 'fixtures/streaming_proto_fixtures.dart';

void main() {
  group('cancel_parity (dart)', () {
    test('records interrupt ordinal from generated proto frames', () {
      final result = decodeCancelParityFixture(buildCancelParityFixture());

      expect(result.total, greaterThan(0));
      expect(result.interruptOrdinal, equals(2));
      expect(result.postCancelCount, isZero);
    });
  });
}
