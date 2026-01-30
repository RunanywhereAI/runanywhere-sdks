/// Tool Calling Types for RunAnywhere SDK
///
/// Type definitions for tool calling (function calling) functionality.
/// Allows LLMs to request external actions (API calls, device functions, etc.)
///
/// Mirrors Swift SDK's ToolCallingTypes.swift
library tool_calling_types;

import 'dart:convert';

// =============================================================================
// TOOL VALUE - Type-safe JSON representation
// =============================================================================

/// A type-safe representation of JSON values for tool arguments and results.
/// Avoids using `dynamic` while supporting all JSON types.
sealed class ToolValue {
  const ToolValue();

  // Convenience value extraction
  String? get stringValue => this is StringToolValue ? (this as StringToolValue).value : null;
  double? get numberValue => this is NumberToolValue ? (this as NumberToolValue).value : null;
  int? get intValue => numberValue?.toInt();
  bool? get boolValue => this is BoolToolValue ? (this as BoolToolValue).value : null;
  List<ToolValue>? get arrayValue =>
      this is ArrayToolValue ? (this as ArrayToolValue).value : null;
  Map<String, ToolValue>? get objectValue =>
      this is ObjectToolValue ? (this as ObjectToolValue).value : null;
  bool get isNull => this is NullToolValue;

  /// Convert to JSON-compatible dynamic value
  dynamic toJson() => switch (this) {
        StringToolValue(value: var v) => v,
        NumberToolValue(value: var v) => v,
        BoolToolValue(value: var v) => v,
        ArrayToolValue(value: var v) => v.map((e) => e.toJson()).toList(),
        ObjectToolValue(value: var v) => v.map((k, val) => MapEntry(k, val.toJson())),
        NullToolValue() => null,
      };

  /// Create from any JSON-compatible value
  static ToolValue from(dynamic value) => switch (value) {
        null => const NullToolValue(),
        String s => StringToolValue(s),
        num n => NumberToolValue(n.toDouble()),
        bool b => BoolToolValue(b),
        List l => ArrayToolValue(l.map(from).toList()),
        Map m => ObjectToolValue(m.map((k, v) => MapEntry(k.toString(), from(v)))),
        _ => StringToolValue(value.toString()),
      };
}

class StringToolValue extends ToolValue {
  final String value;
  const StringToolValue(this.value);
}

class NumberToolValue extends ToolValue {
  final double value;
  const NumberToolValue(this.value);
}

class BoolToolValue extends ToolValue {
  final bool value;
  const BoolToolValue(this.value);
}

class ArrayToolValue extends ToolValue {
  final List<ToolValue> value;
  const ArrayToolValue(this.value);
}

class ObjectToolValue extends ToolValue {
  final Map<String, ToolValue> value;
  const ObjectToolValue(this.value);
}

class NullToolValue extends ToolValue {
  const NullToolValue();
}

// =============================================================================
// PARAMETER TYPES
// =============================================================================

/// Supported parameter types for tool arguments
enum ToolParameterType {
  string('string'),
  number('number'),
  boolean('boolean'),
  object('object'),
  array('array');

  final String value;
  const ToolParameterType(this.value);

  static ToolParameterType fromString(String value) => switch (value.toLowerCase()) {
        'string' => ToolParameterType.string,
        'number' => ToolParameterType.number,
        'boolean' => ToolParameterType.boolean,
        'object' => ToolParameterType.object,
        'array' => ToolParameterType.array,
        _ => ToolParameterType.string,
      };
}

/// A single parameter definition for a tool
class ToolParameter {
  /// Parameter name
  final String name;

  /// Data type of the parameter
  final ToolParameterType type;

  /// Human-readable description
  final String description;

  /// Whether this parameter is required
  final bool required;

  /// Allowed values (for enum-like parameters)
  final List<String>? enumValues;

  const ToolParameter({
    required this.name,
    required this.type,
    required this.description,
    this.required = true,
    this.enumValues,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'type': type.value,
        'description': description,
        'required': required,
        if (enumValues != null) 'enumValues': enumValues,
      };
}

// =============================================================================
// TOOL DEFINITION TYPES
// =============================================================================

/// Definition of a tool that the LLM can use
class ToolDefinition {
  /// Unique name of the tool (e.g., "get_weather")
  final String name;

  /// Human-readable description of what the tool does
  final String description;

  /// Parameters the tool accepts
  final List<ToolParameter> parameters;

  /// Category for organizing tools (optional)
  final String? category;

  const ToolDefinition({
    required this.name,
    required this.description,
    required this.parameters,
    this.category,
  });

