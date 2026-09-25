import { beforeEach, describe, expect, it, vi } from 'vitest';

const generateWithTools = vi.fn();

vi.mock('../../../../../src/Public/API/Runtime/Prerequisites', () => ({
  ensureReady: vi.fn(async () => undefined),
  ensureModelForCategory: vi.fn(async () => 'm'),
}));
vi.mock('../../../../../src/Public/Extensions/RunAnywhere+ModelLifecycle', () => ({
  WebModelLifecycle: { modelInfoForCategory: () => null },
}));
vi.mock('../../../../../src/Public/Extensions/RunAnywhere+ToolCalling', () => ({
  ToolCalling: {
    getRegisteredTools: () => [],
    generateWithTools: (...args: unknown[]) => generateWithTools(...args),
  },
}));

import { llm } from '../../../../../src/Public/API/Namespaces/llm';

const tool = { name: 'get_weather', description: 'Look up the weather', parameters: [] } as never;
const transcript = [
  { role: 'system', content: 'You are a pirate.' },
  { role: 'user', content: 'Weather in Paris?' },
] as const;

describe('llm.generate tool loop with a chat transcript', () => {
  beforeEach(() => {
    generateWithTools.mockReset();
    generateWithTools.mockResolvedValue({ text: 'ok', toolCalls: [], finishReason: 0 });
  });

  it('forwards the transcript system message as the system prompt', async () => {
    await llm.generate(transcript, { tools: [tool] });
    const extra = generateWithTools.mock.calls[0]![2];
    expect(extra.llmOptions.systemPrompt).toBe('You are a pirate.');
  });

  it('lets options.systemPrompt override the transcript system message', async () => {
    await llm.generate(transcript, { tools: [tool], systemPrompt: 'Be terse.' });
    const extra = generateWithTools.mock.calls[0]![2];
    expect(extra.llmOptions.systemPrompt).toBe('Be terse.');
  });
});
