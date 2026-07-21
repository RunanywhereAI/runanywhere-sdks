import { afterEach, describe, expect, it, vi } from 'vitest';

import { LLMProtoAdapter } from '../../../src/Adapters/LLMProtoAdapter';
import { VLMProtoAdapter } from '../../../src/Adapters/VLMProtoAdapter';
import {
  clearLlamaBackendWorkerDead,
  setLlamaBackendWorkerRequired,
} from '../../../src/runtime/BackendWorkerModelOwnership';
import {
  getActiveBackendWorkerHost,
  type BackendWorkerHost,
} from '../../../src/runtime/BackendWorkerHost';
import type * as BackendWorkerHostModule from '../../../src/runtime/BackendWorkerHost.js';
import { LLMGenerateRequest } from '@runanywhere/proto-ts/llm_service';
import { LLMGenerationResult } from '@runanywhere/proto-ts/llm_options';
import { VLMResult } from '@runanywhere/proto-ts/vlm_options';

vi.mock('../../../src/runtime/BackendWorkerHost.js', async () => {
  const actual = await vi.importActual<typeof BackendWorkerHostModule>(
    '../../../src/runtime/BackendWorkerHost.js',
  );
  return {
    ...actual,
    getActiveBackendWorkerHost: vi.fn(),
  };
});

function fakeWorkerHost(inferResult: Uint8Array): BackendWorkerHost {
  return {
    diagnostics: { executionContext: 'worker', queueDepth: 0 },
    infer: vi.fn(async () => ({ resultBytes: inferResult })),
    stream: vi.fn(),
    cancelActiveStreams: vi.fn(),
  } as unknown as BackendWorkerHost;
}

describe('Worker routing policy (commons-first)', () => {
  afterEach(() => {
    setLlamaBackendWorkerRequired(false);
    clearLlamaBackendWorkerDead();
    vi.mocked(getActiveBackendWorkerHost).mockReset();
  });

  it('routes LLM generate through llamacpp BackendWorker when required', async () => {
    setLlamaBackendWorkerRequired(true);
    const resultBytes = LLMGenerationResult.encode(
      LLMGenerationResult.fromPartial({ text: 'ok' }),
    ).finish();
    const host = fakeWorkerHost(resultBytes);
    vi.mocked(getActiveBackendWorkerHost).mockReturnValue(host);

    const adapter = new LLMProtoAdapter({} as never);
    const result = await adapter.generate(
      LLMGenerateRequest.fromPartial({ prompt: 'hi' }),
    );

    expect(host.infer).toHaveBeenCalledWith(
      'llm.generate',
      expect.objectContaining({ requestBytes: expect.any(Uint8Array) }),
    );
    expect(result?.text).toBe('ok');
  });

  it('fail-closes LLM generate when worker is required but unavailable', async () => {
    setLlamaBackendWorkerRequired(true);
    vi.mocked(getActiveBackendWorkerHost).mockReturnValue(null);

    const adapter = new LLMProtoAdapter({} as never);
    await expect(
      adapter.generate(LLMGenerateRequest.fromPartial({ prompt: 'hi' })),
    ).rejects.toThrow(/Backend not available for: llm\.generate|BackendWorker is required/);
  });

  it('routes VLM process through llamacpp BackendWorker when required', async () => {
    setLlamaBackendWorkerRequired(true);
    const resultBytes = VLMResult.encode(
      VLMResult.fromPartial({ text: 'seen' }),
    ).finish();
    const host = fakeWorkerHost(resultBytes);
    vi.mocked(getActiveBackendWorkerHost).mockReturnValue(host);

    const adapter = new VLMProtoAdapter({} as never);
    const result = await adapter.process(
      { data: new Uint8Array([1, 2, 3]), mimeType: 'image/png' } as never,
      { prompt: 'what?' } as never,
    );

    expect(host.infer).toHaveBeenCalledWith(
      'vlm.generate',
      expect.objectContaining({ requestBytes: expect.any(Uint8Array) }),
    );
    expect(result?.text).toBe('seen');
  });
});
