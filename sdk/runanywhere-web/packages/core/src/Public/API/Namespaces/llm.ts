/**
 * `RunAnywhere.llm` — text generation, streaming, structured output, and the
 * tool registry.
 */

import { LLMStreamEventKind } from '@runanywhere/proto-ts/llm_service';
import type { ToolDefinition } from '@runanywhere/proto-ts/tool_calling';
import { StructuredOutputMode } from '@runanywhere/proto-ts/structured_output';
import { LLMProtoAdapter, StructuredOutputProtoAdapter } from '../../../Adapters/ModalityProtoAdapter.js';
import { SDKException } from '../../../Foundation/SDKException.js';
import { ToolCalling, type ToolExecutor } from '../../Extensions/RunAnywhere+ToolCalling.js';
import type { ChatMessage } from '../Inputs.js';
import type { JsonSchema, LlmOptions } from '../Options.js';
import type { GenerationEvent } from '../Events.js';
import type { GenerationResult, StructuredResult } from '../Results.js';
import {
  streamFinalToGenerationResult,
  toGenerationResult,
  toProtoHistory,
  toProtoLlmOptions,
  toStructuredResult,
} from '../Mapping.js';
import { WebModelLifecycle } from '../../Extensions/RunAnywhere+ModelLifecycle.js';
import { ensureModelForCategory, ensureReady } from '../Runtime/Prerequisites.js';
import { ModelCategory } from '@runanywhere/proto-ts/model_types';

function requireAdapter(verb: string): NonNullable<ReturnType<typeof LLMProtoAdapter.tryDefault>> {
  const adapter = LLMProtoAdapter.tryDefault();
  if (!adapter?.supportsProtoLLM()) {
    throw SDKException.backendNotAvailable(
      verb,
      'No Web WASM backend exporting the LLM proto ABI is registered. Install a backend package and call its register() first.',
    );
  }
  return adapter;
}

function isMessageList(value: string | readonly ChatMessage[]): value is readonly ChatMessage[] {
  return Array.isArray(value);
}

/** Split a prompt-or-transcript argument into the prompt and preceding turns. */
function splitInput(input: string | readonly ChatMessage[]): {
  prompt: string;
  history: readonly ChatMessage[];
  systemPrompt?: string;
} {
  if (!isMessageList(input)) return { prompt: input, history: [] };
  const system = input.find((message) => message.role === 'system');
  const conversation = input.filter((message) => message.role !== 'system');
  const last = conversation[conversation.length - 1];
  if (!last) {
    throw SDKException.invalidConfiguration('llm.generate needs at least one non-system message.');
  }
  return {
    prompt: last.content,
    history: conversation.slice(0, -1),
    systemPrompt: system?.content,
  };
}

function buildRequest(input: string | readonly ChatMessage[], options?: LlmOptions) {
  const { prompt, history, systemPrompt } = splitInput(input);
  const merged: LlmOptions = systemPrompt && !options?.systemPrompt
    ? { ...options, systemPrompt }
    : { ...options };
  return {
    prompt,
    requestId: '',
    modelId: merged.model ?? '',
    conversationId: merged.conversationId ?? '',
    history: toProtoHistory(history),
    metadata: {},
    options: toProtoLlmOptions(merged),
  };
}

function usesTools(options?: LlmOptions): boolean {
  if (options?.toolChoice?.kind === 'none') return false;
  if (options?.tools?.length) return true;
  return ToolCalling.getRegisteredTools().length > 0;
}

async function generateWithToolLoop(
  input: string | readonly ChatMessage[],
  options?: LlmOptions,
): Promise<GenerationResult> {
  const { prompt, history } = splitInput(input);
  const protoOptions = toProtoLlmOptions(options);
  const result = await ToolCalling.generateWithTools(
    prompt,
    protoOptions.toolCalling ?? { tools: options?.tools ?? [] },
    {
      llmOptions: {
        maxOutputTokens: protoOptions.maxOutputTokens,
        temperature: protoOptions.temperature,
        topP: protoOptions.topP,
        systemPrompt: protoOptions.systemPrompt,
        reasoning: protoOptions.reasoning,
      },
      history: history.map((message) => message.content),
    },
  );
  return {
    text: result.text,
    thinkingText: result.thinkingContent,
    toolCalls: result.toolCalls,
    finishReason: result.toolCalls.length > 0 ? 'toolCalls' : 'stop',
    inputTokens: 0,
    outputTokens: 0,
    timeToFirstTokenMs: 0,
    tokensPerSecond: 0,
    requestId: result.conversationId ?? '',
    model: '',
  };
}

