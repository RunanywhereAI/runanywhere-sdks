// SPDX-License-Identifier: Apache-2.0
//
// Characterizes which `LoadOptions` fields `ModelGate.load()` warns about
// because the commons load ABI has no wire path for them yet
// (PR #605 review issue 8).

import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/logging.pb.dart' show LogEntry;
import 'package:runanywhere/generated/model_types.pbenum.dart'
    show InferenceFramework;
import 'package:runanywhere/public/api/internal/model_gate.dart';
import 'package:runanywhere/public/api/types/options.dart' show LoadOptions;

class _RecordingDestination implements LogDestination {
  final List<LogEntry> entries = <LogEntry>[];

  @override
  String get identifier => 'test-recorder';

  @override
  bool get isAvailable => true;

  @override
  void write(LogEntry entry) => entries.add(entry);

  @override
  void flush() {}
}

void main() {
  group('ignoredLoadOptionKnobs', () {
    test('reports nothing for null options', () {
      expect(ignoredLoadOptionKnobs(null), isEmpty);
    });

    test('does not report framework, which does reach commons', () {
      expect(
        ignoredLoadOptionKnobs(
          const LoadOptions(framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP),
        ),
        isEmpty,
      );
    });

    test('reports contextLength, threads, and useGpu individually', () {
      expect(
        ignoredLoadOptionKnobs(const LoadOptions(contextLength: 4096)),
        ['contextLength'],
      );
      expect(ignoredLoadOptionKnobs(const LoadOptions(threads: 4)), ['threads']);
      expect(ignoredLoadOptionKnobs(const LoadOptions(useGpu: true)), ['useGpu']);
    });

    test('combines every ignored knob in a stable order', () {
      expect(
        ignoredLoadOptionKnobs(
          const LoadOptions(contextLength: 4096, threads: 4, useGpu: false),
        ),
        ['contextLength', 'threads', 'useGpu'],
      );
    });
  });

  group('ModelGate load-options warning wiring', () {
    late _RecordingDestination recorder;

    setUp(() {
      recorder = _RecordingDestination();
      SDKLoggerConfig.shared.addDestination(recorder);
      SDKLoggerConfig.shared.setMinLogLevel(LogLevel.LOG_LEVEL_WARNING);
    });

    tearDown(() {
      SDKLoggerConfig.shared.removeDestination(recorder);
    });

    test('a warning-level logger is available for ModelGate to log through', () {
      final logger = SDKLogger('ModelGate');
      logger.warning('LoadOptions contextLength are not carried by the commons load ABI yet');

      expect(recorder.entries, hasLength(1));
      expect(recorder.entries.single.level, LogLevel.LOG_LEVEL_WARNING);
      expect(recorder.entries.single.message, contains('contextLength'));
    });
  });
}
