// SPDX-License-Identifier: Apache-2.0
//
// runanywhere_tools.dart — v4 Tools capability (LLM function calling).
//
// §15 type-discipline: tool-calling types come from
// `generated/tool_calling.pb.dart`; orchestration runs inside commons
// via the tool-calling session state machine
// (`rac_tool_calling_session_*_proto`). Dart is a thin executor adapter
// that runs registered closures when commons requests them.
//
// Mirrors Swift `RunAnywhere+ToolCalling.swift`.

import 'dart:async';
import 'dart:convert';
import 'dart:ffi' show nullptr;

import 'package:ffi/ffi.dart' show Utf8Pointer;
import 'package:protobuf/protobuf.dart'
    show GeneratedMessageGenericExtensions;
import 'package:runanywhere/core/native/rac_native.dart' show RacNative;
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/llm_options.pb.dart'
    show LLMGenerationOptions;
import 'package:runanywhere/generated/tool_calling.pb.dart'
    show
        ToolCall,
        ToolCallFormatName,
        ToolCallingOptions,
        ToolCallingResult,
        ToolCallingSessionCreateRequest,
        ToolCallingSessionEvent,
        ToolCallingSessionEvent_Kind,
        ToolChoiceMode,
        ToolDefinition,
        ToolResult,
        ToolValue,
        ToolValueArray,
        ToolValueObject;
import 'package:runanywhere/native/dart_bridge_tool_calling.dart';

/// Executor signature for a tool call.
///
/// Receives the JSON-decoded arguments map (parsed from
/// `ToolCall.argumentsJson`) and returns a JSON-encodable result
/// map. The framework re-encodes the result into
/// `ToolResult.resultJson`.
typedef ToolExecutor = Future<Map<String, dynamic>> Function(
    Map<String, dynamic> args);

/// Executor signature for callers that want generated-proto tool values
/// instead of untyped JSON maps.
typedef TypedToolExecutor = Future<Map<String, ToolValue>> Function(
  Map<String, ToolValue> args,
);

/// Tools (function calling) capability surface.
///
/// Access via `RunAnywhere.tools`.
class RunAnywhereTools {
  RunAnywhereTools._();
  static final RunAnywhereTools _instance = RunAnywhereTools._();
  static RunAnywhereTools get shared => _instance;

  static final Map<String, ToolExecutor> _toolExecutors = {};
  static final Map<String, ToolDefinition> _toolDefinitions = {};
  static final _logger = SDKLogger('RunAnywhere.ToolCalling');

  // Tracks the in-flight session handle so callers can issue
  // a structured-cancel via `cancelGeneration()`. Mirrors the Swift
  // `withTaskCancellationHandler` / Kotlin `invokeOnCompletion` /
  // RN `AbortSignal` / Web `AbortController.abort()` surfaces. Single
  // active generation at a time — concurrent calls overwrite the prior
  // handle (consistent with the rest of the Flutter capability surface,
  // which is single-active-call per capability instance).
  static int _activeSessionHandle = 0;

  // -- registration

  /// Register a tool that the LLM can use.
  ///
  /// Mirrors Swift `RunAnywhere.registerTool(_:executor:)`. Tools are stored
  /// in-memory and available for all subsequent `generateWithTools` calls.
  void registerTool(ToolDefinition definition, ToolExecutor executor) {
    _toolDefinitions[definition.name] = definition;
    _toolExecutors[definition.name] = executor;
    _logger.info('Registered tool: ${definition.name}');
  }


  /// Unregister a tool by name.
  ///
  /// Mirrors Swift `RunAnywhere.unregisterTool(_:)`.
  void unregisterTool(String toolName) {
    _toolDefinitions.remove(toolName);
    _toolExecutors.remove(toolName);
    _logger.info('Unregistered tool: $toolName');
  }

  /// Get all registered tool definitions.
  ///
  /// Mirrors Swift `RunAnywhere.getRegisteredTools()`.
  List<ToolDefinition> getRegisteredTools() =>
      List.unmodifiable(_toolDefinitions.values.toList());

  /// Clear all registered tools.
  ///
  /// Mirrors Swift `RunAnywhere.clearTools()`.
  void clearTools() {
    _toolDefinitions.clear();
    _toolExecutors.clear();
    _logger.info('Cleared all registered tools');
  }

  // -- execution

