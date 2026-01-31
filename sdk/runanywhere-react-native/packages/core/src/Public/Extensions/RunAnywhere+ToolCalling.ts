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

  // Serialize tools to JSON for C++ consumption
  const toolsJson = JSON.stringify(toolsToFormat.map((tool) => ({
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

  // Use async C++ bridge version internally
  // For sync callers, we return a placeholder and log a warning
  // Prefer using formatToolsForPromptAsync for new code
  logger.warning('formatToolsForPrompt is sync but C++ bridge is async. Use formatToolsForPromptAsync() for full C++ integration.');

  return toolsJson; // Return raw JSON - actual formatting done by buildInitialPrompt
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

  // Serialize tools to JSON for C++ consumption
  const toolsJson = JSON.stringify(toolsToFormat.map((tool) => ({
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

  if (!isNativeModuleAvailable()) {
    logger.warning('Native module not available, returning raw tools JSON');
    return toolsJson;
  }

  try {
    const native = requireNativeModule();
    return await native.formatToolsForPrompt(toolsJson, toolFormat);
  } catch (error) {
    logger.error(`C++ formatToolsForPrompt failed: ${error}`);
    return toolsJson;
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
    // Fallback: simple concatenation
    return `${toolsJson}\n\nUser: ${userPrompt}`;
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
    return `${toolsJson}\n\nUser: ${userPrompt}`;
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
  const toolsJson = JSON.stringify(tools.map((tool) => ({
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
    const streamResult = await generateStream(fullPrompt, {
      maxTokens: options?.maxTokens,
      temperature: options?.temperature,
    });

    for await (const token of streamResult.stream) {
      responseText += token;
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
