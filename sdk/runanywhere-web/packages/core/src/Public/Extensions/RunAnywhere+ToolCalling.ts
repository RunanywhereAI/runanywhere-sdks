/**
 * RunAnywhere Web SDK - Tool Calling Extension
 *
 * Adds tool calling (function calling) capabilities to LLM generation.
 * The LLM can request external actions (API calls, calculations, etc.)
 * and the SDK orchestrates the generate -> parse -> execute -> loop cycle.
 *
 * Architecture:
 *   - C++ (rac_tool_calling.h): ALL parsing, prompt formatting, JSON handling
 *   - This file: Tool registry, executor storage, orchestration
 *
 * Mirrors: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Extensions/LLM/
 *
 * Usage:
 *   import { ToolCalling } from '@runanywhere/web';
 *
 *   ToolCalling.registerTool(
 *     { name: 'get_weather', description: 'Gets weather', parameters: [...] },
 *     async (args) => ({ temperature: '72F', condition: 'Sunny' })
 *   );
 *
 *   const result = await ToolCalling.generateWithTools('What is the weather?');
 *   console.log(result.text);
 */

import { RunAnywhere } from '../RunAnywhere';
import { WASMBridge } from '../../Foundation/WASMBridge';
import { SDKError, SDKErrorCode } from '../../Foundation/ErrorTypes';
import { SDKLogger } from '../../Foundation/SDKLogger';
import { TextGeneration } from './RunAnywhere+TextGeneration';
import {
  ToolCallFormat,
  type ToolValue,
  type ToolParameterType,
  type ToolParameter,
  type ToolDefinition,
  type ToolCall,
  type ToolResult,
  type ToolCallingOptions,
  type ToolCallingResult,
  type ToolExecutor,
} from './ToolCallingTypes';

export {
  ToolCallFormat,
  type ToolValue,
  type ToolParameterType,
  type ToolParameter,
  type ToolDefinition,
  type ToolCall,
  type ToolResult,
  type ToolCallingOptions,
  type ToolCallingResult,
  type ToolExecutor,
} from './ToolCallingTypes';

const logger = new SDKLogger('ToolCalling');

/**
 * Generate text and return the complete result.
 *
 * Uses the streaming path (`generateStream`) and drains the token stream
 * to collect the full response text.  On WebGPU + JSPI builds the
 * non-streaming `generate()` C function triggers "trying to suspend
 * JS frames" because the Emscripten JSPI `Suspending` wrapper cannot
 * unwind through mixed WASM/JS frames in the non-streaming code path.
 * The streaming path works because its token callbacks return to JS
 * cleanly between each suspension point.
 */
async function collectGeneration(
  prompt: string,
  opts: { maxTokens?: number; temperature?: number },
): Promise<{ text: string }> {
  const { stream } = await TextGeneration.generateStream(prompt, opts);
  let text = '';
  for await (const token of stream) {
    text += token;
  }
  return { text };
}

function requireBridge(): WASMBridge {
  if (!RunAnywhere.isInitialized) throw SDKError.notInitialized();
  return WASMBridge.shared;
}

// ---------------------------------------------------------------------------
// ToolValue helpers
// ---------------------------------------------------------------------------

/** Create a ToolValue from a plain JS value. */
export function toToolValue(val: unknown): ToolValue {
  if (val === null || val === undefined) return { type: 'null' };
  if (typeof val === 'string') return { type: 'string', value: val };
  if (typeof val === 'number') return { type: 'number', value: val };
  if (typeof val === 'boolean') return { type: 'boolean', value: val };
  if (Array.isArray(val)) return { type: 'array', value: val.map(toToolValue) };
  if (typeof val === 'object') {
    const obj: Record<string, ToolValue> = {};
    for (const [k, v] of Object.entries(val as Record<string, unknown>)) {
      obj[k] = toToolValue(v);
    }
    return { type: 'object', value: obj };
  }
  return { type: 'null' };
}

