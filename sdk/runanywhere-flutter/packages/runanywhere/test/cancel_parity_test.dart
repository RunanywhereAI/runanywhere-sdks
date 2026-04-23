// cancel_parity_test.dart — flutter_test runner for GAP 09 #7 (v3.1 Phase 5.1).

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../../../../tests/streaming/cancel_parity/cancel_parity.dart';

void main() {
  group('cancel_parity (dart)', () {
    setUpAll(() {
      if (!File(CancelParity.defaultInputPath).existsSync()) {
        fail(
          'cancel_parity input missing at ${CancelParity.defaultInputPath}',
        );
      }
    });

    test('records interrupt ordinal and writes trace', () async {
      final result = await CancelParity.run();
      expect(result.total, greaterThan(0));
      expect(result.interruptOrdinal, isNotNull);
    });
  });
}
