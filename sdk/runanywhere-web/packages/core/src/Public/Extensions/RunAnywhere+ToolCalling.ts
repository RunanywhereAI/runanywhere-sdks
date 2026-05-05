/**
 * RunAnywhere+ToolCalling.ts
 *
 * Tool calling namespace — mirrors Swift's `RunAnywhere+ToolCalling.swift`.
 * Re-exports canonical proto-ts types + provides `RunAnywhere.toolCalling.*` surface.
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
  ToolChoiceMode,
  ToolParseRequest as ToolParseRequestMessage,
  ToolParseResult as ToolParseResultMessage,
  ToolPromptFormatRequest as ToolPromptFormatRequestMessage,
  ToolPromptFormatResult as ToolPromptFormatResultMessage,
  ToolResult as ToolResultMessage,
  type ToolCall,
  type ToolCallValidationRequest,
  type ToolCallValidationResult,
  type ToolCallingOptions,
  type ToolCallingResult,
  type ToolDefinition,
  type ToolParseRequest,
  type ToolParseResult,
  type ToolPromptFormatRequest,
  type ToolPromptFormatResult,
  type ToolResult,
} from '@runanywhere/proto-ts/tool_calling';
import type { LLMGenerationOptions, LLMGenerationResult } from '@runanywhere/proto-ts/llm_options';
import { SDKErrorCode, SDKException } from '../../Foundation/SDKException';
import { SDKLogger } from '../../Foundation/SDKLogger';
import { ProtoWasmBridge } from '../../runtime/ProtoWasm';
import {
  tryRunanywhereModule,
  type EmscriptenRunanywhereModule,
} from '../../runtime/EmscriptenModule';
import { TextGeneration } from './RunAnywhere+TextGeneration';

async function generate(
  prompt: string,
  options: Partial<LLMGenerationOptions> & { toolCalling?: Partial<ToolCallingOptions> } = {},
): Promise<LLMGenerationResult> {
  return TextGeneration.generate({ ...options, prompt } as Partial<LLMGenerationOptions>);
}

const logger = new SDKLogger('ToolCalling');

type ToolCallingExport =
  | '_rac_tool_call_parse_proto'
  | '_rac_tool_call_format_prompt_proto'
  | '_rac_tool_call_validate_proto';

type RegisteredTool = {
  definition: ToolDefinition;
  executor: ToolExecutor;
};

export type ToolCallingGenerationOptions = Omit<Partial<LLMGenerationOptions>, 'toolCalling'> & {
  toolCalling?: Partial<ToolCallingOptions>;
};

export type ToolExecutor = (toolCall: ToolCall) => ToolResult | Promise<ToolResult>;

const registeredTools = new Map<string, RegisteredTool>();

function buildToolCallingOptions(
  tools: ToolDefinition[],
  options: ToolCallingGenerationOptions = {},
): ToolCallingOptions {
  const overrides = options.toolCalling ?? {};
  return ToolCallingOptionsMessage.fromPartial({
    tools: overrides.tools ?? tools,
    maxIterations: overrides.maxIterations ?? overrides.maxToolCalls ?? 0,
    autoExecute: overrides.autoExecute ?? true,
    temperature: overrides.temperature ?? options.temperature,
    maxTokens: overrides.maxTokens ?? options.maxTokens,
    systemPrompt: overrides.systemPrompt ?? options.systemPrompt,
    replaceSystemPrompt: overrides.replaceSystemPrompt ?? false,
    keepToolsAvailable: overrides.keepToolsAvailable ?? false,
    formatHint: overrides.formatHint ?? '',
    format: overrides.format,
    customSystemPrompt: overrides.customSystemPrompt,
    maxToolCalls: overrides.maxToolCalls,
    toolChoice: overrides.toolChoice ?? ToolChoiceMode.TOOL_CHOICE_MODE_AUTO,
    forcedToolName: overrides.forcedToolName,
    parallelToolCalls: overrides.parallelToolCalls ?? false,
    requireJsonArguments: overrides.requireJsonArguments ?? true,
  });
}

function buildPromptOptions(
  tools: ToolDefinition[],
  options: Partial<ToolCallingOptions> = {},
): ToolCallingOptions {
  return ToolCallingOptionsMessage.fromPartial({
    ...options,
    tools: options.tools ?? tools,
    maxIterations: options.maxIterations ?? options.maxToolCalls ?? 0,
    autoExecute: options.autoExecute ?? true,
    formatHint: options.formatHint ?? '',
    toolChoice: options.toolChoice ?? ToolChoiceMode.TOOL_CHOICE_MODE_AUTO,
    parallelToolCalls: options.parallelToolCalls ?? false,
    requireJsonArguments: options.requireJsonArguments ?? true,
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
  const module = tryRunanywhereModule();
  if (!module) {
    throw SDKException.backendNotAvailable(
      feature,
      'RunAnywhere WASM module is not initialized.',
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
      SDKErrorCode.BackendError,
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

function toolResultWithDefaults(
  toolCall: ToolCall,
  result: ToolResult,
  startedAtMs: number,
): ToolResult {
  return ToolResultMessage.fromPartial({
    ...result,
    toolCallId: result.toolCallId || toolCall.callId || toolCall.id,
    name: result.name || toolCall.name,
    startedAtMs: result.startedAtMs || startedAtMs,
    completedAtMs: result.completedAtMs || Date.now(),
  });
}

export const ToolCalling = {
  supportsProtoToolCalling(): boolean {
    const module = tryRunanywhereModule();
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
    const registered = registeredTools.get(toolCall.name);
    if (!registered) {
      return ToolResultMessage.fromPartial({
        toolCallId: toolCall.callId || toolCall.id,
        name: toolCall.name,
        resultJson: '',
        success: false,
        error: `Unknown tool: ${toolCall.name}`,
        callId: toolCall.callId || toolCall.id,
        startedAtMs,
        completedAtMs: Date.now(),
      });
    }

    try {
      return toolResultWithDefaults(
        toolCall,
        await registered.executor(toolCall),
        startedAtMs,
      );
    } catch (error) {
      return ToolResultMessage.fromPartial({
        toolCallId: toolCall.callId || toolCall.id,
        name: toolCall.name,
        resultJson: '',
        success: false,
        error: error instanceof Error ? error.message : String(error),
        callId: toolCall.callId || toolCall.id,
        startedAtMs,
        completedAtMs: Date.now(),
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
    return generate(prompt, {
      ...options,
      toolCalling: buildToolCallingOptions(tools, options),
    });
  },

  async generateWithTools(
    prompt: string,
    options: Partial<ToolCallingOptions> = {},
  ): Promise<ToolCallingResult> {
    const tools = options.tools && options.tools.length > 0
      ? options.tools
      : this.getRegisteredTools();
    const effectiveOptions = buildPromptOptions(tools, options);
    const maxIterations = (
      effectiveOptions.maxToolCalls ?? effectiveOptions.maxIterations
    ) || 5;
    const autoExecute = effectiveOptions.autoExecute;

    let fullPrompt = this.buildInitialPrompt(prompt, tools, effectiveOptions);
    let finalText = '';
    let rawText = '';
    let iterationsUsed = 0;
    const toolCalls: ToolCall[] = [];
    const toolResults: ToolResult[] = [];

    for (let i = 0; i < maxIterations; i += 1) {
      iterationsUsed = i + 1;
      const generated = await generate(fullPrompt, {
        maxTokens: effectiveOptions.maxTokens,
        temperature: effectiveOptions.temperature,
        systemPrompt: effectiveOptions.systemPrompt,
        toolCalling: effectiveOptions,
      });
      rawText = generated.text;
      const parsed = this.parseToolCall(rawText, effectiveOptions);
      finalText = parsed.remainingText || rawText;

      if (parsed.errorCode !== 0) {
        return ToolCallingResultMessage.fromPartial({
          text: finalText,
          toolCalls,
          toolResults,
          isComplete: false,
          iterationsUsed,
          rawText,
          errorCode: parsed.errorCode,
          errorMessage: parsed.errorMessage,
        });
      }

      if (!parsed.hasToolCall || parsed.toolCalls.length === 0) {
        break;
      }

      const toolCall = parsed.toolCalls[0]!;
      toolCalls.push(toolCall);
      if (!autoExecute) {
        return ToolCallingResultMessage.fromPartial({
          text: finalText,
          toolCalls,
          toolResults: [],
          isComplete: false,
          iterationsUsed,
          rawText,
          errorCode: parsed.errorCode,
          errorMessage: parsed.errorMessage,
        });
      }

      const toolResult = await this.executeTool(toolCall);
      toolResults.push(toolResult);
      fullPrompt = this.buildFollowupPrompt(prompt, toolResult, effectiveOptions);
    }

    return ToolCallingResultMessage.fromPartial({
      text: finalText,
      toolCalls,
      toolResults,
      isComplete: true,
      iterationsUsed,
      rawText,
      errorCode: 0,
    });
  },
};