/** Convert a ToolValue to a plain JS value. */
export function fromToolValue(tv: ToolValue): unknown {
  switch (tv.type) {
    case 'string': return tv.value;
    case 'number': return tv.value;
    case 'boolean': return tv.value;
    case 'array': return tv.value.map(fromToolValue);
    case 'object': {
      const obj: Record<string, unknown> = {};
      for (const [k, v] of Object.entries(tv.value)) {
        obj[k] = fromToolValue(v);
      }
      return obj;
    }
    case 'null': return null;
  }
}

/** Get a string argument from tool call args. */
export function getStringArg(args: Record<string, ToolValue>, key: string): string | undefined {
  const v = args[key];
  return v?.type === 'string' ? v.value : undefined;
}

/** Get a number argument from tool call args. */
export function getNumberArg(args: Record<string, ToolValue>, key: string): number | undefined {
  const v = args[key];
  return v?.type === 'number' ? v.value : undefined;
}

// ---------------------------------------------------------------------------
// Internal: RegisteredTool interface
// ---------------------------------------------------------------------------

interface RegisteredTool {
  definition: ToolDefinition;
  executor: ToolExecutor;
}

// ---------------------------------------------------------------------------
// Internal: C++ Bridge helpers
// ---------------------------------------------------------------------------

/**
 * Check if C++ tool calling functions are available in the WASM module.
 *
 * On WebGPU builds, all WASM imports are wrapped with WebAssembly.Suspending.
 * Synchronous ccall to C++ tool-calling functions (which are NOT
 * WebAssembly.promising-wrapped) will throw "trying to suspend without
 * WebAssembly.promising" if any import inside the C++ code returns a Promise.
 * To avoid this, we always use the TypeScript fallback on WebGPU builds.
 */
function hasNativeToolCalling(): boolean {
  try {
    const bridge = requireBridge();
    // WebGPU builds have JSPI Suspending on ALL imports, so synchronous
    // ccall to native tool helpers triggers SuspendError.  Use TS fallback.
    if (bridge.accelerationMode === 'webgpu') return false;
    // eslint-disable-next-line @typescript-eslint/no-explicit-any
    return typeof (bridge.module as any)['_rac_tool_call_parse'] === 'function';
  } catch {
    return false;
  }
}

/**
 * Parse LLM output for tool calls.
 * Uses C++ when available, falls back to TypeScript regex parsing.
 */
function parseToolCall(llmOutput: string): { text: string; toolCall: ToolCall | null } {
  if (hasNativeToolCalling()) {
    return parseToolCallNative(llmOutput);
  }
  return parseToolCallTS(llmOutput);
}

/**
 * Parse via C++ rac_tool_call_parse.
 */
function parseToolCallNative(llmOutput: string): { text: string; toolCall: ToolCall | null } {
  const bridge = requireBridge();
  const m = bridge.module;

  // Allocate result struct (rac_tool_call_t)
  // Fields: has_tool_call (i32), tool_name (ptr), arguments_json (ptr),
  //         clean_text (ptr), call_id (i64), format (i32)
  const resultSize = 40; // generous
  const resultPtr = m._malloc(resultSize);
  for (let i = 0; i < resultSize; i++) m.setValue(resultPtr + i, 0, 'i8');

  const inputPtr = bridge.allocString(llmOutput);

  try {
    const rc = m.ccall('rac_tool_call_parse', 'number', ['number', 'number'], [inputPtr, resultPtr]) as number;

    const hasToolCall = m.getValue(resultPtr, 'i32');
    const toolNamePtr = m.getValue(resultPtr + 4, '*') as number;
    const argsJsonPtr = m.getValue(resultPtr + 8, '*') as number;
    const cleanTextPtr = m.getValue(resultPtr + 12, '*') as number;
    const callId = m.getValue(resultPtr + 16, 'i32');

    const cleanText = cleanTextPtr ? bridge.readString(cleanTextPtr) : llmOutput;

    if (rc !== 0 || hasToolCall !== 1 || !toolNamePtr) {
      // Free the result struct
      m.ccall('rac_tool_call_free', null, ['number'], [resultPtr]);
      return { text: cleanText, toolCall: null };
    }

    const toolName = bridge.readString(toolNamePtr);
    const argsJson = argsJsonPtr ? bridge.readString(argsJsonPtr) : '{}';
    const args = parseJsonToToolValues(argsJson);

    // Free the result struct
    m.ccall('rac_tool_call_free', null, ['number'], [resultPtr]);

    return {
      text: cleanText,
      toolCall: {
        toolName,
        arguments: args,
        callId: `call_${callId}`,
      },
    };
  } finally {
    bridge.free(inputPtr);
    m._free(resultPtr);
  }
}

