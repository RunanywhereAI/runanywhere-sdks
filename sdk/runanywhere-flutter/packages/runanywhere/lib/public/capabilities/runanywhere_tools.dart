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

import 'package:fixnum/fixnum.dart' show Int64;
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/tool_calling.pb.dart'
    show
        ToolCall,
        ToolCallingOptions,
        ToolCallingResult,
        ToolCallingSessionCreateRequest,
        ToolCallingSessionEvent,
        ToolCallingSessionEvent_Kind,
        ToolCallingSessionStepWithResultRequest,
        ToolChoiceMode,
        ToolDefinition,
        ToolParseRequest,
        ToolPromptFormatRequest,
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

  // -- registration ---------------------------------------------------------

  /// Register a tool that the LLM can use.
  ///
  /// Mirrors Swift `RunAnywhere.registerTool(_:executor:)`. Tools are stored
  /// in-memory and available for all subsequent `generateWithTools` calls.
  void registerTool(ToolDefinition definition, ToolExecutor executor) {
    _toolDefinitions[definition.name] = definition;
    _toolExecutors[definition.name] = executor;
    _logger.info('Registered tool: ${definition.name}');
  }

  /// Register a tool using generated [ToolValue] arguments and results.
  ///
  /// Mirrors Swift's `ToolExecutor = ([String: RAToolValue]) async throws ->
  /// [String: RAToolValue]`. JSON conversion is delegated to commons via
  /// `rac_tool_value_*_proto`.
  void registerTypedTool(
    ToolDefinition definition,
    TypedToolExecutor executor,
  ) {
    registerTool(definition, (args) async {
      final typedArgs = ToolValues.parseObjectJSON(jsonEncode(args));
      final typedResult = await executor(typedArgs);
      final resultJson = ToolValues.jsonStringFromObject(typedResult);
      final decoded = jsonDecode(resultJson);
      return decoded is Map<String, dynamic>
          ? decoded
          : <String, dynamic>{'value': decoded};
    });
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
  /// Mirrors Swift `RunAnywhere.generateWithTools(prompt:options:toolOptions:toolChoice:forcedToolName:)`
  /// (`RunAnywhere+ToolCalling.swift:234-253`, `makeRunLoopRequest:457-514`).
  Future<ToolCallingResult> generateWithTools(
    String prompt, {
    ToolCallingOptions? options,
    ToolChoiceMode? toolChoice,
    String? forcedToolName,
  }) async {
    final opts = options ?? ToolCallingOptions();
    final tools = opts.tools.isNotEmpty ? opts.tools : getRegisteredTools();
    final autoExecute = opts.hasAutoExecute() ? opts.autoExecute : true;

    // Thread tool_choice / forced_tool_name
    // all the way through to the commons request envelope (fields 7/8 on
    // ToolCallingSessionCreateRequest) so the run-loop / session APIs see
    // them — not just the inline ToolCallingOptions snapshot. Top-level
    // kw args override the options snapshot to mirror Swift behavior.
    final ToolChoiceMode? effectiveToolChoice = toolChoice ??
        (opts.hasToolChoice() &&
                opts.toolChoice != ToolChoiceMode.TOOL_CHOICE_MODE_UNSPECIFIED
            ? opts.toolChoice
            : null);
    final String? effectiveForcedToolName = forcedToolName ??
        (opts.hasForcedToolName() && opts.forcedToolName.isNotEmpty
            ? opts.forcedToolName
            : null);

    final request = ToolCallingSessionCreateRequest(
      prompt: prompt,
      tools: tools,
      formatHint: opts.formatHint,
      maxIterations: opts.hasMaxIterations() ? opts.maxIterations : 5,
      keepToolsAvailable:
          opts.hasKeepToolsAvailable() ? opts.keepToolsAvailable : false,
      validateCalls: true,
      toolChoice: effectiveToolChoice,
      forcedToolName: effectiveForcedToolName,
      maxTokens: opts.hasMaxTokens() ? opts.maxTokens : 1024,
      temperature: opts.hasTemperature() ? opts.temperature : 0.3,
      // Suppress thinking when requested (commons prepends the no-think directive).
      disableThinking: opts.hasDisableThinking() && opts.disableThinking,
    );

    final session = DartBridgeToolCalling.shared.createSession(request);
    // Publish the active session handle so consumers can
    // call `RunAnywhereTools.shared.cancelGeneration()` to interrupt the
    // in-flight loop (mirrors RunAnywhereLLM.cancelGeneration).
    _activeSessionHandle = session.sessionHandle;
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
            try {
              final result = await execute(call);
              collectedResults.add(result);
              DartBridgeToolCalling.shared.sessionStepWithResult(
                ToolCallingSessionStepWithResultRequest(
                  sessionHandle: _toFixnum(session.sessionHandle),
                  toolCallId: call.id,
                  resultJson: result.resultJson,
                  error: result.error,
                ),
              );
            } catch (e) {
              _logger.error('Tool executor threw: $e');
              DartBridgeToolCalling.shared.sessionStepWithResult(
                ToolCallingSessionStepWithResultRequest(
                  sessionHandle: _toFixnum(session.sessionHandle),
                  toolCallId: call.id,
                  resultJson: '',
                  error: e.toString(),
                ),
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
      if (_activeSessionHandle == session.sessionHandle) {
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

  /// Continue generation after manual tool execution (used when
  /// `autoExecute: false`). The previous turn's session is already closed;
  /// we let commons orchestrate a fresh session for the continuation.
  Future<ToolCallingResult> continueWithToolResult(
    String originalPrompt,
    ToolResult toolResult, {
    ToolCallingOptions? options,
  }) async {
    final opts = options ?? ToolCallingOptions();
    final followup = DartBridgeToolCalling.shared.formatPrompt(
      ToolPromptFormatRequest(
        userPrompt: originalPrompt,
        options: opts,
        toolResults: [toolResult],
      ),
    );
    return generateWithTools(
      followup.formattedPrompt.isNotEmpty
          ? followup.formattedPrompt
          : originalPrompt,
      options: opts,
    );
  }

  // -- helpers --------------------------------------------------------------

  /// Format the registered tools into a system-prompt snippet using commons.
  String formatToolsForPrompt([List<ToolDefinition>? tools]) {
    final toolList = tools ?? getRegisteredTools();
    if (toolList.isEmpty) return '';
    final result = DartBridgeToolCalling.shared.formatPrompt(
      ToolPromptFormatRequest(
        options: ToolCallingOptions(tools: toolList),
      ),
    );
    return result.formattedPrompt;
  }

  /// Parse a single tool call out of raw LLM output (no auto-execution).
  ToolCall? parseToolCall(String llmOutput) {
    final result =
        DartBridgeToolCalling.shared.parse(ToolParseRequest(text: llmOutput));
    if (!result.hasToolCall || result.toolCalls.isEmpty) return null;
    return result.toolCalls.first;
  }
}

Int64 _toFixnum(int value) => Int64(value);

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
