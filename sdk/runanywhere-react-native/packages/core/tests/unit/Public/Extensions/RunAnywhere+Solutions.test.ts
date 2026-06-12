/**
 * Generated Solutions public-surface coverage — mirrors Swift
 * SolutionsSurfaceTests.swift. The commons layer is covered by
 * test_solution_runner.cpp, and the Web sibling exercises the
 * SolutionAdapter validation path. On RN the `RunAnywhere.solutions` surface
 * bottoms out in Nitro (`requireNativeModule`), which the ts-jest Node harness
 * does not stage — so this pins the generated proto types that
 * `RunAnywhere.solutions.run(...)` encodes/decodes, matching the pure-TS
 * strategy of ProtoWire.test.ts / ProtoBytes.test.ts.
 */

import {
  SolutionConfig,
  SolutionHandle,
  SolutionType,
  VoiceAgentConfig,
} from '@runanywhere/proto-ts/solutions';

describe('Solutions generated surface', () => {
  it('SolutionConfig carries voice agent oneof fields', () => {
    const config = SolutionConfig.create({
      voiceAgent: {
        llmModelId: 'qwen3-4b-q4_k_m',
        sttModelId: 'whisper-base',
        ttsModelId: 'kokoro',
        vadModelId: 'silero-v5',
        sampleRateHz: 16000,
        chunkMs: 20,
        maxContextTokens: 4096,
        typeKind: SolutionType.SOLUTION_TYPE_VOICE_AGENT,
      },
    });

    expect(config.voiceAgent).toBeDefined();
    expect(config.voiceAgent).toMatchObject({
      llmModelId: 'qwen3-4b-q4_k_m',
      sttModelId: 'whisper-base',
      ttsModelId: 'kokoro',
      vadModelId: 'silero-v5',
      sampleRateHz: 16000,
      chunkMs: 20,
      maxContextTokens: 4096,
      typeKind: SolutionType.SOLUTION_TYPE_VOICE_AGENT,
    });
  });

  it('SolutionConfig round-trips through proto bytes', () => {
    const config = SolutionConfig.create({
      voiceAgent: VoiceAgentConfig.create({ llmModelId: 'qwen3-4b-q4_k_m' }),
    });

    const bytes = SolutionConfig.encode(config).finish();
    expect(bytes.byteLength).toBeGreaterThan(0);

    const decoded = SolutionConfig.decode(bytes);
    expect(decoded.voiceAgent?.llmModelId).toBe('qwen3-4b-q4_k_m');
  });

  it('SolutionHandle descriptor carries its canonical fields', () => {
    const handle = SolutionHandle.fromPartial({
      handleId: 'sol-1',
      solutionType: 'voice_agent',
      createdAtMs: 1_774_000_000_000,
      state: 'created',
    });

    expect(handle.handleId).toBe('sol-1');
    expect(handle.solutionType).toBe('voice_agent');
    expect(handle.createdAtMs).toBe(1_774_000_000_000);
    expect(handle.state).toBe('created');
  });
});
