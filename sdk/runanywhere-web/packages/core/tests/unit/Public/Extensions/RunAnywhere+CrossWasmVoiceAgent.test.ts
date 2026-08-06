import { beforeEach, describe, expect, it, vi } from 'vitest';
import { voiceAgentDefaults } from '@runanywhere/proto-ts/defaults/pool';
import { AudioFormat, ModelCategory } from '@runanywhere/proto-ts/model_types';

const mocks = vi.hoisted(() => ({
  transcribe: vi.fn(),
  synthesize: vi.fn(),
  generate: vi.fn(),
  cancelGeneration: vi.fn(),
  detectVoice: vi.fn(),
  vadLifecycleAvailable: false,
  sttAvailable: true,
  ttsAvailable: true,
  llmAvailable: true,
}));

vi.mock('../../../../src/Public/Extensions/RunAnywhere+STT', () => ({
  STT: { supportsLifecycleProtoSTT: () => mocks.sttAvailable },
  transcribe: mocks.transcribe,
}));

vi.mock('../../../../src/Public/Extensions/RunAnywhere+TTS', () => ({
  TTS: { supportsLifecycleProtoTTS: () => mocks.ttsAvailable },
  synthesize: mocks.synthesize,
}));

vi.mock('../../../../src/Public/Extensions/RunAnywhere+TextGeneration', () => ({
  TextGeneration: {
    supportsProtoLLM: () => mocks.llmAvailable,
    generate: mocks.generate,
    cancelGeneration: mocks.cancelGeneration,
  },
}));

vi.mock('../../../../src/Public/Extensions/RunAnywhere+VAD', () => ({
  VAD: {
    supportsLifecycleProtoVAD: () => mocks.vadLifecycleAvailable,
    detectVoice: mocks.detectVoice,
  },
}));

vi.mock('../../../../src/Public/Extensions/RunAnywhere+ModelLifecycle', () => ({
  WebModelLifecycle: {
    currentModel: ({ category }: { category: ModelCategory }) => ({
      found: category !== ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION
        || mocks.vadLifecycleAvailable,
      modelId: `model-${category}`,
      resolvedPath: `/models/${category}`,
    }),
  },
}));

