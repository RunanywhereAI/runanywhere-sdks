/**
 * `RunAnywhere.llm` — text generation, streaming, structured output, and the
 * tool registry.
 */

import { LLMStreamEventKind, type LLMGenerateRequest } from '@runanywhere/proto-ts/llm_service';
import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import type { ToolDefinition } from '@runanywhere/proto-ts/tool_calling';
import {
  ChatMessage as ProtoChatMessageMessage,
  MessageRole,
  type ChatMessage as ProtoChatMessage,
} from '@runanywhere/proto-ts/chat';
import { LLMProtoAdapter, StructuredOutputProtoAdapter } from '../../../Adapters/ModalityProtoAdapter.js';
import { SDKException } from '../../../Foundation/SDKException.js';
import { ToolCalling, type ToolExecutor } from '../../Extensions/RunAnywhere+ToolCalling.js';
import { WebModelLifecycle } from '../../Extensions/RunAnywhere+ModelLifecycle.js';
import type { ChatMessage } from '../Inputs.js';
import type { JsonSchema, LlmOptions, StructuredOutputMode } from '../Options.js';
import type { GenerationEvent } from '../Events.js';
import type { GenerationResult, StructuredResult } from '../Results.js';
import {
  currentDevicePlacement,
  finishReasonFrom,
  frameworkToBackend,
  streamFinalToGenerationResult,
  toGenerationResult,
  toProtoHistory,
  toProtoLlmOptions,
  toProtoStructuredOutputOptions,
  toStructuredResult,
} from '../Mapping.js';
import { ensureModelForCategory, ensureReady } from '../Runtime/Prerequisites.js';

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

function buildRequest(input: string | readonly ChatMessage[], options?: LlmOptions): LLMGenerateRequest {
  const { prompt, history, systemPrompt } = splitInput(input);
  const merged: LlmOptions = systemPrompt && !options?.systemPrompt
    ? { ...options, systemPrompt }
    : { ...options };
  const messages: ProtoChatMessage[] = [
    ...toProtoHistory(history),
    ProtoChatMessageMessage.fromPartial({ role: MessageRole.MESSAGE_ROLE_USER, content: prompt }),
  ];
  return {
    requestId: '',
    modelId: merged.model ?? '',
    conversationId: merged.conversationId ?? '',
    messages,
    options: toProtoLlmOptions(merged),
  };
}

function usesTools(options?: LlmOptions): boolean {
  if (options?.toolChoice?.kind === 'none') return false;
  if (options?.tools?.length) return true;
  return ToolCalling.getRegisteredTools().length > 0;
}

/** Attach the honest backend/device placement of the currently resident language model. */
function withPlacement(result: GenerationResult): GenerationResult {
  const model = WebModelLifecycle.modelInfoForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE);
  return {
    ...result,
    actualBackend: frameworkToBackend(model?.framework),
    actualDevice: result.actualDevice ?? currentDevicePlacement(),
  };
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
  return withPlacement({
    text: result.text,
    thinkingText: result.thinkingContent,
    toolCalls: result.toolCalls,
    finishReason: finishReasonFrom(result.finishReason, false),
    inputTokens: result.usage?.inputTokens ?? 0,
    outputTokens: result.usage?.outputTokens ?? 0,
    timeToFirstTokenMs: Math.round(result.usage?.ttftMs ?? 0),
    tokensPerSecond: result.usage?.decodeTokensPerSecond ?? 0,
    requestId: '',
    model: '',
  });
}

/**
 * Shared generation core for `generate` and `generateStructured`: resolves
 * the model, then either runs the tool loop or the direct proto call.
 * `structuredOutput`, when given, is spliced into the proto request options
 * after the fact — `LlmOptions` itself carries no structured-output schema.
 */
