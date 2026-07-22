// SPDX-License-Identifier: Apache-2.0

import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/convenience/ra_convenience.dart';
import 'package:runanywhere/generated/diarization.pb.dart';

void main() {
  group('DiarizationOptions threshold validation', () {
    const invalidThresholds = <String, double>{
      'negative': -0.01,
      'above one': 1.01,
      'NaN': double.nan,
    };

    for (final entry in invalidThresholds.entries) {
      test('rejects ${entry.key}', () {
        final options = DiarizationOptions()..threshold = entry.value;

        expect(options.validate, throwsA(isA<SDKException>()));
      });
    }
  });
}
