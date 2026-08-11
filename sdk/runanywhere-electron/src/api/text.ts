// text.ts — the `llm` and `vlm` namespaces plus the tool registry.
//
// LLM generation is proto-native: commons owns the chat template, the thinking
// split, the token accounting, and the JSON extraction, so this file shapes a
// request and reads a result rather than reconstructing any of it.
//
// Tool calling is proto-native too. Commons runs the whole loop — prompt
// dialect, parsing, validation, execution order, follow-up turn, cancellation —
// and the only part left here is the registry of executor functions, which
// cannot live anywhere but the host language.

import { SDKException } from '../errors';
import type { RaBackend } from './backend';
import type { SdkEventHub } from './hub';
import { bridgeStream } from './iter';
import {
  LlmAbi,
  LLMStreamEventKind,
  toPublicFinishReason,
  toPublicMetrics,
  toProtoMessages,
  toProtoOptions,
} from './llm-abi';
import type { LLMGenerationResult } from './llm-abi';
import { ModelAbi } from './model-abi';
import {
  VlmAbi,
  VLMGenerationRequest,
  VLMStreamEventKind,
  materializeImage,
  toPublicVlmFinishReason,
  toPublicVlmMetrics,
} from './vlm-abi';
import {
  ToolAbi,
  ToolCallingOptions,
  ToolCallingSessionCreateRequest,
  toHistoryTurns,
  toProtoTool,
  toProtoToolChoice,
  toPublicCalls,
} from './tool-abi';
import type { ToolRun } from './tool-abi';
import { LLM_DEFAULTS } from './options';
import type { LlmOptions } from './options';
import type { ChatMessage as ProtoChatMessage } from '@runanywhere/proto-ts/chat';
import { MessageRole } from '@runanywhere/proto-ts/chat';
import { ModelCategory as ProtoModelCategory } from '@runanywhere/proto-ts/model_types';
import { FinishReason, ReasoningMode, TokenKind, newRequestId } from './types';
import type {
  ChatMessage,
  GenerationEvent,
  GenerationResult,
  ImageInput,
  JsonSchema,
  StructuredResult,
  ToolCall,
  ToolDefinition,
  ToolExecutor,
} from './types';

// ---------------------------------------------------------------------------
// Tool registry
// ---------------------------------------------------------------------------

/** The `llm.tools` registry. */
export interface ToolsNamespace {
  /** Register a tool and the function that runs it. */
  register(tool: ToolDefinition, executor: ToolExecutor): void;
  /** Forget a registered tool. */
  unregister(name: string): void;
  /** Every registered tool, in registration order. */
  list(): ToolDefinition[];
  /** Forget every registered tool. */
  clear(): void;
}

interface RegisteredTool {
  definition: ToolDefinition;
  executor: ToolExecutor;
}

// ---------------------------------------------------------------------------
// Shared generation plumbing
// ---------------------------------------------------------------------------

/** What both namespaces need from the facade. */
export interface TextDeps {
  backend: RaBackend;
  hub: SdkEventHub;
  requireReady(): void;
}

/** What the `llm` namespace needs on top of {@link TextDeps}. */
export interface LlmDeps extends TextDeps {
  /**
   * Bring a language model into residency. Supplied by the facade because the
   * lifecycle load belongs to the `models` namespace, which owns downloading,
   * registry rows, and the residency policy.
   */
  loadModel(id: string): Promise<void>;
}

// ---------------------------------------------------------------------------
// llm
// ---------------------------------------------------------------------------

/** Text generation, structured output, and tool calling. */
export interface LlmNamespace {
  /**
   * Generate a completion for a prompt or a conversation.
   *
   * @throws SDKException when no model is loaded and `options.model` is absent.
   * @example
   * const r = await RunAnywhere.llm.generate('Explain on-device AI.', { model: 'qwen2.5-0.5b' });
   * console.log(r.text, r.tokensPerSecond);
   */
  generate(
    input: string | ChatMessage[],
    options?: LlmOptions
  ): Promise<GenerationResult>;
  /**
   * Stream a completion as started / token / toolCall / completed events.
   *
   * @throws SDKException on preflight failure; in-flight failures throw into the loop.
   * @example
   * for await (const e of RunAnywhere.llm.generateStream('Write a haiku.'))
   *   if (e.type === 'token') process.stdout.write(e.text);
   */
  generateStream(
    input: string | ChatMessage[],
    options?: LlmOptions
  ): AsyncIterableIterator<GenerationEvent>;
  /** Generate JSON that satisfies `schema`, constraining decoding so it always parses. */
  generateStructured<T = unknown>(
    prompt: string,
    schema: JsonSchema,
    options?: LlmOptions
  ): Promise<StructuredResult<T>>;
  readonly tools: ToolsNamespace;
}

