import { beforeEach, describe, expect, it, vi } from 'vitest';
import { AudioEncoding } from '@runanywhere/proto-ts/voice_events';

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
    stop: vi.fn(),
    dispose: vi.fn(),
  },
  processVoiceTurn: vi.fn(),
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
    stop = mocks.playback.stop;
    dispose = mocks.playback.dispose;
  },
}));

vi.mock('../../../src/Public/Extensions/RunAnywhere+VoiceAgent', () => ({
  processVoiceTurn: mocks.processVoiceTurn,
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

function emitUtterance(capture: (typeof mocks.captures)[number]): void {
  for (let index = 0; index < 4; index += 1) {
    capture.emit(new Float32Array(1_600).fill(0.2));
  }
  for (let index = 0; index < 8; index += 1) {
    capture.emit(new Float32Array(1_600));
  }
}

async function flush(): Promise<void> {
  await Promise.resolve();
  await Promise.resolve();
}

describe('VoiceAgentMicDriver', () => {
  beforeEach(() => {
    mocks.captures.length = 0;
    mocks.captureStart = null;
    mocks.playback.play.mockReset();
    mocks.playback.stop.mockReset();
    mocks.playback.dispose.mockReset();
    mocks.processVoiceTurn.mockReset();
  });

  it('keeps capture gated until synthesized reply playback completes', async () => {
    const playback = deferred<void>();
    mocks.processVoiceTurn.mockResolvedValue(turnResult());
    mocks.playback.play.mockReturnValue(playback.promise);
    const phases: string[] = [];
    const driver = new VoiceAgentMicDriver();
    await driver.start({ onPhase: (phase) => phases.push(phase) });

    const capture = mocks.captures.at(-1)!;
    emitUtterance(capture);
    await flush();

    expect(mocks.playback.play).toHaveBeenCalledOnce();
    expect(phases.at(-1)).toBe('processing');
    expect(capture.clearCount).toBe(12);

    playback.resolve();
    await flush();
    expect(phases.at(-1)).toBe('listening');
  });

  it('drops an in-flight turn after stop/restart instead of leaking old playback', async () => {
    const inference = deferred<ReturnType<typeof turnResult>>();
    mocks.processVoiceTurn.mockReturnValue(inference.promise);
    mocks.playback.play.mockResolvedValue(undefined);
    const onTurn = vi.fn();
    const driver = new VoiceAgentMicDriver();
    await driver.start({ onTurn });
    emitUtterance(mocks.captures.at(-1)!);
    await flush();

    driver.stop();
    expect(mocks.playback.dispose).toHaveBeenCalledOnce();
    await driver.start({ onTurn });
    inference.resolve(turnResult());
    await flush();

    expect(onTurn).not.toHaveBeenCalled();
    expect(mocks.playback.play).not.toHaveBeenCalled();
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
