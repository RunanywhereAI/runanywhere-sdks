// SPDX-License-Identifier: Apache-2.0
//
// `stt.openStream` / `vad.openStream` preflight and honesty contract: a
// container format is rejected before any native work starts, and a stream
// that cannot run never fabricates a successful terminal event.

import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/public/api/namespaces/stt.dart';
import 'package:runanywhere/public/api/namespaces/vad.dart';
import 'package:runanywhere/public/api/types/events.dart';
import 'package:runanywhere/public/api/types/inputs.dart';

void main() {
  group('stt.openStream', () {
    const api = SttApi();

    test('rejects a container format before touching the bridge', () {
      expect(
        () => api.openStream(
          const AudioFormatSpec(encoding: AudioEncoding.container, sampleRate: 16000),
        ),
        throwsA(isA<SDKException>()),
      );
    });

    test('surfaces not-initialized as a thrown error, not a fabricated stream', () {
      expect(
        api.openStream(
          const AudioFormatSpec(encoding: AudioEncoding.pcm16, sampleRate: 16000),
        ),
        throwsA(isA<SDKException>()),
      );
    });
  });

  group('vad.openStream', () {
    const api = VadApi();

    test('rejects a container format before touching the bridge', () {
      expect(
        () => api.openStream(
          const AudioFormatSpec(encoding: AudioEncoding.container, sampleRate: 16000),
        ),
        throwsA(isA<SDKException>()),
      );
    });

    test(
      'never fabricates VadCompleted when the SDK is not initialized',
      () async {
        final stream = api.openStream(
          const AudioFormatSpec(encoding: AudioEncoding.pcm16, sampleRate: 16000),
        );
        final events = await stream.events.toList();
        expect(events, hasLength(1));
        expect(events.single, isA<VadFailed>());
      },
    );
  });
}
