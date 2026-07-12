import { afterEach, describe, expect, it, vi } from 'vitest';
import { LLMGenerateRequest } from '@runanywhere/proto-ts/llm_service';
import { LLMGenerationResult } from '@runanywhere/proto-ts/llm_options';
import {
  VLMGenerationOptions,
  VLMImage,
  VLMResult,
  VLMStreamEvent,
} from '@runanywhere/proto-ts/vlm_options';

import {
  setVisionLanguageProvider,
  type VisionLanguageProvider,
} from '../../../src/Public/Extensions/RunAnywhere+VisionLanguage';
import { TextGeneration } from '../../../src/Public/Extensions/RunAnywhere+TextGeneration';
import { RunAnywhere } from '../../../src/Public/RunAnywhere';
import type { LLMStreamingResult } from '../../../src/types';

describe('RunAnywhere cancellation admission', () => {
  afterEach(() => {
    setVisionLanguageProvider(null);
    vi.restoreAllMocks();
  });

  it('does not admit generation when the signal aborts during services setup', async () => {
    let releaseServices!: () => void;
    const servicesReady = new Promise<void>((resolve) => {
      releaseServices = resolve;
    });
    const ensureServicesReady = vi
      .spyOn(RunAnywhere, 'ensureServicesReady')
      .mockImplementation(() => servicesReady);
    const controller = new AbortController();

    const generation = RunAnywhere.generate(
      LLMGenerateRequest.create({ prompt: 'do not start' }),
      { signal: controller.signal },
    );
    await vi.waitFor(() => expect(ensureServicesReady).toHaveBeenCalledOnce());

    controller.abort();
    releaseServices();

    await expect(generation).rejects.toMatchObject({
      proto: {
        message: 'generate cancelled',
      },
    });
  });

  it('cancels a stream aborted while its native handle is being created', async () => {
    vi.spyOn(RunAnywhere, 'ensureServicesReady').mockResolvedValue(undefined);
    let releaseStream!: (stream: LLMStreamingResult) => void;
    const pendingStream = new Promise<LLMStreamingResult>((resolve) => {
      releaseStream = resolve;
    });
    const createStream = vi
      .spyOn(TextGeneration, 'generateStream')
      .mockImplementation(() => pendingStream);
    const cancel = vi.fn();
    const controller = new AbortController();

    const result = RunAnywhere.generateStream(
      LLMGenerateRequest.create({ prompt: 'do not stream' }),
      { signal: controller.signal },
    );
    await vi.waitFor(() => expect(createStream).toHaveBeenCalledOnce());

    controller.abort();
    releaseStream({
      stream: emptyTextStream(),
      result: Promise.resolve(LLMGenerationResult.create({})),
      cancel,
    });

    await expect(result).rejects.toMatchObject({
      proto: {
        message: 'generateStream cancelled',
      },
    });
    expect(cancel).toHaveBeenCalledOnce();
  });

  it('cancels a VLM stream aborted while the provider is creating it', async () => {
    let releaseStream!: (stream: AsyncIterable<VLMStreamEvent>) => void;
    const pendingStream = new Promise<AsyncIterable<VLMStreamEvent>>((resolve) => {
      releaseStream = resolve;
    });
    const cancelVLMGeneration = vi.fn();
    const processImageStream = vi.fn(() => pendingStream);
    setVisionLanguageProvider(makeProvider({ processImageStream, cancelVLMGeneration }));
    const controller = new AbortController();

    const result = RunAnywhere.processImageStream(
      VLMImage.create({}),
      VLMGenerationOptions.create({}),
      { signal: controller.signal },
    );
    await vi.waitFor(() => expect(processImageStream).toHaveBeenCalledOnce());

    controller.abort();
    releaseStream(emptyVLMStream());

    await expect(result).rejects.toMatchObject({
      proto: {
        message: 'processImageStream cancelled',
      },
    });
    expect(cancelVLMGeneration).toHaveBeenCalledOnce();
  });

  it('detaches the VLM AbortSignal listener when the stream completes', async () => {
    const cancelVLMGeneration = vi.fn();
    setVisionLanguageProvider(makeProvider({
      cancelVLMGeneration,
      processImageStream: vi.fn(async () => oneEventVLMStream()),
    }));
    const controller = new AbortController();
    const addEventListener = vi.spyOn(controller.signal, 'addEventListener');
    const removeEventListener = vi.spyOn(controller.signal, 'removeEventListener');

    const stream = await RunAnywhere.processImageStream(
      VLMImage.create({}),
      VLMGenerationOptions.create({}),
      { signal: controller.signal },
    );
    for await (const _event of stream) {
      // Drain the provider stream to its terminal state.
    }

    expect(addEventListener).toHaveBeenCalledOnce();
    expect(removeEventListener).toHaveBeenCalledOnce();
    controller.abort();
    expect(cancelVLMGeneration).not.toHaveBeenCalled();
  });
});

function makeProvider(
  overrides: Partial<VisionLanguageProvider>,
): VisionLanguageProvider {
  return {
    isInitialized: true,
    isModelLoaded: true,
    processImage: vi.fn(async () => VLMResult.create({})),
    processImageStream: vi.fn(async () => emptyVLMStream()),
    cancelVLMGeneration: vi.fn(),
    ...overrides,
  };
}

async function* emptyVLMStream(): AsyncIterable<VLMStreamEvent> {
  // Intentionally empty.
}

async function* emptyTextStream(): AsyncIterable<string> {
  // Intentionally empty.
}

async function* oneEventVLMStream(): AsyncIterable<VLMStreamEvent> {
  yield VLMStreamEvent.create({ isFinal: true });
}
