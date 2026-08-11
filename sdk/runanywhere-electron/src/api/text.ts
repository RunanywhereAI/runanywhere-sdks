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

import { ErrorCode, SDKException, asSDKException } from '../errors';
import type { RaBackend } from './backend';
import type { SdkEventHub } from './hub';
import { bridgeStream } from './iter';
import type { StreamSink } from './iter';
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
  toPublicToolCall,
} from './tool-abi';
import type { ToolRun } from './tool-abi';
import { LLM_DEFAULTS } from './options';
import type { LlmOptions } from './options';
import type { ChatMessage as ProtoChatMessage } from '@runanywhere/proto-ts/chat';
import { MessageRole } from '@runanywhere/proto-ts/chat';
import { ModelCategory as ProtoModelCategory } from '@runanywhere/proto-ts/model_types';
import type { TokenUsage } from '@runanywhere/proto-ts/token_usage';
import { FinishReason, ReasoningMode, newRequestId, toProtoError } from './types';
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

/**
 * Writes one generation's events onto a sink in the shared grammar, and is the
 * only thing in this file that decides what a terminal event is.
 *
 * Both `llm.generateStream` and `vlm.generateStream` drive it, which is what
 * keeps their two native streams — `LLMStreamEvent` and `VLMStreamEvent`, with
 * different discriminators and different finish-reason spellings — answering to
 * one public contract. It exists as a class rather than a helper per arm because
 * the invariants are stateful: `started` is announced exactly once, `sequence`
 * is monotonic across every delta, the accumulated text is what a `failed` or
 * `cancelled` arm reports as `partial`, and `finish()` refuses to emit a second
 * terminal event after the first.
 */
class GenerationEmitter {
  private readonly textItemId: string;
  private readonly reasoningItemId: string;
  private sequence = 0;
  private toolCallIndex = 0;
  private started = false;
  private terminal = false;
  private text = '';
  private thinking = '';

  constructor(
    private readonly sink: StreamSink<GenerationEvent>,
    private readonly requestId: string
  ) {
    // Derived from the request id rather than random, so the same generation's
    // items are the same across a log, a replay, and a renderer.
    this.textItemId = `${requestId}:text`;
    this.reasoningItemId = `${requestId}:reasoning`;
  }

  /** Whether a terminal event has already been emitted. */
  get finished(): boolean {
    return this.terminal;
  }

  private next(): number {
    this.sequence += 1;
    return this.sequence;
  }

  /** Announce the generation. Idempotent — later calls are no-ops. */
  start(): void {
    if (this.started) return;
    this.started = true;
    this.sink.push({ type: 'started', requestId: this.requestId });
  }

  /** One delta of answer text. */
  textDelta(text: string): void {
    if (!text) return;
    this.start();
    this.text += text;
    this.sink.push({
      type: 'textDelta',
      requestId: this.requestId,
      sequence: this.next(),
      itemId: this.textItemId,
      index: 0,
      text,
    });
  }

  /** One delta of model reasoning. */
  reasoningDelta(text: string): void {
    if (!text) return;
    this.start();
    this.thinking += text;
    this.sink.push({
      type: 'reasoningDelta',
      requestId: this.requestId,
      sequence: this.next(),
      itemId: this.reasoningItemId,
      index: 0,
      text,
    });
  }

  /**
   * One tool call, as `toolCallAdded` followed by `toolArgumentsDone`.
   *
   * Both arms come from the same call because commons parses a call only once
   * its arguments are whole — there is no partial-arguments producer to feed a
   * `toolArgumentsDelta`, so emitting the done arm is honest and emitting a
   * synthetic delta first would not be.
   */
  toolCall(call: ToolCall): void {
    this.start();
    const index = this.toolCallIndex;
    this.toolCallIndex += 1;
    const itemId = call.id || `${this.requestId}:tool-${index}`;
    this.sink.push({
      type: 'toolCallAdded',
      requestId: this.requestId,
      sequence: this.next(),
      itemId,
      index,
      call,
    });
    this.sink.push({
      type: 'toolArgumentsDone',
      requestId: this.requestId,
      sequence: this.next(),
      itemId,
      arguments: JSON.stringify(call.arguments ?? {}),
    });
  }

