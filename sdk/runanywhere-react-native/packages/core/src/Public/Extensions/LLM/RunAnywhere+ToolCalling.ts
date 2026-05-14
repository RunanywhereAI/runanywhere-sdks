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
import {
  arrayBufferToBytes,
  bytesToArrayBuffer,
} from '../../../services/ProtoBytes';

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
 * Generate a response with tool calling. Commons owns the multi-iteration
 * run loop through `rac_tool_calling_run_loop_proto`; this function only
 * forwards the request and supplies the JS executor trampoline.
 */
export async function generateWithTools(
  prompt: string,
  options?: Partial<ToolCallingOptions>
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
  });

  logger.debug(
    `[ToolCalling] Delegating native run loop: format=${formatHint}, tools=${tools.length}`
  );

  const resultBytes = await bridge.toolRunLoopProto(
    bytesToArrayBuffer(ToolCallingSessionCreateRequest.encode(request).finish()),
    async (toolCallBytes: ArrayBuffer) => {
      const toolCall = ToolCall.decode(arrayBufferToBytes(toolCallBytes));
      const result = await executeTool(toolCall);
      return bytesToArrayBuffer(ToolResult.encode(result).finish());
    }
  );

  const bytes = arrayBufferToBytes(resultBytes);
  if (bytes.byteLength === 0) {
    throw SDKException.protoDecodeFailed('toolRunLoopProto');
  }
  return ToolCallingResult.decode(bytes);
}
