import { describe, expect, it } from 'vitest';
import {
  SolutionConfig,
  SolutionType,
  VoiceAgentConfig,
} from '@runanywhere/proto-ts/solutions';
import {
  SolutionAdapter,
  SolutionHandle,
  solutions,
} from '../../../../src/Public/Extensions/RunAnywhere+Solutions';

/**
 * Generated Solutions public-surface coverage — mirrors Swift
 * SolutionsSurfaceTests.swift. The commons layer is covered by
 * test_solution_runner.cpp; this pins the SDK-layer proto round-trip, the
 * `RunAnywhere.solutions` capability shape, and the synchronous input
 * validation that runs before any WASM module is touched (so the assertions
 * stay deterministic without a staged Emscripten module).
 */
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
    expect(SolutionConfig.decode(bytes).voiceAgent?.llmModelId).toBe(
      'qwen3-4b-q4_k_m'
    );
  });

  it('exposes the solutions capability and SolutionHandle surface', () => {
    expect(typeof solutions.run).toBe('function');
    expect(typeof SolutionHandle).toBe('function');
    expect(typeof SolutionAdapter.run).toBe('function');
  });

  it('rejects an empty SolutionConfig before touching the native module', () => {
    // An empty config encodes to zero bytes; the adapter must refuse it
    // synchronously rather than calling rac_solution_create_from_proto.
    expect(() => SolutionAdapter.run({ config: SolutionConfig.create({}) })).toThrow(
      /empty/i
    );
  });
});
