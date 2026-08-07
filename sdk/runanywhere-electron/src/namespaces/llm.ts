// The llm namespace: friendly generate/generateStream/cancel over the proto-byte
// backend. It builds an LLMGenerateRequest, calls the backend, and maps the
// LLMGenerationResult / LLMStreamEvent protos back to the public types. All the
// heavy lifting (templating, sampling, reasoning split) is in commons.

import { LLMGenerateRequest, LLMStreamEvent } from '@runanywhere/proto-ts/llm_service';
import { LLMGenerationResult } from '@runanywhere/proto-ts/llm_options';
import { StructuredOutputOptions } from '@runanywhere/proto-ts/structured_output';
import { TokenKind } from '@runanywhere/proto-ts/voice_events';
import { ChatMessage as ProtoChatMessage, MessageRole } from '@runanywhere/proto-ts/chat';

import { SDKException } from '../errors.js';
import { jsonSchemaToGrammar } from '../grammar.js';
import type { JsonSchema } from '../grammar.js';
import {
  ToolCall,
  ToolCallingResult,
  ToolCallingSessionCreateRequest,
  ToolDefinition as ProtoToolDefinition,
  ToolResult,
} from '@runanywhere/proto-ts/tool_calling';

import type { RaBackend } from '../backend.js';
import { toLlmGenerationOptions } from '../options.js';
import type { LlmOptions } from '../options.js';
import { bridgeStream } from '../stream.js';
import { Role } from '../types.js';
import type { ChatMessage, GenerationEvent, GenerationResult } from '../types.js';

/** Resolves a model id into its component before generation (auto-load + auto-download). */
export type ModelResolver = (modelId: string) => Promise<void>;

/** A tool the model may call. `parameters` is a JSON Schema for the arguments. */
export interface ToolDefinition {
  name: string;
  description: string;
  parameters?: Record<string, unknown>;
}

/** Runs a chosen tool: parsed arguments in, a result object out. */
export type ToolExecutor = (args: Record<string, unknown>) => unknown | Promise<unknown>;

/** A tool the model chose to call. */
export interface ToolCallRecord {
  name: string;
  arguments: Record<string, unknown>;
}

/** The outcome of a tool-calling run. */
export interface ToolRunResult {
  text: string;
  toolCalls: ToolCallRecord[];
}

/** Register tools and let the model call them (commons drives the loop). */
export interface ToolsNamespace {
  register(tool: ToolDefinition, execute: ToolExecutor): void;
  unregister(name: string): void;
  list(): string[];
  /** Answer `prompt`, calling registered tools as the model requests them. */
  run(prompt: string, options?: LlmOptions): Promise<ToolRunResult>;
}

export interface LlmNamespace {
  /** Generate a full completion for a prompt. */
  generate(prompt: string, options?: LlmOptions): Promise<GenerationResult>;
  /** Generate a full completion for a message list (system -> systemPrompt, trailing user -> prompt). */
  generate(messages: ChatMessage[], options?: LlmOptions): Promise<GenerationResult>;
  /** Stream the completion token by token, then a terminal event with the result. */
  generateStream(prompt: string, options?: LlmOptions): AsyncIterableIterator<GenerationEvent>;
  /** Stream a completion for a message list. */
  generateStream(messages: ChatMessage[], options?: LlmOptions): AsyncIterableIterator<GenerationEvent>;
  /** Cancel the in-flight generation, if any. */
  cancel(): Promise<void>;
  /**
   * Generate JSON constrained to `schema` (GBNF-constrained decoding), parsed and
   * returned. Throws if the model somehow produced non-JSON.
   */
  generateStructured<T = unknown>(prompt: string, schema: JsonSchema, options?: LlmOptions): Promise<T>;
  /** Tool calling: register tools, then run(). */
  readonly tools: ToolsNamespace;
}

const ROLE_TO_PROTO: Record<Role, MessageRole> = {
  [Role.SYSTEM]: MessageRole.MESSAGE_ROLE_SYSTEM,
  [Role.USER]: MessageRole.MESSAGE_ROLE_USER,
  [Role.ASSISTANT]: MessageRole.MESSAGE_ROLE_ASSISTANT,
  [Role.TOOL]: MessageRole.MESSAGE_ROLE_TOOL,
};