import {
  __testing__,
  getVoiceAgentAvailability,
  registerVoiceAgentProvider,
} from '../../../../src/Public/Extensions/RunAnywhere+VoiceAgent';

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
  beforeEach(async () => {
    await __testing__.resetFacadeState();
    mocks.transcribe.mockReset().mockResolvedValue(transcript);
    mocks.synthesize.mockReset().mockResolvedValue(speech);
    mocks.generate.mockReset()
      .mockResolvedValueOnce({ text: 'First answer.', finishReason: 'stop' })
      .mockResolvedValueOnce({ text: 'Second answer.', finishReason: 'stop' });
    mocks.cancelGeneration.mockReset();
    mocks.vadLifecycleAvailable = false;
    mocks.sttAvailable = true;
    mocks.ttsAvailable = true;
    mocks.llmAvailable = true;
    mocks.detectVoice.mockReset().mockResolvedValue({
      isSpeech: true,
      confidence: 0.99,
      durationMs: 1_000,
      energy: 0.2,
    });
    expect(registerVoiceAgentProvider()).toBe(true);
  });

  it('keeps energy and model-backed VAD thresholds in their native units', async () => {
    mocks.vadLifecycleAvailable = true;
    const provider = __testing__.createCrossWasmVoiceAgentProvider();
    // `VoiceAgentComposeConfig` has no `vadSampleRate`/`vadFrameLength`/
    // `vadEnergyThreshold`/`sessionId` fields -- VAD tuning nests under
    // `vadConfig: VADConfiguration` (sampleRate/frameLengthMs/
    // activationThreshold), and `sessionId` was deleted outright (Web-only
    // session bookkeeping lives in the provider, not the wire config).
    await provider.initializeVoiceAgent({
      vadConfig: {
        modelId: '',
        sampleRate: 16_000,
        frameLengthMs: 100,
        activationThreshold: 0.005,
        enableAutoCalibration: false,
        calibrationMultiplier: 1,
      },
    });

    await provider.processVoiceTurn(new Float32Array(16_000).fill(0.2));

    expect(mocks.detectVoice).toHaveBeenCalledOnce();
    expect(mocks.detectVoice.mock.calls[0]?.[1]).toMatchObject({
      modelId: `model-${ModelCategory.MODEL_CATEGORY_VOICE_ACTIVITY_DETECTION}`,
      config: {
        sampleRate: 16_000,
        frameLengthMs: 100,
        activationThreshold: 0.5,
      },
    });
    expect(mocks.detectVoice.mock.calls[0]?.[1]).not.toHaveProperty('activationThreshold');
  });

  it('applies the spoken system prompt and bounded conversational history', async () => {
    const provider = __testing__.createCrossWasmVoiceAgentProvider();
    await provider.initializeVoiceAgent({
      vadConfig: {
        modelId: '',
        sampleRate: 16_000,
        frameLengthMs: 100,
        activationThreshold: 0.015,
        enableAutoCalibration: false,
        calibrationMultiplier: 1,
      },
    });
    const audio = new Float32Array(16_000).fill(0.2);

    await provider.processVoiceTurn(audio);
    await provider.processVoiceTurn(audio);

    const firstOptions = mocks.generate.mock.calls[0]?.[0];
    const secondOptions = mocks.generate.mock.calls[1]?.[0];
    expect(firstOptions.systemPrompt).toContain('one or two short, natural, spoken sentences');
    // Assert against the pool rather than a literal. This line pinned 200,
    // which was Web's own voice-agent cap while the other four platforms
    // inherited 96 from the C++ orchestrator; re-pinning a number here would
    // just recreate that divergence in the test suite.
    expect(firstOptions.maxOutputTokens).toBe(voiceAgentDefaults.maxTokens);
    expect(firstOptions.history).toEqual([]);
    expect(secondOptions.history).toHaveLength(2);
    expect(secondOptions.history.map((message: { content: string }) => message.content))
      .toEqual(['What did I ask before?', 'First answer.']);
  });

  it('cancels an old turn at the next async boundary after cleanup/restart', async () => {
    const pending = deferred<typeof transcript>();
    mocks.transcribe.mockReturnValueOnce(pending.promise);
    const provider = __testing__.createCrossWasmVoiceAgentProvider();
    // `VoiceAgentComposeConfig` has no `sessionId` field -- session identity
    // is Web-provider-internal bookkeeping now, not part of the wire config.
    const config = {
      vadConfig: {
        modelId: '',
        sampleRate: 16_000,
        frameLengthMs: 100,
        activationThreshold: 0.015,
        enableAutoCalibration: false,
        calibrationMultiplier: 1,
      },
    };
    await provider.initializeVoiceAgent(config);
    const oldTurn = provider.processVoiceTurn(new Float32Array(16_000).fill(0.2));

    await Promise.resolve(provider.cleanupVoiceAgent());
    await provider.initializeVoiceAgent({ ...config });
    pending.resolve(transcript);

    await expect(oldTurn).rejects.toThrow(/session stopped or restarted/);
    expect(mocks.generate).not.toHaveBeenCalled();
    expect(mocks.cancelGeneration).toHaveBeenCalledOnce();
  });

  it('evicts the cached cross-WASM provider when a required backend disappears', () => {
    expect(getVoiceAgentAvailability()).toMatchObject({
      available: true,
      source: 'cross-wasm',
    });

    mocks.sttAvailable = false;

    expect(getVoiceAgentAvailability()).toMatchObject({
      available: false,
      source: 'unavailable',
    });
    expect(mocks.cancelGeneration).toHaveBeenCalledOnce();
  });
});
