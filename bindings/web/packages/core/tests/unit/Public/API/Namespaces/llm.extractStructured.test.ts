import { beforeEach, describe, expect, it, vi } from 'vitest';

const extractStructuredOutputAsync = vi.fn();

vi.mock('../../../../../src/Public/API/Runtime/Prerequisites', () => ({
  ensureReady: vi.fn(async () => undefined),
  ensureModelForCategory: vi.fn(async () => 'm'),
}));
vi.mock('../../../../../src/Public/Extensions/RunAnywhere+TextGeneration', () => ({
  extractStructuredOutputAsync: (...args: unknown[]) => extractStructuredOutputAsync(...args),
}));

import { llm } from '../../../../../src/Public/API/Namespaces/llm';

const schema = { json: '{"type":"object","properties":{"city":{"type":"string"}}}' };

describe('llm.extractStructured delegation and result mapping', () => {
  beforeEach(() => {
    extractStructuredOutputAsync.mockReset();
  });

  it('delegates to extractStructuredOutputAsync with the schema JSON', async () => {
    extractStructuredOutputAsync.mockResolvedValue({
      json: '{"city":"Paris"}',
      rawText: 'Sure: {"city":"Paris"}',
      validation: { isValid: true },
    });

    const result = await llm.extractStructured('Sure: {"city":"Paris"}', schema);

    expect(extractStructuredOutputAsync).toHaveBeenCalledWith(
      'Sure: {"city":"Paris"}',
      { jsonSchema: schema.json },
    );
    expect(result).toEqual({
      value: { city: 'Paris' },
      raw: 'Sure: {"city":"Paris"}',
      valid: true,
    });
  });

  it('reports invalid output instead of throwing', async () => {
    extractStructuredOutputAsync.mockResolvedValue({
      json: '',
      validation: { isValid: false },
    });

    const result = await llm.extractStructured('not json', schema);

    expect(result).toEqual({ value: undefined, raw: 'not json', valid: false });
  });

  it('applies the schema parse function to the raw text', async () => {
    extractStructuredOutputAsync.mockResolvedValue({
      json: '{"city":"Paris"}',
      rawText: '{"city":"Paris"}',
      validation: { isValid: true },
    });
    const parse = vi.fn((text: string) => ({ parsed: text }));

    const result = await llm.extractStructured('{"city":"Paris"}', { ...schema, parse });

    expect(parse).toHaveBeenCalledWith('{"city":"Paris"}');
    expect(result.value).toEqual({ parsed: '{"city":"Paris"}' });
  });

  it('passes backend errors through unchanged', async () => {
    const error = new Error('Backend not available for: extractStructuredOutputAsync');
    extractStructuredOutputAsync.mockRejectedValue(error);

    await expect(llm.extractStructured('{}', schema)).rejects.toBe(error);
  });
});
