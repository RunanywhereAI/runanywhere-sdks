// text.ts — the `llm` and `vlm` namespaces plus the tool registry.
//
// Tool calling runs here rather than in commons: the C tool-calling ABI is
// proto-only and the Electron addon does not bind it, so the loop is built from
// grammar-constrained selection (real decoding constraints, not prompt-and-hope)
// over `rac_llm_options_t.grammar`.

import { SDKException } from '../errors';
import { jsonSchemaToGrammar } from '../grammar';
import type { JsonSchema } from '../grammar';
import { splitThinking } from '../thinking';
import type { LoadSlot, NativeStreamResult, RaBackend } from './backend';
import type { SdkEventHub } from './hub';
import { bridgeStream } from './iter';
import { LLM_DEFAULTS, toNativeGenerateOptions } from './options';
import type { LlmOptions } from './options';
import {
  FinishReason,
  ModelCategory,
  TokenKind,
  newRequestId,
  requireOneOf,
} from './types';
import type {
  ChatMessage,
  GenerationEvent,
  GenerationResult,
  ImageInput,
  StructuredResult,
  ToolCall,
  ToolDefinition,
  ToolExecutor,
} from './types';

// ---------------------------------------------------------------------------
// Prompt shaping
// ---------------------------------------------------------------------------

/** A prompt plus the history and system turn the engine needs alongside it. */
interface ShapedPrompt {
  prompt: string;
  /** Alternating user/assistant turns, oldest first. */
  history: string[];
  systemPrompt?: string;
}

// rac_llm_options_t.history is a strictly alternating user/assistant array that
// excludes the system prompt and the current prompt, so tool turns are folded into
// the user turn they answer.
function shapePrompt(input: string | ChatMessage[]): ShapedPrompt {
  if (typeof input === 'string') return { prompt: input, history: [] };
  if (!input.length) {
    throw SDKException.validationFailed({
      fieldPath: 'messages',
      message: 'at least one message is required',
    });
  }
  const system = input.filter((m) => m.role === 'system').map((m) => m.content).join('\n\n');
  const turns: Array<{ role: 'user' | 'assistant'; content: string }> = [];
  for (const m of input) {
    if (m.role === 'system') continue;
    const role = m.role === 'assistant' ? 'assistant' : 'user';
    const content = m.role === 'tool' ? `Tool result: ${m.content}` : m.content;
    const last = turns[turns.length - 1];
    if (last && last.role === role) last.content += `\n${content}`;
    else turns.push({ role, content });
  }
  if (!turns.length) {
    throw SDKException.validationFailed({
      fieldPath: 'messages',
      message: 'messages must contain at least one non-system turn',
    });
  }
  // The final turn is the live prompt; whatever precedes it is history, trimmed to
  // start on a user turn so the alternation the engine expects holds.
  const current = turns.pop() as { role: 'user' | 'assistant'; content: string };
  while (turns.length && turns[0].role !== 'user') turns.shift();
  return {
    prompt: current.content,
    history: turns.map((t) => t.content),
    systemPrompt: system || undefined,
  };
}

// ---------------------------------------------------------------------------
// Streamed thinking classification
// ---------------------------------------------------------------------------

const THINK_TAGS = [
  { open: '<think>', close: '</think>' },
  { open: '<thinking>', close: '</thinking>' },
];
const LONGEST_TAG = Math.max(...THINK_TAGS.flatMap((t) => [t.open.length, t.close.length]));

/**
 * Classifies streamed text as answer or thought, tolerating a tag split across
 * token boundaries by holding back the last few characters until they can no
 * longer be the prefix of a tag.
 */
class ThinkingSplitter {
  private pending = '';
  private closeTag: string | null = null;

  /** Classify one incoming token, returning the parts that are now unambiguous. */
  push(token: string): Array<{ text: string; kind: typeof TokenKind.TEXT | typeof TokenKind.THOUGHT }> {
    this.pending += token;
    return this.drain(false);
  }

  /** Flush whatever is held back once the stream has ended. */
  flush(): Array<{ text: string; kind: typeof TokenKind.TEXT | typeof TokenKind.THOUGHT }> {
    return this.drain(true);
  }

