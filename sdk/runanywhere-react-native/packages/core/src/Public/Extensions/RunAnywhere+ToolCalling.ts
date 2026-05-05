/**
 * RunAnywhere+ToolCalling.ts
 *
 * Tool Calling extension for LLM.
 * Allows LLMs to request external actions (API calls, device functions, etc.)
 *
 * ARCHITECTURE:
 * - C++ commons handles: parsing <tool_call> tags and prompt formatting
 * - TypeScript handles: tool registration, executor storage, and JS execution adapters
 *
 * Wave-4 §15 cleanup: Canonical tool-calling shapes now come from
 * `@runanywhere/proto-ts/tool_calling`. RN-only helpers (`ToolExecutor`,
 * `RegisteredTool`) — which carry a JS-side function reference and so cannot
 * round-trip through proto — are declared inline below.
 */

import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { generateStream, generate } from './RunAnywhere+TextGeneration';
import {
  requireNativeModule,
  isNativeModuleAvailable,
} from '../../native';
import { SDKException } from '../../Foundation/ErrorTypes/SDKException';
import {
  ToolParameterType,
  ToolCall,
  ToolResult,
  ToolCallingResult,
  ToolCallingOptions,
  ToolParseRequest,
  ToolParseResult,
  ToolPromptFormatRequest,
  ToolPromptFormatResult,
  ToolCallValidationRequest,
  ToolCallValidationResult,
  type ToolDefinition,
  type ToolParameter,
} from '@runanywhere/proto-ts/tool_calling';
import {
  LLMGenerationOptions,
  type LLMGenerationResult,
} from '@runanywhere/proto-ts/llm_options';
import {
  arrayBufferToBytes,
  bytesToArrayBuffer,
} from '../../services/ProtoBytes';

const logger = new SDKLogger('RunAnywhere.ToolCalling');

// =============================================================================
// RN-LOCAL HELPERS (no proto equivalent — function references can't round-trip
// through wire format).
// =============================================================================

/**
 * Function type for tool executors. Receives the parsed JSON arguments
 * (decoded from `ToolCall.argumentsJson`) and returns a JSON-serialisable
 * result that will be re-encoded into `ToolResult.resultJson`.
 */
export type ToolExecutor = (
  args: Record<string, unknown>
) => Promise<Record<string, unknown>>;

/**
 * A registered tool with its proto-canonical definition and JS executor.
 */
export interface RegisteredTool {
  definition: ToolDefinition;
  executor: ToolExecutor;
}

// Re-export proto-canonical tool-calling types so consumers of this
// extension keep a single import surface.
export type {
  ToolDefinition,
  ToolParameter,
  ToolCall,
  ToolResult,
  ToolCallingOptions,
  ToolCallingResult,
  ToolParseRequest,
  ToolParseResult,
  ToolPromptFormatRequest,
  ToolPromptFormatResult,
  ToolCallValidationRequest,
  ToolCallValidationResult,
};
export { ToolParameterType };

// =============================================================================
// PRIVATE STATE - Stores registered tools and executors
// =============================================================================

const registeredTools: Map<string, RegisteredTool> = new Map();

type ProtoBridgeMethod = (requestBytes: ArrayBuffer) => Promise<ArrayBuffer>;

function toBridgeException(operation: string, error: unknown): SDKException {
  if (error instanceof SDKException) {
    return error;
  }
  const message = error instanceof Error ? error.message : String(error);
  if (/not available|unavailable|not implemented|missing/i.test(message)) {
    return SDKException.notImplemented(`${operation}: ${message}`);
  }
  return SDKException.unknown(
    `${operation}: ${message}`,
    error instanceof Error ? error : undefined
  );
}

function requireNativeProtoMethod(
  methodName: string,
  operation: string
): ProtoBridgeMethod {
  if (!isNativeModuleAvailable()) {
    throw SDKException.notImplemented(
      `${operation}: Native module not available`
    );
  }

  const native = requireNativeModule();
  const method = (native as unknown as Record<string, unknown>)[methodName];
  if (typeof method !== 'function') {
    throw SDKException.notImplemented(
      `${operation}: native method ${methodName} is unavailable`
    );
  }

  return method.bind(native) as ProtoBridgeMethod;
}

