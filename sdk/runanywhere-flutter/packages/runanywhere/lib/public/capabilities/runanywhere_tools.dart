// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_tools.dart — v4 Tools capability (LLM function calling).
//
// §15 type-discipline: hand-rolled tool-calling types deleted; the
// proto-generated `ToolDefinition` / `ToolCall` / `ToolResult` /
// `ToolCallingOptions` / `ToolCallingResult` from
// `generated/tool_calling.pb.dart` are the canonical types.
//
// Owns tool registration, manual tool execution, and the
// tool-enabled generation loop (prompt tools into system prompt,
// parse tool calls out of LLM output, execute, loop).
//
// Mirrors Swift `RunAnywhere+ToolCalling.swift`.

import 'dart:convert';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/llm_options.pb.dart' show LLMGenerationOptions;
import 'package:runanywhere/generated/tool_calling.pb.dart'
    show ToolCall, ToolCallingOptions, ToolCallingResult, ToolDefinition,
        ToolParameter, ToolResult;
import 'package:runanywhere/generated/tool_calling.pbenum.dart'
    show ToolCallFormatName, ToolParameterType;
import 'package:runanywhere/native/dart_bridge_tool_calling.dart';
import 'package:runanywhere/public/capabilities/runanywhere_llm.dart';

/// Executor signature for a tool call.
///
/// Receives the JSON-decoded arguments map (parsed from
/// `ToolCall.argumentsJson`) and returns a JSON-encodable result
/// map. The framework re-encodes the result into
/// `ToolResult.resultJson`.
typedef ToolExecutor = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> args);

/// Format-name string constants for `ToolCallingOptions.formatHint`.
///
/// The actual format logic is handled in C++ commons (single source
/// of truth). Mirrors Swift SDK's `ToolCallFormatName` enum.
abstract class ToolCallFormatNames {
  /// JSON format: `<tool_call>{"tool":"name","arguments":{...}}</tool_call>`
  /// Use for most general-purpose models (Llama, Qwen, Mistral, etc.)
  static const String defaultFormat = 'default';

  /// Liquid AI format: `<|tool_call_start|>[func(args)]<|tool_call_end|>`
  /// Use for LFM2-Tool models
  static const String lfm2 = 'lfm2';
}

String _formatHint(ToolCallingOptions opts) {
  if (opts.formatHint.isNotEmpty) return opts.formatHint;
  // The proto enum surfaces high-level format families
  // (JSON / XML / NATIVE / PYTHONIC / OPENAI_FUNCTIONS / HERMES); the
  // C++ commons format name registry is keyed by string values like
  // "default" and "lfm2". We map the proto enum onto the string keys
  // via `formatHint`. PYTHONIC ↔ "lfm2", everything else ↔ "default".
  if (opts.format == ToolCallFormatName.TOOL_CALL_FORMAT_NAME_PYTHONIC) {
    return ToolCallFormatNames.lfm2;
  }
  return ToolCallFormatNames.defaultFormat;
}

String _toolDefinitionsToJson(List<ToolDefinition> tools) {
  return jsonEncode(tools.map(_toolDefinitionToMap).toList());
}

Map<String, dynamic> _toolDefinitionToMap(ToolDefinition def) => {
      'name': def.name,
      'description': def.description,
      'parameters': def.parameters.map(_toolParameterToMap).toList(),
      if (def.category.isNotEmpty) 'category': def.category,
    };

Map<String, dynamic> _toolParameterToMap(ToolParameter param) => {
      'name': param.name,
      'type': _toolParameterTypeToJson(param.type),
      'description': param.description,
      'required': param.required,
      if (param.enumValues.isNotEmpty) 'enumValues': param.enumValues,
    };

String _toolParameterTypeToJson(ToolParameterType type) {
  switch (type) {
    case ToolParameterType.TOOL_PARAMETER_TYPE_NUMBER:
      return 'number';
    case ToolParameterType.TOOL_PARAMETER_TYPE_BOOLEAN:
      return 'boolean';
    case ToolParameterType.TOOL_PARAMETER_TYPE_OBJECT:
      return 'object';
    case ToolParameterType.TOOL_PARAMETER_TYPE_ARRAY:
      return 'array';
    case ToolParameterType.TOOL_PARAMETER_TYPE_STRING:
    case ToolParameterType.TOOL_PARAMETER_TYPE_UNSPECIFIED:
    default:
      return 'string';
  }
}

/// Tools (function calling) capability surface.
///
/// Access via `RunAnywhereSDK.instance.tools`.
class RunAnywhereTools {
  RunAnywhereTools._();
  static final RunAnywhereTools _instance = RunAnywhereTools._();
  static RunAnywhereTools get shared => _instance;