/** Text generation against the resident language model. */
export const llm = {
  /**
   * Generate a completion, loading and downloading the model when needed.
   *
   * @param input A prompt, or a chat transcript whose last message is the turn to answer.
   * @throws SDKException when no LLM backend is registered or the model cannot be loaded.
   *
   * @example
   * const result = await RunAnywhere.llm.generate('Write a haiku about local AI.');
   * console.log(result.text, result.tokensPerSecond);
   */
  async generate(
    input: string | readonly ChatMessage[],
    options?: LlmOptions,
  ): Promise<GenerationResult> {
    await ensureReady();
    await ensureModelForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE, options?.model);
    if (usesTools(options)) return generateWithToolLoop(input, options);
    const adapter = requireAdapter('llm.generate');
    const result = await adapter.generate(buildRequest(input, options));
    if (!result) {
      throw SDKException.processingFailed('The LLM proto path returned no result.');
    }
    return toGenerationResult(result);
  },

  /**
   * Stream a completion as `started`, `token`, and `completed` events.
   *
   * Breaking out of the iterator cancels the request.
   *
   * @throws SDKException on preflight failure; in-flight failures throw into the consumer.
   */
  generateStream(
    input: string | readonly ChatMessage[],
    options?: LlmOptions,
  ): AsyncIterable<GenerationEvent> {
    return (async function* generation(): AsyncGenerator<GenerationEvent> {
      await ensureReady();
      await ensureModelForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE, options?.model);
      const adapter = requireAdapter('llm.generateStream');
      const request = buildRequest(input, options);
      const events = adapter.generateStream(request);
      let announced = false;
      let text = '';
      let thinking = '';
      let tokens = 0;
      let completed = false;
      const startedAt = performance.now();
      let firstTokenAt: number | undefined;
      try {
        for await (const event of events) {
          if (!announced) {
            announced = true;
            yield { type: 'started', requestId: event.requestId };
          }
          if (event.error) throw new SDKException(event.error);
          if (event.token) {
            firstTokenAt ??= performance.now();
            const thought = event.eventKind === LLMStreamEventKind.LLM_STREAM_EVENT_KIND_THINKING;
            if (thought) thinking += event.token;
            else {
              text += event.token;
              tokens += 1;
            }
            yield { type: 'token', text: event.token, kind: thought ? 'thought' : 'text' };
          }
          if (event.toolCall) yield { type: 'toolCall', toolCall: event.toolCall };
          if (event.result) {
            completed = true;
            const elapsed = performance.now() - startedAt;
            yield {
              type: 'completed',
              result: streamFinalToGenerationResult(
                event.result,
                event.requestId,
                options?.model
                  ?? WebModelLifecycle.modelInfoForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE)?.id
                  ?? '',
                {
                  text,
                  thinkingText: thinking,
                  outputTokens: tokens,
                  ttftMs: firstTokenAt === undefined ? 0 : firstTokenAt - startedAt,
                  tokensPerSecond: elapsed > 0 ? (tokens / elapsed) * 1000 : 0,
                },
              ),
            };
          }
        }
      } finally {
        if (!completed) adapter.cancel();
      }
    })();
  },

  /**
   * Generate JSON that satisfies a schema, returning the parsed value with the
   * raw text alongside it.
   *
   * @throws SDKException when the backend cannot parse structured output.
   */
  async generateStructured(
    prompt: string,
    schema: JsonSchema,
    options?: LlmOptions,
  ): Promise<StructuredResult> {
    const generation = await llm.generate(prompt, {
      ...options,
      structuredOutput: { schema, strict: options?.structuredOutput?.strict ?? true },
    });
    const adapter = StructuredOutputProtoAdapter.tryDefault();
    if (!adapter?.supportsProtoParse()) {
      throw SDKException.backendNotAvailable(
        'llm.generateStructured',
        'This Web WASM build does not export rac_structured_output_parse_proto.',
      );
    }
    const parsed = adapter.parse({
      requestId: generation.requestId,
      text: generation.text,
      options: {
        includeSchemaInPrompt: true,
        jsonSchema: schema.json,
        strictMode: options?.structuredOutput?.strict ?? true,
        mode: StructuredOutputMode.STRUCTURED_OUTPUT_MODE_JSON_SCHEMA,
        repairJson: false,
        maxRetries: 0,
      },
      metadata: {},
    });
    if (!parsed) {
      throw SDKException.processingFailed('Structured-output parsing returned no result.');
    }
    return toStructuredResult(parsed, generation, schema.parse);
  },

  /** Tools the model may call during generation. */
  tools: {
    /** Register a tool and the function that runs it. */
    register(tool: ToolDefinition, executor: ToolExecutor): void {
      ToolCalling.registerTool(tool, executor);
    },

    /** Drop a registered tool by name. */
    unregister(name: string): void {
      ToolCalling.unregisterTool(name);
    },

    /** Every currently registered tool. */
    list(): ToolDefinition[] {
      return ToolCalling.getRegisteredTools();
    },
  },
};
