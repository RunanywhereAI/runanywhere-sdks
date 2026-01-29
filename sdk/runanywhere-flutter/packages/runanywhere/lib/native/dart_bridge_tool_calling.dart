/// DartBridge+ToolCalling
///
/// Tool calling bridge - wraps C++ tool calling functions.
///
/// *** SINGLE SOURCE OF TRUTH FOR TOOL CALLING LOGIC IS IN COMMONS C++ ***
///
/// This is a THIN WRAPPER around rac_tool_calling.h functions.
/// NO LOCAL PARSING LOGIC - everything calls through to C++.
///
/// Platform SDKs handle ONLY:
/// - Tool registry (Dart closures)
/// - Tool execution (Dart async calls)
library dart_bridge_tool_calling;

import 'dart:convert';
import 'dart:ffi';

import 'package:ffi/ffi.dart';

import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/ffi_types.dart';
import 'package:runanywhere/native/platform_loader.dart';

/// Tool call parse result from C++
class ToolCallParseResult {
  final bool hasToolCall;
  final String cleanText;
  final String? toolName;
  final Map<String, dynamic>? arguments;
  final int callId;

  ToolCallParseResult({
    required this.hasToolCall,
    required this.cleanText,
    this.toolName,
    this.arguments,
    required this.callId,
  });
}

/// Tool calling bridge for C++ interop.
///
/// *** ALL PARSING LOGIC IS IN C++ - NO DART FALLBACKS ***
///
/// Provides access to C++ tool calling functions:
/// - Parse <tool_call> tags from LLM output
/// - Format tools for system prompt
/// - Build initial and follow-up prompts
/// - Normalize JSON (fix unquoted keys)
class DartBridgeToolCalling {
  // MARK: - Singleton

  /// Shared instance
  static final DartBridgeToolCalling shared = DartBridgeToolCalling._();

  DartBridgeToolCalling._();

  // MARK: - State

  final _logger = SDKLogger('DartBridge.ToolCalling');
  DynamicLibrary? _lib;

  DynamicLibrary get lib {
    _lib ??= PlatformLoader.loadCommons();
    return _lib!;
  }

  // MARK: - Parse Tool Call (NO FALLBACK)

