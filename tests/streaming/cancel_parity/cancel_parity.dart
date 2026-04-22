// cancel_parity.dart — Dart consumer for GAP 09 #7 (v3.1 Phase 5.1).

import 'dart:io';
import 'dart:typed_data';

import 'package:runanywhere/generated/voice_events.pb.dart';

class CancelParityResult {
  CancelParityResult({
    required this.total,
    required this.interruptOrdinal,
    required this.postCancelCount,
    required this.postCancelMaxDeltaNs,
  });
  final int total;
  final int? interruptOrdinal;
  final int postCancelCount;
  final int postCancelMaxDeltaNs;
}

class CancelParity {
  static const defaultInputPath = '/tmp/cancel_input.bin';
  static const defaultOutputPath = '/tmp/cancel_trace.dart.log';
  static const int magic = 0x43504152; // 'CPAR'

  static Future<CancelParityResult> run({
    String inputPath = defaultInputPath,
    String outputPath = defaultOutputPath,
  }) async {
    final bytes = await File(inputPath).readAsBytes();
    if (bytes.length < 8) {
      throw StateError('input too short');
    }
    final header = ByteData.sublistView(bytes, 0, 8);
    if (header.getUint32(0, Endian.little) != magic) {
      throw StateError('bad magic');
    }
    final count = header.getUint32(4, Endian.little);

    final lines = <String>[];
    var cursor = 8;
    int? interruptOrdinal;
    int? cancelNs;
    var postCancelCount = 0;
    var postCancelMaxDelta = 0;
    final stopwatch = Stopwatch()..start();

    for (var i = 0; i < count; i++) {
      if (cursor + 4 > bytes.length) break;
      final len = ByteData.sublistView(bytes, cursor, cursor + 4)
          .getUint32(0, Endian.little);
      cursor += 4;
      if (cursor + len > bytes.length) break;

      final recvNs = stopwatch.elapsedMicroseconds * 1000;
      final frame = bytes.sublist(cursor, cursor + len);
      cursor += len;

      String kind;
      try {
        final event = VoiceEvent.fromBuffer(frame);
        if (event.hasUserSaid()) {
          kind = 'userSaid';
        } else if (event.hasAssistantToken()) {
          kind = 'assistantToken';
        } else if (event.hasAudio()) {
          kind = 'audio';
        } else if (event.hasVad()) {
          kind = 'vad';
        } else if (event.hasState()) {
          kind = 'state';
        } else if (event.hasError()) {
          kind = 'error';
        } else if (event.hasInterrupted()) {
          kind = 'interrupted';
        } else if (event.hasMetrics()) {
          kind = 'metrics';
        } else {
          kind = 'unknown';
        }
      } catch (_) {
        kind = 'unknown';
      }
      lines.add('$i $kind $recvNs');

      if (kind == 'interrupted' && interruptOrdinal == null) {
        interruptOrdinal = i;
        cancelNs = recvNs;
      } else if (cancelNs != null) {
        postCancelCount++;
        final delta = recvNs - cancelNs;
        if (delta > postCancelMaxDelta) postCancelMaxDelta = delta;
      }
    }

    await File(outputPath).writeAsString(lines.join('\n') + '\n');
    return CancelParityResult(
      total: count,
      interruptOrdinal: interruptOrdinal,
      postCancelCount: postCancelCount,
      postCancelMaxDeltaNs: postCancelMaxDelta,
    );
  }
}
