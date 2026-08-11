// SPDX-License-Identifier: Apache-2.0
//
// Pins that DownloadProgressEvent exposes commons overall_progress and does
// not re-derive percent from bytesDone/bytesTotal.

import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/public/api/types/events.dart';

void main() {
  group('DownloadProgressEvent', () {
    test('carries commons overallProgress without inventing a byte ratio', () {
      const event = DownloadProgressEvent(
        operationId: 'model-a',
        bytesDone: 50,
        bytesTotal: 100,
        overallProgress: 0.42,
      );

      expect(event.overallProgress, 0.42);
      // Multi-file / early frames can disagree with a naive byte ratio —
      // consumers must use overallProgress, not bytesDone/bytesTotal.
      expect(event.bytesDone / event.bytesTotal, isNot(event.overallProgress));
    });

    test('overallProgress stays null when commons has not reported it', () {
      const event = DownloadProgressEvent(
        operationId: 'model-a',
        bytesDone: 10,
        bytesTotal: 100,
      );

      expect(event.overallProgress, isNull);
    });
  });
}
