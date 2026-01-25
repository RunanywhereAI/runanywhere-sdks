/**
 * RunAnywhere+ToolCalling.ts
 *
 * Tool Calling extension for LLM.
 * Allows LLMs to request external actions (API calls, device functions, etc.)
 *
 * ARCHITECTURE:
 * - C++ (ToolCallingBridge) is the SINGLE SOURCE OF TRUTH for parsing logic
 * - TypeScript handles: tool registration, executor storage, orchestration
 * - C++ handles: parseToolCall(), formatToolsPrompt()
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

    const toolCall: ToolCall = {
      toolName: result.toolName,
      arguments: result.argumentsJson || {},
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
 */
export function formatToolsForPrompt(tools?: ToolDefinition[]): string {
  const toolsToFormat = tools || getRegisteredTools();

  if (toolsToFormat.length === 0) {
    return '';
  }

  const toolDescriptions = toolsToFormat.map((tool) => {
    const params = tool.parameters
      .map((p) => `    - ${p.name} (${p.type}${p.required ? ', required' : ''}): ${p.description}`)
      .join('\n');

    return `- ${tool.name}: ${tool.description}\n  Parameters:\n${params}`;
  });

  return `You have access to these tools:

${toolDescriptions.join('\n\n')}

TOOL CALLING FORMAT - YOU MUST USE THIS EXACT FORMAT:
When you need to use a tool, output ONLY this (no other text before or after):
<tool_call>{"tool": "TOOL_NAME", "arguments": {"PARAM_NAME": "VALUE"}}</tool_call>

EXAMPLE - If user asks "what's the weather in Paris":
<tool_call>{"tool": "get_weather", "arguments": {"location": "Paris"}}</tool_call>

RULES:
1. For greetings or general chat, respond normally without tools
2. When using a tool, output ONLY the <tool_call> tag, nothing else
3. Use the exact parameter names shown in the tool definitions above`;
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

/**
 * Generate a response with tool calling support
 * Uses C++ for parsing, TypeScript for execution
 */
export async function generateWithTools(
  prompt: string,
  options?: ToolCallingOptions
): Promise<ToolCallingResult> {
  const tools = options?.tools || getRegisteredTools();
  const maxToolCalls = options?.maxToolCalls || 5;
  const autoExecute = options?.autoExecute ?? true;

  // Build system prompt with tools
  const toolsPrompt = formatToolsForPrompt(tools);
  const systemPrompt = options?.systemPrompt
    ? `${options.systemPrompt}\n\n${toolsPrompt}`
    : toolsPrompt;

  // First generation
  let fullPrompt = systemPrompt ? `${systemPrompt}\n\nUser: ${prompt}` : prompt;

  const allToolCalls: ToolCall[] = [];
  const allToolResults: ToolResult[] = [];
  let finalText = '';
  let iterations = 0;

  while (iterations < maxToolCalls) {
    iterations++;
    console.log(`[ToolCalling] === Iteration ${iterations} ===`);

    // Generate response
    let responseText = '';
    const streamResult = await generateStream(fullPrompt, {
      maxTokens: options?.maxTokens,
      temperature: options?.temperature,
    });

    for await (const token of streamResult.stream) {
      responseText += token;
    }

    console.log(`[ToolCalling] Raw response (${responseText.length} chars): ${responseText.substring(0, 300)}`);

    // Parse for tool calls using C++ (single source of truth)
    const { text, toolCall } = await parseToolCallViaCpp(responseText);
    finalText = text;
    console.log(`[ToolCalling] Parsed - hasToolCall: ${!!toolCall}, cleanText (${finalText.length} chars): "${finalText.substring(0, 150)}"`);

    if (!toolCall) {
      // No tool call, we're done
      console.log('[ToolCalling] No tool call found, breaking loop with finalText');
      break;
    }

    console.log(`[ToolCalling] Tool call: ${toolCall.toolName}(${JSON.stringify(toolCall.arguments)})`);
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
    console.log(`[ToolCalling] Executing tool: ${toolCall.toolName}...`);
    const result = await executeTool(toolCall);
    allToolResults.push(result);
    console.log(`[ToolCalling] Tool result success: ${result.success}`);
    if (result.success) {
      console.log(`[ToolCalling] Tool data: ${JSON.stringify(result.result)}`);
    } else {
      console.log(`[ToolCalling] Tool error: ${result.error}`);
    }

    // Add tool result to context and continue with a clear prompt
    // IMPORTANT: Don't include tool definitions again - just ask for natural response
    const resultData = result.success ? result.result : { error: result.error };

    // Format a clear follow-up prompt for the LLM (WITHOUT tool definitions)
    fullPrompt = `The user asked: "${prompt}"

You used the ${toolCall.toolName} tool and received this data:
${JSON.stringify(resultData, null, 2)}

Now provide a helpful, natural response to the user based on this information. Do NOT use any tools - just respond conversationally.`;
    console.log(`[ToolCalling] Continuing to iteration ${iterations + 1} with tool result...`);
  }

  console.log(`[ToolCalling] === DONE === finalText (${finalText.length} chars): "${finalText.substring(0, 200)}"`);
  console.log(`[ToolCalling] toolCalls: ${allToolCalls.length}, toolResults: ${allToolResults.length}`);

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
    maxToolCalls: (options?.maxToolCalls || 5) - 1,
  });
}

// Legacy export for backwards compatibility
export { parseToolCallViaCpp as parseToolCall };