async function callNativeProto(
  methodName: string,
  requestBytes: ArrayBuffer,
  operation: string
): Promise<Uint8Array> {
  try {
    const method = requireNativeProtoMethod(methodName, operation);
    const responseBytes = await method(requestBytes);
    const bytes = arrayBufferToBytes(responseBytes);
    if (bytes.byteLength === 0) {
      throw SDKException.unknown(
        `${operation}: native bridge returned an empty proto result`
      );
    }
    return bytes;
  } catch (error) {
    throw toBridgeException(operation, error);
  }
}

// =============================================================================
// TOOL REGISTRATION
// =============================================================================

/**
 * Register a tool that the LLM can use.
 *
 * @param definition Proto-canonical `ToolDefinition` (name, description,
 *   parameters using `ToolParameterType` enum values, optional category).
 * @param executor JS function that executes the tool. Receives parsed
 *   arguments and returns a JSON-serialisable result.
 */
export function registerTool(
  definition: ToolDefinition,
  executor: ToolExecutor
): void {
  logger.debug(`Registering tool: ${definition.name}`);
  registeredTools.set(definition.name, { definition, executor });
}

/**
 * Unregister a tool
 */
export function unregisterTool(toolName: string): void {
  registeredTools.delete(toolName);
}

/**
 * Get all registered tool definitions
 */
export function getRegisteredTools(): ToolDefinition[] {
  return Array.from(registeredTools.values()).map((t) => t.definition);
}

/**
 * Clear all registered tools
 */
export function clearTools(): void {
  registeredTools.clear();
}

// =============================================================================
// C++ BRIDGE CALLS - Single Source of Truth
// =============================================================================

/**
 * Parse LLM output for tool calls using the native proto-byte bridge.
 *
 * JS owns only generated proto-ts serialization here; the portable parser
 * and generated result semantics are implemented in native C++ over the
 * commons `rac_tool_call_*` C ABI.
 */
export async function parseToolCallFromOutput(
  llmOutput: string,
  options?: Partial<ToolCallingOptions>
): Promise<ToolParseResult> {
  const request = ToolParseRequest.fromPartial({
    text: llmOutput,
    options: options ? ToolCallingOptions.fromPartial(options) : undefined,
  });
  const responseBytes = await callNativeProto(
    'toolParseProto',
    bytesToArrayBuffer(ToolParseRequest.encode(request).finish()),
    'parseToolCall'
  );
  return ToolParseResult.decode(responseBytes);
}

async function parseToolCallViaCpp(llmOutput: string): Promise<{
  text: string;
  toolCall: ToolCall | null;
}> {
  const result = await parseToolCallFromOutput(llmOutput);
  if (!result.hasToolCall || result.toolCalls.length === 0) {
    return { text: result.remainingText || llmOutput, toolCall: null };
  }
  return {
    text: result.remainingText || '',
    toolCall: result.toolCalls[0] ?? null,
  };
}

async function formatToolPromptViaCpp(
  request: ToolPromptFormatRequest
): Promise<ToolPromptFormatResult> {
  const responseBytes = await callNativeProto(
    'toolFormatPromptProto',
    bytesToArrayBuffer(ToolPromptFormatRequest.encode(request).finish()),
    'formatToolPrompt'
  );
  const result = ToolPromptFormatResult.decode(responseBytes);
  if (result.errorMessage) {
    throw SDKException.unknown(result.errorMessage);
  }
  return result;
}

/**
 * Format tool definitions for LLM prompt (async version)
 * Uses generated proto bytes at the RN boundary and C++ commons for portable
 * prompt semantics.
 *
 * @param tools - Tool definitions (defaults to registered tools)
 * @param format - Tool calling format: 'default' (JSON) or 'lfm2' (Pythonic)
 */
export async function formatToolsForPromptAsync(tools?: ToolDefinition[], format?: string): Promise<string> {
  const toolsToFormat = tools || getRegisteredTools();
  const toolFormat = format?.toLowerCase() || 'default';

  if (toolsToFormat.length === 0) {
    return '';
  }

  const result = await formatToolPromptViaCpp(ToolPromptFormatRequest.fromPartial({
    options: ToolCallingOptions.fromPartial({
      tools: toolsToFormat,
      formatHint: toolFormat,
    }),
  }));
  return result.formattedPrompt;
}

