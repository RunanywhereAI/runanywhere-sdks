// SPDX-License-Identifier: Apache-2.0

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';

import 'fixtures/streaming_proto_fixtures.dart';

void main() {
  group('streaming parity (dart)', () {
    test('voice events match generated proto fixture lines', () {
      final actual = voiceParityEvents().map(formatVoiceEvent).toList();
      expect(actual, equals(expectedVoiceParityLines()));
    });

    test('framed voice events round-trip through generated protos', () {
      final bytes = encodeVoiceEventFrames(
        voiceParityEvents(),
        magic: perfBenchMagic,
      );
      final decoded = decodeVoiceEventFrames(bytes, magic: perfBenchMagic);
      final actual = decoded.map(formatVoiceEvent).toList();

      expect(actual, equals(expectedVoiceParityLines()));
    });

    test('stream cancellation drops post-cancel emissions', () async {
      final controller = StreamController<int>();
      final received = <int>[];
      final subscription = controller.stream.listen(received.add);

      controller.add(1);
      await Future<void>.delayed(Duration.zero);
      await subscription.cancel();
      controller.add(2);
      await Future<void>.delayed(Duration.zero);

      expect(received, equals(<int>[1]));
      await controller.close();
    });
  });
}