  static final Map<String, ToolExecutor> _toolExecutors = {};
  static final Map<String, ToolDefinition> _toolDefinitions = {};
  static final _logger = SDKLogger('RunAnywhere.ToolCalling');

  // -- registration ---------------------------------------------------------

  /// Register a tool the LLM can call. `executor` runs when the LLM
  /// emits a matching tool-call in `generateWithTools`.
  void register(ToolDefinition definition, ToolExecutor executor) {
    _toolDefinitions[definition.name] = definition;
    _toolExecutors[definition.name] = executor;
    _logger.info('Registered tool: ${definition.name}');
  }

  /// Unregister a tool by name.
  void unregister(String toolName) {
    _toolDefinitions.remove(toolName);
    _toolExecutors.remove(toolName);
    _logger.info('Unregistered tool: $toolName');
  }

  /// Snapshot of every currently-registered tool definition.
  List<ToolDefinition> registeredTools() =>
      List.unmodifiable(_toolDefinitions.values.toList());

  /// Clear every registered tool.
  void clear() {
    _toolDefinitions.clear();
    _toolExecutors.clear();
    _logger.info('Cleared all registered tools');
  }

  // -- execution ------------------------------------------------------------

  /// Execute a tool call manually. Used when `autoExecute: false` is
  /// passed to `generateWithTools`.
  Future<ToolResult> execute(ToolCall toolCall) async {
    final executor = _toolExecutors[toolCall.name];
    if (executor == null) {
      return ToolResult(
        toolCallId: toolCall.id,
        name: toolCall.name,
        error: 'Tool not found: ${toolCall.name}',
      );
    }

    Map<String, dynamic> args = const {};
    if (toolCall.argumentsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(toolCall.argumentsJson);
        if (decoded is Map<String, dynamic>) args = decoded;
      } catch (e) {
        _logger.warning(
            'Failed to decode tool arguments JSON for ${toolCall.name}: $e');
      }
    }