/**
 * TypeScript fallback parser for when WASM doesn't have tool_calling compiled.
 * Handles both default and LFM2 formats.
 */
function parseToolCallTS(llmOutput: string): { text: string; toolCall: ToolCall | null } {
  // Try default format: <tool_call>{"tool":"name","arguments":{...}}</tool_call>
  const defaultMatch = llmOutput.match(/<tool_call>([\s\S]*?)(?:<\/tool_call>|$)/);
  if (defaultMatch) {
    const jsonStr = defaultMatch[1].trim();
    const cleanText = llmOutput.replace(/<tool_call>[\s\S]*?(?:<\/tool_call>|$)/, '').trim();
    try {
      const parsed = JSON.parse(jsonStr);
      const toolName = parsed.tool || parsed.name || parsed.function || '';
      const rawArgs = parsed.arguments || parsed.args || parsed.parameters || {};
      return {
        text: cleanText,
        toolCall: {
          toolName,
          arguments: jsonToToolValues(rawArgs),
          callId: `call_${Date.now()}`,
        },
      };
    } catch {
      // Try to fix common LLM JSON issues (unquoted keys)
      try {
        const fixed = jsonStr.replace(/([{,]\s*)(\w+)\s*:/g, '$1"$2":');
        const parsed = JSON.parse(fixed);
        const toolName = parsed.tool || parsed.name || parsed.function || '';
        const rawArgs = parsed.arguments || parsed.args || parsed.parameters || {};
        return {
          text: cleanText,
          toolCall: {
            toolName,
            arguments: jsonToToolValues(rawArgs),
            callId: `call_${Date.now()}`,
          },
        };
      } catch {
        return { text: llmOutput, toolCall: null };
      }
    }
  }

  // Try LFM2 format: <|tool_call_start|>[func_name(arg="val")]<|tool_call_end|>
  const lfm2Match = llmOutput.match(/<\|tool_call_start\|>\s*\[(\w+)\((.*?)\)\]\s*<\|tool_call_end\|>/);
  if (lfm2Match) {
    const funcName = lfm2Match[1];
    const argsStr = lfm2Match[2];
    const cleanText = llmOutput.replace(/<\|tool_call_start\|>[\s\S]*?<\|tool_call_end\|>/, '').trim();

    // Parse LFM2 arguments: arg1="val1", arg2="val2"
    const args: Record<string, ToolValue> = {};
    const argPattern = /(\w+)="([^"]*)"/g;
    let argMatch;
    while ((argMatch = argPattern.exec(argsStr)) !== null) {
      args[argMatch[1]] = { type: 'string', value: argMatch[2] };
    }

    return {
      text: cleanText,
      toolCall: {
        toolName: funcName,
        arguments: args,
        callId: `call_${Date.now()}`,
      },
    };
  }

  return { text: llmOutput, toolCall: null };
}

/**
 * Format tool definitions into system prompt.
 * Uses C++ when available, falls back to TypeScript.
 */
function formatToolsForPrompt(tools: ToolDefinition[], format: ToolCallFormat = ToolCallFormat.Default): string {
  if (tools.length === 0) return '';

  const toolsJson = serializeToolDefinitions(tools);

  if (hasNativeToolCalling()) {
    const bridge = requireBridge();
    const m = bridge.module;
    const jsonPtr = bridge.allocString(toolsJson);
    const fmtPtr = bridge.allocString(format);
    const outPtrPtr = m._malloc(4);
    m.setValue(outPtrPtr, 0, '*');

    try {
      const rc = m.ccall(
        'rac_tool_call_format_prompt_json_with_format_name', 'number',
        ['number', 'number', 'number'],
        [jsonPtr, fmtPtr, outPtrPtr],
      ) as number;

      if (rc === 0) {
        const outPtr = m.getValue(outPtrPtr, '*') as number;
        if (outPtr) {
          const result = bridge.readString(outPtr);
          m.ccall('rac_free', null, ['number'], [outPtr]);
          return result;
        }
      }
    } finally {
      bridge.free(jsonPtr);
      bridge.free(fmtPtr);
      m._free(outPtrPtr);
    }
  }

  // Fallback: build prompt in TypeScript
  return formatToolsForPromptTS(tools, format);
}

