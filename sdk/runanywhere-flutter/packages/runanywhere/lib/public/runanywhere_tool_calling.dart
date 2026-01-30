/// Tool Calling Extension for RunAnywhere SDK
///
/// Provides tool calling (function calling) functionality for LLMs.
/// Allows LLMs to request external actions (API calls, device functions, etc.)
///
/// Matches Swift SDK's RunAnywhere+ToolCalling.swift
library runanywhere_tool_calling;

import 'dart:convert';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_tool_calling.dart';
import 'package:runanywhere/public/runanywhere.dart';
import 'package:runanywhere/public/types/generation_types.dart';
import 'package:runanywhere/public/types/tool_calling_types.dart';

/// Tool calling extension for RunAnywhere
///
/// Provides:
/// - Tool registration and management
/// - Tool-enabled generation with automatic execution
/// - Manual tool execution support
extension RunAnywhereToolCalling on RunAnywhere {
  // Private static registry - stores tool executors by name
  static final Map<String, ToolExecutor> _toolExecutors = {};
  static final Map<String, ToolDefinition> _toolDefinitions = {};
  static final _logger = SDKLogger('RunAnywhere.ToolCalling');

  // ============================================================================
  // MARK: - Tool Registration
  // ============================================================================

  /// Register a tool with the SDK.
  ///
  /// [definition] Tool definition including name, description, and parameters
  /// [executor] Async function to execute when the tool is called
  ///
  /// Example:
  /// ```dart
  /// RunAnywhereTools.registerTool(
  ///   ToolDefinition(
  ///     name: 'get_weather',
  ///     description: 'Get current weather for a location',
  ///     parameters: [
  ///       ToolParameter(
  ///         name: 'location',
  ///         type: ToolParameterType.string,
  ///         description: 'City name or coordinates',
  ///       ),
  ///     ],
  ///   ),
  ///   (args) async {
  ///     final location = args['location']?.stringValue ?? 'Unknown';
  ///     // Call weather API...
  ///     return {'temperature': NumberToolValue(72), 'condition': StringToolValue('Sunny')};
  ///   },
  /// );
  /// ```
  static void registerTool(ToolDefinition definition, ToolExecutor executor) {
    _toolDefinitions[definition.name] = definition;
    _toolExecutors[definition.name] = executor;
    _logger.info('Registered tool: ${definition.name}');
  }

  /// Unregister a tool by name
  static void unregisterTool(String toolName) {
    _toolDefinitions.remove(toolName);
    _toolExecutors.remove(toolName);
    _logger.info('Unregistered tool: $toolName');
  }

  /// Get all registered tool definitions
  static List<ToolDefinition> getRegisteredTools() {
    return List.unmodifiable(_toolDefinitions.values.toList());
  }

  /// Clear all registered tools
  static void clearTools() {
    _toolDefinitions.clear();
    _toolExecutors.clear();
    _logger.info('Cleared all registered tools');
  }

  // ============================================================================
  // MARK: - Tool Execution
  // ============================================================================

  /// Execute a tool call manually.
  ///
  /// [toolCall] The tool call to execute
  /// Returns ToolResult with success/failure and result data
  static Future<ToolResult> executeTool(ToolCall toolCall) async {
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

  // ============================================================================
  // MARK: - Tool-Enabled Generation
  // ============================================================================

  /// Generate text with tool calling support.
  ///
  /// This is the main entry point for tool-enabled generation.
  /// Handles the full tool calling loop:
  /// 1. Format tools into system prompt
  /// 2. Generate LLM response
  /// 3. Parse tool calls from output
  /// 4. Execute tools (if autoExecute is true)
  /// 5. Continue generation with tool results
  /// 6. Repeat until no more tool calls or max iterations reached
  ///
  /// [prompt] User's question or request
  /// [options] Tool calling options (optional)
  ///
  /// Example:
  /// ```dart
  /// final result = await RunAnywhereTools.generateWithTools(
  ///   'What is the weather in San Francisco?',
  /// );
  /// print(result.text); // "The weather in San Francisco is 72°F and Sunny."
  /// print(result.toolCalls); // [ToolCall(name: 'get_weather', ...)]
  /// ```
  static Future<ToolCallingResult> generateWithTools(
    String prompt, {
    ToolCallingOptions? options,
  }) async {
    final opts = options ?? const ToolCallingOptions();
    final tools = opts.tools ?? getRegisteredTools();
    final formatName = opts.formatName;

    if (tools.isEmpty) {
      // No tools - just do regular generation
      final result = await RunAnywhere.generate(prompt);
      return ToolCallingResult(
        text: result.text,
        toolCalls: [],
        toolResults: [],
        isComplete: true,
      );
    }

    // Build tools JSON
    final toolsJson = toolsToJson(tools);
    _logger.debug('Tools JSON: $toolsJson');
    _logger.debug('Using tool call format: $formatName');

    // Build initial prompt with tools using the specified format
    final toolsPrompt = DartBridgeToolCalling.shared.formatToolsPromptWithFormat(
      toolsJson,
      formatName,
    );
    
    // Build the full prompt with system instructions and user query
    final formattedPrompt = '$toolsPrompt\n\nUser: $prompt';
    _logger.debug('Formatted prompt: ${formattedPrompt.substring(0, formattedPrompt.length.clamp(0, 200))}...');

    // Track all tool calls and results
    final allToolCalls = <ToolCall>[];
    final allToolResults = <ToolResult>[];

    var currentPrompt = formattedPrompt;
    var iterations = 0;
    final maxIterations = opts.maxToolCalls;

    while (iterations < maxIterations) {
      iterations++;

      // Match Swift SDK defaults: temperature 0.7, maxTokens 1024
      final genOptions = LLMGenerationOptions(
        maxTokens: opts.maxTokens ?? 1024,
        temperature: opts.temperature ?? 0.7,
      );
      
      // Use streaming like Swift does, then collect all tokens
      final streamResult = await RunAnywhere.generateStream(currentPrompt, options: genOptions);
      final buffer = StringBuffer();
      await for (final token in streamResult.stream) {
        buffer.write(token);
      }
      final responseText = buffer.toString();
      
      _logger.debug('LLM output (iter $iterations): ${responseText.substring(0, responseText.length.clamp(0, 200))}...');

      // Parse for tool calls using C++ bridge (auto-detection like Swift)
      final parseResult = DartBridgeToolCalling.shared.parseToolCall(responseText);

      if (!parseResult.hasToolCall || parseResult.toolName == null) {
        // No tool call - return final result
        return ToolCallingResult(
          text: parseResult.cleanText,
          toolCalls: allToolCalls,
          toolResults: allToolResults,
          isComplete: true,
        );
      }

      // Create tool call
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
        // Return for manual execution
        return ToolCallingResult(
          text: parseResult.cleanText,
          toolCalls: allToolCalls,
          toolResults: allToolResults,
          isComplete: false,
        );
      }

      // Execute the tool
      final toolResult = await executeTool(toolCall);
      allToolResults.add(toolResult);

      // Build follow-up prompt with tool result
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

      _logger.debug('Follow-up prompt: ${currentPrompt.substring(0, currentPrompt.length.clamp(0, 200))}...');
    }

    // Max iterations reached - return what we have
    _logger.warning('Max tool call iterations ($maxIterations) reached');
    return ToolCallingResult(
      text: '',
      toolCalls: allToolCalls,
      toolResults: allToolResults,
      isComplete: true,
    );
  }