async function generateCore(
  input: string | readonly ChatMessage[],
  options: LlmOptions | undefined,
  structuredOutput?: ReturnType<typeof toProtoStructuredOutputOptions>,
): Promise<GenerationResult> {
  await ensureReady();
  await ensureModelForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE, options?.model);
  if (!structuredOutput && usesTools(options)) return generateWithToolLoop(input, options);
  const adapter = requireAdapter('llm.generate');
  const request = buildRequest(input, options);
  if (structuredOutput && request.options) request.options.structuredOutput = structuredOutput;
  const result = await adapter.generate(request);
  if (!result) {
    throw SDKException.processingFailed('The LLM proto path returned no result.');
  }
  return withPlacement(toGenerationResult(result));
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
  generate(
    input: string | readonly ChatMessage[],
    options?: LlmOptions,
  ): Promise<GenerationResult> {
    return generateCore(input, options);
  },

  /**
   * Stream a completion as `started`, `textDelta`/`reasoningDelta`,
   * `toolCallAdded`/`toolArgumentsDone`, `usage`, and a terminal
   * `completed`/`failed` event. Never fabricates a successful `completed`.
   *
   * Breaking out of the iterator cancels the request.
   *
   * @throws SDKException on preflight failure; in-flight failures arrive as a `failed` event.
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

      const itemId = 'response-0';
      let requestId = '';
      let announced = false;
      let text = '';
      let thinking = '';
      let terminal = false;
      let sequence = 0;

      function partial(): Partial<GenerationResult> {
        return { text, thinkingText: thinking || undefined };
      }

      try {
        for await (const event of events) {
          if (event.requestId) requestId = event.requestId;
          if (!announced) {
            announced = true;
            yield { type: 'started', requestId };
          }
          if (event.error) {
            yield { type: 'failed', requestId, partial: partial(), error: event.error };
            terminal = true;
            break;
          }
          if (event.token) {
            const thought = event.eventKind === LLMStreamEventKind.LLM_STREAM_EVENT_KIND_THINKING;
            if (thought) {
              thinking += event.token;
              yield {
                type: 'reasoningDelta', requestId, sequence: sequence++, itemId, index: 0, text: event.token,
              };
            } else {
              text += event.token;
              yield {
                type: 'textDelta', requestId, sequence: sequence++, itemId, index: 0, text: event.token,
              };
            }
          }
          if (event.toolCall) {
            yield {
              type: 'toolCallAdded',
              requestId,
              sequence: sequence++,
              itemId,
              index: 0,
              call: event.toolCall,
            };
            yield {
              type: 'toolArgumentsDone',
              requestId,
              sequence: sequence++,
              itemId,
              arguments: event.toolCall.argumentsJson,
            };
          }
          if (event.result) {
            terminal = true;
            const result = withPlacement(streamFinalToGenerationResult(
              event.result,
              requestId,
              options?.model
                ?? WebModelLifecycle.modelInfoForCategory(ModelCategory.MODEL_CATEGORY_LANGUAGE)?.id
                ?? '',
            ));
            yield {
              type: 'usage',
              requestId,
              sequence: sequence++,
              usage: {
                inputTokens: result.inputTokens,
                outputTokens: result.outputTokens,
                totalTokens: event.result.usage?.totalTokens ?? 0,
                decodeTokensPerSecond: result.tokensPerSecond,
                prefillMs: event.result.promptEvalTimeMs ?? 0,
                ttftMs: result.timeToFirstTokenMs,
              },
            };
            yield { type: 'completed', requestId, result };
          }
        }
      } catch (error) {
        yield { type: 'failed', requestId, partial: partial(), error: SDKException.fromUnknown(error).proto };
        terminal = true;
      } finally {
        if (!terminal) adapter.cancel();
      }
    })();
  },

  /**
   * Generate JSON that satisfies a schema, returning the parsed value with
   * the raw text alongside it.
   *
   * @param mode `'validationOnly'` (default) parses and validates after
   *   generation; `'repair'` additionally attempts to fix malformed JSON.
   *   `'constrained'` fails preflight — Web has no grammar-constrained
   *   decoding hook.
   * @throws SDKException when the backend cannot parse structured output,
   *   or `mode` is `'constrained'`.
   */
  async generateStructured(
    prompt: string,
    schema: JsonSchema,
    mode: StructuredOutputMode = 'validationOnly',
    options?: LlmOptions,
  ): Promise<StructuredResult> {
    if (mode === 'constrained') {
      throw SDKException.unsupportedCapability(
        "llm.generateStructured(mode: 'constrained')",
        'The Web SDK has no grammar-constrained decoding hook; use "validationOnly" or "repair".',
      );
    }
    const structuredOutput = toProtoStructuredOutputOptions(schema.json, mode);
    const generation = await generateCore(prompt, options, structuredOutput);
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
      options: structuredOutput,
      metadata: {},
    });
    if (!parsed) {
      throw SDKException.processingFailed('Structured-output parsing returned no result.');
    }
    return toStructuredResult(parsed, generation, mode, schema.parse);
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
