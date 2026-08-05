/**
 * `RunAnywhere.llm` — text generation, streaming, structured output, and tools.
 */

import { ModelCategory } from '@runanywhere/proto-ts/model_types';
import {
  LLMGenerationResult,
  type LLMGenerationOptions,
} from '@runanywhere/proto-ts/llm_options';
import {
  LLMGenerateRequest,
  LLMStreamEvent,
  LLMStreamEventKind,
} from '@runanywhere/proto-ts/llm_service';
import { ToolCallingSessionCreateRequest } from '@runanywhere/proto-ts/tool_calling';
import { TokenKind as ProtoTokenKind } from '@runanywhere/proto-ts/voice_events';
import {
  ToolCall,
  ToolCallingResult,
  ToolResult,
  type ToolDefinition,
} from '@runanywhere/proto-ts/tool_calling';
import {
  StructuredOutputOptions,
  StructuredOutputRequest,
  StructuredOutputResult,
} from '@runanywhere/proto-ts/structured_output';

import { SDKException } from '../../Foundation/Errors/SDKException';
import { requireInitialized } from '../../Foundation/Initialization/InitializedGuard';
import {
  clearTools,
  executeTool,
  getRegisteredTools,
  registerTool,
  toolValueMapToJson,
  toolValueMapFromJson,
  unregisterTool,
} from '../Extensions/LLM/RunAnywhere+ToolCalling';
import { decode, decodeEvent, encode, nextRequestId, preflight } from './Bridge';
import { ensureModelLoaded } from './Models';
import { toLlmOptions, toToolCallingOptions } from './Options';
import { toChatMessages } from './Inputs';
import { pushStream } from './Stream';
import {
  emptyGenerationResult,
  toGenerationResult,
  toGenerationResultFromStream,
  toStructuredResult,
} from './Results';
import type {
  ChatMessage,
  GenerationEvent,
  GenerationResult,
  JsonSchema,
  LlmOptions,
  StructuredOutputMode,
  StructuredResult,
  ToolExecutor,
} from './Types';

interface PromptAndHistory {
  prompt: string;
  history: ChatMessage[];
}

function splitMessages(input: string | ChatMessage[]): PromptAndHistory {
  if (typeof input === 'string') return { prompt: input, history: [] };
  if (input.length === 0) {
    throw SDKException.invalidInput('llm.generate needs at least one message');
  }
  const history = input.slice(0, -1);
  const last = input[input.length - 1];
  return { prompt: last?.content ?? '', history };
}

async function toolsForRequest(options?: LlmOptions): Promise<ToolDefinition[]> {
  if (options?.toolChoice === 'none') return [];
  if (options?.tools && options.tools.length > 0) return options.tools;
  return getRegisteredTools();
}

async function buildRequest(
  input: string | ChatMessage[],
  options: LlmOptions | undefined,
  requestId: string,
  tools: ToolDefinition[]
): Promise<LLMGenerateRequest> {
  const { prompt, history } = splitMessages(input);
  if (options?.model) {
    await ensureModelLoaded(options.model, ModelCategory.MODEL_CATEGORY_LANGUAGE);
  }
  const generation: LLMGenerationOptions = toLlmOptions(options);
  if (tools.length > 0) {
    generation.toolCalling = toToolCallingOptions(tools, options);
  }
  return LLMGenerateRequest.fromPartial({
    prompt,
    requestId,
    ...(options?.model ? { modelId: options.model } : {}),
    options: generation,
    history: toChatMessages(history),
  });
}