/**
 * Validate a parsed tool call against the generated tool registry snapshot.
 *
 * The JS layer only serializes the generated request and supplies the current
 * registered tool definitions. Commons owns validation and argument
 * normalization semantics.
 */
export async function validateToolCall(
  toolCall: ToolCall,
  options?: Partial<ToolCallingOptions>
): Promise<ToolCallValidationResult> {
  const tools = options?.tools ?? getRegisteredTools();
  const request = ToolCallValidationRequest.fromPartial({
    toolCall,
    options: ToolCallingOptions.fromPartial({
      ...options,
      tools,
    }),
  });
  const responseBytes = await callNativeProto(
    'toolValidateProto',
    bytesToArrayBuffer(ToolCallValidationRequest.encode(request).finish()),
    'validateToolCall'
  );
  return ToolCallValidationResult.decode(responseBytes);
}

// =============================================================================
// TOOL EXECUTION (TypeScript - needs JS APIs)
// =============================================================================

/**
 * Execute a tool call.
 *
 * Reads the proto `ToolCall.argumentsJson` payload, decodes it, runs the
 * registered executor, and returns a proto `ToolResult` with the executor
 * output JSON-encoded into `resultJson` (or `error` populated on failure).
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
      result: {},
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
      result: {},
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
      result: {},
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
      result: {},
      startedAtMs,
      completedAtMs: Date.now(),
    });
  }
}

// =============================================================================
// MAIN API: GENERATE WITH TOOLS
// =============================================================================

/**
 * Build initial prompt using C++ bridge.
 */
async function buildInitialPromptViaCpp(
  userPrompt: string,
  tools: ToolDefinition[],
  options?: Partial<ToolCallingOptions>
): Promise<string> {
  const formatHint = (options?.formatHint || 'default').toLowerCase();
  const result = await formatToolPromptViaCpp(ToolPromptFormatRequest.fromPartial({
    userPrompt,
    options: ToolCallingOptions.fromPartial({
      ...options,
      tools,
      formatHint,
      maxToolCalls: options?.maxToolCalls ?? options?.maxIterations ?? 5,
      autoExecute: options?.autoExecute ?? true,
      temperature: options?.temperature ?? 0.7,
      maxTokens: options?.maxTokens ?? 1024,
    }),
  }));
  return result.formattedPrompt;
}

/**
 * Build follow-up prompt using the native proto-byte bridge.
 */
async function buildFollowupPromptViaCpp(
  originalPrompt: string,
  tools: ToolDefinition[],
  toolResult: ToolResult,
  keepToolsAvailable: boolean,
  formatHint: string
): Promise<string> {
  const result = await formatToolPromptViaCpp(ToolPromptFormatRequest.fromPartial({
    userPrompt: originalPrompt,
    options: ToolCallingOptions.fromPartial({
      tools,
      keepToolsAvailable,
      formatHint,
    }),
    toolResults: [toolResult],
  }));
  return result.formattedPrompt;
}

/**
 * Generate a response with tool calling support.
 *
 * Uses C++ for parsing AND prompt building (single source of truth).
 *
 * ARCHITECTURE:
 * - Parsing & Prompts: C++ commons via proto-byte bridge
 * - Registry & Execution: TypeScript (needs JS APIs like fetch)
 * - Orchestration: This function manages the generate-parse-execute loop
 */