    try {
      _logger.debug('Executing tool: ${toolCall.name}');
      final result = await executor(args);
      _logger.debug('Tool ${toolCall.name} completed successfully');
      return ToolResult(
        toolCallId: toolCall.id,
        name: toolCall.name,
        resultJson: jsonEncode(result),
      );
    } catch (e) {
      _logger.error('Tool ${toolCall.name} failed: $e');
      return ToolResult(
        toolCallId: toolCall.id,
        name: toolCall.name,
        error: e.toString(),
      );
    }
  }

  // -- tool-enabled generation ---------------------------------------------

  /// Generate text with tool calling support. Drives the full loop:
  /// format tools into the system prompt, stream LLM output, parse
  /// tool calls, execute, continue until no more tool calls (or
  /// `maxIterations` is reached).
  Future<ToolCallingResult> generateWithTools(
    String prompt, {
    ToolCallingOptions? options,
  }) async {
    final opts = options ?? ToolCallingOptions();
    final tools = opts.tools.isNotEmpty ? opts.tools : registeredTools();
    final formatName = _formatHint(opts);

    if (tools.isEmpty) {
      final result = await RunAnywhereLLM.shared.generate(prompt);
      return ToolCallingResult(
        text: result.text,
        toolCalls: const [],
        toolResults: const [],
        isComplete: true,
      );
    }

    final toolsJson = _toolDefinitionsToJson(tools);
    _logger.debug('Tools JSON: $toolsJson');
    _logger.debug('Using tool call format: $formatName');

    final toolsPrompt = DartBridgeToolCalling.shared
        .formatToolsPromptWithFormat(toolsJson, formatName);

    final formattedPrompt = '$toolsPrompt\n\nUser: $prompt';
    _logger.debug(
        'Formatted prompt: ${formattedPrompt.substring(0, formattedPrompt.length.clamp(0, 200))}...');

    final allToolCalls = <ToolCall>[];
    final allToolResults = <ToolResult>[];

    var currentPrompt = formattedPrompt;
    var iterations = 0;
    final maxIterations = opts.hasMaxIterations() ? opts.maxIterations : 5;

    while (iterations < maxIterations) {
      iterations++;

      final genOptions = LLMGenerationOptions(
        maxTokens: opts.hasMaxTokens() ? opts.maxTokens : 1024,
        temperature: opts.hasTemperature() ? opts.temperature : 0.3,
      );

      // v2 close-out Phase G-2: generateStream returns
      // Stream<LLMStreamEvent>; accumulate token text off each event.
      final eventStream = RunAnywhereLLM.shared
          .generateStream(currentPrompt, genOptions);
      final buffer = StringBuffer();
      await for (final event in eventStream) {
        if (event.isFinal) {
          if (event.errorMessage.isNotEmpty) {
            throw Exception(event.errorMessage);
          }
          break;
        }
        if (event.token.isNotEmpty) buffer.write(event.token);
      }
      final responseText = buffer.toString();

      _logger.debug(
          'LLM output (iter $iterations): ${responseText.substring(0, responseText.length.clamp(0, 200))}...');

      final parseResult =
          DartBridgeToolCalling.shared.parseToolCall(responseText);

      if (!parseResult.hasToolCall || parseResult.toolName == null) {
        return ToolCallingResult(
          text: parseResult.cleanText,
          toolCalls: allToolCalls,
          toolResults: allToolResults,
          isComplete: true,
          iterationsUsed: iterations,
        );
      }

      final toolCall = ToolCall(
        id: parseResult.callId.toString(),
        name: parseResult.toolName!,
        argumentsJson:
            parseResult.arguments != null ? jsonEncode(parseResult.arguments) : '',
      );
      allToolCalls.add(toolCall);

      _logger.info('Tool call detected: ${toolCall.name}');

      final autoExecute =
          opts.hasAutoExecute() ? opts.autoExecute : true;
      if (!autoExecute) {
        return ToolCallingResult(
          text: parseResult.cleanText,
          toolCalls: allToolCalls,
          toolResults: allToolResults,
          isComplete: false,
          iterationsUsed: iterations,
        );
      }

      final toolResult = await execute(toolCall);
      allToolResults.add(toolResult);

      final resultJson = toolResult.resultJson.isNotEmpty
          ? toolResult.resultJson
          : '{"error": "${toolResult.error.isNotEmpty ? toolResult.error : 'Unknown error'}"}';

      currentPrompt = DartBridgeToolCalling.shared.buildFollowupPrompt(
        originalPrompt: prompt,
        toolsPrompt: opts.keepToolsAvailable
            ? DartBridgeToolCalling.shared.formatToolsPrompt(toolsJson)
            : null,
        toolName: toolCall.name,
        toolResultJson: resultJson,
        keepToolsAvailable: opts.keepToolsAvailable,
      );

      _logger.debug(
          'Follow-up prompt: ${currentPrompt.substring(0, currentPrompt.length.clamp(0, 200))}...');
    }

    _logger.warning('Max tool call iterations ($maxIterations) reached');
    return ToolCallingResult(
      text: '',
      toolCalls: allToolCalls,
      toolResults: allToolResults,
      isComplete: true,
      iterationsUsed: iterations,
    );
  }

  /// Continue generation after manual tool execution (used when
  /// `autoExecute: false`).
  Future<ToolCallingResult> continueWithToolResult(
    String originalPrompt,
    ToolResult toolResult, {
    ToolCallingOptions? options,
  }) async {
    final opts = options ?? ToolCallingOptions();
    final tools = opts.tools.isNotEmpty ? opts.tools : registeredTools();
    final toolsJson = _toolDefinitionsToJson(tools);

    final resultJson = toolResult.resultJson.isNotEmpty
        ? toolResult.resultJson
        : '{"error": "${toolResult.error.isNotEmpty ? toolResult.error : 'Unknown error'}"}';

    final followupPrompt = DartBridgeToolCalling.shared.buildFollowupPrompt(
      originalPrompt: originalPrompt,
      toolsPrompt: opts.keepToolsAvailable
          ? DartBridgeToolCalling.shared.formatToolsPrompt(toolsJson)
          : null,
      toolName: toolResult.name,
      toolResultJson: resultJson,
      keepToolsAvailable: opts.keepToolsAvailable,
    );

    return generateWithTools(followupPrompt, options: opts);
  }

  // -- helpers --------------------------------------------------------------

  /// Format the registered tools into a system-prompt snippet.
  String formatToolsForPrompt([List<ToolDefinition>? tools]) {
    final toolList = tools ?? registeredTools();
    if (toolList.isEmpty) return '';
    final toolsJson = _toolDefinitionsToJson(toolList);
    return DartBridgeToolCalling.shared.formatToolsPrompt(toolsJson);
  }

  /// Parse a tool call out of raw LLM output (no auto-execution).
  ToolCall? parseToolCall(String llmOutput) {
    final result = DartBridgeToolCalling.shared.parseToolCall(llmOutput);
    if (!result.hasToolCall || result.toolName == null) {
      return null;
    }
    return ToolCall(
      id: result.callId.toString(),
      name: result.toolName!,
      argumentsJson:
          result.arguments != null ? jsonEncode(result.arguments) : '',
    );
  }
}
