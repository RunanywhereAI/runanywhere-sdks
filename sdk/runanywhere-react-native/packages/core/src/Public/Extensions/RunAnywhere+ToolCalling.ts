/**
 * RunAnywhere+ToolCalling.ts
 *
 * Tool Calling extension for LLM.
 * Allows LLMs to request external actions (API calls, device functions, etc.)
 *
 * ARCHITECTURE:
 * - C++ (ToolCallingBridge) handles: parsing <tool_call> tags (single source of truth)
 * - TypeScript handles: tool registration, executor storage, prompt formatting, orchestration
 */

import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import { generateStream } from './RunAnywhere+TextGeneration';
import {
  requireNativeModule,
  isNativeModuleAvailable,
} from '../../native';
import type {
  ToolDefinition,
  ToolCall,
  ToolResult,
  ToolExecutor,
  RegisteredTool,
  ToolCallingOptions,
  ToolCallingResult,
} from '../../types/ToolCallingTypes';

const logger = new SDKLogger('RunAnywhere.ToolCalling');

// =============================================================================
// PRIVATE STATE - Stores registered tools and executors
// Executors must stay in TypeScript (they need JS APIs like fetch)
// =============================================================================

const registeredTools: Map<string, RegisteredTool> = new Map();

type SerializedToolDefinition = Pick<ToolDefinition, 'name' | 'description'> & {
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
      type: p.type,
      description: p.description,
      required: p.required,
      ...(p.enum ? { enumValues: p.enum } : {}),
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
 * Register a tool that the LLM can use
 *
 * @param definition Tool definition (name, description, parameters)
 * @param executor Function that executes the tool (stays in TypeScript)
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

    // Parse argumentsJson if it's a string, otherwise use as-is
    let args: Record<string, unknown> = {};
    if (result.argumentsJson) {
      args = typeof result.argumentsJson === 'string'
        ? JSON.parse(result.argumentsJson)
        : result.argumentsJson;
    }

    const toolCall: ToolCall = {
      toolName: result.toolName,
      arguments: args,
      callId: `call_${result.callId || Date.now()}`,
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
 * Execute a tool call
 * Stays in TypeScript because executors need JS APIs (fetch, etc.)
 */
export async function executeTool(toolCall: ToolCall): Promise<ToolResult> {
  const tool = registeredTools.get(toolCall.toolName);

  if (!tool) {
    return {
      toolName: toolCall.toolName,
      success: false,
      error: `Unknown tool: ${toolCall.toolName}`,
      callId: toolCall.callId,
    };
  }

  try {
    logger.debug(`Executing tool: ${toolCall.toolName}`);
    const result = await tool.executor(toolCall.arguments);

    return {
      toolName: toolCall.toolName,
      success: true,
      result,
      callId: toolCall.callId,
    };
  } catch (error) {
    const errorMessage = error instanceof Error ? error.message : String(error);
    logger.error(`Tool execution failed: ${errorMessage}`);

    return {
      toolName: toolCall.toolName,
      success: false,
      error: errorMessage,
      callId: toolCall.callId,
    };
  }
}

// =============================================================================
// MAIN API: GENERATE WITH TOOLS
// =============================================================================

// =============================================================================
// C++ BRIDGE HELPERS - Use C++ single source of truth for prompt building
// =============================================================================

/**
 * Build initial prompt using C++ bridge
 * Falls back to simple concatenation if native unavailable
 */
async function buildInitialPromptViaCpp(
  userPrompt: string,
  toolsJson: string,
  options?: ToolCallingOptions
): Promise<string> {
  if (!isNativeModuleAvailable()) {
    const toolsPrompt = formatSerializedToolsJsonFallback(
      toolsJson,
      options?.format?.toLowerCase() || 'default'
    );
    return `${toolsPrompt}\n\nUser: ${userPrompt}`;
  }

  try {
    const native = requireNativeModule();
    const optionsJson = JSON.stringify({
      maxToolCalls: options?.maxToolCalls ?? 5,
      autoExecute: options?.autoExecute ?? true,
      temperature: options?.temperature ?? 0.7,
      maxTokens: options?.maxTokens ?? 1024,
      format: options?.format ?? 'default',
      replaceSystemPrompt: options?.replaceSystemPrompt ?? false,
      keepToolsAvailable: options?.keepToolsAvailable ?? false,
      systemPrompt: options?.systemPrompt,
    });
    return await native.buildInitialPrompt(userPrompt, toolsJson, optionsJson);
  } catch (error) {
    logger.error(`C++ buildInitialPrompt failed: ${error}`);
    const toolsPrompt = formatSerializedToolsJsonFallback(
      toolsJson,
      options?.format?.toLowerCase() || 'default'
    );
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

// =============================================================================
// MAIN API: GENERATE WITH TOOLS
// =============================================================================

/**
 * Generate a response with tool calling support
 * Uses C++ for parsing AND prompt building (single source of truth)
 *
 * ARCHITECTURE:
 * - Parsing & Prompts: C++ ToolCallingBridge (single source of truth)
 * - Registry & Execution: TypeScript (needs JS APIs like fetch)
 * - Orchestration: This function manages the generate-parse-execute loop
 */
export async function generateWithTools(
  prompt: string,
  options?: ToolCallingOptions
): Promise<ToolCallingResult> {
  const tools = options?.tools ?? getRegisteredTools();
  const maxToolCalls = options?.maxToolCalls ?? 5;
  const autoExecute = options?.autoExecute ?? true;
  const keepToolsAvailable = options?.keepToolsAvailable ?? false;
  const format = options?.format || 'default';

  logger.debug(`[ToolCalling] Starting with format: ${format}, tools: ${tools.length}`);

  // Serialize tools to JSON for C++ consumption
  const toolsJson = serializeToolsForCpp(tools);

  // Build initial prompt using C++ single source of truth
  let fullPrompt = await buildInitialPromptViaCpp(prompt, toolsJson, options);
  logger.debug(`[ToolCalling] Initial prompt built (${fullPrompt.length} chars)`);

  // Get formatted tools prompt for follow-up (if keepToolsAvailable)
  const toolsPrompt = keepToolsAvailable
    ? await formatToolsForPromptAsync(tools, format)
    : '';

  const allToolCalls: ToolCall[] = [];
  const allToolResults: ToolResult[] = [];
  let finalText = '';
  let iterations = 0;

  while (iterations < maxToolCalls) {
    iterations++;
    logger.debug(`[ToolCalling] === Iteration ${iterations} ===`);

    // Generate response
    let responseText = '';
    for await (const token of generateStream(fullPrompt, {
      maxTokens: options?.maxTokens ?? 1000,
      temperature: options?.temperature ?? 0.7,
      topP: 1.0,
      topK: 0,
      repetitionPenalty: 1.0,
      stopSequences: [],
      streamingEnabled: true,
      preferredFramework: 0,
    })) {
      responseText += token.text;
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

    logger.debug(`[ToolCalling] Tool call: ${toolCall.toolName}(${JSON.stringify(toolCall.arguments)})`);
    allToolCalls.push(toolCall);

    if (!autoExecute) {
      // Return tool calls for manual execution
      return {
        text: finalText,
        toolCalls: allToolCalls,
        toolResults: [],
        isComplete: false,
      };
    }

    // Execute the tool (in TypeScript - needs JS APIs)
    logger.debug(`[ToolCalling] Executing tool: ${toolCall.toolName}...`);
    const result = await executeTool(toolCall);
    allToolResults.push(result);
    logger.debug(`[ToolCalling] Tool result success: ${result.success}`);
    if (result.success) {
      logger.debug(`[ToolCalling] Tool data: ${JSON.stringify(result.result)}`);
    } else {
      logger.debug(`[ToolCalling] Tool error: ${result.error}`);
    }

    // Build follow-up prompt using C++ single source of truth
    const resultData = result.success ? result.result : { error: result.error };
    fullPrompt = await buildFollowupPromptViaCpp(
      prompt,
      toolsPrompt,
      toolCall.toolName,
      JSON.stringify(resultData),
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
  };
}

/**
 * Continue generation after manual tool execution
 */
export async function continueWithToolResult(
  previousPrompt: string,
  toolCall: ToolCall,
  toolResult: ToolResult,
  options?: ToolCallingOptions
): Promise<ToolCallingResult> {
  const resultJson = toolResult.success
    ? JSON.stringify(toolResult.result)
    : `Error: ${toolResult.error}`;

  const continuedPrompt = `${previousPrompt}\n\nTool Result for ${toolCall.toolName}: ${resultJson}\n\nBased on the tool result, please provide your response:`;

  return generateWithTools(continuedPrompt, {
    ...options,
    maxToolCalls: (options?.maxToolCalls ?? 5) - 1,
  });
}

// Legacy export for backwards compatibility
export { parseToolCallViaCpp as parseToolCall };