  /// Parse LLM output for tool calls using C++ implementation.
  ///
  /// *** THIS IS THE ONLY PARSING IMPLEMENTATION - NO DART FALLBACK ***
  ///
  /// Handles all edge cases:
  /// - Missing closing tags (brace-matching)
  /// - Unquoted JSON keys ({tool: "name"} → {"tool": "name"})
  /// - Multiple key naming conventions
  /// - Tool name as key pattern
  ///
  /// [llmOutput] Raw LLM output text
  /// Returns parsed result with tool call info
  ToolCallParseResult parseToolCall(String llmOutput) {
    try {
      final parseFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<RacToolCallStruct>),
          int Function(Pointer<Utf8>, Pointer<RacToolCallStruct>)>(
        'rac_tool_call_parse',
      );

      final freeFn = lib.lookupFunction<
          Void Function(Pointer<RacToolCallStruct>),
          void Function(Pointer<RacToolCallStruct>)>(
        'rac_tool_call_free',
      );

      final outputPtr = llmOutput.toNativeUtf8();
      final resultPtr = calloc<RacToolCallStruct>();

      try {
        final rc = parseFn(outputPtr, resultPtr);

        if (rc != RAC_SUCCESS) {
          return ToolCallParseResult(
            hasToolCall: false,
            cleanText: llmOutput,
            callId: 0,
          );
        }

        final result = resultPtr.ref;
        final hasToolCall = result.hasToolCall == RAC_TRUE;

        String cleanText = llmOutput;
        if (result.cleanText != nullptr) {
          cleanText = result.cleanText.toDartString();
        }

        String? toolName;
        Map<String, dynamic>? arguments;
        int callId = 0;

        if (hasToolCall) {
          if (result.toolName != nullptr) {
            toolName = result.toolName.toDartString();
          }

          if (result.argumentsJson != nullptr) {
            final argsJson = result.argumentsJson.toDartString();
            try {
              arguments = jsonDecode(argsJson) as Map<String, dynamic>;
            } catch (e) {
              arguments = {};
            }
          }

          callId = result.callId;
        }

        freeFn(resultPtr);

        return ToolCallParseResult(
          hasToolCall: hasToolCall,
          cleanText: cleanText,
          toolName: toolName,
          arguments: arguments,
          callId: callId,
        );
      } finally {
        calloc.free(outputPtr);
        calloc.free(resultPtr);
      }
    } catch (e) {
      _logger.error('parseToolCall failed: $e');
      return ToolCallParseResult(
        hasToolCall: false,
        cleanText: llmOutput,
        callId: 0,
      );
    }
  }

  // MARK: - Format Tools for Prompt (NO FALLBACK)

  /// Format tool definitions into a system prompt using C++ implementation
  /// with a specific format.
  ///
  /// [toolsJson] JSON array of tool definitions
  /// [formatName] Format name ("default", "lfm2")
  /// Returns formatted system prompt string
  String formatToolsPromptWithFormat(String toolsJson, String formatName) {
    if (toolsJson.isEmpty || toolsJson == '[]') {
      return '';
    }

    try {
      final formatFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Pointer<Utf8>>),
          int Function(Pointer<Utf8>, Pointer<Utf8>, Pointer<Pointer<Utf8>>)>(
        'rac_tool_call_format_prompt_json_with_format_name',
      );

      final racFreeFn = lib.lookupFunction<Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>('rac_free');

      final toolsPtr = toolsJson.toNativeUtf8();
      final formatPtr = formatName.toNativeUtf8();
      final promptPtrPtr = calloc<Pointer<Utf8>>();

      try {
        final rc = formatFn(toolsPtr, formatPtr, promptPtrPtr);

        if (rc != RAC_SUCCESS || promptPtrPtr.value == nullptr) {
          _logger.error('formatToolsPromptWithFormat C++ returned error: $rc');
          return formatToolsPrompt(toolsJson); // Fallback to default
        }

        final result = promptPtrPtr.value.toDartString();
        racFreeFn(promptPtrPtr.value.cast());
        return result;
      } finally {
        calloc.free(toolsPtr);
        calloc.free(formatPtr);
        calloc.free(promptPtrPtr);
      }
    } catch (e) {
      _logger.error('formatToolsPromptWithFormat failed: $e');
      return formatToolsPrompt(toolsJson); // Fallback to default
    }
  }

  /// Format tool definitions into a system prompt using C++ implementation
  /// (uses default format).
  ///
  /// [toolsJson] JSON array of tool definitions
  /// Returns formatted system prompt string
  String formatToolsPrompt(String toolsJson) {
    if (toolsJson.isEmpty || toolsJson == '[]') {
      return '';
    }

    try {
      final formatFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>),
          int Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>)>(
        'rac_tool_call_format_prompt_json',
      );

      final racFreeFn = lib.lookupFunction<Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>('rac_free');

      final toolsPtr = toolsJson.toNativeUtf8();
      final promptPtrPtr = calloc<Pointer<Utf8>>();

      try {
        final rc = formatFn(toolsPtr, promptPtrPtr);

        if (rc != RAC_SUCCESS || promptPtrPtr.value == nullptr) {
          return '';
        }

        final result = promptPtrPtr.value.toDartString();
        racFreeFn(promptPtrPtr.value.cast());
        return result;
      } finally {
        calloc.free(toolsPtr);
        calloc.free(promptPtrPtr);
      }
    } catch (e) {
      _logger.error('formatToolsPrompt failed: $e');
      return '';
    }
  }

  // MARK: - Build Initial Prompt (NO FALLBACK)

  /// Build initial prompt with tools and user query using C++ implementation.
  ///
  /// [userPrompt] The user's question/request
  /// [toolsJson] JSON array of tool definitions
  /// [optionsJson] Options as JSON (can be empty)
  /// Returns complete formatted prompt
  String buildInitialPrompt(
    String userPrompt,
    String toolsJson, {
    String? optionsJson,
  }) {
    try {
      final buildFn = lib.lookupFunction<
          Int32 Function(
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<RacToolCallingOptionsStruct>,
            Pointer<Pointer<Utf8>>,
          ),
          int Function(
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<RacToolCallingOptionsStruct>,
            Pointer<Pointer<Utf8>>,
          )>('rac_tool_call_build_initial_prompt');

      final racFreeFn = lib.lookupFunction<Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>('rac_free');

      final userPtr = userPrompt.toNativeUtf8();
      final toolsPtr = toolsJson.toNativeUtf8();
      final optionsPtr = calloc<RacToolCallingOptionsStruct>();
      final promptPtrPtr = calloc<Pointer<Utf8>>();

      // Set default options
      optionsPtr.ref.maxToolCalls = 5;
      optionsPtr.ref.autoExecute = RAC_TRUE;
      optionsPtr.ref.temperature = 0.7;
      optionsPtr.ref.maxTokens = 1024;
      optionsPtr.ref.systemPrompt = nullptr;
      optionsPtr.ref.replaceSystemPrompt = RAC_FALSE;
      optionsPtr.ref.keepToolsAvailable = RAC_FALSE;

      try {
        final rc = buildFn(userPtr, toolsPtr, optionsPtr, promptPtrPtr);

        if (rc != RAC_SUCCESS || promptPtrPtr.value == nullptr) {
          return userPrompt;
        }

        final result = promptPtrPtr.value.toDartString();
        racFreeFn(promptPtrPtr.value.cast());
        return result;
      } finally {
        calloc.free(userPtr);
        calloc.free(toolsPtr);
        calloc.free(optionsPtr);
        calloc.free(promptPtrPtr);
      }
    } catch (e) {
      _logger.error('buildInitialPrompt failed: $e');
      return userPrompt;
    }
  }

  // MARK: - Build Follow-up Prompt (NO FALLBACK)

  /// Build follow-up prompt after tool execution using C++ implementation.
  ///
  /// [originalPrompt] The original user prompt
  /// [toolsPrompt] Formatted tools prompt (can be empty)
  /// [toolName] Name of executed tool
  /// [toolResultJson] Tool result as JSON
  /// [keepToolsAvailable] Whether to keep tools in follow-up
  /// Returns follow-up prompt string
  String buildFollowupPrompt({
    required String originalPrompt,
    String? toolsPrompt,
    required String toolName,
    required String toolResultJson,
    bool keepToolsAvailable = false,
  }) {
    try {
      final buildFn = lib.lookupFunction<
          Int32 Function(
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Int32,
            Pointer<Pointer<Utf8>>,
          ),
          int Function(
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<Utf8>,
            Pointer<Utf8>,
            int,
            Pointer<Pointer<Utf8>>,
          )>('rac_tool_call_build_followup_prompt');

      final racFreeFn = lib.lookupFunction<Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>('rac_free');

      final originalPtr = originalPrompt.toNativeUtf8();
      final toolsPromptPtr =
          toolsPrompt != null ? toolsPrompt.toNativeUtf8() : nullptr;
      final toolNamePtr = toolName.toNativeUtf8();
      final resultPtr = toolResultJson.toNativeUtf8();
      final promptPtrPtr = calloc<Pointer<Utf8>>();

      try {
        final rc = buildFn(
          originalPtr,
          toolsPromptPtr,
          toolNamePtr,
          resultPtr,
          keepToolsAvailable ? RAC_TRUE : RAC_FALSE,
          promptPtrPtr,
        );

        if (rc != RAC_SUCCESS || promptPtrPtr.value == nullptr) {
          return '';
        }

        final result = promptPtrPtr.value.toDartString();
        racFreeFn(promptPtrPtr.value.cast());
        return result;
      } finally {
        calloc.free(originalPtr);
        if (toolsPromptPtr != nullptr) calloc.free(toolsPromptPtr);
        calloc.free(toolNamePtr);
        calloc.free(resultPtr);
        calloc.free(promptPtrPtr);
      }
    } catch (e) {
      _logger.error('buildFollowupPrompt failed: $e');
      return '';
    }
  }

  // MARK: - JSON Normalization (NO FALLBACK)

  /// Normalize JSON by adding quotes around unquoted keys using C++ implementation.
  ///
  /// [jsonStr] Raw JSON possibly with unquoted keys
  /// Returns normalized JSON string
  String normalizeJson(String jsonStr) {
    try {
      final normalizeFn = lib.lookupFunction<
          Int32 Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>),
          int Function(Pointer<Utf8>, Pointer<Pointer<Utf8>>)>(
        'rac_tool_call_normalize_json',
      );

      final racFreeFn = lib.lookupFunction<Void Function(Pointer<Void>),
          void Function(Pointer<Void>)>('rac_free');

      final inputPtr = jsonStr.toNativeUtf8();
      final outputPtrPtr = calloc<Pointer<Utf8>>();

      try {
        final rc = normalizeFn(inputPtr, outputPtrPtr);

        if (rc != RAC_SUCCESS || outputPtrPtr.value == nullptr) {
          return jsonStr;
        }

        final result = outputPtrPtr.value.toDartString();
        racFreeFn(outputPtrPtr.value.cast());
        return result;
      } finally {
        calloc.free(inputPtr);
        calloc.free(outputPtrPtr);
      }
    } catch (e) {
      _logger.error('normalizeJson failed: $e');
      return jsonStr;
    }
  }
}
