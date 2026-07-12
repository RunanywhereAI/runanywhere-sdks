/**
 * RunAnywhere+ToolCalling.ts
 *
 * Tool calling namespace — mirrors Swift's `RunAnywhere+ToolCalling.swift`.
 * Re-exports canonical proto-ts types + provides `RunAnywhere.toolCalling.*` surface.
 *
 * pass2-syn-026: the orchestration loop lives in commons. The Web SDK
 * delegates `generateWithTools` to `rac_tool_calling_session_create_proto` +
 * `rac_tool_calling_session_step_with_result_proto` so commons drives
 * generate -> parse -> validate -> follow-up, and TS only owns the executor
 * closure (which needs to await async JS APIs). Mirrors Kotlin's
 * `ToolCallingOrchestrator.jvmAndroid.kt` session-based delegation.
 */

export type {
  ToolCallingOptions,
  ToolDefinition,
  ToolCall,
  ToolResult,
  ToolCallingResult,
  ToolCallValidationRequest,
  ToolCallValidationResult,
  ToolParseRequest,
  ToolParseResult,
  ToolPromptFormatRequest,
  ToolPromptFormatResult,
  ToolValue,
} from '@runanywhere/proto-ts/tool_calling';

export {
  ToolCallFormatName,
  ToolChoiceMode,
  ToolParameterType,
} from '@runanywhere/proto-ts/tool_calling';

import {
  ToolCallValidationRequest as ToolCallValidationRequestMessage,
  ToolCallValidationResult as ToolCallValidationResultMessage,
  ToolCallingOptions as ToolCallingOptionsMessage,
  ToolCallingResult as ToolCallingResultMessage,
  ToolCallingSessionCreateRequest as ToolCallingSessionCreateRequestMessage,
  ToolCallingSessionEvent as ToolCallingSessionEventMessage,
  ToolCallingSessionStepWithResultRequest as ToolCallingSessionStepWithResultRequestMessage,
  ToolCallFormatName,
  ToolChoiceMode,
  ToolParseRequest as ToolParseRequestMessage,
  ToolParseResult as ToolParseResultMessage,
  ToolPromptFormatRequest as ToolPromptFormatRequestMessage,
  ToolPromptFormatResult as ToolPromptFormatResultMessage,
  ToolResult as ToolResultMessage,
  ToolValue as ToolValueMessage,
  ToolValueJSON as ToolValueJSONMessage,
  type ToolValue,
  type ToolCall,
  type ToolCallValidationRequest,
  type ToolCallValidationResult,
  type ToolCallingOptions,
  type ToolCallingResult,
  type ToolCallingSessionEvent,
  type ToolDefinition,
  type ToolParseRequest,
  type ToolParseResult,
  type ToolPromptFormatRequest,
  type ToolPromptFormatResult,
  type ToolResult,
} from '@runanywhere/proto-ts/tool_calling';
import type { LLMGenerationOptions, LLMGenerationResult } from '@runanywhere/proto-ts/llm_options';
import { SDKError as SDKErrorMessage } from '@runanywhere/proto-ts/errors';
import { ProtoErrorCode, SDKException } from '../../Foundation/SDKException.js';
import { SDKLogger } from '../../Foundation/SDKLogger.js';
import { ProtoWasmBridge } from '../../runtime/ProtoWasm.js';
import { wasmUint64ToSafeNumber } from '../../runtime/WasmInt64.js';
import {
  getModuleForCapability,
  type EmscriptenRunanywhereModule,
} from '../../runtime/EmscriptenModule.js';
import { callEmscriptenAsyncNumber } from '../../runtime/EmscriptenAsync.js';
import { TextGeneration } from './RunAnywhere+TextGeneration.js';

const logger = new SDKLogger('ToolCalling');

type ToolCallingExport =
  | '_rac_tool_call_parse_proto'
  | '_rac_tool_call_format_prompt_proto'
  | '_rac_tool_call_validate_proto'
  | '_rac_tool_calling_session_create_proto'
  | '_rac_tool_calling_session_step_with_result_proto'
  | '_rac_tool_calling_session_destroy_proto'
  | '_rac_tool_calling_session_cancel_proto'
  | '_rac_tool_value_to_json_proto'
  | '_rac_tool_value_from_json_proto';

type RegisteredTool = {
  definition: ToolDefinition;
  executor: ToolExecutor;
};

export type ToolCallingGenerationOptions = Omit<Partial<LLMGenerationOptions>, 'toolCalling'> & {
  toolCalling?: Partial<ToolCallingOptions>;
};

