import { afterEach, describe, expect, it, vi } from 'vitest';

import { EmbeddingsProtoAdapter } from '../../../src/Adapters/EmbeddingsProtoAdapter';
import { STTProtoAdapter } from '../../../src/Adapters/STTProtoAdapter';
import {
  getActiveBackendWorkerHost,
  type BackendWorkerHost,
} from '../../../src/runtime/BackendWorkerHost';
import {
  EmbeddingsRequest,
  EmbeddingsResult,
} from '@runanywhere/proto-ts/embeddings_options';
import { STTOutput } from '@runanywhere/proto-ts/stt_options';

vi.mock('../../../src/runtime/BackendWorkerHost.js', async () => {
  const actual = await vi.importActual<typeof import('../../../src/runtime/BackendWorkerHost.js')>(
    '../../../src/runtime/BackendWorkerHost.js',
  );
  return {
    ...actual,
    getActiveBackendWorkerHost: vi.fn(),
  };
});

function fakeOnnxHost(inferResult: Uint8Array): BackendWorkerHost {
  return {
    diagnostics: { executionContext: 'worker', queueDepth: 0 },
    infer: vi.fn(async () => ({ resultBytes: inferResult })),
    stream: vi.fn(),
    cancelActiveStreams: vi.fn(),
  } as unknown as BackendWorkerHost;
}

describe('ONNX worker routing policy', () => {
  afterEach(() => {
    vi.mocked(getActiveBackendWorkerHost).mockReset();
  });

  it('routes embeddings.embed through the onnx BackendWorker', async () => {
    const resultBytes = EmbeddingsResult.encode(
      EmbeddingsResult.fromPartial({
        vectors: [{ values: [0.1, 0.2], dimension: 2 }],
        dimension: 2,
      }),
    ).finish();
    const host = fakeOnnxHost(resultBytes);
    vi.mocked(getActiveBackendWorkerHost).mockReturnValue(host);

    const adapter = new EmbeddingsProtoAdapter({} as never);
    const result = await adapter.embedBatchLifecycle(
      EmbeddingsRequest.fromPartial({ texts: ['hello'] }),
    );

    expect(getActiveBackendWorkerHost).toHaveBeenCalledWith('onnx');
    expect(host.infer).toHaveBeenCalledWith(
      'embeddings.embed',
      expect.objectContaining({ requestBytes: expect.any(Uint8Array) }),
    );
    expect(result?.dimension).toBe(2);
    expect(result?.vectors?.[0]?.values).toHaveLength(2);
  });

  it('routes stt.transcribe through the onnx BackendWorker', async () => {
    const resultBytes = STTOutput.encode(
      STTOutput.fromPartial({ text: 'hello' }),
    ).finish();
    const host = fakeOnnxHost(resultBytes);
    vi.mocked(getActiveBackendWorkerHost).mockReturnValue(host);

    const adapter = new STTProtoAdapter({} as never);
    const result = await adapter.transcribeLifecycle(
      new Uint8Array([1, 2, 3]),
      {} as never,
    );

    expect(getActiveBackendWorkerHost).toHaveBeenCalledWith('onnx');
    expect(host.infer).toHaveBeenCalledWith(
      'stt.transcribe',
      expect.objectContaining({ requestBytes: expect.any(Uint8Array) }),
    );
    expect(result?.text).toBe('hello');
  });
});