  /// Execute a tool call manually. Used when `autoExecute: false` is
  /// passed to `generateWithTools`.
  ///
  /// Mirrors Swift `RunAnywhere.executeTool(_:)` semantics
  /// (RunAnywhere+ToolCalling.swift:158-203): unknown tools, argument
  /// parse failures, and executor errors all surface as `success: false`
  /// results — a parse failure must NOT silently execute the tool with
  /// empty arguments, which would make bad model output look like a
  /// successful empty-argument call.
  Future<ToolResult> execute(ToolCall toolCall) async {
    final executor = _toolExecutors[toolCall.name];
    if (executor == null) {
      return ToolResult(
        toolCallId: toolCall.id,
        name: toolCall.name,
        success: false,
        error: 'Tool not found: ${toolCall.name}',
      );
    }

    Map<String, dynamic> args = const {};
    if (toolCall.argumentsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(toolCall.argumentsJson);
        if (decoded is Map<String, dynamic>) {
          args = decoded;
        } else {
          return ToolResult(
            toolCallId: toolCall.id,
            name: toolCall.name,
            success: false,
            error: 'Failed to parse tool arguments: expected a JSON object, '
                'got ${decoded.runtimeType}',
          );
        }
      } catch (e) {
        return ToolResult(
          toolCallId: toolCall.id,
          name: toolCall.name,
          success: false,
          error: 'Failed to parse tool arguments: $e',
        );
      }
    }