  /** What had been generated so far, for a `failed` or `cancelled` arm. */
  private partial(): Partial<GenerationResult> | undefined {
    if (!this.text && !this.thinking) return undefined;
    return { text: this.text, thinkingText: this.thinking || undefined };
  }

  /**
   * Close the generation on `result`, as `usage` then `completed` — or as
   * `cancelled` when commons reports the generation was stopped rather than
   * finished. Without that branch a cancel is indistinguishable from a normal
   * end and no caller can offer a retry.
   */
  complete(result: GenerationResult): void {
    if (this.terminal) return;
    this.start();
    if (result.finishReason === FinishReason.CANCELLED) {
      this.terminal = true;
      this.sink.push({
        type: 'cancelled',
        requestId: this.requestId,
        partial: { ...this.partial(), ...result },
      });
      return;
    }
    this.sink.push({
      type: 'usage',
      requestId: this.requestId,
      sequence: this.next(),
      usage: usageOf(result),
    });
    this.terminal = true;
    this.sink.push({ type: 'completed', requestId: this.requestId, result });
  }

  /**
   * Close the generation on a failure, or on `cancelled` when the failure IS a
   * cancellation — commons reports a stopped tool loop as `RAC_ERROR_CANCELLED`
   * and a stopped session stream as an ERROR event carrying the same code.
   */
  fail(error: unknown): void {
    if (this.terminal) return;
    this.start();
    this.terminal = true;
    const failure = asSDKException(error);
    if (failure.code === ErrorCode.ERROR_CODE_CANCELLED) {
      this.sink.push({ type: 'cancelled', requestId: this.requestId, partial: this.partial() });
      return;
    }
    this.sink.push({
      type: 'failed',
      requestId: this.requestId,
      partial: this.partial(),
      error: toProtoError(failure),
    });
  }

  /**
   * Close a stream whose producer ended without reporting a terminal event.
   * The grammar has no silent finish, so this is a `failed` rather than a
   * fabricated `completed` for output nothing confirmed was complete.
   */
  endWithoutTerminal(): void {
    if (this.terminal) return;
    this.fail(
      SDKException.generationFailed(
        this.started
          ? 'the generation stream ended before a terminal event'
          : 'the generation ended before producing any output'
      )
    );
  }
}

/**
 * The token accounting for a finished generation, as the generated
 * `TokenUsage`. Built from the public result rather than re-read from the proto
 * so the `usage` event and `completed.result` can never disagree; `prefillMs`
 * stays 0 because the public result does not carry the prefill split.
 */
