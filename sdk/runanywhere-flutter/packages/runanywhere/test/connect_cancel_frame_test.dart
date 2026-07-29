import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/generated/connect.pb.dart';

void main() {
  group('Connect cancel framing', () {
    test('cancel request round-trips inside ConnectClientFrame', () {
      final frame = ConnectClientFrame(
        cancel: ConnectInvocationCancelRequest(
          sessionId: 'session-1',
          requestId: 'req-42',
        ),
      );
      final decoded = ConnectClientFrame.fromBuffer(frame.writeToBuffer());
      expect(decoded.hasCancel(), isTrue);
      expect(decoded.cancel.sessionId, 'session-1');
      expect(decoded.cancel.requestId, 'req-42');
      expect(decoded.whichPayload(), ConnectClientFrame_Payload.cancel);
    });

    test('length-prefixed frames retain partial headers across chunks', () {
      final payload = ConnectClientFrame(
        cancel: ConnectInvocationCancelRequest(
          sessionId: 's',
          requestId: 'r',
        ),
      ).writeToBuffer();
      final header = ByteData(4)..setUint32(0, payload.length, Endian.big);
      final framed = Uint8List.fromList([...header.buffer.asUint8List(), ...payload]);

      final first = framed.sublist(0, 3);
      final second = framed.sublist(3);
      expect(first.length, lessThan(4));

      final buffer = <int>[...first, ...second];
      final length = ByteData.sublistView(
        Uint8List.fromList(buffer.sublist(0, 4)),
      ).getUint32(0, Endian.big);
      expect(length, payload.length);
      final body = buffer.sublist(4, 4 + length);
      final decoded = ConnectClientFrame.fromBuffer(body);
      expect(decoded.cancel.requestId, 'r');
    });
  });
}