/** Build the `llm` namespace over the commons LLM proto ABI. */
export function createLlmNamespace(deps: LlmDeps): LlmNamespace {
  const llm = new LlmAbi(deps.backend);
  const toolLoop = new ToolAbi(deps.backend);
  const models = new ModelAbi(deps.backend);
  const registry = new Map<string, RegisteredTool>();

  const tools: ToolsNamespace = {
    register(tool, executor) {
      if (!tool || !tool.name) {
        throw SDKException.validationFailed({
          fieldPath: 'tool.name',
          message: 'a tool needs a name',
        });
      }
      registry.set(tool.name, { definition: tool, executor });
    },
    unregister(name) {
      registry.delete(name);
    },
    list() {
      return [...registry.values()].map((t) => ({ ...t.definition }));
    },
    clear() {
      registry.clear();
    },
  };

  const activeTools = (options: LlmOptions): RegisteredTool[] => {
    if (options.tools && options.tools.length) {
      // Request-scoped tools reuse a registered executor when the names match, so
      // a caller can narrow the tool set without re-supplying the functions.
      return options.tools.map((definition) => ({
        definition,
        executor:
          registry.get(definition.name)?.executor ??
          (() => {
            throw SDKException.validationFailed({
              fieldPath: `tools.${definition.name}`,
              message: `no executor registered for tool '${definition.name}'`,
            });
          }),
      }));
    }
    return [...registry.values()];
  };

  /**
   * Run one call commons decided on. Validation already happened there unless
   * the caller turned it off, so an unknown name here means the executor set
   * is the authority and it does not know this tool.
   */
  async function invokeTool(
    available: RegisteredTool[],
    name: string,
    args: Record<string, unknown>
  ): Promise<Record<string, unknown>> {
    const tool = available.find((t) => t.definition.name === name);
    if (!tool) throw SDKException.validationFailed({
      fieldPath: `tools.${name}`,
      message: `no executor registered for tool '${name}'`,
    });
    return tool.executor(args);
  }

  /**
   * The model this request runs against. Commons owns residency, so "what is
   * loaded" is a lifecycle question rather than a slot lookup.
   */
  async function resolveModel(requested: string | undefined): Promise<string> {
    const current = await models.current({ includeModelMetadata: false });
    if (!requested) {
      if (current.found && current.modelId) return current.modelId;
      throw SDKException.validationFailed({
        fieldPath: 'options.model',
        message: 'no language model is loaded — pass options.model or call models.load() first',
      });
    }
    if (current.found && current.modelId === requested) return requested;
    await deps.loadModel(requested);
    return requested;
  }

  /**
   * The run loop takes the turn being answered as `prompt` and everything
   * before it as history, so a conversation splits at its last user turn.
   */
  function splitForToolLoop(messages: ProtoChatMessage[]): {
    prompt: string;
    history: string[];
  } {
    let turn = messages.length - 1;
    for (let i = messages.length - 1; i >= 0; i--) {
      if (messages[i].role === MessageRole.MESSAGE_ROLE_USER) {
        turn = i;
        break;
      }
    }
    return {
      prompt: messages[turn]?.content ?? '',
      history: messages.slice(0, Math.max(0, turn)).map((m) => m.content),
    };
  }

  /** The tool policy for one request, as one `ToolCallingOptions`. */
  function toolOptionsFor(
    options: LlmOptions,
    available: RegisteredTool[]
  ): ToolCallingOptions {
    const choice = toProtoToolChoice(options.toolChoice ?? LLM_DEFAULTS.toolChoice);
    if (choice.forcedToolName && !available.some((t) => t.definition.name === choice.forcedToolName)) {
      throw SDKException.validationFailed({
        fieldPath: 'options.toolChoice',
        message: `forced tool '${choice.forcedToolName}' is not registered`,
      });
    }
    return ToolCallingOptions.fromPartial({
      tools: available.map((t) => toProtoTool(t.definition)),
      autoExecute: true,
      systemPrompt: options.systemPrompt,
      toolChoice: choice.mode,
      forcedToolName: choice.forcedToolName,
      maxToolCalls: options.maxToolCalls,
      parallelToolCalls: options.parallelToolCalls ?? false,
      validateCalls: options.validateCalls,
      // Left at the proto default (false), matching Swift: after a call is
      // executed the next turn is synthesis. Keeping tools live lets a small
      // model call the same tool until it trips max_tool_calls, which commons
      // reports as a failed run rather than an answer.
      topP: options.topP,
      disableThinking: options.reasoning?.mode === ReasoningMode.OFF,
    });
  }

  /**
   * Start the loop in commons. `onRun` hands the caller the cancel handle
   * before the first generation, which is what lets a streaming caller stop a
   * loop that is several tool rounds deep.
   */
  async function generateWithTools(
    input: string | ChatMessage[],
    options: LlmOptions,
    available: RegisteredTool[],
    requestId: string,
    onToolCall?: (call: ToolCall) => void,
    onRun?: (run: ToolRun) => void
  ): Promise<GenerationResult> {
    const model = await resolveModel(options.model);
    const { prompt, history } = splitForToolLoop(toProtoMessages(input));
    const run = toolLoop.start(
      ToolCallingSessionCreateRequest.fromPartial({
        prompt,
        history: toHistoryTurns(history),
        options: toolOptionsFor(options, available),
      }),
      (name, args) => invokeTool(available, name, args),
      onToolCall
    );
    onRun?.(run);
    const result = await run.result;
    const calls = toPublicCalls(result);
    return {
      text: result.text,
      thinkingText: result.thinkingContent || undefined,
      toolCalls: calls,
      finishReason: toPublicFinishReason(result.finishReason),
      inputTokens: result.usage?.inputTokens ?? 0,
      outputTokens: result.usage?.outputTokens ?? 0,
      timeToFirstTokenMs: result.usage?.ttftMs ?? 0,
      tokensPerSecond: result.usage?.decodeTokensPerSecond ?? 0,
      requestId,
      model,
    };
  }

  /** One plain generation, as commons reported it. */
  async function generateRaw(
    input: string | ChatMessage[],
    options: LlmOptions
  ): Promise<{ result: LLMGenerationResult; requestId: string; model: string }> {
    const model = await resolveModel(options.model);
    const requestId = newRequestId();
    const result = await llm.generate({
      requestId,
      modelId: model,
      conversationId: '',
      options: toProtoOptions(options),
      messages: toProtoMessages(input),
    });
    return { result, requestId, model };
  }

  function toGenerationResult(
    result: LLMGenerationResult,
    requestId: string,
    model: string
  ): GenerationResult {
    return {
      text: result.text,
      thinkingText: result.thinkingContent || undefined,
      toolCalls: [],
      finishReason: toPublicFinishReason(result.finishReason),
      ...toPublicMetrics(result, requestId, model),
    };
  }

  /** Whether this request should go through the commons tool loop at all. */
  function toolsFor(options: LlmOptions): RegisteredTool[] {
    if ((options.toolChoice ?? LLM_DEFAULTS.toolChoice) === 'NONE') return [];
    return activeTools(options);
  }

  async function generate(
    input: string | ChatMessage[],
    options: LlmOptions = {}
  ): Promise<GenerationResult> {
    deps.requireReady();
    const available = toolsFor(options);
    if (available.length) {
      return generateWithTools(input, options, available, newRequestId());
    }
    const raw = await generateRaw(input, options);
    return toGenerationResult(raw.result, raw.requestId, raw.model);
  }

  /**
   * A tool-enabled turn does not stream tokens. Commons runs its generations
   * with `streaming_enabled = RAC_FALSE` inside the run loop
   * (tool_calling_generation_internal.h), so the honest events are the tool
   * calls as they execute and then one completed result. Plain turns stream
   * token by token as before.
   */
  function generateStream(
    input: string | ChatMessage[],
    options: LlmOptions = {}
  ): AsyncIterableIterator<GenerationEvent> {
    deps.requireReady();
    const requestId = newRequestId();
    const available = toolsFor(options);
    if (available.length) {
      let run: ToolRun | null = null;
      return bridgeStream<GenerationEvent>(
        async (sink) => {
          sink.push({ type: 'started', requestId });
          const result = await generateWithTools(
            input,
            options,
            available,
            requestId,
            (call) => sink.push({ type: 'toolCall', toolCall: call }),
            (started) => {
              run = started;
            }
          );
          sink.push({ type: 'completed', result });
        },
        () => run?.cancel() ?? Promise.resolve()
      );
    }
    return bridgeStream<GenerationEvent>(
      async (sink) => {
        const model = await resolveModel(options.model);
        sink.push({ type: 'started', requestId });
        for await (const event of llm.generateStream({
          requestId,
          modelId: model,
          conversationId: '',
          options: toProtoOptions(options),
          messages: toProtoMessages(input),
        })) {
          switch (event.eventKind) {
            case LLMStreamEventKind.LLM_STREAM_EVENT_KIND_TOKEN:
              sink.push({ type: 'token', text: event.token, kind: TokenKind.TEXT });
              break;
            // Commons emits these only when reasoning.includeInOutput is set, so
            // there is no second gate here.
            case LLMStreamEventKind.LLM_STREAM_EVENT_KIND_THINKING:
              sink.push({ type: 'token', text: event.token, kind: TokenKind.THOUGHT });
              break;
            case LLMStreamEventKind.LLM_STREAM_EVENT_KIND_COMPLETED:
              if (event.result) {
                sink.push({
                  type: 'completed',
                  result: toGenerationResult(event.result, requestId, model),
                });
              }
              break;
            case LLMStreamEventKind.LLM_STREAM_EVENT_KIND_ERROR:
              if (event.error) throw SDKException.fromProto(event.error);
              break;
            default:
              break;
          }
        }
      },
      () => llm.cancel()
    );
  }

  async function generateStructured<T = unknown>(
    prompt: string,
    schema: JsonSchema,
    options: LlmOptions = {}
  ): Promise<StructuredResult<T>> {
    deps.requireReady();
    const raw = await generateRaw(prompt, {
      ...options,
      structuredOutput: { schema, strict: options.structuredOutput?.strict ?? true },
    });
    // Commons extracts the document during generation; the parse call is the
    // fallback for a backend that answered without populating json_output.
    let json = raw.result.jsonOutput ?? '';
    let valid = raw.result.structuredOutputValidation?.isValid ?? false;
    if (!json) {
      const parsed = await llm.parseStructured({
        requestId: raw.requestId,
        text: raw.result.text,
        options: { schema: JSON.stringify(schema) },
        metadata: {},
      });
      json = parsed.json;
      valid = parsed.validation?.isValid ?? false;
    }
    let value: T;
    try {
      value = JSON.parse(json) as T;
    } catch {
      value = undefined as unknown as T;
      valid = false;
    }
    return {
      value,
      raw: json,
      valid,
      finishReason: toPublicFinishReason(raw.result.finishReason),
      ...toPublicMetrics(raw.result, raw.requestId, raw.model),
    };
  }

  return { generate, generateStream, generateStructured, tools };
}