/**
 * Extra options accepted by [generateWithTools]. Mirrors Swift's
 * `generateWithTools(prompt:options:toolOptions:...)` two-channel shape
 * (RunAnywhere+ToolCalling.swift:250-257) the same way the RN SDK does.
 */
export interface GenerateWithToolsOptions {
  signal?: AbortSignal;
  /**
   * LLM generation options channel — Swift parity
   * (`generateWithTools(prompt:options:toolOptions:...)`): tool options that
   * are unset fall back to these, and `topP` comes from here exclusively.
   * Defaults mirror Swift `RALLMGenerationOptions.defaults()`
   * (maxTokens 100, temperature 0.8, topP 1.0).
   */
  llmOptions?: Partial<
    Pick<
      LLMGenerationOptions,
      'maxTokens' | 'temperature' | 'topP' | 'systemPrompt' | 'disableThinking'
    >
  >;
  /**
   * Swift parity: when omitted the proto field stays UNSET so commons applies
   * its documented default (true). Hosts that delegate validation to their
   * executor pass `false`.
   */
  validateCalls?: boolean;
}

/**
 * Function type for JS-native tool executors — Swift parity:
 * `ToolExecutor = ([String: RAToolValue]) async throws -> [String: RAToolValue]`
 * (ToolCallingTypes.swift:19). Receives the parsed `argumentsJson` object and
 * returns the result object the SDK serializes into `resultJson`; throw to
 * surface a failure.
 */
export type ToolExecutor = (
  args: Record<string, ToolValue>,
) => Record<string, ToolValue> | Promise<Record<string, ToolValue>>;

const registeredTools = new Map<string, RegisteredTool>();

/**
 * Resolve the canonical per-turn tool-call cap.
 */
function maxToolCallCount(options: ToolCallingOptions): number {
  const explicit = options.maxToolCalls ?? 0;
  return explicit > 0 ? explicit : 5;
}

/** Canonical ID carried by ToolCall.id. */
function toolCallIdentifier(toolCall: ToolCall): string {
  return toolCall.id;
}

function buildToolCallingOptions(
  tools: ToolDefinition[],
  options: ToolCallingGenerationOptions = {},
): ToolCallingOptions {
  const overrides = options.toolCalling ?? {};
  return ToolCallingOptionsMessage.fromPartial({
    tools: overrides.tools ?? tools,
    maxToolCalls: overrides.maxToolCalls ?? 5,
    autoExecute: overrides.autoExecute ?? true,
    temperature: overrides.temperature ?? options.temperature,
    maxTokens: overrides.maxTokens ?? options.maxTokens,
    systemPrompt: overrides.systemPrompt ?? options.systemPrompt,
    replaceSystemPrompt: overrides.replaceSystemPrompt ?? false,
    keepToolsAvailable: overrides.keepToolsAvailable ?? false,
    format: overrides.format ?? ToolCallFormatName.TOOL_CALL_FORMAT_NAME_JSON,
    toolChoice: overrides.toolChoice ?? ToolChoiceMode.TOOL_CHOICE_MODE_AUTO,
    forcedToolName: overrides.forcedToolName,
    requireJsonArguments: overrides.requireJsonArguments ?? false,
  });
}

function buildPromptOptions(
  tools: ToolDefinition[],
  options: Partial<ToolCallingOptions> = {},
): ToolCallingOptions {
  return ToolCallingOptionsMessage.fromPartial({
    ...options,
    tools: options.tools ?? tools,
    maxToolCalls: options.maxToolCalls ?? 5,
    autoExecute: options.autoExecute ?? true,
    format: options.format ?? ToolCallFormatName.TOOL_CALL_FORMAT_NAME_JSON,
    toolChoice: options.toolChoice ?? ToolChoiceMode.TOOL_CHOICE_MODE_AUTO,
    // pass2-syn-006-followup-web: explicitly propagate forcedToolName so that
    // tool_choice=SPECIFIC reaches the commons parse/format/validate primitives
    // (and any future session/run-loop ABI). Spread alone is not sufficient
    // when callers pass undefined keys.
    forcedToolName: options.forcedToolName,
    requireJsonArguments: options.requireJsonArguments ?? false,
  });
}

function missingToolCallingExports(
  module: EmscriptenRunanywhereModule,
  names: ToolCallingExport[],
): string[] {
  return names.filter((name) => typeof module[name] !== 'function');
}

