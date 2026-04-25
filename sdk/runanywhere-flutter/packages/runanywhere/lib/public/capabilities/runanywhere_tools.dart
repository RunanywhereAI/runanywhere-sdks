// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_tools.dart — v4 Tools capability (LLM function calling).
//
// Owns tool registration, manual tool execution, and the
// tool-enabled generation loop (prompt tools into system prompt,
// parse tool calls out of LLM output, execute, loop).
//
// Mirrors Swift `RunAnywhere+ToolCalling.swift`.

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_tool_calling.dart';
import 'package:runanywhere/public/capabilities/runanywhere_llm.dart';
import 'package:runanywhere/public/types/generation_types.dart';
import 'package:runanywhere/public/types/tool_calling_types.dart';

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
    final executor = _toolExecutors[toolCall.toolName];
    if (executor == null) {
      return ToolResult(
        toolName: toolCall.toolName,
        success: false,
        error: 'Tool not found: ${toolCall.toolName}',
        callId: toolCall.callId,
      );
    }

    try {
      _logger.debug('Executing tool: ${toolCall.toolName}');
      final result = await executor(toolCall.arguments);
      _logger.debug('Tool ${toolCall.toolName} completed successfully');
      return ToolResult(
        toolName: toolCall.toolName,
        success: true,
        result: result,
        callId: toolCall.callId,
      );
    } catch (e) {
      _logger.error('Tool ${toolCall.toolName} failed: $e');
      return ToolResult(
        toolName: toolCall.toolName,
        success: false,
        error: e.toString(),
        callId: toolCall.callId,
      );
    }
  }

  // -- tool-enabled generation ---------------------------------------------

  /// Generate text with tool calling support. Drives the full loop:
  /// format tools into the system prompt, stream LLM output, parse
  /// tool calls, execute, continue until no more tool calls (or
  /// `maxToolCalls` is reached).
  Future<ToolCallingResult> generateWithTools(
    String prompt, {
    ToolCallingOptions? options,
  }) async {
    final opts = options ?? const ToolCallingOptions();
    final tools = opts.tools ?? registeredTools();
    final formatName = opts.formatName;

    if (tools.isEmpty) {
      final result = await RunAnywhereLLM.shared.generate(prompt);
      return ToolCallingResult(
        text: result.text,
        toolCalls: [],
        toolResults: [],
        isComplete: true,
      );
    }

    final toolsJson = toolsToJson(tools);
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
    final maxIterations = opts.maxToolCalls;

    while (iterations < maxIterations) {
      iterations++;

      final genOptions = LLMGenerationOptions(
        maxTokens: opts.maxTokens ?? 1024,
        temperature: opts.temperature ?? 0.3,
      );

      // v2 close-out Phase G-2: generateStream now returns
      // Stream<LLMStreamEvent>; accumulate token text off each event.
      final eventStream = RunAnywhereLLM.shared
          .generateStream(currentPrompt, options: genOptions);
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
        );
      }

      final toolCall = ToolCall(
        toolName: parseResult.toolName!,
        arguments: parseResult.arguments != null
            ? dynamicMapToToolValueMap(parseResult.arguments!)
            : {},
        callId: parseResult.callId.toString(),
      );
      allToolCalls.add(toolCall);

      _logger.info('Tool call detected: ${toolCall.toolName}');

      if (!opts.autoExecute) {
        return ToolCallingResult(
          text: parseResult.cleanText,
          toolCalls: allToolCalls,
          toolResults: allToolResults,
          isComplete: false,
        );
      }

      final toolResult = await execute(toolCall);
      allToolResults.add(toolResult);

      final resultJson = toolResult.result != null
          ? toolResultToJsonString(toolResult.result!)
          : '{"error": "${toolResult.error ?? 'Unknown error'}"}';

      currentPrompt = DartBridgeToolCalling.shared.buildFollowupPrompt(
        originalPrompt: prompt,
        toolsPrompt: opts.keepToolsAvailable
            ? DartBridgeToolCalling.shared.formatToolsPrompt(toolsJson)
            : null,
        toolName: toolCall.toolName,
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
    );
  }

  /// Continue generation after manual tool execution (used when
  /// `autoExecute: false`).
  Future<ToolCallingResult> continueWithToolResult(
    String originalPrompt,
    ToolResult toolResult, {
    ToolCallingOptions? options,
  }) async {
    final opts = options ?? const ToolCallingOptions();
    final tools = opts.tools ?? registeredTools();
    final toolsJson = toolsToJson(tools);

    final resultJson = toolResult.result != null
        ? toolResultToJsonString(toolResult.result!)
        : '{"error": "${toolResult.error ?? 'Unknown error'}"}';

    final followupPrompt = DartBridgeToolCalling.shared.buildFollowupPrompt(
      originalPrompt: originalPrompt,
      toolsPrompt: opts.keepToolsAvailable
          ? DartBridgeToolCalling.shared.formatToolsPrompt(toolsJson)
          : null,
      toolName: toolResult.toolName,
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
    final toolsJson = toolsToJson(toolList);
    return DartBridgeToolCalling.shared.formatToolsPrompt(toolsJson);
  }

  /// Parse a tool call out of raw LLM output (no auto-execution).
  ToolCall? parseToolCall(String llmOutput) {
    final result = DartBridgeToolCalling.shared.parseToolCall(llmOutput);
    if (!result.hasToolCall || result.toolName == null) {
      return null;
    }
    return ToolCall(
      toolName: result.toolName!,
      arguments: result.arguments != null
          ? dynamicMapToToolValueMap(result.arguments!)
          : {},
      callId: result.callId.toString(),
    );
  }
}