export async function generateWithTools(
  prompt: string,
  options?: Partial<ToolCallingOptions>
): Promise<ToolCallingResult> {
  const tools = options?.tools ?? getRegisteredTools();
  const maxIterations = options?.maxIterations ?? 5;
  const autoExecute = options?.autoExecute ?? true;
  const keepToolsAvailable = options?.keepToolsAvailable ?? false;
  const formatHint = (options?.formatHint || 'default').toLowerCase();

  logger.debug(`[ToolCalling] Starting with format: ${formatHint}, tools: ${tools.length}`);

  // Build initial prompt using C++ single source of truth
  let fullPrompt = await buildInitialPromptViaCpp(prompt, tools, options);
  logger.debug(`[ToolCalling] Initial prompt built (${fullPrompt.length} chars)`);

  const allToolCalls: ToolCall[] = [];
  const allToolResults: ToolResult[] = [];
  let finalText = '';
  let iterations = 0;

  while (iterations < maxIterations) {
    iterations++;
    logger.debug(`[ToolCalling] === Iteration ${iterations} ===`);

    // Generate response
    let responseText = '';
    for await (const event of generateStream(fullPrompt, LLMGenerationOptions.fromPartial({
      maxTokens: options?.maxTokens ?? 1000,
      temperature: options?.temperature ?? 0.7,
      topP: 1.0,
      topK: 0,
      repetitionPenalty: 1.0,
      stopSequences: [],
      streamingEnabled: true,
      preferredFramework: 0,
      enableRealTimeTracking: false,
    }))) {
      if (event.token) responseText += event.token;
      if (event.isFinal) break;
    }

    logger.debug(`[ToolCalling] Raw response (${responseText.length} chars): ${responseText.substring(0, 300)}`);

    // Parse for tool calls using C++ (single source of truth)
    const { text, toolCall } = await parseToolCallViaCpp(responseText);
    finalText = text;
    logger.debug(`[ToolCalling] Parsed - hasToolCall: ${!!toolCall}, cleanText (${finalText.length} chars): "${finalText.substring(0, 150)}"`);

    if (!toolCall) {
      // No tool call, we're done - LLM provided a natural response
      logger.debug('[ToolCalling] No tool call found, breaking loop with finalText');
      break;
    }

    logger.debug(`[ToolCalling] Tool call: ${toolCall.name}(${toolCall.argumentsJson})`);
    allToolCalls.push(toolCall);

    if (!autoExecute) {
      // Return tool calls for manual execution
      return ToolCallingResult.fromPartial({
        text: finalText,
        toolCalls: allToolCalls,
        toolResults: [],
        isComplete: false,
        iterationsUsed: iterations,
      });
    }

    // Execute the tool (in TypeScript - needs JS APIs)
    logger.debug(`[ToolCalling] Executing tool: ${toolCall.name}...`);
    const result = await executeTool(toolCall);
    allToolResults.push(result);
    const succeeded = !result.error;
    logger.debug(`[ToolCalling] Tool result success: ${succeeded}`);
    if (succeeded) {
      logger.debug(`[ToolCalling] Tool data: ${result.resultJson}`);
    } else {
      logger.debug(`[ToolCalling] Tool error: ${result.error}`);
    }

    fullPrompt = await buildFollowupPromptViaCpp(
      prompt,
      tools,
      result,
      keepToolsAvailable,
      formatHint
    );

    logger.debug(`[ToolCalling] Continuing to iteration ${iterations + 1} with tool result...`);
  }

  logger.debug(`[ToolCalling] === DONE === finalText (${finalText.length} chars): "${finalText.substring(0, 200)}"`);
  logger.debug(`[ToolCalling] toolCalls: ${allToolCalls.length}, toolResults: ${allToolResults.length}`);

  return ToolCallingResult.fromPartial({
    text: finalText,
    toolCalls: allToolCalls,
    toolResults: allToolResults,
    isComplete: true,
    iterationsUsed: iterations,
    rawText: finalText,
  });
}

/**
 * Continue generation after a tool result has been produced externally.
 *
 * Canonical cross-SDK signature (§3):
 *   `continueWithToolResult(toolCallId: string, result: string) → LLMGenerationResult`
 *
 * The tool call ID and result string are appended to the current conversation
 * context held by the LLM component, then generation is resumed. The returned
 * `LLMGenerationResult` carries the model's response text and token metrics.
 */
export async function continueWithToolResult(
  toolCallId: string,
  result: string
): Promise<LLMGenerationResult> {
  // Build a follow-up prompt that injects the tool result.
  const continuedPrompt =
    `Tool call ID: ${toolCallId}\nTool result: ${result}\n\nBased on the tool result, please provide your response:`;
  return generate(continuedPrompt);
}
