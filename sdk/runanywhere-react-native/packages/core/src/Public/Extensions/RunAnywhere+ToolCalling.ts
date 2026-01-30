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
 * IMPORTANT: This MUST match the C++ implementation in rac_tool_calling.cpp
 * The C++ function is: rac_tool_call_format_prompt_json_with_format()
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

  // Serialize tools to JSON array - EXACTLY like C++ does
  const toolsJson = JSON.stringify(toolsToFormat.map((tool) => ({
    name: tool.name,
    description: tool.description,
    parameters: tool.parameters.map((p) => ({
      name: p.name,
      type: p.type,
      description: p.description,
      required: p.required,
      ...(p.enumValues ? { enumValues: p.enumValues } : {}),
    })),
  })));

  // Format-specific instructions - MUST match C++ get_format_example_json()
  let formatExample: string;

  if (toolFormat === 'lfm2') {
    // LFM2 format - EXACTLY matches C++ RAC_TOOL_FORMAT_LFM2
    formatExample = `## OUTPUT FORMAT
You MUST respond with ONLY a tool call in this exact format:
<|tool_call_start|>[function_name(param="value")]<|tool_call_end|>

## EXAMPLES
Q: What's the weather in NYC?
A: <|tool_call_start|>[get_weather(location="New York")]<|tool_call_end|>

Q: weather in sf
A: <|tool_call_start|>[get_weather(location="San Francisco")]<|tool_call_end|>

Q: calculate 2+2
A: <|tool_call_start|>[calculate(expression="2+2")]<|tool_call_end|>`;
  } else {
    // Default JSON format - EXACTLY matches C++ RAC_TOOL_FORMAT_DEFAULT
    formatExample = `## OUTPUT FORMAT
You MUST respond with ONLY a tool call in this exact format:
<tool_call>{"tool": "function_name", "arguments": {"param": "value"}}</tool_call>

## EXAMPLES
Q: What's the weather in NYC?
A: <tool_call>{"tool": "get_weather", "arguments": {"location": "New York"}}</tool_call>

Q: weather in sf
A: <tool_call>{"tool": "get_weather", "arguments": {"location": "San Francisco"}}</tool_call>

Q: calculate 2+2
A: <tool_call>{"tool": "calculate", "arguments": {"expression": "2+2"}}</tool_call>`;
  }

  // Build prompt EXACTLY like C++ rac_tool_call_format_prompt_json_with_format()
  // See: sdk/runanywhere-commons/src/features/llm/tool_calling.cpp lines 1343-1358
  return `# TOOLS
${toolsJson}

${formatExample}

## RULES
- Weather question = call get_weather
- Math question = call calculate
- Time question = call get_current_time
- DO NOT make up data. ALWAYS use the tool.`;
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
 *
 * ARCHITECTURE:
 * - Parsing: C++ ToolCallingBridge (single source of truth)
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
  const replaceSystemPrompt = options?.replaceSystemPrompt ?? false;
  const keepToolsAvailable = options?.keepToolsAvailable ?? false;
  const format = options?.format || 'default';

  logger.debug(`[ToolCalling] Starting with format: ${format}, tools: ${tools.length}`);

  // Build system prompt with tools (pass format for correct instructions)
  const toolsPrompt = formatToolsForPrompt(tools, format);

  // Handle system prompt based on replaceSystemPrompt option
  let systemPrompt: string;
  if (replaceSystemPrompt && options?.systemPrompt) {
    // Use user's system prompt as-is (they handle tool instructions themselves)
    systemPrompt = options.systemPrompt;
  } else if (options?.systemPrompt) {
    // Merge user's system prompt with tool instructions (default behavior)
    systemPrompt = `${options.systemPrompt}\n\n${toolsPrompt}`;
  } else {
    // Use only tool instructions
    systemPrompt = toolsPrompt;
  }

  // Build conversation history for context preservation
  const conversationHistory: Array<{ role: string; content: string }> = [];

  // Initial prompt with system context
  let fullPrompt = systemPrompt ? `${systemPrompt}\n\nUser: ${prompt}` : prompt;
  conversationHistory.push({ role: 'user', content: prompt });

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
      conversationHistory.push({ role: 'assistant', content: finalText });
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

    // Add tool interaction to conversation history
    conversationHistory.push({ role: 'assistant', content: `[Tool: ${toolCall.toolName}]` });
    conversationHistory.push({ role: 'tool', content: JSON.stringify(result.success ? result.result : { error: result.error }) });

    // Build follow-up prompt based on keepToolsAvailable option
    const resultData = result.success ? result.result : { error: result.error };

    if (keepToolsAvailable) {
      // Keep tool definitions available for potential additional tool calls
      fullPrompt = `${systemPrompt}

User: ${prompt}

You previously used the ${toolCall.toolName} tool and received:
${JSON.stringify(resultData, null, 2)}

Based on this tool result, either use another tool if needed, or provide a helpful response to the user.`;
    } else {
      // Default: Remove tool definitions to encourage natural response
      fullPrompt = `The user asked: "${prompt}"

You used the ${toolCall.toolName} tool and received this data:
${JSON.stringify(resultData, null, 2)}

Now provide a helpful, natural response to the user based on this information. Do NOT use any tools - just respond conversationally.`;
    }

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
