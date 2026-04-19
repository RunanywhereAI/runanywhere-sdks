// SPDX-License-Identifier: Apache-2.0
import 'package:test/test.dart';
import 'package:runanywhere_core/runanywhere_core.dart';

void main() {
  group('VoiceAgentConfig', () {
    test('has expected defaults', () {
      const cfg = VoiceAgentConfig();
      expect(cfg.llm, 'qwen3-4b');
      expect(cfg.stt, 'whisper-base');
      expect(cfg.tts, 'kokoro');
      expect(cfg.enableBargeIn, isTrue);
    });
  });

  group('VoiceSession', () {
    test('without native core yields backend-unavailable', () async {
      final session = RunAnywhere.solution(
        SolutionConfig.voiceAgent(const VoiceAgentConfig()),
      );
      final events = await session.run().toList();
      expect(events.length, 1);
      expect(events.first, isA<VoiceError>());
      expect((events.first as VoiceError).code, -6);
    });
  });
}
