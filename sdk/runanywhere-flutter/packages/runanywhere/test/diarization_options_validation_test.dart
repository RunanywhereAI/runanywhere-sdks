// SPDX-License-Identifier: Apache-2.0

// Release-scope note (cross-SDK parity): Flutter's diarization surface is
// intentionally limited to the generated proto types plus option validation for
// this release. There is no DartBridge diarization slice and no
// `RunAnywhere.diarize` Dart API yet — a functional diarization binding ships
// only on Swift, Kotlin, and Web. React Native is likewise proto-only for now.
// This gap is deliberate and tracked as a follow-up parity item; this test
// guards the one surface Flutter does expose (DiarizationOptions.validate).

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