function requireToolCallingModule(
  feature: string,
  names: ToolCallingExport[],
): EmscriptenRunanywhereModule {
  const module = getModuleForCapability('tool-calling');
  if (!module) {
    throw SDKException.backendNotAvailable(
      feature,
      'No backend that exports rac_tool_call_*_proto / rac_tool_calling_session_*_proto is registered. ' +
      'Call LlamaCPP.register() (or another tool-calling-providing backend) first.',
    );
  }

  const missing = [
    ...missingToolCallingExports(module, names),
    ...new ProtoWasmBridge(module, logger).missingProtoBufferExports(),
  ];
  if (missing.length > 0) {
    throw SDKException.backendNotAvailable(
      feature,
      `This Web WASM build does not export ${missing.join(', ')}.`,
    );
  }
  return module;
}

function readToolParse(request: ToolParseRequest): ToolParseResult {
  const module = requireToolCallingModule('toolCalling.parse', [
    '_rac_tool_call_parse_proto',
  ]);
  const result = new ProtoWasmBridge(module, logger).withEncodedRequest(
    ToolParseRequestMessage.fromPartial(request),
    ToolParseRequestMessage,
    ToolParseResultMessage,
    (requestPtr, requestSize, outResult) => (
      module._rac_tool_call_parse_proto!(requestPtr, requestSize, outResult)
    ),
    'rac_tool_call_parse_proto',
  );
  if (!result) {
    throw SDKException.backendNotAvailable(
      'toolCalling.parse',
      'rac_tool_call_parse_proto returned no ToolParseResult bytes.',
    );
  }
  return result;
}

function readToolPromptFormat(
  request: ToolPromptFormatRequest,
): ToolPromptFormatResult {
  const module = requireToolCallingModule('toolCalling.formatPrompt', [
    '_rac_tool_call_format_prompt_proto',
  ]);
  const result = new ProtoWasmBridge(module, logger).withEncodedRequest(
    ToolPromptFormatRequestMessage.fromPartial(request),
    ToolPromptFormatRequestMessage,
    ToolPromptFormatResultMessage,
    (requestPtr, requestSize, outResult) => (
      module._rac_tool_call_format_prompt_proto!(requestPtr, requestSize, outResult)
    ),
    'rac_tool_call_format_prompt_proto',
  );
  if (!result) {
    throw SDKException.backendNotAvailable(
      'toolCalling.formatPrompt',
      'rac_tool_call_format_prompt_proto returned no ToolPromptFormatResult bytes.',
    );
  }
  if (result.errorCode !== 0) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_BACKEND_ERROR,
      'Tool prompt formatting failed',
      result.errorMessage,
    );
  }
  return result;
}

function readToolCallValidation(
  request: ToolCallValidationRequest,
): ToolCallValidationResult {
  const module = requireToolCallingModule('toolCalling.validateCall', [
    '_rac_tool_call_validate_proto',
  ]);
  const result = new ProtoWasmBridge(module, logger).withEncodedRequest(
    ToolCallValidationRequestMessage.fromPartial(request),
    ToolCallValidationRequestMessage,
    ToolCallValidationResultMessage,
    (requestPtr, requestSize, outResult) => (
      module._rac_tool_call_validate_proto!(requestPtr, requestSize, outResult)
    ),
    'rac_tool_call_validate_proto',
  );
  if (!result) {
    throw SDKException.backendNotAvailable(
      'toolCalling.validateCall',
      'rac_tool_call_validate_proto returned no ToolCallValidationResult bytes.',
    );
  }
  return result;
}

/**
 * ToolValue -> JSON via commons (`rac_tool_value_to_json_proto`) — Swift
 * parity: `RAToolValue.toJSONString()` (ToolCallingTypes.swift). The
 * recursive walk lives in C++ so every SDK shares one source of truth.
 */
function toolValueToJSONString(value: ToolValue): string | null {
  const module = requireToolCallingModule('toolCalling.toolValueToJSON', [
    '_rac_tool_value_to_json_proto',
  ]);
  const result = new ProtoWasmBridge(module, logger).withEncodedRequest(
    ToolValueMessage.fromPartial(value),
    ToolValueMessage,
    ToolValueJSONMessage,
    (requestPtr, requestSize, outResult) => (
      module._rac_tool_value_to_json_proto!(requestPtr, requestSize, outResult)
    ),
    'rac_tool_value_to_json_proto',
  );
  return result?.json ?? null;
}

/**
 * Parse a JSON object string into a ToolValue field map via commons
 * (`rac_tool_value_from_json_proto`) — Swift parity:
 * `RAToolValue.parseObjectJSON` (ToolCallingTypes.swift:94). Throws when the
 * input is not valid JSON or the root is not an object.
 */