    try {
      _logger.debug('Executing tool: ${toolCall.name}');
      final result = await executor(args);
      _logger.debug('Tool ${toolCall.name} completed successfully');
      return ToolResult(
        toolCallId: toolCall.id,
        name: toolCall.name,
        success: true,
        resultJson: jsonEncode(result),
      );
    } catch (e) {
      _logger.error('Tool ${toolCall.name} failed: $e');
      return ToolResult(
        toolCallId: toolCall.id,
        name: toolCall.name,
        success: false,
        error: e.toString(),
      );
    }
  }

  // -- tool-enabled generation

  /// Generate text with tool calling support. Delegates the full
  /// parse-execute-loop to commons via
  /// `rac_tool_calling_session_create_proto`; Dart only runs registered
  /// executors when commons emits a `tool_call` event.
  ///
  /// [toolChoice] mirrors the OpenAI `tool_choice` knob: callers can pin
  /// the LLM to NONE / AUTO / SPECIFIC without having to manually mutate
  /// a [ToolCallingOptions] proto. When non-null it overrides
  /// `options.toolChoice` for this call.
  /// [forcedToolName] is the companion to `toolChoice=SPECIFIC` — the
  /// tool name the LLM is forced to invoke. Overrides
  /// `options.forcedToolName` when non-null.
  ///
  /// Mirrors Swift `RunAnywhere.generateWithTools(prompt:options:toolOptions:toolChoice:forcedToolName:validateCalls:)`
  /// (`RunAnywhere+ToolCalling.swift:250-280`, `makeRunLoopRequest:491-548`):
  /// tool options take precedence per knob, falling back to the LLM
  /// generation [llmOptions]; `top_p` always comes from the LLM options;
  /// `validate_calls` is left UNSET unless the caller supplies it (commons
  /// applies its documented default).
  Future<ToolCallingResult> generateWithTools(
    String prompt, {
    LLMGenerationOptions? llmOptions,
    ToolCallingOptions? options,
    ToolChoiceMode? toolChoice,
    String? forcedToolName,
    bool? validateCalls,
  }) async {
    // Swift default: `options: RALLMGenerationOptions = .defaults()`.
    final llm = llmOptions ?? _defaultLLMOptions();
    // Swift: `toolOptions ?? (options.hasToolCalling ? options.toolCalling
    // : RAToolCallingOptions.defaults())`.
    final opts = (options ??
            (llm.hasToolCalling() ? llm.toolCalling : _defaultToolOptions()))
        .deepCopy();
    if (toolChoice != null) {
      opts.toolChoice = toolChoice;
    }
    if (forcedToolName != null) {
      opts.forcedToolName = forcedToolName;
    }
    final tools = opts.tools.isNotEmpty ? opts.tools : getRegisteredTools();
    final autoExecute = opts.hasAutoExecute() ? opts.autoExecute : true;

    // Mirrors Swift makeRunLoopRequest (RunAnywhere+ToolCalling.swift:491-548).
    final request = ToolCallingSessionCreateRequest(
      prompt: prompt,
      tools: tools,
      formatHint: opts.resolvedFormatName,
      maxIterations: opts.maxToolCallCount,
      keepToolsAvailable: opts.keepToolsAvailable,
      maxTokens: (opts.hasMaxTokens() && opts.maxTokens > 0)
          ? opts.maxTokens
          : llm.maxTokens,
      temperature: opts.hasTemperature() ? opts.temperature : llm.temperature,
      topP: llm.topP,
      // Suppress thinking when either options surface asks for it.
      disableThinking: opts.disableThinking || llm.disableThinking,
    );
    // `validate_calls` is `optional bool` on the proto — leave it UNSET when
    // the caller did not supply a value so commons applies its documented
    // default (true).
    if (validateCalls != null) {
      request.validateCalls = validateCalls;
    }
    if (opts.toolChoice != ToolChoiceMode.TOOL_CHOICE_MODE_UNSPECIFIED) {
      request.toolChoice = opts.toolChoice;
    }
    if (opts.hasForcedToolName() && opts.forcedToolName.isNotEmpty) {
      request.forcedToolName = opts.forcedToolName;
    }
    // System prompt: tool options win, then the LLM options.
    if (opts.hasSystemPrompt() && opts.systemPrompt.isNotEmpty) {
      request.systemPrompt = opts.systemPrompt;
    } else if (llm.hasSystemPrompt() && llm.systemPrompt.isNotEmpty) {
      request.systemPrompt = llm.systemPrompt;
    }

    final session = DartBridgeToolCalling.shared.createSession(request);
    // Publish the active session handle so consumers can
    // call `RunAnywhereTools.shared.cancelGeneration()` to interrupt the
    // in-flight loop (mirrors RunAnywhereLLM.cancelGeneration). The native
    // session id resolves a turn after create starts (it now runs off the UI
    // isolate), so publish it once known.
    unawaited(session.sessionId
        .then((id) => _activeSessionHandle = id)
        .catchError((Object _) => _activeSessionHandle));
    final collectedCalls = <ToolCall>[];
    final collectedResults = <ToolResult>[];
    final completer = Completer<ToolCallingResult>();

    late final StreamSubscription<ToolCallingSessionEvent> sub;
    sub = session.events.listen(
      (event) async {
        switch (event.whichKind()) {
          case ToolCallingSessionEvent_Kind.toolCall:
            final call = event.toolCall;
            collectedCalls.add(call);
            _logger.info('Tool call detected: ${call.name}');
            if (!autoExecute) {
              if (!completer.isCompleted) {
                completer.complete(
                  ToolCallingResult(
                    text: '',
                    toolCalls: collectedCalls,
                    toolResults: collectedResults,
                    isComplete: false,
                  ),
                );
              }
              await sub.cancel();
              return;
            }
            // Forward the result to the session worker, which fills in its own
            // session id and runs the next turn off the UI isolate; the turn's
            // events arrive back on this stream.
            try {
              final result = await execute(call);
              collectedResults.add(result);
              session.stepWithResult(
                toolCallId: call.id,
                resultJson: result.resultJson,
                error: result.error,
              );
            } catch (e) {
              _logger.error('Tool executor threw: $e');
              session.stepWithResult(
                toolCallId: call.id,
                resultJson: '',
                error: e.toString(),
              );
            }
            break;
          case ToolCallingSessionEvent_Kind.finalResult:
            if (!completer.isCompleted) {
              completer.complete(event.finalResult);
            }
            await sub.cancel();
            break;
          case ToolCallingSessionEvent_Kind.errorBytes:
            if (!completer.isCompleted) {
              completer.completeError(
                StateError('Tool calling session error bytes received'),
              );
            }
            await sub.cancel();
            break;
          case ToolCallingSessionEvent_Kind.llmStreamEventBytes:
          case ToolCallingSessionEvent_Kind.notSet:
            break;
        }
      },
      onError: (Object error, StackTrace stackTrace) async {
        if (!completer.isCompleted) {
          completer.completeError(error, stackTrace);
        }
        await sub.cancel();
      },
    );

    try {
      return await completer.future;
    } finally {
      // Clear the published handle BEFORE close — once close
      // returns, any pending cancelGeneration() call would race a freshly
      // started session.
      if (_activeSessionHandle == session.resolvedSessionId) {
        _activeSessionHandle = 0;
      }
      await session.close();
    }
  }

  /// Cancel the in-flight `generateWithTools` call, if any.
  ///
  /// Routes through `rac_tool_calling_session_cancel_proto`
  /// via [DartBridgeToolCalling.cancelSession]. Idempotent — a no-op when no
  /// session is in flight (returns `false`). Safe to call from any isolate
  /// for which the bridge is loaded; the underlying ABI is documented as
  /// thread-safe and idempotent.
  ///
  /// Mirrors Swift `withTaskCancellationHandler`, Kotlin `invokeOnCompletion`,
  /// RN `AbortSignal`, and Web `AbortController.abort()` behavior on
  /// `generateWithTools`.
  ///
  /// Returns `true` when a cancel was issued to a live session; `false` when
  /// no session was active (idempotent no-op) or when the underlying ABI
  /// rejected the request.
  bool cancelGeneration() {
    final handle = _activeSessionHandle;
    if (handle == 0) {
      _logger.debug(
          'cancelGeneration: no active tool-calling session to cancel');
      return false;
    }
    _logger.info('Cancelling in-flight tool-calling session: handle=$handle');
    return DartBridgeToolCalling.shared.cancelSession(handle);
  }


  // -- helpers

  /// Mirrors Swift `RALLMGenerationOptions.defaults()`
  /// (RALLMTypes+CppBridge.swift:13-21).
  static LLMGenerationOptions _defaultLLMOptions() => LLMGenerationOptions(
        maxTokens: 100,
        temperature: 0.8,
        topP: 1.0,
        topK: 0,
        repetitionPenalty: 1.0,
      );

  /// Mirrors Swift `RAToolCallingOptions.defaults()`
  /// (ToolCallingTypes.swift:148-154).
  static ToolCallingOptions _defaultToolOptions() => ToolCallingOptions(
        maxIterations: 5,
        maxToolCalls: 5,
        autoExecute: true,
        format: ToolCallFormatName.TOOL_CALL_FORMAT_NAME_JSON,
        formatHint: 'default',
      );
}

