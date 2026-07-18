import { afterEach, describe, expect, it } from 'vitest';
import { registerDuckDuckGoSearchTool } from '../../../../src/Public/Helpers/registerDuckDuckGoSearchTool';
import { ToolCalling } from '../../../../src/Public/Extensions/RunAnywhere+ToolCalling';

describe('registerDuckDuckGoSearchTool', () => {
  afterEach(() => ToolCalling.clearTools());

  it('registers the explicitly demo-only web search tool', () => {
    registerDuckDuckGoSearchTool();
    expect(ToolCalling.getRegisteredTools()).toEqual([
      expect.objectContaining({
        name: 'web_search',
        description: expect.stringContaining('DuckDuckGo'),
      }),
    ]);
  });
});
