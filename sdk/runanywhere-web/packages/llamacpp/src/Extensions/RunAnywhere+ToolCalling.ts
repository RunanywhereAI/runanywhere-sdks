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

import { RunAnywhere, SDKError, SDKErrorCode, SDKLogger } from '@runanywhere/web';
import { LlamaCppBridge } from '../Foundation/LlamaCppBridge';
import { TextGeneration } from './RunAnywhere+TextGeneration';
import {
  ToolCallFormat,
  type ToolValue,
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

function requireBridge(): LlamaCppBridge {
  if (!RunAnywhere.isInitialized) throw SDKError.notInitialized();
  return LlamaCppBridge.shared;
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
//
// SINGLE SOURCE OF TRUTH: all tool-call parsing, prompt formatting, and
// follow-up prompt building goes through the commons C ABI (rac_tool_call_*)
// compiled into the WASM module. No TypeScript duplicate of parsing logic.
//
// The C++ tool-calling functions are pure (no imports, no I/O, no suspension
// points), so synchronous ccall is safe on both JIT and JSPI/WebGPU builds.
// ---------------------------------------------------------------------------

/**
 * Assert that the WASM module has the required rac_tool_call_* exports.
 * If this throws, the loaded WASM was built without the tool_calling source
 * compiled in — fix the build, do not silently fall back.
 */
function assertNativeToolCalling(): void {
  const bridge = requireBridge();
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  const mod = bridge.module as any;
  if (typeof mod['_rac_tool_call_parse'] !== 'function') {
    throw new SDKError(
      SDKErrorCode.NotInitialized,
      'rac_tool_call_parse not exported by WASM module - rebuild with tool_calling.cpp compiled in',
    );
  }
}

/**
 * Parse LLM output for tool calls via commons C ABI.
 */
function parseToolCall(llmOutput: string): { text: string; toolCall: ToolCall | null } {
  assertNativeToolCalling();
  return parseToolCallNative(llmOutput);
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
 * Format tool definitions into system prompt via commons C ABI.
 */
function formatToolsForPrompt(tools: ToolDefinition[], format: ToolCallFormat = ToolCallFormat.Default): string {
  if (tools.length === 0) return '';

  assertNativeToolCalling();
  const bridge = requireBridge();
  const m = bridge.module;
  const toolsJson = serializeToolDefinitions(tools);
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

    if (rc !== 0) {
      throw new SDKError(
        SDKErrorCode.BackendError,
        `rac_tool_call_format_prompt_json_with_format_name failed with code ${rc}`,
      );
    }
    const outPtr = m.getValue(outPtrPtr, '*') as number;
    if (!outPtr) return '';
    const result = bridge.readString(outPtr);
    m.ccall('rac_free', null, ['number'], [outPtr]);
    return result;
  } finally {
    bridge.free(jsonPtr);
    bridge.free(fmtPtr);
    m._free(outPtrPtr);
  }
}

/**
 * Build follow-up prompt after tool execution via commons C ABI.
 */
function buildFollowUpPrompt(
  originalPrompt: string,
  toolsPrompt: string | null,
  toolName: string,
  toolResultJson: string,
  keepToolsAvailable: boolean,
): string {
  assertNativeToolCalling();
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

    if (rc !== 0) {
      throw new SDKError(
        SDKErrorCode.BackendError,
        `rac_tool_call_build_followup_prompt failed with code ${rc}`,
      );
    }
    const outPtr = m.getValue(outPtrPtr, '*') as number;
    if (!outPtr) return '';
    const result = bridge.readString(outPtr);
    m.ccall('rac_free', null, ['number'], [outPtr]);
    return result;
  } finally {
    bridge.free(promptPtr);
    if (toolsPromptPtr) bridge.free(toolsPromptPtr);
    bridge.free(namePtr);
    bridge.free(resultPtr);
    m._free(outPtrPtr);
  }
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
