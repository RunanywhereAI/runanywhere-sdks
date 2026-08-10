/**
 * RunAnywhere+ToolCalling.ts
 *
 * Tool calling for LLM. The native run loop and prompt formatting live in
 * commons (`rac_tool_calling_run_loop_proto`); TypeScript
 * only owns the registry of JS callbacks and the per-call executor trampoline.
 *
 * Mirrors `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/RunAnywhere+ToolCalling.swift`.
 */

import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';
import { requireNativeModule, isNativeModuleAvailable } from '../../../native';
import { SDKException } from '../../../Foundation/Errors/SDKException';
import {
  ToolCall,
  ToolResult,
  ToolCallingResult,
  ToolCallingOptions,
  ToolCallFormatName,
  ToolCallingRole,
  type ToolDefinition,
  type ToolValue,
  type ToolValueArray,
  type ToolValueObject,
} from '@runanywhere/proto-ts/tool_calling';
import { ToolCallingSessionCreateRequest } from '@runanywhere/proto-ts/tool_calling';
import type { LLMGenerationOptions } from '@runanywhere/proto-ts/llm_options';
import { arrayBufferToBytes, bytesToBase64 } from '../../../services/ProtoBytes';
import { ensureServicesReady } from '../../../Foundation/Initialization/ServicesReadyGuard';
import { requireInitialized } from '../../../Foundation/Initialization/InitializedGuard';
import { encodeProtoMessage } from '../../../services/ProtoWire';

const logger = new SDKLogger('RunAnywhere.ToolCalling');

/**
 * Function type for tool executors. Receives parsed arguments as a
 * proto-canonical `ToolValue` map (mirrors Swift's `[String: RAToolValue]`
 * and Kotlin's `Map<String, ToolValue>`) and returns a result in the same
 * typed form. Fields are accessed via `args.location?.stringValue`,
 * `args.count?.numberValue`, etc. — matching the Swift `RAToolValue.string`
 * / `.number` pattern on the wire-canonical oneof tree.
 */
export type ToolExecutor = (
  args: Record<string, ToolValue>
) => Promise<Record<string, ToolValue>>;

/** A registered tool with its proto-canonical definition and JS executor. */
export interface RegisteredTool {
  definition: ToolDefinition;
  executor: ToolExecutor;
}

export type {
  ToolDefinition,
  ToolCall,
  ToolResult,
  ToolCallingOptions,
  ToolCallingResult,
  ToolCallingSessionCreateRequest,
  ToolValue,
  ToolValueArray,
  ToolValueObject,
};

// ---------------------------------------------------------------------------
// ToolValue ↔ plain-JSON bridge (RN-layer mirror of commons'
// `rac_tool_value_from_json_proto` / `rac_tool_value_to_json_proto`).
//
// `argumentsJson` arriving from the LLM is plain JSON (e.g.
// `{"location":"NYC","count":5}`). Swift delegates the deep walk to
// commons via `RAToolValue.parseObjectJSON`; RN performs the equivalent
// walk here in TypeScript so executors receive the same `ToolValue` oneof
// tree rather than `unknown`.
// ---------------------------------------------------------------------------

function plainJsonToToolValue(value: unknown): ToolValue {
  if (value === null || value === undefined) {
    return { nullValue: true };
  }
  if (typeof value === 'string') {
    return { stringValue: value };
  }
  if (typeof value === 'number') {
    return { numberValue: value };
  }
  if (typeof value === 'boolean') {
    return { boolValue: value };
  }
  if (Array.isArray(value)) {
    const arr: ToolValueArray = { values: value.map(plainJsonToToolValue) };
    return { arrayValue: arr };
  }
  if (typeof value === 'object') {
    const fields: Record<string, ToolValue> = {};
    for (const [k, v] of Object.entries(value as Record<string, unknown>)) {
      fields[k] = plainJsonToToolValue(v);
    }
    const obj: ToolValueObject = { fields };
    return { objectValue: obj };
  }
  return { stringValue: String(value) };
}

