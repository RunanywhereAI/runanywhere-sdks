/**
 * RunAnywhere+ToolCalling.ts
 *
 * Tool Calling extension for LLM.
 * Allows LLMs to request external actions (API calls, device functions, etc.)
 *
 * ARCHITECTURE:
 * - C++ (ToolCallingBridge) handles: parsing <tool_call> tags (single source of truth)
 * - TypeScript handles: tool registration, executor storage, prompt formatting, orchestration
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
import {
  ToolParameterType,
  type ToolDefinition,
  type ToolParameter,
  type ToolCall,
  type ToolResult,
  type ToolCallingOptions,
  type ToolCallingResult,
} from '@runanywhere/proto-ts/tool_calling';
import type { LLMGenerationResult } from '@runanywhere/proto-ts/llm_options';

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
};
export { ToolParameterType };

// =============================================================================
// PRIVATE STATE - Stores registered tools and executors
// =============================================================================

const registeredTools: Map<string, RegisteredTool> = new Map();

/**
 * Map a proto `ToolParameterType` enum value to the lowercase JSON-Schema
 * style scalar string that the C++ bridge expects in its serialised
 * tool descriptors.
 */
function parameterTypeToWireString(type: ToolParameterType): string {
  switch (type) {
    case ToolParameterType.TOOL_PARAMETER_TYPE_STRING:
      return 'string';
    case ToolParameterType.TOOL_PARAMETER_TYPE_NUMBER:
      return 'number';
    case ToolParameterType.TOOL_PARAMETER_TYPE_BOOLEAN:
      return 'boolean';
    case ToolParameterType.TOOL_PARAMETER_TYPE_OBJECT:
      return 'object';
    case ToolParameterType.TOOL_PARAMETER_TYPE_ARRAY:
      return 'array';
    case ToolParameterType.TOOL_PARAMETER_TYPE_UNSPECIFIED:
    case ToolParameterType.UNRECOGNIZED:
    default:
      return 'string';
  }
}

type SerializedToolDefinition = {
  name: string;
  description: string;
  parameters: Array<{
    name: string;
    type: string;
    description: string;
    required: boolean;
    enumValues?: string[];
  }>;
};

function serializeToolsForCpp(toolsToFormat: ToolDefinition[]): string {
  return JSON.stringify(toolsToFormat.map((tool) => ({
    name: tool.name,
    description: tool.description,
    parameters: tool.parameters.map((p) => ({
      name: p.name,
      type: parameterTypeToWireString(p.type),
      description: p.description,
      required: p.required,
      ...(p.enumValues && p.enumValues.length > 0
        ? { enumValues: p.enumValues }
        : {}),
    })),
  })));
}

function getFormatInstructions(format: string): string {
  switch (format) {
    case 'lfm2':
      return [
        'TOOL CALLING FORMAT (LFM2):',
        'When you need to use a tool, output ONLY this format:',
        '<|tool_call_start|>[TOOL_NAME(param="VALUE_FROM_USER_QUERY")]<|tool_call_end|>',
        '',
        "CRITICAL: Extract the EXACT value from the user's question:",
        '- User asks \'weather in Tokyo\' -> <|tool_call_start|>[get_weather(location="Tokyo")]<|tool_call_end|>',
        '- User asks \'weather in sf\' -> <|tool_call_start|>[get_weather(location="San Francisco")]<|tool_call_end|>',
        '',
        'RULES:',
        '1. For greetings or general chat, respond normally without tools',
        '2. Use Python-style function call syntax inside the tags',
        '3. String values MUST be quoted with double quotes',
        '4. Multiple arguments are separated by commas',
      ].join('\n');
    case 'default':
    default:
      return [
        'TOOL CALLING FORMAT - YOU MUST USE THIS EXACT FORMAT:',
        'When you need to use a tool, output ONLY this (no other text before or after):',
        '<tool_call>{"tool": "TOOL_NAME", "arguments": {"PARAM_NAME": "VALUE_FROM_USER_QUERY"}}</tool_call>',
        '',
        "CRITICAL: Extract the EXACT value from the user's question:",
        '- User asks \'weather in Tokyo\' -> <tool_call>{"tool": "get_weather", "arguments": {"location": "Tokyo"}}</tool_call>',
        '- User asks \'weather in sf\' -> <tool_call>{"tool": "get_weather", "arguments": {"location": "San Francisco"}}</tool_call>',
        '',
        'RULES:',
        '1. For greetings or general chat, respond normally without tools',
        '2. When using a tool, output ONLY the <tool_call> tag, nothing else',
        '3. Use the exact parameter names shown in the tool definitions above',
      ].join('\n');
  }
}

function formatToolsForPromptFallback(
  toolsToFormat: SerializedToolDefinition[],
  format: string
): string {
  if (toolsToFormat.length === 0) {
    return '';
  }

  let prompt = 'You have access to these tools:\n\n';

  for (const tool of toolsToFormat) {
    prompt += `- ${tool.name}: ${tool.description ?? ''}\n`;

    if (tool.parameters.length > 0) {
      prompt += '  Parameters:\n';
      for (const param of tool.parameters) {
        prompt += `    - ${param.name} (${param.type}${param.required ? ', required' : ''}): ${param.description ?? ''}\n`;
      }
    }

    prompt += '\n';
  }

  prompt += getFormatInstructions(format);
  return prompt;
}