/**
 * Build follow-up prompt after tool execution.
 * Uses C++ when available, falls back to TypeScript.
 */
function buildFollowUpPrompt(
  originalPrompt: string,
  toolsPrompt: string | null,
  toolName: string,
  toolResultJson: string,
  keepToolsAvailable: boolean,
): string {
  if (hasNativeToolCalling()) {
    const bridge = requireBridge();
    const m = bridge.module;
    const promptPtr = bridge.allocString(originalPrompt);
    const toolsPromptPtr = toolsPrompt ? bridge.allocString(toolsPrompt) : 0;
    const namePtr = bridge.allocString(toolName);
    const resultPtr = bridge.allocString(toolResultJson);
    const outPtrPtr = m._malloc(4);
    m.setValue(outPtrPtr, 0, '*');

    try {
      const rc = m.ccall(
        'rac_tool_call_build_followup_prompt', 'number',
        ['number', 'number', 'number', 'number', 'number', 'number'],
        [promptPtr, toolsPromptPtr, namePtr, resultPtr, keepToolsAvailable ? 1 : 0, outPtrPtr],
      ) as number;

      if (rc === 0) {
        const outPtr = m.getValue(outPtrPtr, '*') as number;
        if (outPtr) {
          const result = bridge.readString(outPtr);
          m.ccall('rac_free', null, ['number'], [outPtr]);
          return result;
        }
      }
    } finally {
      bridge.free(promptPtr);
      if (toolsPromptPtr) bridge.free(toolsPromptPtr);
      bridge.free(namePtr);
      bridge.free(resultPtr);
      m._free(outPtrPtr);
    }
  }

  // Fallback: build in TypeScript
  return buildFollowUpPromptTS(originalPrompt, toolName, toolResultJson, keepToolsAvailable);
}

// ---------------------------------------------------------------------------
// TypeScript fallback helpers
// ---------------------------------------------------------------------------

function formatToolsForPromptTS(tools: ToolDefinition[], format: ToolCallFormat): string {
  const toolDescriptions = tools.map((t) => {
    const params = t.parameters.map((p) => {
      const req = p.required !== false ? ' (required)' : ' (optional)';
      return `    - ${p.name} (${p.type}${req}): ${p.description}`;
    }).join('\n');
    return `  ${t.name}: ${t.description}\n    Parameters:\n${params}`;
  }).join('\n\n');

  if (format === ToolCallFormat.LFM2) {
    return `You have access to the following tools:\n\n${toolDescriptions}\n\nTo use a tool, respond with:\n<|tool_call_start|>[tool_name(arg1="value1", arg2="value2")]<|tool_call_end|>\n\nIf no tool is needed, respond normally.`;
  }

  return `You have access to the following tools:\n\n${toolDescriptions}\n\nTo use a tool, respond with:\n<tool_call>{"tool": "tool_name", "arguments": {"arg1": "value1"}}</tool_call>\n\nIf no tool is needed, respond normally.`;
}

function buildFollowUpPromptTS(
  originalPrompt: string,
  toolName: string,
  toolResultJson: string,
  keepToolsAvailable: boolean,
): string {
  if (keepToolsAvailable) {
    return `User: ${originalPrompt}\n\nYou previously used the ${toolName} tool and received:\n${toolResultJson}\n\nBased on this tool result, either use another tool if needed, or provide a helpful response.`;
  }
  return `The user asked: "${originalPrompt}"\n\nYou used the ${toolName} tool and received this data:\n${toolResultJson}\n\nNow provide a helpful, natural response to the user based on this information.`;
}

// ---------------------------------------------------------------------------
// JSON <-> ToolValue conversion
// ---------------------------------------------------------------------------

