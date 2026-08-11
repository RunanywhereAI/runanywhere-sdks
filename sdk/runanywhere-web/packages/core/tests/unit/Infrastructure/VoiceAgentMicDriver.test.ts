import { beforeEach, describe, expect, it, vi } from 'vitest';
import { AudioEncoding } from '@runanywhere/proto-ts/model_types';

const mocks = vi.hoisted(() => ({
  captures: [] as Array<{
    emit: (chunk: Float32Array) => void;
    clearCount: number;
    capturing: boolean;
    stopCount: number;
  }>,
  captureStart: null as Promise<void> | null,
  playback: {
    play: vi.fn(),
    playEncoded: vi.fn(),
    stop: vi.fn(),
    dispose: vi.fn(),
  },
  feedVoiceAgentAudio: vi.fn(),
  supportsVoiceAgentFeedAudio: vi.fn(() => true),
  float32ToPcm16: vi.fn((samples: Float32Array) => new Uint8Array(samples.length * 2)),
}));

vi.mock('../../../src/Infrastructure/AudioCapture', () => ({
  AudioCapture: class {
    private chunkCallback: ((chunk: Float32Array) => void) | undefined;
    private state = {
      emit: (chunk: Float32Array): void => this.chunkCallback?.(chunk),
      clearCount: 0,
      capturing: false,
      stopCount: 0,
    };

    constructor() {
      mocks.captures.push(this.state);
    }

    get isCapturing(): boolean { return this.state.capturing; }

    async start(onChunk?: (chunk: Float32Array) => void): Promise<void> {
      this.chunkCallback = onChunk;
      if (mocks.captureStart) await mocks.captureStart;
      this.state.capturing = true;
    }

    stop(): void {
      this.state.stopCount += 1;
      this.state.capturing = false;
    }
    clearBuffer(): void { this.state.clearCount += 1; }
  },
}));

vi.mock('../../../src/Infrastructure/AudioPlayback', () => ({
  AudioPlayback: class {
    play = mocks.playback.play;
    playEncoded = mocks.playback.playEncoded;
    stop = mocks.playback.stop;
    dispose = mocks.playback.dispose;
  },
}));

vi.mock('../../../src/Public/Extensions/RunAnywhere+AudioConvert', () => ({
  float32ToPcm16: mocks.float32ToPcm16,
}));

vi.mock('../../../src/Public/Extensions/RunAnywhere+VoiceAgent', () => ({
  feedVoiceAgentAudio: mocks.feedVoiceAgentAudio,
  supportsVoiceAgentFeedAudio: mocks.supportsVoiceAgentFeedAudio,
}));

import { VoiceAgentMicDriver } from '../../../src/Infrastructure/VoiceAgentMicDriver';

function deferred<T>(): {
  promise: Promise<T>;
  resolve: (value: T) => void;
} {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}

function turnResult() {
  return {
    speechDetected: true,
    transcription: 'hello',
    assistantResponse: 'hi there',
    synthesizedAudio: new Uint8Array(3_200),
    synthesizedAudioSampleRateHz: 16_000,
    synthesizedAudioChannels: 1,
    synthesizedAudioEncoding: AudioEncoding.AUDIO_ENCODING_PCM_S16_LE,
    sessionId: 'test',
    turnId: 'turn',
    sttTimeMs: 1,
    llmTimeMs: 1,
    ttsTimeMs: 1,
    totalTimeMs: 3,
    errorCode: 0,
  };
}

async function flush(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
  await Promise.resolve();
  await new Promise((resolve) => setTimeout(resolve, 25));
}

describe('VoiceAgentMicDriver', () => {
  beforeEach(() => {
    mocks.captures.length = 0;
    mocks.captureStart = null;
    mocks.playback.play.mockReset();
    mocks.playback.playEncoded.mockReset();
    mocks.playback.stop.mockReset();
    mocks.playback.dispose.mockReset();
    mocks.feedVoiceAgentAudio.mockReset();
    mocks.supportsVoiceAgentFeedAudio.mockReset();
    mocks.supportsVoiceAgentFeedAudio.mockReturnValue(true);
    mocks.float32ToPcm16.mockClear();
  });

  it('fails explicitly when commons feed audio is unavailable', async () => {
    mocks.supportsVoiceAgentFeedAudio.mockReturnValue(false);
    const driver = new VoiceAgentMicDriver();
    await expect(driver.start()).rejects.toMatchObject({
      message: expect.stringContaining('VoiceAgentMicDriver'),
      proto: {
        nestedMessage: expect.stringContaining('rac_voice_agent_feed_audio_proto'),
      },
    });
  });

  it('feeds captured PCM into commons and plays synthesized replies', async () => {
    const playback = deferred<void>();
    mocks.feedVoiceAgentAudio
      .mockResolvedValueOnce(null)
      .mockResolvedValueOnce(turnResult());
    mocks.playback.playEncoded.mockReturnValue(playback.promise);
    const phases: string[] = [];
    const turns: Array<{ userText: string; assistantText: string }> = [];
    const driver = new VoiceAgentMicDriver();
    await driver.start({
      onPhase: (phase) => phases.push(phase),
      onTurn: (turn) => { turns.push(turn); },
    });

    const capture = mocks.captures.at(-1)!;
    capture.emit(new Float32Array(1_600).fill(0.1));
    await flush();
    capture.emit(new Float32Array(1_600).fill(0.2));
    await flush();

    expect(mocks.float32ToPcm16).toHaveBeenCalled();
    expect(mocks.feedVoiceAgentAudio).toHaveBeenCalled();
    expect(turns).toEqual([{ userText: 'hello', assistantText: 'hi there' }]);
    expect(mocks.playback.playEncoded).toHaveBeenCalledOnce();
    expect(phases).toContain('listening');
    expect(phases).toContain('speaking');

    playback.resolve();
    await flush();
    expect(phases.at(-1)).toBe('listening');
  });

  it('drops an in-flight playout after stop/restart instead of leaking old playback', async () => {
    const inference = deferred<ReturnType<typeof turnResult> | null>();
    mocks.feedVoiceAgentAudio.mockReturnValue(inference.promise);
    mocks.playback.playEncoded.mockResolvedValue(undefined);
    const onTurn = vi.fn();
    const driver = new VoiceAgentMicDriver();
    await driver.start({ onTurn });
    mocks.captures.at(-1)!.emit(new Float32Array(1_600).fill(0.2));
    await flush();

    driver.stop();
    expect(mocks.playback.dispose).toHaveBeenCalledOnce();
    await driver.start({ onTurn });
    inference.resolve(turnResult());
    await flush();

    expect(onTurn).not.toHaveBeenCalled();
    expect(mocks.playback.playEncoded).not.toHaveBeenCalled();
  });

  it('closes capture when microphone permission resolves after stop', async () => {
    const permission = deferred<void>();
    mocks.captureStart = permission.promise;
    const phases: string[] = [];
    const driver = new VoiceAgentMicDriver();

    const starting = driver.start({ onPhase: (phase) => phases.push(phase) });
    await flush();
    const capture = mocks.captures.at(-1)!;
    driver.stop();
    permission.resolve();
    await starting;

    expect(capture.stopCount).toBe(2);
    expect(capture.capturing).toBe(false);
    expect(phases).not.toContain('listening');
  });
});