  private drain(
    final: boolean
  ): Array<{ text: string; kind: typeof TokenKind.TEXT | typeof TokenKind.THOUGHT }> {
    const out: Array<{ text: string; kind: typeof TokenKind.TEXT | typeof TokenKind.THOUGHT }> = [];
    for (;;) {
      if (this.closeTag) {
        const at = this.pending.indexOf(this.closeTag);
        if (at >= 0) {
          if (at > 0) out.push({ text: this.pending.slice(0, at), kind: TokenKind.THOUGHT });
          this.pending = this.pending.slice(at + this.closeTag.length);
          this.closeTag = null;
          continue;
        }
        const safe = this.safeLength(final);
        if (safe > 0) {
          out.push({ text: this.pending.slice(0, safe), kind: TokenKind.THOUGHT });
          this.pending = this.pending.slice(safe);
        }
        return out;
      }
      let best = -1;
      let bestTag: (typeof THINK_TAGS)[number] | null = null;
      for (const tag of THINK_TAGS) {
        const at = this.pending.indexOf(tag.open);
        if (at >= 0 && (best < 0 || at < best)) {
          best = at;
          bestTag = tag;
        }
      }
      if (best >= 0 && bestTag) {
        if (best > 0) out.push({ text: this.pending.slice(0, best), kind: TokenKind.TEXT });
        this.pending = this.pending.slice(best + bestTag.open.length);
        this.closeTag = bestTag.close;
        continue;
      }
      const safe = this.safeLength(final);
      if (safe > 0) {
        out.push({ text: this.pending.slice(0, safe), kind: TokenKind.TEXT });
        this.pending = this.pending.slice(safe);
      }
      return out;
    }
  }

  // Everything except a trailing run that could still grow into a tag.
  private safeLength(final: boolean): number {
    if (final) return this.pending.length;
    return Math.max(0, this.pending.length - (LONGEST_TAG - 1));
  }
}

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
}

interface RegisteredTool {
  definition: ToolDefinition;
  executor: ToolExecutor;
}

const NO_TOOL = '__none';
// Enough room for a tool call's JSON object regardless of the answer budget.
const TOOL_SELECTION_TOKENS = 256;

function toolPickerGrammar(tools: ToolDefinition[], allowNone: boolean): string {
  const branches: JsonSchema[] = tools.map((t) => ({
    type: 'object',
    properties: { name: { const: t.name }, arguments: t.parameters as JsonSchema },
    required: ['name', 'arguments'],
  }));
  if (allowNone) {
    branches.push({
      type: 'object',
      properties: { name: { const: NO_TOOL }, arguments: { type: 'object', properties: {} } },
      required: ['name'],
    });
  }
  return jsonSchemaToGrammar(branches.length === 1 ? branches[0] : { anyOf: branches });
}