function parseJsonToToolValues(json: string): Record<string, ToolValue> {
  try {
    const parsed = JSON.parse(json);
    return jsonToToolValues(parsed);
  } catch {
    return {};
  }
}

function jsonToToolValues(obj: Record<string, unknown>): Record<string, ToolValue> {
  const result: Record<string, ToolValue> = {};
  for (const [key, val] of Object.entries(obj)) {
    result[key] = toToolValue(val);
  }
  return result;
}

function toolValueToJson(val: ToolValue): unknown {
  return fromToolValue(val);
}

function toolResultToJsonString(result: Record<string, ToolValue>): string {
  const plain: Record<string, unknown> = {};
  for (const [k, v] of Object.entries(result)) {
    plain[k] = toolValueToJson(v);
  }
  return JSON.stringify(plain);
}

function serializeToolDefinitions(tools: ToolDefinition[]): string {
  return JSON.stringify(tools.map((t) => ({
    name: t.name,
    description: t.description,
    parameters: t.parameters.map((p) => ({
      name: p.name,
      type: p.type,
      description: p.description,
      required: p.required ?? true,
      ...(p.enumValues ? { enumValues: p.enumValues } : {}),
    })),
  })));
}

// ---------------------------------------------------------------------------
// Tool Calling Extension
// ---------------------------------------------------------------------------

class ToolCallingImpl {
  readonly extensionName = 'ToolCalling';
  private toolRegistry = new Map<string, RegisteredTool>();

  /**
   * Register a tool that the LLM can use.
   *
   * @param definition - Tool definition (name, description, parameters)
   * @param executor - Async function that executes the tool
   */
  registerTool(definition: ToolDefinition, executor: ToolExecutor): void {
    this.toolRegistry.set(definition.name, { definition, executor });
    logger.info(`Tool registered: ${definition.name}`);
  }

  /**
   * Unregister a tool by name.
   */
  unregisterTool(name: string): void {
    this.toolRegistry.delete(name);
    logger.info(`Tool unregistered: ${name}`);
  }

  /**
   * Get all registered tool definitions.
   */
  getRegisteredTools(): ToolDefinition[] {
    return Array.from(this.toolRegistry.values()).map((t) => t.definition);
  }

  /**
   * Clear all registered tools.
   */
  clearTools(): void {
    this.toolRegistry.clear();
    logger.info('All tools cleared');
  }

  /**
   * Execute a tool call by looking up the registered executor.
   */
  async executeTool(toolCall: ToolCall): Promise<ToolResult> {
    const registered = this.toolRegistry.get(toolCall.toolName);
    if (!registered) {
      return {
        toolName: toolCall.toolName,
        success: false,
        error: `Unknown tool: ${toolCall.toolName}`,
        callId: toolCall.callId,
      };
    }

    try {
      const result = await registered.executor(toolCall.arguments);
      return {
        toolName: toolCall.toolName,
        success: true,
        result,
        callId: toolCall.callId,
      };
    } catch (err) {
      return {
        toolName: toolCall.toolName,
        success: false,
        error: err instanceof Error ? err.message : String(err),
        callId: toolCall.callId,
      };
    }
  }