async function generateWithToolLoop(
  input: string | ChatMessage[],
  options: LlmOptions | undefined,
  tools: ToolDefinition[],
  requestId: string
): Promise<GenerationResult> {
  const native = await preflight();
  const { prompt, history } = splitMessages(input);
  if (options?.model) {
    await ensureModelLoaded(options.model, ModelCategory.MODEL_CATEGORY_LANGUAGE);
  }
  const generation = toLlmOptions(options);
  const toolCalling = toToolCallingOptions(tools, options);
  const request = ToolCallingSessionCreateRequest.fromPartial({
    prompt,
    maxTokens: generation.maxOutputTokens,
    temperature: generation.temperature,
    topP: generation.topP,
    systemPrompt: generation.systemPrompt ?? '',
    tools: toolCalling.tools,
    format: toolCalling.format,
    maxToolCalls: toolCalling.maxToolCalls,
    keepToolsAvailable: toolCalling.keepToolsAvailable,
    toolChoice: toolCalling.toolChoice,
    forcedToolName: toolCalling.forcedToolName,
    disableThinking: toolCalling.disableThinking,
    autoExecute: toolCalling.autoExecute,
    replaceSystemPrompt: toolCalling.replaceSystemPrompt,
    requireJsonArguments: toolCalling.requireJsonArguments,
    parallelToolCalls: toolCalling.parallelToolCalls,
    // Prior turns flattened to [user0, asst0, ...] message contents; commons
    // threads these into every generate in the loop (mirrors ToolCallingOrchestrator.kt).
    history: history.map((message) => message.content),
  });

  const resultBytes = await native.toolRunLoopProtoWithHandle(
    encode(request, ToolCallingSessionCreateRequest),
    async (toolCallBytes: ArrayBuffer) => {
      const call = decodeEvent(toolCallBytes, ToolCall);
      const outcome = await executeTool(call);
      return encode(outcome, ToolResult);
    },
    () => undefined
  );
  const result = decode(resultBytes, ToolCallingResult, 'toolRunLoop');
  if (result.errorMessage) {
    throw SDKException.generationFailed(result.errorMessage);
  }
  return {
    text: result.text,
    ...(result.thinkingContent ? { thinkingText: result.thinkingContent } : {}),
    toolCalls: result.toolCalls,
    finishReason: result.toolCalls.length > 0 ? 'toolCalls' : 'stop',
    inputTokens: result.usage?.inputTokens ?? 0,
    outputTokens: result.usage?.outputTokens ?? 0,
    timeToFirstTokenMs: 0,
    tokensPerSecond: result.usage?.tokensPerSecond ?? 0,
    requestId,
    model: options?.model ?? '',
  };
}

function tokenKind(event: LLMStreamEvent): 'text' | 'thought' {
  return event.kind === ProtoTokenKind.TOKEN_KIND_THOUGHT ||
    event.eventKind === LLMStreamEventKind.LLM_STREAM_EVENT_KIND_THINKING
    ? 'thought'
    : 'text';
}

