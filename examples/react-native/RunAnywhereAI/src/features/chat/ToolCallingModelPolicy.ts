/**
 * Tool-calling routing and execution policy for the chat screen.
 *
 * Mirrors the Android example's ToolCallingModelPolicy /
 * ToolCallingExecutionPolicy (examples/android/.../chat/ToolCallingModelPolicy.kt)
 * so every platform gates and budgets tool calling identically. Sampling knobs
 * (temperature, top-p, max tokens) travel through generateWithTools' llmOptions
 * channel on React Native rather than the tool-options message.
 */

import type { ModelInfo } from '@runanywhere/proto-ts/model_types';
import type { ToolCallingOptions, ToolDefinition } from '@runanywhere/core';

/** The generation path selected after tool/model compatibility preflight. */
export enum ToolCallingRoute {
  StandardGeneration = 'standard',
  ToolGeneration = 'tool',
  Blocked = 'blocked',
}

export interface ToolCallingAvailability {
  isAvailable: boolean;
  message?: string;
}

export interface ToolCallingPreflight {
  route: ToolCallingRoute;
  availability: ToolCallingAvailability;
}

/** Sampling channel forwarded to generateWithTools via `extra.llmOptions`. */
export interface ToolCallingSampling {
  maxOutputTokens: number;
  temperature: number;
  topP: number;
}

export interface ToolCallingExecutionPlan {
  llmOptions: ToolCallingSampling;
  toolOptions: Partial<ToolCallingOptions>;
}

const unavailable = (message: string): ToolCallingAvailability => ({
  isAvailable: false,
  message,
});

/**
 * App-level production gate for tool calling.
 *
 * Tool definitions, format instructions, the user prompt, and follow-up tool
 * results all share the model context window. The built-in catalog currently
 * produces an initial tools prompt just over 512 tokens, so 512-token models
 * fail before decoding. A published 1K window is the minimum supported tool
 * configuration; the execution budget below bounds output and loop duration so
 * compatible small models stay responsive.
 */
export const ToolCallingModelPolicy = {
  MINIMUM_CONTEXT_TOKENS: 1024,

  evaluate(model: ModelInfo | null): ToolCallingAvailability {
    if (!model) {
      return unavailable('Choose a chat model before enabling Web & tools.');
    }
    const modelName = model.name || model.id || 'The current model';
    const contextLength = model.contextLength;
    if (contextLength <= 0) {
      return unavailable(
        `${modelName} does not publish a context-window capability. ` +
          'Choose a model with at least 1,024 tokens for Web & tools.'
      );
    }
    if (contextLength < ToolCallingModelPolicy.MINIMUM_CONTEXT_TOKENS) {
      return unavailable(
        `${modelName} has a ${contextLength}-token context window. ` +
          'Web & tools require at least 1,024 tokens. Choose a larger-context model.'
      );
    }
    return { isAvailable: true };
  },

  preflight(
    toolsRequested: boolean,
    registeredToolCount: number,
    model: ModelInfo | null
  ): ToolCallingPreflight {
    if (!toolsRequested || registeredToolCount <= 0) {
      return {
        route: ToolCallingRoute.StandardGeneration,
        availability: ToolCallingModelPolicy.evaluate(model),
      };
    }
    const availability = ToolCallingModelPolicy.evaluate(model);
    return {
      route: availability.isAvailable
        ? ToolCallingRoute.ToolGeneration
        : ToolCallingRoute.Blocked,
      availability,
    };
  },
} as const;

/** Tool-only limits applied after the normal chat response-budget policy. */
export const ToolCallingExecutionPolicy = {
  // The shared native loop stops the forced decision at the tool-call closing
  // marker with an independent safety ceiling. Final synthesis stays concise
  // while retaining room for an answer and a source URL.
  MAX_FINAL_RESPONSE_TOKENS: 96,
  MAX_TOOL_CALLS: 2,
  TIMEOUT_MILLIS: 45000,
  PROGRESS_MESSAGE: 'Using web & tools…',

  plan(
    tools: ToolDefinition[],
    requestedMaxTokens?: number
  ): ToolCallingExecutionPlan {
    const maxOutputTokens =
      requestedMaxTokens !== undefined &&
      requestedMaxTokens >= 1 &&
      requestedMaxTokens <= ToolCallingExecutionPolicy.MAX_FINAL_RESPONSE_TOKENS
        ? requestedMaxTokens
        : ToolCallingExecutionPolicy.MAX_FINAL_RESPONSE_TOKENS;
    return {
      // Tool decisions must be reproducible: greedy sampling (temperature 0,
      // top-p 1) with a tight response budget.
      llmOptions: { maxOutputTokens, temperature: 0, topP: 1 },
      toolOptions: {
        tools,
        maxToolCalls: ToolCallingExecutionPolicy.MAX_TOOL_CALLS,
        autoExecute: true,
        keepToolsAvailable: false,
        disableThinking: true,
        // One model turn may request multiple tools (e.g. weather + time) and
        // get them all executed before a single follow-up reply.
        parallelToolCalls: true,
      },
    };
  },
} as const;