function usageOf(result: GenerationResult): TokenUsage {
  return {
    inputTokens: result.inputTokens,
    outputTokens: result.outputTokens,
    totalTokens: result.inputTokens + result.outputTokens,
    decodeTokensPerSecond: result.tokensPerSecond,
    prefillMs: 0,
    ttftMs: result.timeToFirstTokenMs,
  };
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
   * Stream a completion as `started`, `textDelta`/`reasoningDelta`,
   * `toolCallAdded`/`toolArgumentsDone`, `usage`, and exactly one terminal
   * `completed`/`failed`/`cancelled`. Never fabricates a successful `completed`.
   *
   * @throws SDKException on preflight failure; an in-flight failure arrives as
   *   a `failed` event so a caller can render a retry.
   * @example
   * for await (const e of RunAnywhere.llm.generateStream('Write a haiku.'))
   *   if (e.type === 'textDelta') process.stdout.write(e.text);
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
      finishReason: calls.length ? FinishReason.TOOL_CALLS : FinishReason.STOP,
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
   *
   * Both shapes terminate through the same {@link GenerationEmitter}, so a
   * failure or a cancel is a `failed`/`cancelled` event on the stream rather
   * than an exception thrown out of `next()`. That is the whole point of the
   * terminal arms: a caller that has already rendered half an answer needs to
   * know which way it ended without a `try` around its render loop.
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
          const events = new GenerationEmitter(sink, requestId);
          events.start();
          try {
            const result = await generateWithTools(
              input,
              options,
              available,
              requestId,
              (call) => events.toolCall(call),
              (started) => {
                run = started;
              }
            );
            events.complete(result);
          } catch (e) {
            events.fail(e);
          }
        },
        () => run?.cancel() ?? Promise.resolve()
      );
    }
    return bridgeStream<GenerationEvent>(
      async (sink) => {
        const events = new GenerationEmitter(sink, requestId);
        try {
          const model = await resolveModel(options.model);
          events.start();
          for await (const event of llm.generateStream({
            requestId,
            modelId: model,
            conversationId: '',
            options: toProtoOptions(options),
            messages: toProtoMessages(input),
          })) {
            switch (event.eventKind) {
              case LLMStreamEventKind.LLM_STREAM_EVENT_KIND_TOKEN:
                events.textDelta(event.token);
                break;
              // Commons emits these only when reasoning.includeInOutput is set, so
              // there is no second gate here.
              case LLMStreamEventKind.LLM_STREAM_EVENT_KIND_THINKING:
                events.reasoningDelta(event.token);
                break;
              // Commons parses a call out of the streamed text and republishes it
              // on this arm (llm_module.cpp's dispatch_terminal_once), so a plain
              // turn that produced one still reports it structurally.
              case LLMStreamEventKind.LLM_STREAM_EVENT_KIND_TOOL_CALL:
                if (event.toolCall) events.toolCall(toPublicToolCall(event.toolCall));
                break;
              case LLMStreamEventKind.LLM_STREAM_EVENT_KIND_COMPLETED:
                // `finishReason` on the terminal result is what tells a normal
                // end from a cancel: commons runs both through
                // dispatch_terminal_once and only the reason differs.
                if (event.result) {
                  events.complete(toGenerationResult(event.result, requestId, model));
                }
                break;
              case LLMStreamEventKind.LLM_STREAM_EVENT_KIND_ERROR:
                if (event.error) events.fail(SDKException.fromProto(event.error));
                break;
              default:
                break;
            }
            if (events.finished) break;
          }
          events.endWithoutTerminal();
        } catch (e) {
          events.fail(e);
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
  /**
   * Stream the answer as `started`, `textDelta`, `usage`, and exactly one
   * terminal `completed`/`failed`/`cancelled` — the same grammar
   * {@link LlmNamespace.generateStream} uses.
   */
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
        const events = new GenerationEmitter(sink, requestId);
        try {
          const model = await resolveModel(options.model);
          const { request, release } = requestFor(input, prompt, options, requestId, model);
          try {
            for await (const event of vlm.generateStream(request)) {
              switch (event.kind) {
                case VLMStreamEventKind.VLM_STREAM_EVENT_KIND_STARTED:
                  events.start();
                  break;
                case VLMStreamEventKind.VLM_STREAM_EVENT_KIND_TOKEN:
                  events.textDelta(event.token);
                  break;
                case VLMStreamEventKind.VLM_STREAM_EVENT_KIND_COMPLETED:
                  if (event.result) {
                    events.complete({
                      text: event.result.text,
                      toolCalls: [],
                      finishReason:
                        FinishReason[toPublicVlmFinishReason(event.result.finishReason)],
                      ...toPublicVlmMetrics(event.result, requestId, model),
                    });
                  }
                  break;
                case VLMStreamEventKind.VLM_STREAM_EVENT_KIND_ERROR:
                  if (event.error) events.fail(SDKException.fromProto(event.error));
                  break;
                // IMAGE_ENCODED marks the encode/decode boundary. There is no
                // public event for it yet, and inventing one here would put a
                // vision-only shape into the shared GenerationEvent union.
                default:
                  break;
              }
              if (events.finished) break;
            }
          } finally {
            release();
          }
          events.endWithoutTerminal();
        } catch (e) {
          events.fail(e);
        }
      },
      () => vlm.cancel()
    );
  }

  return { generate, generateStream };
}
