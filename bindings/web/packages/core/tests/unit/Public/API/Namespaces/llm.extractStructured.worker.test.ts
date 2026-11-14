import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import {
  StructuredOutputParseRequest,
  StructuredOutputResult,
} from '@runanywhere/proto-ts/structured_output';

const infer = vi.fn();

vi.mock('../../../../../src/Public/API/Runtime/Prerequisites', () => ({
  ensureReady: vi.fn(async () => undefined),
  ensureModelForCategory: vi.fn(async () => 'm'),
}));
vi.mock('../../../../../src/runtime/BackendWorkerHost', async (importOriginal) => ({
  ...(await importOriginal<Record<string, unknown>>()),
  getActiveBackendWorkerHost: () => ({ diagnostics: { executionContext: 'worker' }, infer }),
}));

import { llm } from '../../../../../src/Public/API/Namespaces/llm';
import { adapterState } from '../../../../../src/Adapters/ProtoAdapterTypes';
import { setLlamaBackendWorkerRequired } from '../../../../../src/runtime/BackendWorkerModelOwnership';

const schema = { json: '{"type":"object","properties":{"city":{"type":"string"}}}' };

// The main-thread module exports no structured-output ABI at all, so any
// result has to come from the worker.
const mainThreadModule = {} as NonNullable<typeof adapterState.modalitySlots['structured-output']>;

describe('llm.extractStructured with a worker-owned model', () => {
  beforeEach(() => {
    infer.mockReset();
    setLlamaBackendWorkerRequired(true);
    adapterState.modalitySlots['structured-output'] = mainThreadModule;
  });

  afterEach(() => {
    setLlamaBackendWorkerRequired(false);
    adapterState.modalitySlots['structured-output'] = null;
  });

  it('parses on the BackendWorker through structured.parse', async () => {
    infer.mockResolvedValue({
      resultBytes: StructuredOutputResult.encode(StructuredOutputResult.fromPartial({
        json: '{"city":"Paris"}',
        rawText: '{"city":"Paris"}',
        validation: { isValid: true },
      })).finish(),
    });

    const result = await llm.extractStructured('{"city":"Paris"}', schema);

    expect(infer).toHaveBeenCalledTimes(1);
    const [operation, payload] = infer.mock.calls[0]!;
    expect(operation).toBe('structured.parse');
    const request = StructuredOutputParseRequest.decode(payload.requestBytes);
    expect(request.text).toBe('{"city":"Paris"}');
    expect(request.options?.schema).toBe(schema.json);
    expect(result).toEqual({ value: { city: 'Paris' }, raw: '{"city":"Paris"}', valid: true });
  });
});