  /// Continue generation after manual tool execution.
  ///
  /// Use this when autoExecute is false and you've executed tools manually.
  ///
  /// [originalPrompt] The original user prompt
  /// [toolResult] Result from manual tool execution
  /// [options] Tool calling options
  static Future<ToolCallingResult> continueWithToolResult(
    String originalPrompt,
    ToolResult toolResult, {
    ToolCallingOptions? options,
  }) async {
    final opts = options ?? const ToolCallingOptions();
    final tools = opts.tools ?? getRegisteredTools();
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

    // Continue with the follow-up
    return generateWithTools(followupPrompt, options: opts);
  }

  // ============================================================================
  // MARK: - Helper Functions
  // ============================================================================

  /// Format tools for system prompt.
  ///
  /// Useful for inspecting or customizing tool prompts.
  static String formatToolsForPrompt([List<ToolDefinition>? tools]) {
    final toolList = tools ?? getRegisteredTools();
    if (toolList.isEmpty) return '';

    final toolsJson = toolsToJson(toolList);
    return DartBridgeToolCalling.shared.formatToolsPrompt(toolsJson);
  }

  /// Parse tool call from LLM output.
  ///
  /// Useful for manual parsing without automatic execution.
  static ToolCall? parseToolCall(String llmOutput) {
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

/// Convenience class for tool calling without extension syntax
///
/// Use this for simpler imports:
/// ```dart
/// import 'package:runanywhere/public/runanywhere_tool_calling.dart';
///
/// RunAnywhereTools.registerTool(...);
/// final result = await RunAnywhereTools.generateWithTools('...');
/// ```
class RunAnywhereTools {
  RunAnywhereTools._();

  /// Register a tool with the SDK
  static void registerTool(ToolDefinition definition, ToolExecutor executor) =>
      RunAnywhereToolCalling.registerTool(definition, executor);

  /// Unregister a tool by name
  static void unregisterTool(String toolName) =>
      RunAnywhereToolCalling.unregisterTool(toolName);

  /// Get all registered tool definitions
  static List<ToolDefinition> getRegisteredTools() =>
      RunAnywhereToolCalling.getRegisteredTools();

  /// Clear all registered tools
  static void clearTools() => RunAnywhereToolCalling.clearTools();

  /// Execute a tool call manually
  static Future<ToolResult> executeTool(ToolCall toolCall) =>
      RunAnywhereToolCalling.executeTool(toolCall);

  /// Generate text with tool calling support
  static Future<ToolCallingResult> generateWithTools(
    String prompt, {
    ToolCallingOptions? options,
  }) =>
      RunAnywhereToolCalling.generateWithTools(prompt, options: options);

  /// Continue generation after manual tool execution
  static Future<ToolCallingResult> continueWithToolResult(
    String originalPrompt,
    ToolResult toolResult, {
    ToolCallingOptions? options,
  }) =>
      RunAnywhereToolCalling.continueWithToolResult(
        originalPrompt,
        toolResult,
        options: options,
      );

  /// Format tools for system prompt
  static String formatToolsForPrompt([List<ToolDefinition>? tools]) =>
      RunAnywhereToolCalling.formatToolsForPrompt(tools);

  /// Parse tool call from LLM output
  static ToolCall? parseToolCall(String llmOutput) =>
      RunAnywhereToolCalling.parseToolCall(llmOutput);
}
