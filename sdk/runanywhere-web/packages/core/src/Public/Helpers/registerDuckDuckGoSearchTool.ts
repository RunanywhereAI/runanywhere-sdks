import {
  ToolDefinition,
  ToolParameterType,
  ToolValue,
} from '@runanywhere/proto-ts/tool_calling';
import { ToolCalling } from '../Extensions/RunAnywhere+ToolCalling.js';

/**
 * Registers a small DuckDuckGo Instant Answer API tool for demos.
 *
 * This helper is intentionally not part of core inference: it makes a network
 * request, is subject to the host page's CSP/CORS policy, and should be
 * replaced with a host-controlled search provider in production.
 */
export function registerDuckDuckGoSearchTool(): void {
  ToolCalling.registerTool(
    ToolDefinition.fromPartial({
      name: 'web_search',
      description: 'Search the public web using DuckDuckGo Instant Answers.',
      parameters: [{
        name: 'query',
        type: ToolParameterType.TOOL_PARAMETER_TYPE_STRING,
        description: 'The search query',
        required: true,
        enumValues: [],
      }],
    }),
    async (args) => {
      const query = args.query?.stringValue?.trim();
      if (!query) throw new Error('web_search requires a non-empty query');
      const response = await fetch(
        `https://api.duckduckgo.com/?q=${encodeURIComponent(query)}&format=json&no_html=1&skip_disambig=1`,
      );
      if (!response.ok) throw new Error(`DuckDuckGo search failed (HTTP ${response.status})`);
      const body = await response.json() as {
        AbstractText?: string;
        AbstractURL?: string;
        RelatedTopics?: Array<{ Text?: string; FirstURL?: string }>;
      };
      const related = body.RelatedTopics?.find((topic) => topic.Text)?.Text ?? '';
      return {
        answer: ToolValue.fromPartial({ stringValue: body.AbstractText || related || 'No instant answer found.' }),
        url: ToolValue.fromPartial({ stringValue: body.AbstractURL || '' }),
      };
    },
  );
}