function formatSerializedToolsJsonFallback(
  toolsJson: string,
  format: string
): string {
  try {
    const parsed = JSON.parse(toolsJson) as SerializedToolDefinition[];
    return formatToolsForPromptFallback(parsed, format);
  } catch (error) {
    logger.error(`Failed to parse tools JSON for fallback formatting: ${error}`);
    return toolsJson;
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
 * Parse LLM output for tool calls using C++ ToolCallingBridge
 * C++ is the single source of truth for parsing logic
 */
async function parseToolCallViaCpp(llmOutput: string): Promise<{
  text: string;
  toolCall: ToolCall | null;
}> {
  if (!isNativeModuleAvailable()) {
    logger.warning('Native module not available for parseToolCall');
    return { text: llmOutput, toolCall: null };
  }

  try {
    const native = requireNativeModule();
    const resultJson = await native.parseToolCallFromOutput(llmOutput);
    const result = JSON.parse(resultJson);

    if (!result.hasToolCall) {
      return { text: result.cleanText || llmOutput, toolCall: null };
    }

    // Normalise C++ output into the proto `ToolCall` shape: an `id`,
    // a `name`, a JSON-encoded `argumentsJson`, and a `type` discriminator.
    const argumentsJson =
      typeof result.argumentsJson === 'string'
        ? result.argumentsJson
        : JSON.stringify(result.argumentsJson ?? {});

    const toolCall: ToolCall = {
      id: `call_${result.callId || Date.now()}`,
      name: result.toolName,
      argumentsJson,
      type: 'function',
    };

    return { text: result.cleanText || '', toolCall };
  } catch (error) {
    logger.error(`C++ parseToolCall failed: ${error}`);
    return { text: llmOutput, toolCall: null };
  }
}

/**
 * Format tool definitions for LLM prompt
 * Creates a system prompt describing available tools
 *
 * Uses C++ single source of truth via native module.
 * Falls back to synchronous TypeScript implementation if native unavailable.
 *
 * @param tools - Tool definitions (defaults to registered tools)
 * @param format - Tool calling format: 'default' (JSON) or 'lfm2' (Pythonic)
 */
export function formatToolsForPrompt(tools?: ToolDefinition[], format?: string): string {
  const toolsToFormat = tools || getRegisteredTools();
  const toolFormat = format?.toLowerCase() || 'default';

  if (toolsToFormat.length === 0) {
    return '';
  }

  return formatToolsForPromptFallback(
    JSON.parse(serializeToolsForCpp(toolsToFormat)) as SerializedToolDefinition[],
    toolFormat
  );
}

/**
 * Format tool definitions for LLM prompt (async version)
 * Uses C++ single source of truth for consistent formatting across all platforms.
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

  const toolsJson = serializeToolsForCpp(toolsToFormat);

  if (!isNativeModuleAvailable()) {
    logger.warning('Native module not available, using TypeScript tool prompt formatter');
    return formatSerializedToolsJsonFallback(toolsJson, toolFormat);
  }

  try {
    const native = requireNativeModule();
    return await native.formatToolsForPrompt(toolsJson, toolFormat);
  } catch (error) {
    logger.error(`C++ formatToolsForPrompt failed: ${error}`);
    return formatSerializedToolsJsonFallback(toolsJson, toolFormat);
  }
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

  if (!tool) {
    return {
      toolCallId: toolCall.id,
      name: toolCall.name,
      resultJson: '',
      error: `Unknown tool: ${toolCall.name}`,
    };
  }

  let parsedArgs: Record<string, unknown> = {};
  try {
    parsedArgs = toolCall.argumentsJson
      ? (JSON.parse(toolCall.argumentsJson) as Record<string, unknown>)
      : {};
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    logger.error(`Tool argument parsing failed: ${errorMessage}`);
    return {
      toolCallId: toolCall.id,
      name: toolCall.name,
      resultJson: '',
      error: `Failed to parse tool arguments: ${errorMessage}`,
    };
  }

  try {
    logger.debug(`Executing tool: ${toolCall.name}`);
    const result = await tool.executor(parsedArgs);

    return {
      toolCallId: toolCall.id,
      name: toolCall.name,
      resultJson: JSON.stringify(result),
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    logger.error(`Tool execution failed: ${errorMessage}`);

    return {
      toolCallId: toolCall.id,
      name: toolCall.name,
      resultJson: '',
      error: errorMessage,
    };
  }
}

// =============================================================================
// MAIN API: GENERATE WITH TOOLS
// =============================================================================

/**
 * Build initial prompt using C++ bridge
 * Falls back to simple concatenation if native unavailable
 */
async function buildInitialPromptViaCpp(
  userPrompt: string,
  toolsJson: string,
  options?: Partial<ToolCallingOptions>
): Promise<string> {
  const formatHint = (options?.formatHint || 'default').toLowerCase();
  if (!isNativeModuleAvailable()) {
    const toolsPrompt = formatSerializedToolsJsonFallback(toolsJson, formatHint);
    return `${toolsPrompt}\n\nUser: ${userPrompt}`;
  }

  try {
    const native = requireNativeModule();
    const optionsJson = JSON.stringify({
      maxToolCalls: options?.maxIterations ?? 5,
      autoExecute: options?.autoExecute ?? true,
      temperature: options?.temperature ?? 0.7,
      maxTokens: options?.maxTokens ?? 1024,
      format: formatHint,
      replaceSystemPrompt: options?.replaceSystemPrompt ?? false,
      keepToolsAvailable: options?.keepToolsAvailable ?? false,
      systemPrompt: options?.systemPrompt,
    });
    return await native.buildInitialPrompt(userPrompt, toolsJson, optionsJson);
  } catch (error) {
    logger.error(`C++ buildInitialPrompt failed: ${error}`);
    const toolsPrompt = formatSerializedToolsJsonFallback(toolsJson, formatHint);
    return `${toolsPrompt}\n\nUser: ${userPrompt}`;
  }
}

/**
 * Build follow-up prompt using C++ bridge
 * Falls back to template string if native unavailable
 */
async function buildFollowupPromptViaCpp(
  originalPrompt: string,
  toolsPrompt: string,
  toolName: string,
  resultJson: string,
  keepToolsAvailable: boolean
): Promise<string> {
  if (!isNativeModuleAvailable()) {
    // Fallback: simple template
    if (keepToolsAvailable) {
      return `${toolsPrompt}\n\nUser: ${originalPrompt}\n\nTool ${toolName} returned: ${resultJson}`;
    }
    return `The user asked: "${originalPrompt}"\n\nYou used ${toolName} and got: ${resultJson}\n\nRespond naturally.`;
  }

  try {
    const native = requireNativeModule();
    return await native.buildFollowupPrompt(
      originalPrompt,
      toolsPrompt,
      toolName,
      resultJson,
      keepToolsAvailable
    );
  } catch (error) {
    logger.error(`C++ buildFollowupPrompt failed: ${error}`);
    return `The user asked: "${originalPrompt}"\n\nYou used ${toolName} and got: ${resultJson}`;
  }
}

/**
 * Generate a response with tool calling support.
 *
 * Uses C++ for parsing AND prompt building (single source of truth).
 *
 * ARCHITECTURE:
 * - Parsing & Prompts: C++ ToolCallingBridge (single source of truth)
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

  // Serialize tools to JSON for C++ consumption
  const toolsJson = serializeToolsForCpp(tools);

  // Build initial prompt using C++ single source of truth
  let fullPrompt = await buildInitialPromptViaCpp(prompt, toolsJson, options);
  logger.debug(`[ToolCalling] Initial prompt built (${fullPrompt.length} chars)`);

  // Get formatted tools prompt for follow-up (if keepToolsAvailable)
  const toolsPrompt = keepToolsAvailable
    ? await formatToolsForPromptAsync(tools, formatHint)
    : '';

  const allToolCalls: ToolCall[] = [];
  const allToolResults: ToolResult[] = [];
  let finalText = '';
  let iterations = 0;

  while (iterations < maxIterations) {
    iterations++;
    logger.debug(`[ToolCalling] === Iteration ${iterations} ===`);

    // Generate response
    let responseText = '';
    for await (const event of generateStream(fullPrompt, {
      maxTokens: options?.maxTokens ?? 1000,
      temperature: options?.temperature ?? 0.7,
      topP: 1.0,
      topK: 0,
      repetitionPenalty: 1.0,
      stopSequences: [],
      streamingEnabled: true,
      preferredFramework: 0,
    })) {
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
      return {
        text: finalText,
        toolCalls: allToolCalls,
        toolResults: [],
        isComplete: false,
        iterationsUsed: iterations,
      };
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

    // Build follow-up prompt using C++ single source of truth
    const followupBody = succeeded
      ? result.resultJson
      : JSON.stringify({ error: result.error });
    fullPrompt = await buildFollowupPromptViaCpp(
      prompt,
      toolsPrompt,
      toolCall.name,
      followupBody,
      keepToolsAvailable
    );

    logger.debug(`[ToolCalling] Continuing to iteration ${iterations + 1} with tool result...`);
  }

  logger.debug(`[ToolCalling] === DONE === finalText (${finalText.length} chars): "${finalText.substring(0, 200)}"`);
  logger.debug(`[ToolCalling] toolCalls: ${allToolCalls.length}, toolResults: ${allToolResults.length}`);

  return {
    text: finalText,
    toolCalls: allToolCalls,
    toolResults: allToolResults,
    isComplete: true,
    iterationsUsed: iterations,
  };
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

// Legacy export for backwards compatibility
export { parseToolCallViaCpp as parseToolCall };