function parseObjectJSON(json: string): Record<string, ToolValue> {
  const module = requireToolCallingModule('toolCalling.toolValueFromJSON', [
    '_rac_tool_value_from_json_proto',
  ]);
  const value = new ProtoWasmBridge(module, logger).withEncodedRequest(
    ToolValueJSONMessage.fromPartial({ json }),
    ToolValueJSONMessage,
    ToolValueMessage,
    (requestPtr, requestSize, outResult) => (
      module._rac_tool_value_from_json_proto!(requestPtr, requestSize, outResult)
    ),
    'rac_tool_value_from_json_proto',
  );
  if (!value) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_INVALID_INPUT,
      'Failed to parse tool arguments JSON',
      'rac_tool_value_from_json_proto returned no ToolValue bytes.',
    );
  }
  if (!value.objectValue) {
    throw SDKException.fromCode(
      -ProtoErrorCode.ERROR_CODE_INVALID_INPUT,
      'ToolCall.argumentsJson must decode to a JSON object',
    );
  }
  return value.objectValue.fields;
}

/** Swift parity: `RAToolValue.jsonString(from:)` (ToolCallingTypes.swift:112). */
function jsonStringFromObject(object: Record<string, ToolValue>): string {
  // Empty object short-circuits to the canonical "{}" the C ABI would emit,
  // keeping failure-path results independent of the WASM bridge.
  if (Object.keys(object).length === 0) return '{}';
  return toolValueToJSONString(
    ToolValueMessage.fromPartial({ objectValue: { fields: object } }),
  ) ?? '{}';
}

/**
 * Swift parity: `makeToolResult` (RunAnywhere+ToolCalling.swift:463) —
 * `resultJson` is the canonical wire shape; the typed result map is
 * serialized through commons.
 */
function makeToolResult(params: {
  name: string;
  success: boolean;
  result?: Record<string, ToolValue>;
  error?: string;
  toolCallId?: string;
  startedAtMs: number;
}): ToolResult {
  return ToolResultMessage.fromPartial({
    name: params.name,
    success: params.success,
    resultJson: jsonStringFromObject(params.result ?? {}),
    error: params.error,
    toolCallId: params.toolCallId,
    startedAtMs: params.startedAtMs,
    completedAtMs: Date.now(),
  });
}

/**
 * Build the ToolCallingSessionCreateRequest proto consumed by
 * `_rac_tool_calling_session_create_proto`. Mirrors Swift's
 * `makeRunLoopRequest` (RunAnywhere+ToolCalling.swift:491-548) so the C++
 * loop receives identical input regardless of SDK: tool options take
 * precedence, unset values fall back to the LLM options channel, whose
 * defaults are Swift's `RALLMGenerationOptions.defaults()`
 * (maxTokens 100, temperature 0.8, topP 1.0).
 */
function buildSessionCreateRequest(
  prompt: string,
  tools: ToolDefinition[],
  effectiveOptions: ToolCallingOptions,
  extra: GenerateWithToolsOptions = {},
): Uint8Array {
  const llm = extra.llmOptions;
  const toolMaxTokens = effectiveOptions.maxTokens;
  const request = ToolCallingSessionCreateRequestMessage.fromPartial({
    prompt,
    maxTokens:
      toolMaxTokens !== undefined && toolMaxTokens > 0
        ? toolMaxTokens
        : (llm?.maxTokens ?? 100),
    temperature: effectiveOptions.temperature ?? llm?.temperature ?? 0.8,
    // topP has no slot on ToolCallingOptions — Swift reads it from the LLM
    // options channel exclusively (RunAnywhere+ToolCalling.swift:516).
    topP: llm?.topP ?? 1.0,
    systemPrompt: effectiveOptions.systemPrompt || llm?.systemPrompt || '',
    tools,
    format:
      effectiveOptions.format ?? ToolCallFormatName.TOOL_CALL_FORMAT_NAME_JSON,
    maxToolCalls: Math.max(maxToolCallCount(effectiveOptions), 0),
    keepToolsAvailable: effectiveOptions.keepToolsAvailable ?? false,
    // `validate_calls` is `optional bool` on the proto. Leave it UNSET unless
    // the caller chose, so commons applies its documented default (true) —
    // parity with Swift makeRunLoopRequest (RunAnywhere+ToolCalling.swift:528-537).
    validateCalls: extra.validateCalls,
    // pass2-syn-006-followup-web: thread the OpenAI-style tool_choice /
    // forced_tool_name knobs into the canonical request envelope (idl
    // fields 7/8). Commons build_options_snapshot copies them onto every
    // synthesized ToolCallingOptions before format/validate proto calls.
    // TOOL_CHOICE_MODE_UNSPECIFIED = 0, so the truthy check excludes both
    // undefined and the explicit "unspecified" sentinel.
    toolChoice: effectiveOptions.toolChoice
      ? effectiveOptions.toolChoice
      : undefined,
    forcedToolName:
      effectiveOptions.forcedToolName && effectiveOptions.forcedToolName.length > 0
        ? effectiveOptions.forcedToolName
        : undefined,
    // Suppress thinking when EITHER options surface asks for it — Swift:
    // `toolOptions.disableThinking || options.disableThinking`
    // (RunAnywhere+ToolCalling.swift:548).
    disableThinking:
      (effectiveOptions.disableThinking ?? false) || (llm?.disableThinking ?? false),
    autoExecute: effectiveOptions.autoExecute ?? true,
    replaceSystemPrompt: effectiveOptions.replaceSystemPrompt ?? false,
    requireJsonArguments: effectiveOptions.requireJsonArguments ?? false,
  });
  return ToolCallingSessionCreateRequestMessage.encode(request).finish();
}

