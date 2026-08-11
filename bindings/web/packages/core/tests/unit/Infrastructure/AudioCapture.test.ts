import { afterEach, describe, expect, it, vi } from 'vitest';

import { AudioCapture } from '../../../src/Infrastructure/AudioCapture';

function deferred<T>(): { promise: Promise<T>; resolve: (value: T) => void } {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}

function installAudioGraph(moduleLoad: Promise<void> = Promise.resolve()): {
  addModule: ReturnType<typeof vi.fn>;
  analyser: { disconnect: ReturnType<typeof vi.fn> };
  cancelAnimationFrame: ReturnType<typeof vi.fn>;
  closeContext: ReturnType<typeof vi.fn>;
  port: {
    close: ReturnType<typeof vi.fn>;
    onmessage: ((event: MessageEvent<unknown>) => void) | null;
  };
  sourceNode: {
    connect: ReturnType<typeof vi.fn>;
    disconnect: ReturnType<typeof vi.fn>;
  };
  stopTrack: ReturnType<typeof vi.fn>;
  workletNode: {
    connect: ReturnType<typeof vi.fn>;
    disconnect: ReturnType<typeof vi.fn>;
  };
  workletOptions: () => AudioWorkletNodeOptions | undefined;
  workletProcessorName: () => string | undefined;
} {
  const stopTrack = vi.fn();
  const stream = {
    getTracks: () => [{ stop: stopTrack }],
  } as unknown as MediaStream;
  vi.stubGlobal('navigator', {
    mediaDevices: {
      getUserMedia: vi.fn(async () => stream),
    },
  });

  const sourceNode = {
    connect: vi.fn(),
    disconnect: vi.fn(),
  };
  const analyser = {
    disconnect: vi.fn(),
    fftSize: 0,
    frequencyBinCount: 128,
    getByteFrequencyData: vi.fn(),
  };
  const addModule = vi.fn(() => moduleLoad);
  const closeContext = vi.fn(async () => undefined);
  const destination = {};

  class TestAudioContext {
    readonly audioWorklet = { addModule };
    readonly destination = destination;
    readonly sampleRate = 16_000;
    readonly state = 'running';
    readonly close = closeContext;
    readonly createAnalyser = vi.fn(() => analyser);
    readonly createMediaStreamSource = vi.fn(() => sourceNode);
    readonly resume = vi.fn(async () => undefined);
  }
  vi.stubGlobal('AudioContext', TestAudioContext);

  const port = {
    close: vi.fn(),
    onmessage: null as ((event: MessageEvent<unknown>) => void) | null,
  };
  const workletNode = {
    connect: vi.fn(),
    disconnect: vi.fn(),
  };
  let processorName: string | undefined;
  let options: AudioWorkletNodeOptions | undefined;
  class TestAudioWorkletNode {
    readonly port = port;
    onprocessorerror: (() => void) | null = null;
    readonly connect = workletNode.connect;
    readonly disconnect = workletNode.disconnect;

    constructor(
      _context: BaseAudioContext,
      name: string,
      nodeOptions?: AudioWorkletNodeOptions,
    ) {
      processorName = name;
      options = nodeOptions;
    }
  }
  vi.stubGlobal('AudioWorkletNode', TestAudioWorkletNode);

  const cancelAnimationFrame = vi.fn();
  vi.stubGlobal('requestAnimationFrame', vi.fn(() => 17));
  vi.stubGlobal('cancelAnimationFrame', cancelAnimationFrame);

  return {
    addModule,
    analyser,
    cancelAnimationFrame,
    closeContext,
    port,
    sourceNode,
    stopTrack,
    workletNode,
    workletOptions: () => options,
    workletProcessorName: () => processorName,
  };
}

describe('AudioCapture pending start lifecycle', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
  });

  it('stops a stream granted after capture was stopped', async () => {
    const permission = deferred<MediaStream>();
    const stopTrack = vi.fn();
    vi.stubGlobal('navigator', {
      mediaDevices: {
        getUserMedia: vi.fn(() => permission.promise),
      },
    });
    const capture = new AudioCapture();

    const starting = capture.start();
    capture.stop();
    permission.resolve({
      getTracks: () => [{ stop: stopTrack }],
    } as unknown as MediaStream);
    await starting;

    expect(stopTrack).toHaveBeenCalledOnce();
    expect(capture.isCapturing).toBe(false);
  });

  it('loads the packaged worklet and delivers exact Float32 chunks', async () => {
    const graph = installAudioGraph();
    const onChunk = vi.fn();
    const capture = new AudioCapture({ sampleRate: 16_000, chunkSize: 1600, channels: 1 });

    await capture.start(onChunk);

    expect(graph.addModule).toHaveBeenCalledWith(
      expect.stringMatching(/\/AudioCaptureProcessor\.js$/),
    );
    expect(graph.workletProcessorName()).toBe('runanywhere-audio-capture');
    expect(graph.workletOptions()).toMatchObject({
      channelCount: 1,
      processorOptions: { chunkSize: 1600 },
    });
    expect(capture.isCapturing).toBe(true);

    const chunk = Float32Array.from([0.25, -0.5, 0.75]);
    graph.port.onmessage?.({ data: chunk } as MessageEvent<unknown>);

    expect(onChunk).toHaveBeenCalledOnce();
    expect(onChunk).toHaveBeenCalledWith(chunk);
    expect(capture.getAudioBuffer()).toEqual(chunk);

    capture.stop();

    expect(graph.port.close).toHaveBeenCalledOnce();
    expect(graph.workletNode.disconnect).toHaveBeenCalledOnce();
    expect(graph.analyser.disconnect).toHaveBeenCalledOnce();
    expect(graph.sourceNode.disconnect).toHaveBeenCalledOnce();
    expect(graph.closeContext).toHaveBeenCalledOnce();
    expect(graph.stopTrack).toHaveBeenCalledOnce();
    expect(graph.cancelAnimationFrame).toHaveBeenCalledWith(17);
  });

  it('releases pending worklet resources when stopped during module loading', async () => {
    const moduleLoad = deferred<void>();
    const graph = installAudioGraph(moduleLoad.promise);
    const capture = new AudioCapture();

    const starting = capture.start();
    await vi.waitFor(() => {
      expect(graph.addModule).toHaveBeenCalledOnce();
    });
    capture.stop();
    moduleLoad.resolve(undefined);
    await starting;

    expect(capture.isCapturing).toBe(false);
    expect(graph.closeContext).toHaveBeenCalledOnce();
    expect(graph.stopTrack).toHaveBeenCalledOnce();
    expect(graph.workletProcessorName()).toBeUndefined();
  });
});