// ---------------------------------------------------------------------------
// vlm
// ---------------------------------------------------------------------------

/** Vision-language generation over an image and a prompt. */
export interface VlmNamespace {
  /**
   * Answer `prompt` about `image`.
   *
   * @throws SDKException when no vision model is loaded and `options.model` is absent.
   * @example
   * const r = await RunAnywhere.vlm.generate(image.file('/tmp/cat.jpg'), 'What is this?');
   * console.log(r.text);
   */
  generate(
    input: ImageInput,
    prompt: string,
    options?: LlmOptions
  ): Promise<GenerationResult>;
  /** Stream the answer as started / token / completed events. */
  generateStream(
    input: ImageInput,
    prompt: string,
    options?: LlmOptions
  ): AsyncIterableIterator<GenerationEvent>;
}

/** What the `vlm` namespace needs on top of {@link TextDeps}. */
export interface VlmDeps extends TextDeps {
  /** Bring a vision model into residency; owned by the `models` namespace. */
  loadModel(id: string): Promise<void>;
}

/** Build the `vlm` namespace over the commons VLM proto ABI. */
export function createVlmNamespace(deps: VlmDeps): VlmNamespace {
  const vlm = new VlmAbi(deps.backend);
  const models = new ModelAbi(deps.backend);

  /** The vision model this request runs against, from the lifecycle store. */
  async function resolveModel(requested: string | undefined): Promise<string> {
    const current = await models.current({
      category: ProtoModelCategory.MODEL_CATEGORY_VISION,
      includeModelMetadata: false,
    });
    if (!requested) {
      if (current.found && current.modelId) return current.modelId;
      throw SDKException.validationFailed({
        fieldPath: 'options.model',
        message: 'no vision model is loaded — pass options.model or call models.load() first',
      });
    }
    if (current.found && current.modelId === requested) return requested;
    await deps.loadModel(requested);
    return requested;
  }

  function requestFor(
    input: ImageInput,
    prompt: string,
    options: LlmOptions,
    requestId: string,
    model: string
  ): { request: VLMGenerationRequest; release(): void } {
    const materialized = materializeImage(input);
    return {
      release: materialized.release,
      request: VLMGenerationRequest.fromPartial({
        requestId,
        modelId: model,
        images: [materialized.image],
        prompt,
        options: toProtoOptions(options),
      }),
    };
  }

  async function generate(
    input: ImageInput,
    prompt: string,
    options: LlmOptions = {}
  ): Promise<GenerationResult> {
    deps.requireReady();
    const model = await resolveModel(options.model);
    const requestId = newRequestId();
    const { request, release } = requestFor(input, prompt, options, requestId, model);
    try {
      const result = await vlm.generate(request);
      return {
        text: result.text,
        toolCalls: [],
        finishReason: FinishReason[toPublicVlmFinishReason(result.finishReason)],
        ...toPublicVlmMetrics(result, requestId, model),
      };
    } finally {
      release();
    }
  }

  function generateStream(
    input: ImageInput,
    prompt: string,
    options: LlmOptions = {}
  ): AsyncIterableIterator<GenerationEvent> {
    deps.requireReady();
    const requestId = newRequestId();
    return bridgeStream<GenerationEvent>(
      async (sink) => {
        const model = await resolveModel(options.model);
        const { request, release } = requestFor(input, prompt, options, requestId, model);
        try {
          for await (const event of vlm.generateStream(request)) {
          switch (event.kind) {
            case VLMStreamEventKind.VLM_STREAM_EVENT_KIND_STARTED:
              sink.push({ type: 'started', requestId });
              break;
            case VLMStreamEventKind.VLM_STREAM_EVENT_KIND_TOKEN:
              sink.push({ type: 'token', text: event.token, kind: TokenKind.TEXT });
              break;
            case VLMStreamEventKind.VLM_STREAM_EVENT_KIND_COMPLETED:
              if (event.result) {
                sink.push({
                  type: 'completed',
                  result: {
                    text: event.result.text,
                    toolCalls: [],
                    finishReason: FinishReason[toPublicVlmFinishReason(event.result.finishReason)],
                    ...toPublicVlmMetrics(event.result, requestId, model),
                  },
                });
              }
              break;
            case VLMStreamEventKind.VLM_STREAM_EVENT_KIND_ERROR:
              if (event.error) throw SDKException.fromProto(event.error);
              break;
            // IMAGE_ENCODED marks the encode/decode boundary. There is no
            // public event for it yet, and inventing one here would put a
            // vision-only shape into the shared GenerationEvent union.
              default:
                break;
            }
          }
        } finally {
          release();
        }
      },
      () => vlm.cancel()
    );
  }

  return { generate, generateStream };
}