/**
 * Result of attempting to decode a ToolCallingSessionEvent emitted by the
 * commons callback. pass3-syn-152: a `null` return previously silently dropped
 * decode failures, which then surfaced as a misleading "session stalled"
 * error in the drain loop. The discriminated shape lets the caller propagate
 * a structured error pointing at the real cause (proto decode break) instead
 * of the symptom (no terminal event observed).
 */
type SessionEventDecode =
  | { kind: 'event'; event: ToolCallingSessionEvent }
  | { kind: 'decode-error'; error: Error }
  | { kind: 'empty' };

function decodeSessionEvent(
  module: EmscriptenRunanywhereModule,
  bytesPtr: number,
  size: number,
): SessionEventDecode {
  if (!bytesPtr || size <= 0) return { kind: 'empty' };
  const slice = module.HEAPU8.slice(bytesPtr, bytesPtr + size);
  try {
    return { kind: 'event', event: ToolCallingSessionEventMessage.decode(slice) };
  } catch (err) {
    const error = err instanceof Error ? err : new Error(String(err));
    logger.warning(
      `failed to decode ToolCallingSessionEvent: ${error.message}`,
    );
    return { kind: 'decode-error', error };
  }
}

function encodeStepRequest(
  sessionHandle: bigint,
  toolCallId: string,
  resultJson: string,
  error?: string,
): Uint8Array {
  const message = ToolCallingSessionStepWithResultRequestMessage.fromPartial({
    sessionHandle: wasmUint64ToSafeNumber(sessionHandle, 'tool-calling session handle'),
    toolCallId,
    resultJson,
    error,
  });
  return ToolCallingSessionStepWithResultRequestMessage.encode(message).finish();
}

