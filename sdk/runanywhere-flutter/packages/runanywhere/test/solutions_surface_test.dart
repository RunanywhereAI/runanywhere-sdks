// SPDX-License-Identifier: Apache-2.0
//
// Generated Solutions public-surface coverage — mirrors Swift
// SolutionsSurfaceTests.swift. The commons layer is covered by
// test_solution_runner.cpp; this pins the SDK-layer proto round-trip plus the
// `RunAnywhere.solutions` capability shape so a drift in the generated types or
// the public `run` surface fails at unit-test time. The lifecycle verbs bottom
// out in `dart_bridge_solutions.dart` (native), so we exercise only the
// proto-decode + capability surface here, matching the strategy in
// voice_agent_stream_adapter_test.dart.

import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/generated/solutions.pb.dart' hide SolutionHandle;
import 'package:runanywhere/public/capabilities/runanywhere_solutions.dart';
import 'package:runanywhere/public/runanywhere.dart';

void main() {
  group('Solutions generated surface', () {
    test('SolutionConfig carries voice agent oneof fields', () {
      final config = SolutionConfig()
        ..voiceAgent = (VoiceAgentConfig()
          ..llmModelId = 'qwen3-4b-q4_k_m'
          ..sttModelId = 'whisper-base'
          ..ttsModelId = 'kokoro'
          ..vadModelId = 'silero-v5'
          ..sampleRateHz = 16000
          ..chunkMs = 20
          ..maxContextTokens = 4096
          ..typeKind = SolutionType.SOLUTION_TYPE_VOICE_AGENT);

      expect(config.hasVoiceAgent(), isTrue);
      final voiceAgent = config.voiceAgent;
      expect(voiceAgent.llmModelId, 'qwen3-4b-q4_k_m');
      expect(voiceAgent.sttModelId, 'whisper-base');
      expect(voiceAgent.ttsModelId, 'kokoro');
      expect(voiceAgent.vadModelId, 'silero-v5');
      expect(voiceAgent.sampleRateHz, 16000);
      expect(voiceAgent.chunkMs, 20);
      expect(voiceAgent.maxContextTokens, 4096);
      expect(voiceAgent.typeKind, SolutionType.SOLUTION_TYPE_VOICE_AGENT);
    });

    test('SolutionConfig round-trips through proto bytes', () {
      final config = SolutionConfig()
        ..voiceAgent = (VoiceAgentConfig()..llmModelId = 'qwen3-4b-q4_k_m');

      final bytes = config.writeToBuffer();
      expect(bytes, isNotEmpty);
      expect(SolutionConfig.fromBuffer(Uint8List.fromList(bytes)), config);
    });

    test('RunAnywhere.solutions exposes the Solutions capability', () {
      final capability = RunAnywhere.solutions;
      expect(capability, isA<RunAnywhereSolutions>());
      // Pin the run signature: exactly one of config / configBytes / yaml.
      final Future<SolutionHandle> Function({
        SolutionConfig? config,
        Uint8List? configBytes,
        String? yaml,
      }) run = capability.run;
      expect(run, isNotNull);
    });
  });
}