/** Split a message list Swift-style: system -> systemPrompt, trailing user -> prompt, middle -> history. */
function splitMessages(
  messages: ChatMessage[],
  options?: LlmOptions
): { options: LlmOptions; prompt: string; history: ProtoChatMessage[] } {
  const system = messages
    .filter((m) => m.role === Role.SYSTEM)
    .map((m) => m.content)
    .join('\n\n');
  const rest = messages.filter((m) => m.role !== Role.SYSTEM);
  const last = rest[rest.length - 1];
  if (!last || last.role !== Role.USER) {
    throw SDKException.invalidInput('the last message must be a user turn');
  }
  const history = rest.slice(0, -1).map((m) =>
    ProtoChatMessage.fromPartial({
      role: ROLE_TO_PROTO[m.role],
      content: m.content,
      ...(m.toolCallId ? { toolCallId: m.toolCallId } : {}),
    })
  );
  const merged: LlmOptions = { ...options, systemPrompt: options?.systemPrompt ?? (system || undefined) };
  return { options: merged, prompt: last.content, history };
}

function buildRequest(prompt: string, options?: LlmOptions, history?: ProtoChatMessage[]): Uint8Array {
  return LLMGenerateRequest.encode(
    LLMGenerateRequest.fromPartial({
      prompt,
      ...(options?.model ? { modelId: options.model } : {}),
      ...(history && history.length ? { history } : {}),
      options: toLlmGenerationOptions(options),
    })
  ).finish();
}

/** Normalize the (prompt | messages) overload into a single request shape. */
function normalize(
  input: string | ChatMessage[],
  options?: LlmOptions
): { options: LlmOptions; prompt: string; history: ProtoChatMessage[] } {
  if (typeof input === 'string') return { options: options ?? {}, prompt: input, history: [] };
  return splitMessages(input, options);
}

function toResult(res: LLMGenerationResult): GenerationResult {
  return {
    text: res.text,
    // Trim so a model that emits only whitespace as its reasoning (e.g. "\n\n")
    // reads as no reasoning rather than an empty block.
    thinking: (res.thinkingContent ?? '').trim(),
    toolCalls: [],
    finishReason: res.finishReason ?? '',
    metrics: {
      inputTokens: res.usage?.inputTokens ?? 0,
      outputTokens: res.usage?.outputTokens ?? res.responseTokens ?? 0,
      totalTokens: res.usage?.totalTokens ?? 0,
      timeToFirstTokenMs: res.ttftMs ?? 0,
      totalTimeMs: res.generationTimeMs ?? 0,
      tokensPerSecond: res.usage?.tokensPerSecond ?? 0,
    },
  };
}

function createToolsNamespace(backend: RaBackend, resolve: ModelResolver): ToolsNamespace {
  const registry = new Map<string, { def: ToolDefinition; execute: ToolExecutor }>();

  // Run one tool: decode the ToolCall, run the registered executor on its parsed
  // arguments, encode a ToolResult. Errors become an unsuccessful ToolResult so
  // the model can react rather than the whole loop failing.
  async function onExecute(toolCallBytes: Uint8Array): Promise<Uint8Array> {
    const call = ToolCall.decode(toolCallBytes);
    const entry = registry.get(call.name);
    let result: ToolResult;
    if (!entry) {
      result = ToolResult.fromPartial({
        toolCallId: call.id,
        name: call.name,
        success: false,
        error: `no tool registered named "${call.name}"`,
      });
    } else {
      try {
        const args = call.argumentsJson ? (JSON.parse(call.argumentsJson) as Record<string, unknown>) : {};
        const value = await entry.execute(args);
        result = ToolResult.fromPartial({
          toolCallId: call.id,
          name: call.name,
          success: true,
          resultJson: JSON.stringify(value ?? null),
        });
      } catch (e) {
        result = ToolResult.fromPartial({
          toolCallId: call.id,
          name: call.name,
          success: false,
          error: e instanceof Error ? e.message : String(e),
        });
      }
    }
    return ToolResult.encode(result).finish();
  }

  return {
    register(tool, execute) {
      registry.set(tool.name, { def: tool, execute });
    },
    unregister(name) {
      registry.delete(name);
    },
    list() {
      return [...registry.keys()];
    },
    async run(prompt, options = {}) {
      if (options.model) await resolve(options.model);
      const tools = [...registry.values()].map((e) =>
        ProtoToolDefinition.fromPartial({
          name: e.def.name,
          description: e.def.description,
          ...(e.def.parameters ? { jsonSchema: JSON.stringify(e.def.parameters) } : {}),
        })
      );
      const req = ToolCallingSessionCreateRequest.fromPartial({
        prompt,
        tools,
        autoExecute: true,
        maxTokens: options.maxOutputTokens ?? 512,
        temperature: options.temperature ?? 0.7,
        ...(options.systemPrompt !== undefined ? { systemPrompt: options.systemPrompt } : {}),
      });
      const out = ToolCallingResult.decode(
        await backend.toolRunLoop(ToolCallingSessionCreateRequest.encode(req).finish(), onExecute)
      );
      return {
        text: out.text,
        toolCalls: out.toolCalls.map((c) => ({
          name: c.name,
          arguments: c.argumentsJson ? (JSON.parse(c.argumentsJson) as Record<string, unknown>) : {},
        })),
      };
    },
  };
}