export const ToolCalling = {
  supportsProtoToolCalling(): boolean {
    const module = getModuleForCapability('tool-calling');
    if (!module) return false;
    return missingToolCallingExports(module, [
      '_rac_tool_call_parse_proto',
      '_rac_tool_call_format_prompt_proto',
      '_rac_tool_call_validate_proto',
    ]).length === 0 && new ProtoWasmBridge(module, logger).hasProtoBufferExports();
  },

  registerTool(definition: ToolDefinition, executor: ToolExecutor): void {
    registeredTools.set(definition.name, { definition, executor });
  },

  unregisterTool(name: string): void {
    registeredTools.delete(name);
  },

  getRegisteredTools(): ToolDefinition[] {
    return Array.from(registeredTools.values()).map(({ definition }) => definition);
  },

  clearTools(): void {
    registeredTools.clear();
  },

  async executeTool(toolCall: ToolCall): Promise<ToolResult> {
    const startedAtMs = Date.now();
    const toolCallId = toolCallIdentifier(toolCall);
    const registered = registeredTools.get(toolCall.name);
    if (!registered) {
      return makeToolResult({
        name: toolCall.name,
        success: false,
        error: `Unknown tool: ${toolCall.name}`,
        toolCallId,
        startedAtMs,
      });
    }

    let parsedArgs: Record<string, ToolValue>;
    try {
      parsedArgs = parseObjectJSON(toolCall.argumentsJson);
    } catch (error) {
      // Swift parity (RunAnywhere+ToolCalling.swift:171-184): surface bad-JSON
      // arguments as success=false so callers can distinguish parse errors
      // from genuine empty-argument calls.
      return makeToolResult({
        name: toolCall.name,
        success: false,
        error: `Failed to parse tool arguments: ${error instanceof Error ? error.message : String(error)}`,
        toolCallId,
        startedAtMs,
      });
    }

    try {
      return makeToolResult({
        name: toolCall.name,
        success: true,
        result: await registered.executor(parsedArgs),
        toolCallId,
        startedAtMs,
      });
    } catch (error) {
      return makeToolResult({
        name: toolCall.name,
        success: false,
        error: error instanceof Error ? error.message : String(error),
        toolCallId,
        startedAtMs,
      });
    }
  },

  parse(request: ToolParseRequest): ToolParseResult {
    return readToolParse(request);
  },

  parseToolCall(text: string, options?: Partial<ToolCallingOptions>): ToolParseResult {
    return readToolParse({
      text,
      options: options ? ToolCallingOptionsMessage.fromPartial(options) : undefined,
    });
  },

  formatPrompt(request: ToolPromptFormatRequest): ToolPromptFormatResult {
    return readToolPromptFormat(request);
  },

  validateCall(request: ToolCallValidationRequest): ToolCallValidationResult {
    return readToolCallValidation(request);
  },

  validateToolCall(
    toolCall: ToolCall,
    options: Partial<ToolCallingOptions> = {},
  ): ToolCallValidationResult {
    const tools = options.tools && options.tools.length > 0
      ? options.tools
      : this.getRegisteredTools();
    return readToolCallValidation({
      toolCall,
      options: buildPromptOptions(tools, options),
    });
  },

  formatToolsForPrompt(
    tools?: ToolDefinition[],
    options: Partial<ToolCallingOptions> = {},
  ): string {
    const effectiveTools = tools ?? this.getRegisteredTools();
    if (effectiveTools.length === 0) return '';
    return readToolPromptFormat({
      userPrompt: '',
      options: buildPromptOptions(effectiveTools, options),
      toolResults: [],
    }).formattedPrompt;
  },

  buildInitialPrompt(
    prompt: string,
    tools?: ToolDefinition[],
    options: Partial<ToolCallingOptions> = {},
  ): string {
    const effectiveTools = tools ?? this.getRegisteredTools();
    return readToolPromptFormat({
      userPrompt: prompt,
      options: buildPromptOptions(effectiveTools, options),
      toolResults: [],
    }).formattedPrompt;
  },

  buildFollowupPrompt(
    prompt: string,
    toolResult: ToolResult,
    options: Partial<ToolCallingOptions> = {},
  ): string {
    return readToolPromptFormat({
      userPrompt: prompt,
      options: buildPromptOptions(options.tools ?? this.getRegisteredTools(), options),
      toolResults: [toolResult],
    }).formattedPrompt;
  },

  async generate(
    prompt: string,
    tools: ToolDefinition[],
    options?: ToolCallingGenerationOptions,
  ): Promise<LLMGenerationResult> {
    return TextGeneration.generate({
      ...options,
      prompt,
      toolCalling: buildToolCallingOptions(tools, options),
    });
  },

  /**
   * pass2-syn-026: delegates the generate -> parse -> validate -> execute ->
   * follow-up loop to commons via the session ABI (`rac_tool_calling_session_*`).
   * The Web SDK only owns the executor closure (which is async, so we cannot
   * use the synchronous `rac_tool_calling_run_loop_proto` callback the way
   * Swift does). Events flow out through an `addFunction` trampoline; tool
   * results flow back in via `session_step_with_result_proto`. Mirrors
   * Kotlin's `ToolCallingOrchestrator.jvmAndroid.kt` session-based delegation.
   *
   * The TS side is now a thin event-pump driver — no manual parse loop, no
   * manual buildFollowupPrompt walk, no JS-side iteration cap. Every loop
   * semantic (validation, max_tool_calls, format selection, validation policy
   * on the W1 tool_choice=NONE fix) is owned by `tool_calling_run_loop.cpp` /
   * `tool_calling_session.cpp`.
   */
  async generateWithTools(
    prompt: string,
    options: Partial<ToolCallingOptions> = {},
    extra: GenerateWithToolsOptions = {},
  ): Promise<ToolCallingResult> {
    // pass3-syn-153: short-circuit when the AbortSignal is already aborted
    // BEFORE allocating the trampoline / handle slot or calling commons.
    // DOM AbortSignal does NOT re-fire the 'abort' event on a signal that is
    // already aborted, and `_rac_tool_calling_session_create_proto` runs an
    // entire `run_generate_loop` (one full LLM generate, multi-second on
    // realistic models) before its Asyncify-aware call resolves. Catching that
    // state here mirrors Swift's eager `Task.checkCancellation()` pattern and
    // avoids entering the Asyncify-backed generate cycle at all.
    if (extra.signal?.aborted) {
      throw SDKException.fromCode(
        -ProtoErrorCode.ERROR_CODE_GENERATION_CANCELLED,
        'Tool-calling generation cancelled',
        'AbortSignal was already aborted before generateWithTools was invoked',
      );
    }

    const tools = options.tools && options.tools.length > 0
      ? options.tools
      : this.getRegisteredTools();
    const effectiveOptions = buildPromptOptions(tools, options);

    const module = requireToolCallingModule('toolCalling.generateWithTools', [
      '_rac_tool_calling_session_create_proto',
      '_rac_tool_calling_session_step_with_result_proto',
      '_rac_tool_calling_session_destroy_proto',
    ]);
    if (!module.addFunction || !module.removeFunction || !module._malloc || !module._free) {
      throw SDKException.backendNotAvailable(
        'toolCalling.generateWithTools',
        'WASM module is missing addFunction/removeFunction or heap helpers required for the tool-calling session bridge.',
      );
    }

    const bridge = new ProtoWasmBridge(module, logger);
    const requestBytes = buildSessionCreateRequest(prompt, tools, effectiveOptions, extra);

    let sessionHandle = 0n;
    let cancelDispatched = false;
    const dispatchCancel = () => {
      if (
        sessionHandle !== 0n &&
        !cancelDispatched &&
        typeof module._rac_tool_calling_session_cancel_proto === 'function'
      ) {
        try {
          module._rac_tool_calling_session_cancel_proto(sessionHandle);
          cancelDispatched = true;
        } catch (err) {
          logger.warning(
            `session_cancel_proto failed: ${err instanceof Error ? err.message : String(err)}`,
          );
        }
      }
    };

    // Event queue: the C session callback fires before each awaited
    // session_create_proto / session_step_with_result_proto invocation
    // resolves. WebGPU may unwind either export through Asyncify, so the
    // callback and request heap storage must remain live until the matching
    // ccall({ async: true }) promise settles.
    const events: ToolCallingSessionEvent[] = [];
    // pass3-syn-152: latch the first decode failure so the drain loop can
    // surface a structured error (instead of falling through to the
    // misleading "session stalled" branch). Decode failures are rare but
    // when they happen the diagnostic should point at the actual cause.
    let decodeFailure: Error | null = null;
    const callbackPtr = module.addFunction((bytesPtr: number, size: number /*, userData */) => {
      const decoded = decodeSessionEvent(module, bytesPtr, size);
      if (decoded.kind === 'event') {
        events.push(decoded.event);
      } else if (decoded.kind === 'decode-error' && !decodeFailure) {
        decodeFailure = decoded.error;
      }
    }, 'viii');
    const handleCallbackPtr = module.addFunction((handle: bigint /*, userData */) => {
      sessionHandle = handle;
      // If abort won the narrow window between the eager check and handle
      // publication, wait until this callback returns before entering the C
      // API again. Asyncify yields the initial generation back to the event
      // loop, where this microtask can dispatch cancellation.
      if (extra.signal?.aborted) {
        queueMicrotask(dispatchCancel);
      }
    }, 'vji');

    // pass2-syn-007: wire AbortSignal into _rac_tool_calling_session_cancel_proto.
    // Asyncify yields to the browser event loop while an awaited native call
    // is in flight. Once commons has published the session handle, abort can
    // therefore latch cancellation during a later step continuation;
    // backend compute may use its own workers internally.
    const onAbort = () => {
      dispatchCancel();
    };
    extra.signal?.addEventListener('abort', onAbort);
    const cleanup = () => {
      extra.signal?.removeEventListener('abort', onAbort);
      try {
        if (sessionHandle !== 0n) {
          module._rac_tool_calling_session_destroy_proto!(sessionHandle);
        }
      } catch (err) {
        logger.warning(
          `session_destroy_proto failed: ${err instanceof Error ? err.message : String(err)}`,
        );
      }
      module.removeFunction!(callbackPtr);
      module.removeFunction!(handleCallbackPtr);
    };

    try {
      const createRc = await bridge.withHeapBytesAsync(requestBytes, (ptr, size) => (
        callEmscriptenAsyncNumber(
          module,
          'rac_tool_calling_session_create_proto',
          ['number', 'number', 'number', 'number', 'number', 'number'],
          [ptr, size, callbackPtr, 0, handleCallbackPtr, 0],
          () => module._rac_tool_calling_session_create_proto!(
            ptr,
            size,
            callbackPtr,
            0,
            handleCallbackPtr,
            0,
          ),
        )
      ));
      if (createRc !== 0) {
        throw SDKException.fromCode(
          -ProtoErrorCode.ERROR_CODE_BACKEND_ERROR,
          'rac_tool_calling_session_create_proto failed',
          `rc=${createRc}`,
        );
      }
      if (sessionHandle === 0n) {
        throw SDKException.fromCode(
          -ProtoErrorCode.ERROR_CODE_BACKEND_ERROR,
          'rac_tool_calling_session_create_proto failed',
          'commons returned success without publishing a session handle',
        );
      }
      // pass2-syn-007: if the AbortSignal already fired before the session
      // handle was published, fan that cancel through to commons now.
      if (extra.signal?.aborted) {
        onAbort();
        throw SDKException.fromCode(
          -ProtoErrorCode.ERROR_CODE_GENERATION_CANCELLED,
          'Tool-calling generation cancelled',
          'AbortSignal fired while the initial tool-calling generation was in flight',
        );
      }

      // Pump the event queue. Commons fires either:
      //  - final_result    -> done
      //  - error_bytes     -> error
      //  - tool_call       -> execute in TS, feed back via step_with_result_proto
      // Once each awaited create/step call resolves, its buffered events fully
      // describe the next session state.
      while (true) {
        const drained = events.splice(0, events.length);
        let pendingToolCall: ToolCall | null = null;
        let finalResult: ToolCallingResult | null = null;
        let errorBytes: Uint8Array | null = null;
        for (const event of drained) {
          if (event.finalResult) {
            finalResult = event.finalResult;
          } else if (event.errorBytes && event.errorBytes.length > 0) {
            errorBytes = event.errorBytes;
          } else if (event.toolCall) {
            pendingToolCall = event.toolCall;
          }
        }

        if (finalResult) {
          return finalResult;
        }
        if (errorBytes) {
          let decodedError: ReturnType<typeof SDKErrorMessage.decode> | undefined;
          try {
            decodedError = SDKErrorMessage.decode(errorBytes);
          } catch {
            // Preserve the protocol-level fallback for malformed custom builds.
          }
          if (decodedError?.message) throw new SDKException(decodedError);
          throw SDKException.fromCode(
            -ProtoErrorCode.ERROR_CODE_BACKEND_ERROR,
            'Tool-calling session failed',
            `commons error_bytes (${errorBytes.length}B)`,
          );
        }
        if (!pendingToolCall) {
          // pass3-syn-152: if the session callback observed at least one
          // proto-decode failure since the last drain, surface that as the
          // root cause — the "stalled" symptom is downstream of the dropped
          // event. Without this, telemetry would chase the C++
          // session state machine for what is actually a JS-side decode
          // break (e.g. a backwards-incompatible proto rev in a custom
          // build, or an addFunction wiring bug).
          if (decodeFailure) {
            throw SDKException.fromCode(
              -ProtoErrorCode.ERROR_CODE_BACKEND_ERROR,
              'Tool-calling session event decode failed',
              `failed to decode ToolCallingSessionEvent: ${(decodeFailure as Error).message}`,
            );
          }
          // No tool call and no final/error event — commons should always emit
          // one of these terminal events when the awaited native step resolves.
          // Treat as an internal protocol violation.
          throw SDKException.fromCode(
            -ProtoErrorCode.ERROR_CODE_BACKEND_ERROR,
            'Tool-calling session stalled',
            'commons returned no event after step_with_result',
          );
        }

        // Execute the tool in TS (async).
        const toolResult = await this.executeTool(pendingToolCall);
        const toolCallId = toolResult.toolCallId || toolCallIdentifier(pendingToolCall);
        const stepBytes = encodeStepRequest(
          sessionHandle,
          toolCallId,
          toolResult.resultJson ?? '',
          toolResult.success ? undefined : toolResult.error,
        );
        const stepRc = await bridge.withHeapBytesAsync(stepBytes, (ptr, size) => (
          callEmscriptenAsyncNumber(
            module,
            'rac_tool_calling_session_step_with_result_proto',
            ['number', 'number'],
            [ptr, size],
            () => module._rac_tool_calling_session_step_with_result_proto!(ptr, size),
          )
        ));
        if (stepRc !== 0) {
          throw SDKException.fromCode(
            -ProtoErrorCode.ERROR_CODE_BACKEND_ERROR,
            'rac_tool_calling_session_step_with_result_proto failed',
            `rc=${stepRc}`,
          );
        }
        // Loop back; the step call has refilled `events`.
      }
    } finally {
      // Drop unused parse exports reference so the function isn't tree-shaken
      // out of the typed module signature in non-session paths.
      void ToolCallingResultMessage;
      cleanup();
    }
  },
};