  Map<String, dynamic> toJson() => {
        'name': name,
        'description': description,
        'parameters': parameters.map((p) => p.toJson()).toList(),
        if (category != null) 'category': category,
      };
}

// =============================================================================
// TOOL CALL TYPES (LLM requesting to use a tool)
// =============================================================================

/// A request from the LLM to execute a tool
class ToolCall {
  /// Name of the tool to execute
  final String toolName;

  /// Arguments to pass to the tool
  final Map<String, ToolValue> arguments;

  /// Unique ID for this tool call (for tracking)
  final String? callId;

  const ToolCall({
    required this.toolName,
    required this.arguments,
    this.callId,
  });

  /// Get a string argument by name
  String? getString(String key) => arguments[key]?.stringValue;

  /// Get a number argument by name
  double? getNumber(String key) => arguments[key]?.numberValue;

  /// Get a bool argument by name
  bool? getBool(String key) => arguments[key]?.boolValue;
}

// =============================================================================
// TOOL RESULT TYPES (Result after execution)
// =============================================================================

/// Result of executing a tool
class ToolResult {
  /// Name of the tool that was executed
  final String toolName;

  /// Whether execution was successful
  final bool success;

  /// Result data (if successful)
  final Map<String, ToolValue>? result;

  /// Error message (if failed)
  final String? error;

  /// The original call ID (for tracking)
  final String? callId;

  const ToolResult({
    required this.toolName,
    required this.success,
    this.result,
    this.error,
    this.callId,
  });

  Map<String, dynamic> toJson() => {
        'toolName': toolName,
        'success': success,
        if (result != null) 'result': result!.map((k, v) => MapEntry(k, v.toJson())),
        if (error != null) 'error': error,
        if (callId != null) 'callId': callId,
      };
}

// =============================================================================
// TOOL EXECUTOR TYPES
// =============================================================================

/// Function type for tool executors.
/// Takes arguments as strongly-typed ToolValue map, returns result map.
typedef ToolExecutor = Future<Map<String, ToolValue>> Function(Map<String, ToolValue> args);

// =============================================================================
// TOOL CALLING OPTIONS
// =============================================================================

/// Options for tool-enabled generation
class ToolCallingOptions {
  /// Available tools for this generation (if not provided, uses registered tools)
  final List<ToolDefinition>? tools;

  /// Maximum number of tool calls allowed in one conversation turn (default: 5)
  final int maxToolCalls;

  /// Whether to automatically execute tools or return them for manual execution (default: true)
  final bool autoExecute;

  /// Temperature for generation
  final double? temperature;

  /// Maximum tokens to generate
  final int? maxTokens;

  /// System prompt to use (will be merged with tool instructions by default)
  final String? systemPrompt;

  /// If true, replaces the system prompt entirely instead of appending tool instructions
  final bool replaceSystemPrompt;

  /// If true, keeps tool definitions available after the first tool call
  final bool keepToolsAvailable;

  const ToolCallingOptions({
    this.tools,
    this.maxToolCalls = 5,
    this.autoExecute = true,
    this.temperature,
    this.maxTokens,
    this.systemPrompt,
    this.replaceSystemPrompt = false,
    this.keepToolsAvailable = false,
  });
}

// =============================================================================
// TOOL CALLING RESULT TYPES
// =============================================================================

/// Result of a generation that may include tool calls
class ToolCallingResult {
  /// The final text response
  final String text;

  /// Any tool calls the LLM made
  final List<ToolCall> toolCalls;

  /// Results of executed tools (if autoExecute was true)
  final List<ToolResult> toolResults;

  /// Whether the response is complete or waiting for tool results
  final bool isComplete;

  /// Conversation ID for continuing with tool results
  final String? conversationId;

  const ToolCallingResult({
    required this.text,
    required this.toolCalls,
    required this.toolResults,
    required this.isComplete,
    this.conversationId,
  });
}

// =============================================================================
// HELPER FUNCTIONS
// =============================================================================

/// Serialize tools to JSON string
String toolsToJson(List<ToolDefinition> tools) {
  return jsonEncode(tools.map((t) => t.toJson()).toList());
}

/// Convert Map<String, ToolValue> to JSON string
String toolResultToJsonString(Map<String, ToolValue> result) {
  return jsonEncode(result.map((k, v) => MapEntry(k, v.toJson())));
}

/// Convert Map<String, dynamic> to Map<String, ToolValue>
Map<String, ToolValue> dynamicMapToToolValueMap(Map<String, dynamic> map) {
  return map.map((k, v) => MapEntry(k, ToolValue.from(v)));
}