function toolValueToPlainJson(tv: ToolValue): unknown {
  if (tv.nullValue) return null;
  if (tv.stringValue !== undefined) return tv.stringValue;
  if (tv.numberValue !== undefined) return tv.numberValue;
  if (tv.boolValue !== undefined) return tv.boolValue;
  if (tv.arrayValue !== undefined) {
    return tv.arrayValue.values.map(toolValueToPlainJson);
  }
  if (tv.objectValue !== undefined) {
    const out: Record<string, unknown> = {};
    for (const [k, v] of Object.entries(tv.objectValue.fields)) {
      out[k] = toolValueToPlainJson(v);
    }
    return out;
  }
  return null;
}

/** Parse a plain-JSON object string into a `Record<string, ToolValue>` map.
 *  Mirrors `RAToolValue.parseObjectJSON` from Swift's ToolCallingTypes.swift. */
function parseObjectJSON(json: string): Record<string, ToolValue> {
  const raw: unknown = JSON.parse(json);
  if (typeof raw !== 'object' || raw === null || Array.isArray(raw)) {
    throw new Error(
      `ToolCall.argumentsJson must decode to a JSON object, got ${typeof raw}`
    );
  }
  const result: Record<string, ToolValue> = {};
  for (const [k, v] of Object.entries(raw as Record<string, unknown>)) {
    result[k] = plainJsonToToolValue(v);
  }
  return result;
}

/** Serialize a `Record<string, ToolValue>` result map back to a JSON string.
 *  Mirrors `RAToolValue.jsonString(from:)` from Swift's ToolCallingTypes.swift. */
function toolValueMapToJsonString(map: Record<string, ToolValue>): string {
  const out: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(map)) {
    out[k] = toolValueToPlainJson(v);
  }
  return JSON.stringify(out);
}

/** Convert a proto `ToolValue` argument map into plain JSON values. */
export function toolValueMapToJson(
  map: Record<string, ToolValue>
): Record<string, unknown> {
  const out: Record<string, unknown> = {};
  for (const [key, value] of Object.entries(map)) {
    out[key] = toolValueToPlainJson(value);
  }
  return out;
}

/** Convert plain JSON values into the proto `ToolValue` map executors return. */
export function toolValueMapFromJson(
  map: Record<string, unknown>
): Record<string, ToolValue> {
  const out: Record<string, ToolValue> = {};
  for (const [key, value] of Object.entries(map)) {
    out[key] = plainJsonToToolValue(value);
  }
  return out;
}

/**
 * Convert a flat alternating `[user0, asst0, user1, asst1, ...]` history
 * (excluding the current turn) into the wire `ToolCallingHistoryTurn[]`.
 * Mirrors `chat.proto`'s role mapping (`MESSAGE_ROLE_USER` ->
 * `TOOL_CALLING_ROLE_USER`, `MESSAGE_ROLE_ASSISTANT` ->
 * `TOOL_CALLING_ROLE_ASSISTANT`).
 */
function toToolCallingHistory(
  turns: string[]
): { role: ToolCallingRole; content: string }[] {
  return turns.map((content, index) => ({
    role:
      index % 2 === 0
        ? ToolCallingRole.TOOL_CALLING_ROLE_USER
        : ToolCallingRole.TOOL_CALLING_ROLE_ASSISTANT,
    content,
  }));
}

const registeredTools: Map<string, RegisteredTool> = new Map();

/**
 * Register a tool the LLM can call. The executor is invoked from the native
 * run loop whenever the model produces a matching tool call.
 */
export function registerTool(
  definition: ToolDefinition,
  executor: ToolExecutor
): Promise<void> {
  logger.debug(`Registering tool: ${definition.name}`);
  registeredTools.set(definition.name, { definition, executor });
  return Promise.resolve();
}

export function unregisterTool(toolName: string): Promise<void> {
  registeredTools.delete(toolName);
  return Promise.resolve();
}

export function getRegisteredTools(): Promise<ToolDefinition[]> {
  return Promise.resolve(
    Array.from(registeredTools.values()).map((t) => t.definition)
  );
}

export function clearTools(): Promise<void> {
  registeredTools.clear();
  return Promise.resolve();
}

/**
 * Execute a single parsed tool call against the registry. Used by
 * `generateWithTools` as the native-callback trampoline and exposed for
 * tests / hosts that want to drive tool execution manually.
 *
 * `ToolResult.success` is renamed `isError` with inverted polarity: the
 * proto3 zero value (`false`) is now the "good result" default (Anthropic
 * `is_error`, MCP `isError`), so every `success: false` below becomes
 * `isError: true` and `success: true` becomes `isError: false`.
 */