/// Run-loop knobs derived from [ToolCallingOptions]. Mirrors Swift's
/// `RAToolCallingOptions` extension (ToolCallingTypes.swift:157-171).
extension ToolCallingOptionsRunLoop on ToolCallingOptions {
  /// Effective max tool-call iterations — explicit max_tool_calls wins over
  /// max_iterations; non-positive values fall back to 5.
  int get maxToolCallCount {
    final explicit = hasMaxToolCalls() ? maxToolCalls : maxIterations;
    return explicit > 0 ? explicit : 5;
  }

  /// Format hint string for the commons session request. Delegates the
  /// proto-enum → hint-string mapping to commons
  /// (`rac_tool_call_format_hint_from_format_name`) so every SDK shares one
  /// source of truth.
  String get resolvedFormatName {
    if (hasFormat()) {
      final fn =
          RacNative.bindings.rac_tool_call_format_hint_from_format_name;
      if (fn != null) {
        final ptr = fn(format.value);
        if (ptr != nullptr) {
          // Static literal owned by commons — read, never free.
          return ptr.toDartString();
        }
      }
    }
    return formatHint.isEmpty ? 'default' : formatHint;
  }
}

/// Generated-proto [ToolValue] helpers. Recursive JSON conversion lives in
/// commons; this class only exposes ergonomic Dart entrypoints.
abstract final class ToolValues {
  static ToolValue string(String value) => ToolValue(stringValue: value);

  static ToolValue intValue(int value) =>
      ToolValue(numberValue: value.toDouble());

  static ToolValue number(num value) =>
      ToolValue(numberValue: value.toDouble());

  static ToolValue boolean(bool value) => ToolValue(boolValue: value);

  static ToolValue nullValue() => ToolValue(nullValue: true);

  static ToolValue array(Iterable<ToolValue> values) =>
      ToolValue(arrayValue: ToolValueArray(values: values));

  static ToolValue object(Map<String, ToolValue> fields) =>
      ToolValue(objectValue: ToolValueObject(fields: fields.entries));

  static String toJSONString(ToolValue value) =>
      DartBridgeToolCalling.shared.toolValueToJson(value);

  static ToolValue fromJSONString(String json) =>
      DartBridgeToolCalling.shared.toolValueFromJson(json);

  static Map<String, ToolValue> parseObjectJSON(String json) {
    final value = fromJSONString(json);
    return value.hasObjectValue()
        ? Map.unmodifiable(value.objectValue.fields)
        : const <String, ToolValue>{};
  }

  static String jsonStringFromObject(Map<String, ToolValue> object) =>
      toJSONString(ToolValue(objectValue: ToolValueObject(fields: object.entries)));
}

extension ToolValueAccessors on ToolValue {
  String? get string {
    return hasStringValue() ? stringValue : null;
  }

  double? get number {
    return hasNumberValue() ? numberValue : null;
  }

  int? get intValue {
    final value = number;
    return value?.toInt();
  }

  bool? get boolean {
    return hasBoolValue() ? boolValue : null;
  }

  List<ToolValue>? get array {
    return hasArrayValue() ? List.unmodifiable(arrayValue.values) : null;
  }

  Map<String, ToolValue>? get object {
    return hasObjectValue() ? Map.unmodifiable(objectValue.fields) : null;
  }

  bool get isNull => hasNullValue() && nullValue;

  String? toJSONString() {
    return ToolValues.toJSONString(this);
  }
}