function toolPickerPrompt(prompt: string, tools: ToolDefinition[], allowNone: boolean): string {
  const listed = tools
    .map((t) => `- ${t.name}${t.description ? ': ' + t.description : ''}`)
    .join('\n');
  const escape = allowNone
    ? `\nIf no tool is needed, reply with {"name": "${NO_TOOL}"}.`
    : '';
  return `${prompt}\n\nAvailable tools:\n${listed}${escape}\n\nReply with a single JSON tool call.`;
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

/** Load the model a request names, or use whatever already occupies the slot. */
async function resolveModelFor(
  deps: TextDeps,
  slot: LoadSlot,
  category: ModelCategory,
  requested: string | undefined
): Promise<string> {
  const current = await deps.backend.loaded(slot);
  if (!requested) {
    if (current) return current.id;
    throw SDKException.validationFailed({
      fieldPath: 'options.model',
      message: `no ${slot} model is loaded — pass options.model or call models.load() first`,
    });
  }
  if (current && current.id === requested) return current.id;
  const loaded = await deps.backend.ensure(slot, requested);
  deps.hub.emit({ type: 'modelLoaded', id: loaded.id, category });
  return loaded.id;
}

// A cancelled stream reports CANCELLED; hitting the token ceiling reports LENGTH.
function finishReasonFor(
  native: NativeStreamResult | null,
  maxOutputTokens: number,
  toolCalls: ToolCall[]
): FinishReason {
  if (native?.cancelled) return FinishReason.CANCELLED;
  if (toolCalls.length) return FinishReason.TOOL_CALLS;
  if (native && native.outputTokens > 0 && native.outputTokens >= maxOutputTokens) {
    return FinishReason.LENGTH;
  }
  return FinishReason.STOP;
}

interface RawGeneration {
  text: string;
  thinkingText?: string;
  native: NativeStreamResult | null;
  fallbackTtftMs: number;
  fallbackTokens: number;
  elapsedMs: number;
}

// One streaming call, collected. Metrics come from the engine's completion
// callback when it supplied them, otherwise from wall-clock timing here.
async function runOnce(
  call: (onToken: (t: string) => void) => Promise<NativeStreamResult>
): Promise<RawGeneration> {
  const startedAt = Date.now();
  let firstAt = -1;
  let tokens = 0;
  let text = '';
  const native = await call((token) => {
    if (firstAt < 0) firstAt = Date.now();
    tokens += 1;
    text += token;
  });
  const split = splitThinking(text);
  return {
    text: split.thinking ? split.response : text,
    thinkingText: split.thinking || undefined,
    native,
    fallbackTtftMs: firstAt < 0 ? 0 : firstAt - startedAt,
    fallbackTokens: tokens,
    elapsedMs: Date.now() - startedAt,
  };
}

function metricsFrom(
  raw: RawGeneration,
  requestId: string,
  model: string
): {
  inputTokens: number;
  outputTokens: number;
  timeToFirstTokenMs: number;
  tokensPerSecond: number;
  requestId: string;
  model: string;
} {
  const n = raw.native;
  const useNative = !!n && n.hasMetrics;
  const outputTokens = useNative ? (n as NativeStreamResult).outputTokens : raw.fallbackTokens;
  const ttft = useNative ? (n as NativeStreamResult).timeToFirstTokenMs : raw.fallbackTtftMs;
  let tps = useNative ? (n as NativeStreamResult).tokensPerSecond : 0;
  if (!tps) {
    const genMs = Math.max(0, raw.elapsedMs - ttft);
    tps = genMs > 0 ? outputTokens / (genMs / 1000) : 0;
  }
  return {
    inputTokens: useNative ? (n as NativeStreamResult).inputTokens : 0,
    outputTokens,
    timeToFirstTokenMs: ttft,
    tokensPerSecond: tps,
    requestId,
    model,
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

/** Build the `llm` namespace over a backend. */
export function createLlmNamespace(deps: TextDeps): LlmNamespace {
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

  const generateRaw = (
    prompt: string,
    options: LlmOptions,
    shaped: ShapedPrompt,
    grammar: string | undefined,
    onToken: (t: string) => void
  ): Promise<NativeStreamResult> =>
    deps.backend.llmGenerate(
      prompt,
      toNativeGenerateOptions(
        { ...options, systemPrompt: options.systemPrompt ?? shaped.systemPrompt },
        { grammar, history: shaped.history }
      ),
      onToken
    );

  // Pick a tool (grammar-constrained), run it, and fold the result into the prompt.
  // Returns the calls made and the prompt the final answer should be built from.
  async function runToolLoop(
    shaped: ShapedPrompt,
    options: LlmOptions,
    available: RegisteredTool[],
    onToolCall: (call: ToolCall) => void
  ): Promise<string> {
    const choice = options.toolChoice ?? LLM_DEFAULTS.toolChoice;
    if (choice === 'NONE' || !available.length) return shaped.prompt;
    const forced = typeof choice === 'object' ? choice.forced : undefined;
    const candidates = forced
      ? available.filter((t) => t.definition.name === forced)
      : available;
    if (forced && !candidates.length) {
      throw SDKException.validationFailed({
        fieldPath: 'options.toolChoice',
        message: `forced tool '${forced}' is not registered`,
      });
    }
    const allowNone = choice === 'AUTO';
    const maxCalls = options.maxToolCalls ?? LLM_DEFAULTS.maxToolCalls;
    const definitions = candidates.map((c) => c.definition);
    let prompt = shaped.prompt;
    // The selection round emits a JSON object, not an answer, so it gets its own
    // budget: a caller asking for 24 answer tokens would otherwise have the tool
    // call truncated mid-object and nothing would parse.
    const selectionOptions: LlmOptions = {
      ...options,
      tools: [],
      toolChoice: 'NONE',
      maxOutputTokens: Math.max(TOOL_SELECTION_TOKENS, options.maxOutputTokens ?? 0),
    };

    for (let round = 0; round < maxCalls; round++) {
      const grammar = toolPickerGrammar(definitions, allowNone && round > 0 ? true : allowNone);
      let json = '';
      await generateRaw(
        toolPickerPrompt(prompt, definitions, allowNone),
        selectionOptions,
        { ...shaped, prompt },
        grammar,
        (t) => {
          json += t;
        }
      );
      let picked: { name?: string; arguments?: Record<string, unknown> };
      try {
        picked = JSON.parse(json.trim());
      } catch {
        // A malformed pick is fatal when the caller demanded a tool. Under AUTO the
        // model was free to call nothing, so fall back to answering the prompt
        // rather than failing a request that never needed a tool.
        if (choice !== 'AUTO') {
          throw SDKException.generationFailed(
            `tool selection did not return valid JSON: ${json.trim()}`
          );
        }
        return prompt;
      }
      if (!picked.name || picked.name === NO_TOOL) return prompt;
      const tool = candidates.find((t) => t.definition.name === picked.name);
      if (!tool) return prompt;
      const args = picked.arguments ?? {};
      const call: ToolCall = { id: newRequestId('call'), name: tool.definition.name, arguments: args };
      const result = await tool.executor(args);
      call.result = result;
      onToolCall(call);
      prompt = `${prompt}\n\nTool ${call.name}(${JSON.stringify(args)}) returned ${JSON.stringify(result)}.`;
      // A forced or required choice is satisfied by one call; AUTO may chain.
      if (choice !== 'AUTO') return prompt;
    }
    return prompt;
  }

  const structuredGrammar = (options: LlmOptions): string | undefined => {
    const so = options.structuredOutput;
    if (!so || so.strict === false) return undefined;
    return jsonSchemaToGrammar(so.schema);
  };

  async function generate(
    input: string | ChatMessage[],
    options: LlmOptions = {}
  ): Promise<GenerationResult> {
    deps.requireReady();
    const model = await resolveModelFor(deps, 'llm', ModelCategory.LANGUAGE, options.model);
    const shaped = shapePrompt(input);
    const requestId = newRequestId();
    const toolCalls: ToolCall[] = [];
    const available = activeTools(options);
    const prompt = available.length
      ? await runToolLoop(shaped, options, available, (c) => toolCalls.push(c))
      : shaped.prompt;
    const raw = await runOnce((onToken) =>
      generateRaw(prompt, options, { ...shaped, prompt }, structuredGrammar(options), onToken)
    );
    const includeThoughts = options.reasoning?.includeInOutput ?? false;
    return {
      text: raw.text,
      thinkingText: includeThoughts || raw.thinkingText ? raw.thinkingText : undefined,
      toolCalls,
      finishReason: finishReasonFor(
        raw.native,
        options.maxOutputTokens ?? LLM_DEFAULTS.maxOutputTokens,
        toolCalls
      ),
      ...metricsFrom(raw, requestId, model),
    };
  }

  function generateStream(
    input: string | ChatMessage[],
    options: LlmOptions = {}
  ): AsyncIterableIterator<GenerationEvent> {
    deps.requireReady();
    const requestId = newRequestId();
    return bridgeStream<GenerationEvent>(
      async (sink) => {
        const model = await resolveModelFor(deps, 'llm', ModelCategory.LANGUAGE, options.model);
        const shaped = shapePrompt(input);
        sink.push({ type: 'started', requestId });
        const toolCalls: ToolCall[] = [];
        const available = activeTools(options);
        const prompt = available.length
          ? await runToolLoop(shaped, options, available, (call) => {
              toolCalls.push(call);
              sink.push({ type: 'toolCall', toolCall: call });
            })
          : shaped.prompt;

        const splitter = new ThinkingSplitter();
        const includeThoughts = options.reasoning?.includeInOutput ?? false;
        let answer = '';
        let thoughts = '';
        const startedAt = Date.now();
        let firstAt = -1;
        let tokenCount = 0;
        const native = await generateRaw(
          prompt,
          options,
          { ...shaped, prompt },
          structuredGrammar(options),
          (token) => {
            if (firstAt < 0) firstAt = Date.now();
            tokenCount += 1;
            for (const part of splitter.push(token)) {
              if (part.kind === TokenKind.THOUGHT) {
                thoughts += part.text;
                if (includeThoughts) sink.push({ type: 'token', text: part.text, kind: part.kind });
              } else {
                answer += part.text;
                sink.push({ type: 'token', text: part.text, kind: part.kind });
              }
            }
          }
        );
        for (const part of splitter.flush()) {
          if (part.kind === TokenKind.THOUGHT) {
            thoughts += part.text;
            if (includeThoughts) sink.push({ type: 'token', text: part.text, kind: part.kind });
          } else {
            answer += part.text;
            sink.push({ type: 'token', text: part.text, kind: part.kind });
          }
        }
        const raw: RawGeneration = {
          text: answer,
          thinkingText: thoughts || undefined,
          native,
          fallbackTtftMs: firstAt < 0 ? 0 : firstAt - startedAt,
          fallbackTokens: tokenCount,
          elapsedMs: Date.now() - startedAt,
        };
        sink.push({
          type: 'completed',
          result: {
            text: answer,
            thinkingText: thoughts || undefined,
            toolCalls,
            finishReason: finishReasonFor(
              native,
              options.maxOutputTokens ?? LLM_DEFAULTS.maxOutputTokens,
              toolCalls
            ),
            ...metricsFrom(raw, requestId, model),
          },
        });
      },
      () => deps.backend.llmCancel()
    );
  }

  async function generateStructured<T = unknown>(
    prompt: string,
    schema: JsonSchema,
    options: LlmOptions = {}
  ): Promise<StructuredResult<T>> {
    const merged: LlmOptions = { ...options, structuredOutput: { schema, strict: true } };
    const result = await generate(prompt, merged);
    const raw = result.text.trim();
    let value: T;
    let valid = true;
    try {
      value = JSON.parse(raw) as T;
    } catch {
      value = undefined as unknown as T;
      valid = false;
    }
    return {
      value,
      raw,
      valid,
      finishReason: result.finishReason,
      inputTokens: result.inputTokens,
      outputTokens: result.outputTokens,
      timeToFirstTokenMs: result.timeToFirstTokenMs,
      tokensPerSecond: result.tokensPerSecond,
      requestId: result.requestId,
      model: result.model,
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

// The addon takes a path, base64, or raw RGB; encoded bytes go across as base64
// because rac_vlm_image_t has no "encoded buffer" variant.
function toNativeImage(input: ImageInput): {
  path?: string;
  base64?: string;
  rgb?: Uint8Array;
  width?: number;
  height?: number;
} {
  requireOneOf(input, ['path', 'bytes', 'rgb'], 'image');
  if (input.path) return { path: input.path };
  if (input.rgb) return { rgb: input.rgb, width: input.width, height: input.height };
  return { base64: Buffer.from(input.bytes as Uint8Array).toString('base64') };
}

/** Build the `vlm` namespace over a backend. */
export function createVlmNamespace(deps: TextDeps): VlmNamespace {
  async function generate(
    input: ImageInput,
    prompt: string,
    options: LlmOptions = {}
  ): Promise<GenerationResult> {
    deps.requireReady();
    const model = await resolveModelFor(deps, 'vlm', ModelCategory.VISION, options.model);
    const requestId = newRequestId();
    const img = toNativeImage(input);
    const raw = await runOnce((onToken) =>
      deps.backend.vlmGenerate(img, prompt, toNativeGenerateOptions(options), onToken)
    );
    return {
      text: raw.text,
      thinkingText: raw.thinkingText,
      toolCalls: [],
      finishReason: finishReasonFor(
        raw.native,
        options.maxOutputTokens ?? LLM_DEFAULTS.maxOutputTokens,
        []
      ),
      ...metricsFrom(raw, requestId, model),
    };
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
        const model = await resolveModelFor(deps, 'vlm', ModelCategory.VISION, options.model);
        const img = toNativeImage(input);
        sink.push({ type: 'started', requestId });
        const startedAt = Date.now();
        let firstAt = -1;
        let tokenCount = 0;
        let text = '';
        const native = await deps.backend.vlmGenerate(
          img,
          prompt,
          toNativeGenerateOptions(options),
          (token) => {
            if (firstAt < 0) firstAt = Date.now();
            tokenCount += 1;
            text += token;
            sink.push({ type: 'token', text: token, kind: TokenKind.TEXT });
          }
        );
        const raw: RawGeneration = {
          text,
          native,
          fallbackTtftMs: firstAt < 0 ? 0 : firstAt - startedAt,
          fallbackTokens: tokenCount,
          elapsedMs: Date.now() - startedAt,
        };
        sink.push({
          type: 'completed',
          result: {
            text,
            toolCalls: [],
            finishReason: finishReasonFor(
              native,
              options.maxOutputTokens ?? LLM_DEFAULTS.maxOutputTokens,
              []
            ),
            ...metricsFrom(raw, requestId, model),
          },
        });
      },
      () => deps.backend.vlmCancel()
    );
  }

  return { generate, generateStream };
}
