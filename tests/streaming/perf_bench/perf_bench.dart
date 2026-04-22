// perf_bench.dart — Dart consumer for the GAP 09 #8 perf bench.
//
// v2.1 quick-wins Item 3 scaffold. Reads /tmp/perf_input.bin (produced
// by tests/streaming/perf_bench/perf_producer.cpp), decodes each
// VoiceEvent via protoc_plugin output, computes the consumer-side
// latency delta, and writes per-event delta_ns to /tmp/perf_bench.dart.log.
//
// Status: SCAFFOLD. Per-SDK runner integration (`flutter test` with
// dart:ffi shared-lib resolution) is the v2.1-2 follow-up.

import 'dart:io';
import 'dart:typed_data';
// import 'package:runanywhere/generated/voice_events.pb.dart';

class PerfBench {
  static const String inputPath = '/tmp/perf_input.bin';
  static const String outputPath = '/tmp/perf_bench.dart.log';
  static const int magic = 0x42504152; // 'RAPB'

  static Future<void> run() async {
    final file = File(inputPath);
    final bytes = await file.readAsBytes();
    final view = ByteData.view(bytes.buffer);

    if (bytes.length < 8) {
      throw StateError('Input too short');
    }
    final readMagic = view.getUint32(0, Endian.little);
    if (readMagic != magic) {
      throw StateError('Bad magic: ${readMagic.toRadixString(16)}');
    }
    final count = view.getUint32(4, Endian.little);

    final deltas = Int64List(count);
    var cursor = 8;
    final stopwatch = Stopwatch()..start();

    for (var i = 0; i < count; i++) {
      if (cursor + 4 > bytes.length) break;
      final len = view.getUint32(cursor, Endian.little);
      cursor += 4;
      if (cursor + len > bytes.length) break;
      final frame = bytes.sublist(cursor, cursor + len);
      cursor += len;

      // Mark consumer-receive timestamp BEFORE decode to include
      // proto-decode cost in latency.
      final recvNs = stopwatch.elapsedMicroseconds * 1000;

      // SCAFFOLD: replace with actual protoc_plugin decode.
      // final event = VoiceEvent.fromBuffer(frame);
      // final producerNs = event.metrics.tokensGenerated.toInt();
      // ignore: unused_local_variable
      final _ = frame.length;
      final producerNs = recvNs; // scaffold no-op

      deltas[i] = recvNs - producerNs;
    }

    final outFile = File(outputPath);
    await outFile.writeAsString(deltas.map((d) => '$d').join('\n') + '\n');
    print('perf_bench.dart: wrote ${deltas.length} deltas to $outputPath');
  }
}

// flutter test entry point (commented until v2.1-2 integrates):
// import 'package:test/test.dart';
// void main() {
//   test('p50 under 1ms', () async {
//     await PerfBench.run();
//     // Aggregator asserts the p50 threshold.
//   });
// }