/** Text generation: one-shot, streaming, structured, and tool-driven. */
export const llm = {
  /**
   * Generate a completion for a prompt or a chat transcript.
   *
   * @example
   * const result = await RunAnywhere.llm.generate('Summarize on-device AI in one line.');
   * console.log(result.text, result.tokensPerSecond);
   *
   * @throws SDKException when no language model is available or generation fails.
   */
  async generate(
    input: string | ChatMessage[],
    options?: LlmOptions
  ): Promise<GenerationResult> {
    const requestId = nextRequestId('llm');
    const tools = await toolsForRequest(options);
    if (tools.length > 0) {
      return generateWithToolLoop(input, options, tools, requestId);
    }
    const native = await preflight();
    const request = await buildRequest(input, options, requestId, tools);
    const resultBytes = await native.llmGenerateProto(
      encode(request, LLMGenerateRequest)
    );
    return toGenerationResult(
      decode(resultBytes, LLMGenerationResult, 'llmGenerate'),
      requestId
    );
  },

  /**
   * Stream a completion as `started`, token deltas, then `completed`.
   *
   * @throws SDKException into the consumer when generation fails in flight.
   */
  generateStream(
    input: string | ChatMessage[],
    options?: LlmOptions
  ): AsyncIterable<GenerationEvent> {
    requireInitialized();
    const requestId = nextRequestId('llm');
    let cancelled = false;
    let cancel: (() => Promise<void>) | null = null;

    return pushStream<GenerationEvent>(
      async (controller) => {
        const native = await preflight();
        const tools = await toolsForRequest(options);
        const request = await buildRequest(input, options, requestId, tools);
        if (cancelled) {
          controller.finish();
          return;
        }
        cancel = async () => {
          await native.llmCancelProto().catch(() => undefined);
        };
        controller.push({ type: 'started', requestId });

        let sawCompletion = false;
        let sawAnyEvent = false;
        let accumulatedText = '';
        let accumulatedThinking = '';

        void native
          .llmGenerateStreamProto(
            encode(request, LLMGenerateRequest),
            (eventBytes: ArrayBuffer) => {
              sawAnyEvent = true;
              const event = decodeEvent(eventBytes, LLMStreamEvent);
              if (event.error) {
                sawCompletion = true;
                controller.push({
                  type: 'failed',
                  requestId,
                  partial: accumulatedText || undefined,
                  error: new SDKException(event.error),
                });
                controller.finish();
                return;
              }
              if (event.toolCall) {
                controller.push({ type: 'toolCall', toolCall: event.toolCall });
              }
              if (event.token.length > 0) {
                const kind = tokenKind(event);
                if (kind === 'thought') {
                  accumulatedThinking += event.token;
                } else {
                  accumulatedText += event.token;
                }
                controller.push({ type: 'token', text: event.token, kind });
              }
              if (event.isFinal) {
                sawCompletion = true;
                controller.push({
                  type: 'completed',
                  requestId,
                  result: event.result
                    ? toGenerationResultFromStream(
                        event.result,
                        requestId,
                        options?.model ?? ''
                      )
                    : emptyGenerationResult(requestId, options?.model ?? ''),
                });
                controller.finish();
              }
            }
          )
          .then(() => {
            if (sawCompletion) {
              controller.finish();
              return;
            }
            // The native call resolved without ever sending `isFinal`. Never
            // fabricate a successful `completed` — the stream ends `failed`
            // instead, unless it never produced a single event, which is
            // reported the same way.
            if (!sawAnyEvent) {
              controller.fail(
                SDKException.generationFailed(
                  'Generation ended before producing any output'
                )
              );
              return;
            }
            controller.push({
              type: 'failed',
              requestId,
              partial: accumulatedText || undefined,
              error: SDKException.generationFailed(
                'Generation stream ended before a terminal event'
              ),
            });
            controller.finish();
          })
          .catch((error: Error) => controller.fail(error));
      },
      async () => {
        cancelled = true;
        await cancel?.();
      }
    );
  },

  /**
   * Generate a value that conforms to `schema`.
   *
   * `mode` picks how the schema is enforced:
   * - `'validationOnly'` (default): generate freely, then validate.
   * - `'repair'`: validate, then retry once with a repair instruction if invalid.
   * - `'constrained'`: engine-constrained decoding — fails preflight until a
   *   constrained-decoding engine is wired in.
   *
   * Sampling knobs in `options` are not forwarded: commons'
   * `StructuredOutputRequest` carries no generation submessage, so the
   * structured pipeline applies its own defaults. `options.model` is honoured.
   *
   * @throws SDKException when `mode` cannot be honored, generation fails, or
   * the output cannot be parsed.
   */
  async generateStructured<T = unknown>(
    prompt: string,
    schema: JsonSchema,
    options?: LlmOptions,
    mode: StructuredOutputMode = 'validationOnly'
  ): Promise<StructuredResult<T>> {
    if (mode === 'constrained') {
      throw SDKException.notImplemented(
        "llm.generateStructured(mode: 'constrained') needs engine-level constrained decoding, " +
          "which is not wired in yet; use 'validationOnly' or 'repair'"
      );
    }
    const native = await preflight();
    const requestId = nextRequestId('structured');
    if (options?.model) {
      await ensureModelLoaded(
        options.model,
        ModelCategory.MODEL_CATEGORY_LANGUAGE
      );
    }
    const runOnce = async (text: string): Promise<StructuredOutputResult> => {
      const request = StructuredOutputRequest.fromPartial({
        requestId,
        prompt: text,
        options: StructuredOutputOptions.fromPartial({
          schema,
          strictMode: options?.structuredOutput?.strict ?? true,
          includeSchemaInPrompt: true,
        }),
      });
      const resultBytes = await native.structuredOutputGenerateProto(
        encode(request, StructuredOutputRequest)
      );
      return decode(resultBytes, StructuredOutputResult, 'structuredOutputGenerate');
    };

    let result = await runOnce(prompt);
    if (mode === 'repair' && !(result.validation?.isValid ?? true)) {
      const repairPrompt =
        `${prompt}\n\nYour previous answer did not match the required JSON schema. ` +
        'Reply again with ONLY JSON that satisfies this schema.\n\n' +
        `Previous invalid answer: ${result.rawText ?? ''}`;
      result = await runOnce(repairPrompt);
    }
    return toStructuredResult<T>(
      result,
      emptyGenerationResult(requestId, options?.model ?? ''),
      mode
    );
  },

  /** Tools the model may call during generation. */
  tools: {
    /**
     * Make a tool callable by the model, executed by `executor`.
     *
     * @example
     * RunAnywhere.llm.tools.register(weatherTool, async (args) => ({ tempC: 21 }));
     */
    async register(
      tool: ToolDefinition,
      executor: ToolExecutor
    ): Promise<void> {
      await registerTool(tool, async (args) =>
        toolValueMapFromJson(await executor(toolValueMapToJson(args)))
      );
    },

    /** Stop offering a tool to the model. */
    async unregister(name: string): Promise<void> {
      await unregisterTool(name);
    },

    /** Every tool currently registered. */
    list(): Promise<ToolDefinition[]> {
      return getRegisteredTools();
    },

    /** Drop every registered tool. */
    clear(): Promise<void> {
      return clearTools();
    },
  },
};