export async function executeTool(toolCall: ToolCall): Promise<ToolResult> {
  const tool = registeredTools.get(toolCall.name);
  const startedAtMs = Date.now();

  if (!tool) {
    return ToolResult.fromPartial({
      toolCallId: toolCall.id,
      name: toolCall.name,
      resultJson: '',
      error: `Unknown tool: ${toolCall.name}`,
      isError: true,
      startedAtMs,
      completedAtMs: Date.now(),
    });
  }

  let parsedArgs: Record<string, ToolValue> = {};
  try {
    parsedArgs = toolCall.argumentsJson
      ? parseObjectJSON(toolCall.argumentsJson)
      : {};
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    logger.error(`Tool argument parsing failed: ${errorMessage}`);
    return ToolResult.fromPartial({
      toolCallId: toolCall.id,
      name: toolCall.name,
      resultJson: '',
      error: `Failed to parse tool arguments: ${errorMessage}`,
      isError: true,
      startedAtMs,
      completedAtMs: Date.now(),
    });
  }

  try {
    logger.debug(`Executing tool: ${toolCall.name}`);
    const result = await tool.executor(parsedArgs);
    return ToolResult.fromPartial({
      toolCallId: toolCall.id,
      name: toolCall.name,
      resultJson: toolValueMapToJsonString(result),
      isError: false,
      startedAtMs,
      completedAtMs: Date.now(),
    });
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    logger.error(`Tool execution failed: ${errorMessage}`);
    return ToolResult.fromPartial({
      toolCallId: toolCall.id,
      name: toolCall.name,
      resultJson: '',
      error: errorMessage,
      isError: true,
      startedAtMs,
      completedAtMs: Date.now(),
    });
  }
}

/**
 * Optional cancellation signal accepted by [generateWithTools]. Mirrors the
 * Web `fetch`-style `AbortSignal` so callers can cancel an in-flight run loop
 * via `controller.abort()`.
 *
 * Wires through to `rac_tool_calling_run_loop_cancel_proto`.
 */
export interface GenerateWithToolsOptions {
  signal?: AbortSignal;
  /**
   * Sampling/system-prompt channel forwarded onto the request's
   * `ToolCallingOptions`. `maxOutputTokens`/`temperature`/`reasoning` are
   * deleted from `ToolCallingOptions` outright (idl: they duplicated the
   * enclosing `LLMGenerationOptions` in the two embeddings that had one,
   * and the standalone run-loop request has none) — only `topP` and
   * `systemPrompt` still have a channel here; the run loop otherwise keeps
   * commons' own greedy generation defaults.
   */
  llmOptions?: Partial<Pick<LLMGenerationOptions, 'topP' | 'systemPrompt'>>;
  /**
   * Swift parity: when omitted the proto field stays UNSET so commons applies
   * its documented default (true). Hosts that delegate validation to their
   * executor pass `false`.
   */
  validateCalls?: boolean;
  /**
   * Prior conversation turns as a flat alternating list [user0, asst0, ...],
   * EXCLUDING the current turn (which travels as `prompt`). Threaded into
   * commons so the tool-calling loop keeps multi-turn context, matching the
   * standard path's ChatMessage history as strings. Defaults to empty.
   */
  history?: string[];
}

/**
 * Generate a response with tool calling. Commons owns the multi-iteration
 * run loop through `rac_tool_calling_run_loop_proto`; this
 * function only forwards the request and supplies the JS executor trampoline.
 *
 * `ToolCallingSessionCreateRequest` is collapsed to 3 fields — `prompt`,
 * `history` (now typed `ToolCallingHistoryTurn[]`, not `string[]`), and
 * `options: ToolCallingOptions` — deleting the 14 flat knobs that used to be
 * re-published on the request; every one of them now lives on `options`
 * alone (or, for `temperature`/`maxTokens`, nowhere: the run loop keeps
 * commons' own greedy defaults, since this request has no enclosing
 * `LLMGenerationOptions` to inherit them from).
 *
 * Pass an `AbortSignal` via `extra.signal` to cancel the in-flight loop —
 * Nitro publishes the native run-loop handle synchronously so we can fan an
 * `abort()` into `rac_tool_calling_run_loop_cancel_proto`.
 */
