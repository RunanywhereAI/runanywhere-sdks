// SPDX-License-Identifier: Apache-2.0
//
// parity_test.dart — GAP 09 Phase 20 streaming parity test (Dart).
// See tests/streaming/README.md.

import 'package:test/test.dart';

void main() {
  group('GAP 09 streaming parity', () {
    test('voiceAgent streams expected events',
        () async {
      // GAP 09 ship: scaffold + adapter wiring; golden events land in Wave D.
      // final adapter = VoiceAgentStreamAdapter(handle);
      // final collected = await adapter.stream()
      //     .map(_eventSummary).take(20).toList();
      // expect(collected, expectedGoldenSequence());
    }, skip: 'GAP 09 ship: golden events file lands in Wave D.');

    test('cancellation yields no stale events',
        () async {
      // expect: after subscription.cancel(), zero events within 100ms.
    }, skip: 'GAP 09 ship: pairs with golden events file in Wave D.');
  });
}
