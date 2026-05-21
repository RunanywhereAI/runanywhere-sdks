/**
 * RunAnywhere+ToolCalling.ts
 *
 * Tool calling for LLM. The native run loop and prompt formatting live in
 * commons (`rac_tool_calling_run_loop_proto`); TypeScript only owns the
 * registry of JS callbacks and the per-call executor trampoline.
 *
 * Mirrors `sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/RunAnywhere+ToolCalling.swift`.
 */

import { SDKLogger } from '../../../Foundation/Logging/Logger/SDKLogger';
import { requireNativeModule, isNativeModuleAvailable } from '../../../native';
import { SDKException } from '../../../Foundation/Errors/SDKException';
import {
  ToolParameterType,
  ToolCall,
  ToolResult,
  ToolCallingResult,
  ToolCallingOptions,
  ToolCallingSessionCreateRequest,
  type ToolDefinition,
  type ToolParameter,
} from '@runanywhere/proto-ts/tool_calling';
import { arrayBufferToBytes } from '../../../services/ProtoBytes';
import { encodeProtoMessage } from '../../../services/ProtoWire';

const logger = new SDKLogger('RunAnywhere.ToolCalling');

/**
 * Function type for tool executors. Receives the parsed JSON arguments
 * (decoded from `ToolCall.argumentsJson`) and returns a JSON-serialisable
 * result that will be re-encoded into `ToolResult.resultJson`.
 */
export type ToolExecutor = (
  args: Record<string, unknown>
) => Promise<Record<string, unknown>>;

/** A registered tool with its proto-canonical definition and JS executor. */
export interface RegisteredTool {
  definition: ToolDefinition;
  executor: ToolExecutor;
}

export type {
  ToolDefinition,
  ToolParameter,
  ToolCall,
  ToolResult,
  ToolCallingOptions,
  ToolCallingResult,
  ToolCallingSessionCreateRequest,
};
export { ToolParameterType };

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
      success: false,
      startedAtMs,
      completedAtMs: Date.now(),
    });
  }

  let parsedArgs: Record<string, unknown> = {};
  try {
    parsedArgs = toolCall.argumentsJson
      ? (JSON.parse(toolCall.argumentsJson) as Record<string, unknown>)
      : {};
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    logger.error(`Tool argument parsing failed: ${errorMessage}`);
    return ToolResult.fromPartial({
      toolCallId: toolCall.id,
      name: toolCall.name,
      resultJson: '',
      error: `Failed to parse tool arguments: ${errorMessage}`,
      success: false,
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
      resultJson: JSON.stringify(result),
      success: true,
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
      success: false,
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
 * pass2-syn-007: wires through to `rac_tool_calling_run_loop_cancel_proto`.
 */
export interface GenerateWithToolsOptions {
  signal?: AbortSignal;
}

/**
 * Generate a response with tool calling. Commons owns the multi-iteration
 * run loop through `rac_tool_calling_run_loop_proto`; this function only
 * forwards the request and supplies the JS executor trampoline.
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
  if (!isNativeModuleAvailable()) {
    throw SDKException.nativeModuleUnavailable();
  }

  const native = requireNativeModule();
  const bridge = native as unknown as {
    toolRunLoopProto?: (
      requestBytes: ArrayBuffer,
      onExecuteToolBytes: (toolCallBytes: ArrayBuffer) => Promise<ArrayBuffer>
    ) => Promise<ArrayBuffer>;
    // pass2-syn-007: optional cancel-aware variant. When the native module
    // ships the with-handle variant, we drive that instead so AbortSignal
    // can interrupt the in-flight C call.
    toolRunLoopProtoWithHandle?: (
      requestBytes: ArrayBuffer,
      onExecuteToolBytes: (toolCallBytes: ArrayBuffer) => Promise<ArrayBuffer>,
      onHandle: (runLoopHandle: number) => void
    ) => Promise<ArrayBuffer>;
    toolRunLoopCancelProto?: (runLoopHandle: number) => void;
  };

  if (typeof bridge.toolRunLoopProto !== 'function') {
    throw SDKException.notImplemented(
      'generateWithTools requires native toolRunLoopProto backed by rac_tool_calling_run_loop_proto'
    );
  }

  const tools = options?.tools ?? (await getRegisteredTools());
  const formatHint = (options?.formatHint || 'default').toLowerCase();
  const request = ToolCallingSessionCreateRequest.fromPartial({
    prompt,
    maxTokens: options?.maxTokens ?? 1024,
    temperature: options?.temperature ?? 0.7,
    topP: 1.0,
    systemPrompt: options?.systemPrompt ?? '',
    tools,
    formatHint,
    maxIterations: options?.maxIterations ?? options?.maxToolCalls ?? 5,
    keepToolsAvailable: options?.keepToolsAvailable ?? false,
    validateCalls: true,
    // pass2-syn-006-followup-rn: thread the OpenAI-style tool_choice /
    // forced_tool_name knobs into the canonical request envelope (idl
    // fields 7/8). Commons build_options_snapshot copies them onto every
    // synthesized ToolCallingOptions before format/validate proto calls.
    toolChoice: options?.toolChoice,
    forcedToolName: options?.forcedToolName,
  });

  logger.debug(
    `[ToolCalling] Delegating native run loop: format=${formatHint}, tools=${tools.length}`
  );

  const encodedRequest = encodeProtoMessage(request, ToolCallingSessionCreateRequest);
  const onExecute = async (toolCallBytes: ArrayBuffer) => {
    const toolCall = ToolCall.decode(arrayBufferToBytes(toolCallBytes));
    const result = await executeTool(toolCall);
    return encodeProtoMessage(result, ToolResult);
  };

  const signal = extra?.signal;
  // Prefer the cancel-aware variant when both halves of the ABI are exported.
  if (
    typeof bridge.toolRunLoopProtoWithHandle === 'function' &&
    typeof bridge.toolRunLoopCancelProto === 'function'
  ) {
    let runLoopHandle = 0;
    const onHandle = (handle: number) => {
      runLoopHandle = handle;
      if (signal?.aborted && runLoopHandle !== 0) {
        bridge.toolRunLoopCancelProto!(runLoopHandle);
      }
    };
    const abortListener = () => {
      if (runLoopHandle !== 0) {
        bridge.toolRunLoopCancelProto!(runLoopHandle);
      }
    };
    signal?.addEventListener('abort', abortListener);
    try {
      const resultBytes = await bridge.toolRunLoopProtoWithHandle(
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

  // Legacy ABI fallback — no cancellation possible on this path.
  if (signal && !signal.aborted) {
    logger.warning(
      'toolRunLoopProtoWithHandle not exported by native module; AbortSignal will not interrupt the in-flight call'
    );
  }

  const resultBytes = await bridge.toolRunLoopProto(
    encodedRequest,
    onExecute
  );

  const bytes = arrayBufferToBytes(resultBytes);
  if (bytes.byteLength === 0) {
    throw SDKException.protoDecodeFailed('toolRunLoopProto');
  }
  return ToolCallingResult.decode(bytes);
}
