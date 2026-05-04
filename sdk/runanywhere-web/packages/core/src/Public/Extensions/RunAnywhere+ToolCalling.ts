/**
 * RunAnywhere+ToolCalling.ts
 *
 * Tool calling namespace — mirrors Swift's `RunAnywhere+ToolCalling.swift`.
 * Re-exports canonical proto-ts types + provides `RunAnywhere.toolCalling.*` surface.
 */

export type {
  ToolCallingOptions,
  ToolDefinition,
  ToolCall,
  ToolResult,
} from '@runanywhere/proto-ts/tool_calling';

import type { ToolCallingOptions, ToolDefinition } from '@runanywhere/proto-ts/tool_calling';
import type { LLMGenerationOptions, LLMGenerationResult } from '@runanywhere/proto-ts/llm_options';
import { generate } from './RunAnywhere+Convenience';

export const ToolCalling = {
  async generate(
    prompt: string,
    _tools: ToolDefinition[],
    options?: Partial<LLMGenerationOptions & { toolCallingOptions?: ToolCallingOptions }>,
  ): Promise<LLMGenerationResult> {
    return generate(prompt, options);
  },
};
