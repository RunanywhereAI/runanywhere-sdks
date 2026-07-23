import { describe, expect, it } from 'vitest';
import {
  SolutionConfig,
  SolutionType,
  VoiceAgentConfig,
} from '@runanywhere/proto-ts/solutions';
import {
  SolutionAdapter,
  SolutionHandle,
  SolutionModuleCoordinator,
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
    expect(typeof SolutionModuleCoordinator.resolve).toBe('function');
  });

  it('feeds UTF-8 text or bytes, cancels, and waits through deterministic teardown', async () => {
    const calls: string[] = [];
    const heap = new Uint8Array(128);
    let nextPtr = 8;
    const module = {
      _rac_solution_cancel: () => {
        calls.push('cancel');
        return 0;
      },
      _rac_solution_feed: (_handle: number, ptr: number) => {
        let end = ptr;
        while (heap[end] !== 0) end += 1;
        calls.push(`feed:${new TextDecoder().decode(heap.subarray(ptr, end))}`);
        return 0;
      },
      _rac_solution_destroy: () => calls.push('destroy'),
      _malloc: (size: number) => {
        const ptr = nextPtr;
        nextPtr += size;
        return ptr;
      },
      _free: () => undefined,
      lengthBytesUTF8: (value: string) => new TextEncoder().encode(value).byteLength,
      stringToUTF8: (value: string, ptr: number, maxBytes: number) => {
        const bytes = new TextEncoder().encode(value);
        heap.set(bytes.subarray(0, maxBytes - 1), ptr);
        heap[ptr + Math.min(bytes.length, maxBytes - 1)] = 0;
        return bytes.length;
      },
    };
    const handle = new SolutionHandle(42, module as never);

    handle.feed('hello');
    handle.feed(new TextEncoder().encode('world'));
    handle.cancel();
    await handle.wait();

    expect(calls).toEqual(['feed:hello', 'feed:world', 'cancel', 'destroy']);
    expect(handle.isAlive).toBe(false);
  });

  it('rejects an empty SolutionConfig before touching the native module', () => {
    // An empty config encodes to zero bytes; the adapter must refuse it
    // synchronously rather than calling rac_solution_create_from_proto.
    expect(() => SolutionAdapter.run({ config: SolutionConfig.create({}) })).toThrow(
      /empty/i
    );
  });
});