export function createLlmNamespace(backend: RaBackend, resolve: ModelResolver): LlmNamespace {
  const tools = createToolsNamespace(backend, resolve);
  return {
    tools,
    async generate(input: string | ChatMessage[], options?: LlmOptions) {
      const n = normalize(input, options);
      if (n.options.model) await resolve(n.options.model);
      return toResult(
        LLMGenerationResult.decode(await backend.llmGenerate(buildRequest(n.prompt, n.options, n.history)))
      );
    },

    generateStream(input: string | ChatMessage[], options?: LlmOptions) {
      const n = normalize(input, options);
      let answer = '';
      let thinking = '';
      let finishReason = '';
      let outputTokens = 0;
      let elapsedMs = 0;
      let ttftMs = 0;
      let startedAt = 0;
      return bridgeStream<GenerationEvent>(
        async (sink) => {
          if (n.options.model) await resolve(n.options.model);
          startedAt = Date.now();
          return backend.llmGenerateStream(buildRequest(n.prompt, n.options, n.history), (bytes) => {
            const ev = LLMStreamEvent.decode(bytes);
            const isThinking = ev.kind === TokenKind.TOKEN_KIND_THOUGHT;
            if (ev.token) {
              if (ttftMs === 0 && startedAt) ttftMs = Date.now() - startedAt;
              if (isThinking) thinking += ev.token;
              else answer += ev.token;
            }
            if (ev.completionTokensGenerated) outputTokens = ev.completionTokensGenerated;
            if (ev.elapsedMs) elapsedMs = ev.elapsedMs;
            if (ev.finishReason) finishReason = ev.finishReason;
            if (ev.isFinal) {
              // Prefer the final result's own metrics; fall back to what the
              // deltas gave us (and a wall-clock rate) so tok/s and TTFT are real.
              const r = ev.result;
              const outTok = r?.usage?.outputTokens || outputTokens;
              const totalMs = r?.totalTimeMs || elapsedMs || (startedAt ? Date.now() - startedAt : 0);
              const ttft = r?.timeToFirstTokenMs || ttftMs;
              const tps = r?.usage?.tokensPerSecond || (totalMs > 0 ? outTok / (totalMs / 1000) : 0);
              sink.push({
                token: '',
                isFinal: true,
                isThinking: false,
                result: {
                  text: answer || r?.text || '',
                  thinking: (thinking || r?.thinkingContent || '').trim(),
                  toolCalls: [],
                  finishReason: finishReason || r?.finishReason || '',
                  metrics: {
                    inputTokens: r?.usage?.inputTokens || 0,
                    outputTokens: outTok,
                    totalTokens: r?.usage?.totalTokens || outTok,
                    timeToFirstTokenMs: ttft,
                    totalTimeMs: totalMs,
                    tokensPerSecond: tps,
                  },
                },
              });
            } else {
              sink.push({ token: ev.token, isFinal: false, isThinking });
            }
          });
        },
        () => backend.llmCancel()
      );
    },

    async cancel() {
      await backend.llmCancel();
    },

    async generateStructured<T = unknown>(prompt: string, schema: JsonSchema, options?: LlmOptions): Promise<T> {
      if (options?.model) await resolve(options.model);
      const req = LLMGenerateRequest.encode(
        LLMGenerateRequest.fromPartial({
          prompt,
          ...(options?.model ? { modelId: options.model } : {}),
          options: {
            ...toLlmGenerationOptions(options),
            structuredOutput: StructuredOutputOptions.fromPartial({
              grammar: jsonSchemaToGrammar(schema),
            }),
          },
        })
      ).finish();
      const res = LLMGenerationResult.decode(await backend.llmGenerate(req));
      const text = res.text.trim();
      try {
        return JSON.parse(text) as T;
      } catch {
        throw SDKException.generationFailed(`structured output was not valid JSON: ${text}`);
      }
    },
  };
}