export async function generateWithTools(
  prompt: string,
  options?: Partial<ToolCallingOptions>,
  extra?: GenerateWithToolsOptions
): Promise<ToolCallingResult> {
  // Swift parity: guard isInitialized (RunAnywhere+ToolCalling.swift:258-260).
  requireInitialized();
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }
  // Swift parity: RunAnywhere+ToolCalling.swift:261 gates on ensureServicesReady.
  await ensureServicesReady();

  const native = requireNativeModule();
  const runLoopWithHandle = (
    requestBytes: ArrayBuffer,
    onExecuteToolBytes: (toolCallBytes: ArrayBuffer) => Promise<string>,
    onHandle: (runLoopHandle: number) => void
  ) =>
    native.toolRunLoopProtoWithHandle(
      requestBytes,
      onExecuteToolBytes,
      onHandle
    );
  const cancelRunLoop = (runLoopHandle: number) => {
    void native.toolRunLoopCancelProto(runLoopHandle);
  };

  const tools = options?.tools ?? (await getRegisteredTools());
  const format =
    options?.format ?? ToolCallFormatName.TOOL_CALL_FORMAT_NAME_JSON;
  const toolCalling = ToolCallingOptions.fromPartial({
    tools,
    format,
    maxToolCalls: options?.maxToolCalls,
    keepToolsAvailable: options?.keepToolsAvailable ?? false,
    toolChoice: options?.toolChoice,
    forcedToolName: options?.forcedToolName,
    autoExecute: options?.autoExecute ?? true,
    replaceSystemPrompt: options?.replaceSystemPrompt ?? false,
    requireJsonArguments: options?.requireJsonArguments ?? false,
    disableThinking: options?.disableThinking ?? false,
    parallelToolCalls: options?.parallelToolCalls ?? false,
    topP: extra?.llmOptions?.topP,
    systemPrompt: extra?.llmOptions?.systemPrompt,
    // Leave unset unless the caller chose — commons defaults to true.
    validateCalls: extra?.validateCalls,
  });
  const request = ToolCallingSessionCreateRequest.fromPartial({
    prompt,
    // Prior turns as a flat alternating [user0, asst0, ...] list of message
    // contents (excluding the current turn, which is `prompt`); commons
    // flattens role-tagged history back to this same alternating shape, so
    // round-tripping through USER/ASSISTANT roles here is lossless.
    history: toToolCallingHistory(extra?.history ?? []),
    options: toolCalling,
  });

  logger.debug(
    `[ToolCalling] Delegating native run loop: format=${ToolCallFormatName[format]}, tools=${tools.length}`
  );

  const encodedRequest = encodeProtoMessage(
    request,
    ToolCallingSessionCreateRequest
  );
  const onExecute = async (toolCallBytes: ArrayBuffer): Promise<string> => {
    const toolCall = ToolCall.decode(arrayBufferToBytes(toolCallBytes));
    const result = await executeTool(toolCall);
    // Return base64 rather than an ArrayBuffer: the native run loop reads the
    // result off the JS thread, where a JS ArrayBuffer's data() is unreadable.
    return bytesToBase64(arrayBufferToBytes(encodeProtoMessage(result, ToolResult)));
  };

  const signal = extra?.signal;
  let runLoopHandle = 0;
  const onHandle = (handle: number) => {
    runLoopHandle = handle;
    if (signal?.aborted && runLoopHandle !== 0) {
      cancelRunLoop(runLoopHandle);
    }
  };
  const abortListener = () => {
    if (runLoopHandle !== 0) {
      cancelRunLoop(runLoopHandle);
    }
  };
  signal?.addEventListener('abort', abortListener);
  try {
    const resultBytes = await runLoopWithHandle(
      encodedRequest,
      onExecute,
      onHandle
    );
    const bytes = arrayBufferToBytes(resultBytes);
    if (bytes.byteLength === 0) {
      throw SDKException.protoDecodeFailed('toolRunLoopProtoWithHandle');
    }
    return ToolCallingResult.decode(bytes);
  } finally {
    signal?.removeEventListener('abort', abortListener);
  }
}