  /**
   * Generate a response with tool calling support.
   *
   * Orchestrates: generate -> parse -> execute -> loop
   *
   * @param prompt - The user's prompt
   * @param options - Tool calling options
   * @returns Result with final text, all tool calls, and their results
   */
  async generateWithTools(
    prompt: string,
    options: ToolCallingOptions = {},
  ): Promise<ToolCallingResult> {
    if (!RunAnywhere.isInitialized) {
      throw SDKError.notInitialized();
    }

    if (!TextGeneration.isModelLoaded) {
      throw new SDKError(SDKErrorCode.ModelNotLoaded, 'No LLM model loaded. Call loadModel() first.');
    }

    const maxToolCalls = options.maxToolCalls ?? 5;
    const autoExecute = options.autoExecute ?? true;
    const format: ToolCallFormat = options.format ?? ToolCallFormat.Default;
    const registeredTools = this.getRegisteredTools();
    const tools = options.tools ?? registeredTools;

    // Build tool system prompt
    logger.debug('[generateWithTools] Formatting tools for prompt...');
    let toolsPrompt: string;
    try {
      toolsPrompt = formatToolsForPrompt(tools, format);
      logger.debug(`[generateWithTools] Tools prompt formatted (${toolsPrompt.length} chars)`);
    } catch (fmtErr) {
      logger.error(`[generateWithTools] formatToolsForPrompt failed: ${fmtErr instanceof Error ? fmtErr.message : String(fmtErr)}`);
      throw fmtErr;
    }

    let systemPrompt: string;
    if (options.replaceSystemPrompt && options.systemPrompt) {
      systemPrompt = options.systemPrompt;
    } else if (options.systemPrompt) {
      systemPrompt = `${options.systemPrompt}\n\n${toolsPrompt}`;
    } else {
      systemPrompt = toolsPrompt;
    }

    let fullPrompt = systemPrompt ? `${systemPrompt}\n\nUser: ${prompt}` : prompt;

    const allToolCalls: ToolCall[] = [];
    const allToolResults: ToolResult[] = [];
    let finalText = '';

    for (let i = 0; i < maxToolCalls; i++) {
      // Generate – non-streaming avoids JSPI callback issues with WebGPU
      logger.debug(`[generateWithTools] Round ${i + 1}/${maxToolCalls}, calling collectGeneration...`);
      let genResult: { text: string };
      try {
        genResult = await collectGeneration(fullPrompt, {
          maxTokens: options.maxTokens ?? 1024,
          temperature: options.temperature ?? 0.3,
        });
        logger.debug(`[generateWithTools] Generation complete (${genResult.text.length} chars)`);
      } catch (genErr) {
        logger.error(`[generateWithTools] collectGeneration failed: ${genErr instanceof Error ? `${genErr.message}\nStack: ${genErr.stack}` : String(genErr)}`);
        throw genErr;
      }

      // Parse for tool calls
      const { text, toolCall } = parseToolCall(genResult.text);
      finalText = text;

      if (!toolCall) break;

      allToolCalls.push(toolCall);
      logger.info(`Tool call detected: ${toolCall.toolName}`);

      if (!autoExecute) {
        return {
          text: finalText,
          toolCalls: allToolCalls,
          toolResults: [],
          isComplete: false,
        };
      }

      // Execute tool
      const result = await this.executeTool(toolCall);
      allToolResults.push(result);

      const resultJson = result.success && result.result
        ? toolResultToJsonString(result.result)
        : JSON.stringify({ error: result.error ?? 'Unknown error' });

      logger.info(`Tool ${toolCall.toolName} ${result.success ? 'succeeded' : 'failed'}`);

      // Build follow-up prompt
      fullPrompt = buildFollowUpPrompt(
        prompt,
        options.keepToolsAvailable ? toolsPrompt : null,
        toolCall.toolName,
        resultJson,
        options.keepToolsAvailable ?? false,
      );
    }

    return {
      text: finalText,
      toolCalls: allToolCalls,
      toolResults: allToolResults,
      isComplete: true,
    };
  }

  /**
   * Clean up the tool calling extension (clears all registered tools).
   */
  cleanup(): void {
    this.toolRegistry.clear();
  }

  /**
   * Continue generation after manual tool execution.
   * Use when autoExecute is false.
   */
  async continueWithToolResult(
    previousPrompt: string,
    toolCall: ToolCall,
    toolResult: ToolResult,
    options?: ToolCallingOptions,
  ): Promise<ToolCallingResult> {
    const resultJson = toolResult.success && toolResult.result
      ? toolResultToJsonString(toolResult.result)
      : `Error: ${toolResult.error ?? 'Unknown error'}`;

    const continuedPrompt = `${previousPrompt}\n\nTool Result for ${toolCall.toolName}: ${resultJson}\n\nBased on the tool result, please provide your response:`;

    return this.generateWithTools(continuedPrompt, {
      ...options,
      maxToolCalls: (options?.maxToolCalls ?? 5) - 1,
    });
  }
}

export const ToolCalling = new ToolCallingImpl();
