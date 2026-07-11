import { beforeEach, describe, expect, it, vi } from 'vitest';
import { AudioFormat, ModelCategory } from '@runanywhere/proto-ts/model_types';

const mocks = vi.hoisted(() => ({
  transcribe: vi.fn(),
  synthesize: vi.fn(),
  generate: vi.fn(),
  cancelGeneration: vi.fn(),
}));

vi.mock('../../../../src/Public/Extensions/RunAnywhere+STT', () => ({
  STT: { supportsLifecycleProtoSTT: () => true },
  transcribe: mocks.transcribe,
}));

vi.mock('../../../../src/Public/Extensions/RunAnywhere+TTS', () => ({
  TTS: { supportsLifecycleProtoTTS: () => true },
  synthesize: mocks.synthesize,
}));

vi.mock('../../../../src/Public/Extensions/RunAnywhere+TextGeneration', () => ({
  TextGeneration: {
    supportsProtoLLM: () => true,
    generate: mocks.generate,
    cancelGeneration: mocks.cancelGeneration,
  },
}));

vi.mock('../../../../src/Public/Extensions/RunAnywhere+VAD', () => ({
  VAD: {
    supportsLifecycleProtoVAD: () => false,
    detectVoiceAuto: vi.fn(),
  },
}));

vi.mock('../../../../src/Public/Extensions/RunAnywhere+ModelLifecycle', () => ({
  WebModelLifecycle: {
    currentModel: ({ category }: { category: ModelCategory }) => ({
      found: category !== ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION,
      modelId: `model-${category}`,
      resolvedPath: `/models/${category}`,
    }),
  },
}));

import { __testing__ } from '../../../../src/Public/Extensions/RunAnywhere+VoiceAgent';

function deferred<T>(): { promise: Promise<T>; resolve: (value: T) => void } {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}

const transcript = {
  text: 'What did I ask before?',
  confidence: 0.97,
  durationMs: 1_000,
  languageCode: 'en',
  segmentIndex: 0,
};

const speech = {
  audioData: new Uint8Array(3_200),
  audioFormat: AudioFormat.AUDIO_FORMAT_PCM_S16LE,
  sampleRate: 16_000,
  chunkIndex: 0,
  durationMs: 100,
};

describe('CrossWasmVoiceAgentProvider', () => {
  beforeEach(() => {
    mocks.transcribe.mockReset().mockResolvedValue(transcript);
    mocks.synthesize.mockReset().mockResolvedValue(speech);
    mocks.generate.mockReset()
      .mockResolvedValueOnce({ text: 'First answer.', finishReason: 'stop' })
      .mockResolvedValueOnce({ text: 'Second answer.', finishReason: 'stop' });
    mocks.cancelGeneration.mockReset();
  });

  it('applies the spoken system prompt and bounded conversational history', async () => {
    const provider = __testing__.createCrossWasmVoiceAgentProvider();
    await provider.initializeVoiceAgent({
      vadSampleRate: 16_000,
      vadFrameLength: 0.1,
      vadEnergyThreshold: 0.015,
      wakewordEnabled: false,
      wakewordThreshold: 0.5,
      sessionId: 'conversation',
    });
    const audio = new Float32Array(16_000).fill(0.2);

    await provider.processVoiceTurn(audio);
    await provider.processVoiceTurn(audio);

    const firstOptions = mocks.generate.mock.calls[0]?.[0];
    const secondOptions = mocks.generate.mock.calls[1]?.[0];
    expect(firstOptions.systemPrompt).toContain('one or two short, natural, spoken sentences');
    expect(firstOptions.maxTokens).toBe(200);
    expect(firstOptions.history).toEqual([]);
    expect(secondOptions.history).toHaveLength(2);
    expect(secondOptions.history.map((message: { content: string }) => message.content))
      .toEqual(['What did I ask before?', 'First answer.']);
  });

  it('cancels an old turn at the next async boundary after cleanup/restart', async () => {
    const pending = deferred<typeof transcript>();
    mocks.transcribe.mockReturnValueOnce(pending.promise);
    const provider = __testing__.createCrossWasmVoiceAgentProvider();
    const config = {
      vadSampleRate: 16_000,
      vadFrameLength: 0.1,
      vadEnergyThreshold: 0.015,
      wakewordEnabled: false,
      wakewordThreshold: 0.5,
      sessionId: 'old',
    };
    await provider.initializeVoiceAgent(config);
    const oldTurn = provider.processVoiceTurn(new Float32Array(16_000).fill(0.2));

    await Promise.resolve(provider.cleanupVoiceAgent());
    await provider.initializeVoiceAgent({ ...config, sessionId: 'new' });
    pending.resolve(transcript);

    await expect(oldTurn).rejects.toThrow(/session stopped or restarted/);
    expect(mocks.generate).not.toHaveBeenCalled();
    expect(mocks.cancelGeneration).toHaveBeenCalledOnce();
  });
});
