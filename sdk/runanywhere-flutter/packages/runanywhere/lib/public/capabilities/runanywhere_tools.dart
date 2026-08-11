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

import 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/convenience/ra_convenience.dart';
import 'package:runanywhere/generated/finish_reason.pbenum.dart'
    show FinishReason;
import 'package:runanywhere/generated/llm_options.pb.dart'
    show LLMGenerationOptions;
import 'package:runanywhere/generated/thinking_tag_pattern.pbenum.dart'
    show ReasoningMode;
import 'package:runanywhere/generated/tool_calling.pb.dart'
    show
        ToolCall,
        ToolCallFormatName,
        ToolCallingHistoryTurn,
        ToolCallingOptions,
        ToolCallingResult,
        ToolCallingRole,
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
typedef ToolExecutor =
    Future<Map<String, dynamic>> Function(Map<String, dynamic> args);

/// Executor signature for callers that want generated-proto tool values
/// instead of untyped JSON maps.
typedef TypedToolExecutor =
    Future<Map<String, ToolValue>> Function(Map<String, ToolValue> args);

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
        isError: true,
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
            isError: true,
            error:
                'Failed to parse tool arguments: expected a JSON object, '
                'got ${decoded.runtimeType}',
          );
        }
      } catch (e) {
        return ToolResult(
          toolCallId: toolCall.id,
          name: toolCall.name,
          isError: true,
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
        isError: false,
        resultJson: jsonEncode(result),
      );
    } catch (e) {
      _logger.error('Tool ${toolCall.name} failed: $e');
      return ToolResult(
        toolCallId: toolCall.id,
        name: toolCall.name,
        isError: true,
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
  /// Mirrors Swift `RunAnywhere.generateWithTools(prompt:options:toolOptions:toolChoice:forcedToolName:validateCalls:)`
  /// (`RunAnywhere+ToolCalling.swift:250-280`, `makeRunLoopRequest:491-548`):
  /// tool options take precedence per knob, falling back to the LLM
  /// generation [llmOptions]; `top_p` always comes from the LLM options;
  /// `validate_calls` is left UNSET unless the caller supplies it (commons
  /// applies its documented default).
  ///
  /// [history] carries prior conversation turns as a flat alternating list
  /// `[user0, asst0, user1, asst1, ...]`, EXCLUDING the current turn (which
  /// travels as [prompt]). commons threads it through the session path so
  /// multi-turn tool use keeps context, matching the standard generate path's
  /// message history as strings. Defaulted empty for source compatibility.
  Future<ToolCallingResult> generateWithTools(
    String prompt, {
    LLMGenerationOptions? llmOptions,
    ToolCallingOptions? options,
    ToolChoiceMode? toolChoice,
    String? forcedToolName,
    bool? validateCalls,
    bool? parallelToolCalls,
    List<String> history = const [],
  }) async {
    // Swift default: `options: RALLMGenerationOptions = .defaults()`.
    final llm = llmOptions ?? _defaultLLMOptions();
    // Swift: `toolOptions ?? (options.hasToolCalling ? options.toolCalling
    // : RAToolCallingOptions())`.
    final opts =
        (options ??
                (llm.hasToolCalling() ? llm.toolCalling : _defaultToolOptions()))
            .deepCopy();
    if (toolChoice != null) {
      opts.toolChoice = toolChoice;
    }
    if (forcedToolName != null) {
      opts.forcedToolName = forcedToolName;
    }
    if (parallelToolCalls != null) {
      opts.parallelToolCalls = parallelToolCalls;
    }
    if (validateCalls != null) {
      opts.validateCalls = validateCalls;
    }
    if (opts.tools.isEmpty) {
      opts.tools.addAll(getRegisteredTools());
    }

    // idl/tool_calling.proto collapsed ToolCallingSessionCreateRequest to
    // prompt/history/options — every generation knob (tools, format,
    // maxToolCalls, autoExecute, replaceSystemPrompt, requireJsonArguments,
    // keepToolsAvailable, parallelToolCalls, validateCalls, toolChoice,
    // forcedToolName, disableThinking, systemPrompt, topP) lives exclusively
    // on ToolCallingOptions now. temperature/maxOutputTokens have no home on
    // the new request shape at all (commons keeps its own greedy defaults
    // for the tool loop) and are intentionally dropped. Mirrors Swift
    // `generateWithTools` (RunAnywhere+ToolCalling.swift:262-321).
    if (!opts.hasTopP()) {
      opts.topP = llm.topP;
    }
    if (!opts.hasSystemPrompt() || opts.systemPrompt.isEmpty) {
      if (llm.hasSystemPrompt() && llm.systemPrompt.isNotEmpty) {
        opts.systemPrompt = llm.systemPrompt;
      }
    }
    // Suppress thinking when either options surface asks for it.
    opts.disableThinking =
        opts.disableThinking ||
        (llm.hasReasoning() &&
            llm.reasoning.mode == ReasoningMode.REASONING_MODE_OFF);

    final autoExecute = opts.hasAutoExecute() ? opts.autoExecute : true;

    // Mirrors Swift makeRunLoopRequest (RunAnywhere+ToolCalling.swift:431-452):
    // prior conversation turns as a flat alternating list [user0, asst0, ...],
    // EXCLUDING the current turn (which is `prompt`), mapped onto alternating
    // USER/ASSISTANT ToolCallingHistoryTurn entries.
    final historyTurns = [
      for (var i = 0; i < history.length; i++)
        ToolCallingHistoryTurn(
          role: i.isEven
              ? ToolCallingRole.TOOL_CALLING_ROLE_USER
              : ToolCallingRole.TOOL_CALLING_ROLE_ASSISTANT,
          content: history[i],
        ),
    ];

    final request = ToolCallingSessionCreateRequest(
      prompt: prompt,
      history: historyTurns,
      options: opts,
    );

    final session = DartBridgeToolCalling.shared.createSession(request);
    // Publish the active session handle so consumers can
    // call `RunAnywhereTools.shared.cancelGeneration()` to interrupt the
    // in-flight loop (mirrors RunAnywhereLLM.cancelGeneration). The native
    // session id is published synchronously before native generation starts,
    // so expose it as soon as the worker forwards that callback.
    unawaited(
      session.sessionId
          .then((id) => _activeSessionHandle = id)
          .catchError((Object _) => _activeSessionHandle),
    );
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
                    finishReason: FinishReason.FINISH_REASON_TOOL_CALLS,
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
        'cancelGeneration: no active tool-calling session to cancel',
      );
      return false;
    }
    _logger.info('Cancelling in-flight tool-calling session: handle=$handle');
    return DartBridgeToolCalling.shared.cancelSession(handle);
  }

  // -- helpers --------------------------------------------------------------

  /// Generated from the rac_default annotations in idl/llm_options.proto.
  static LLMGenerationOptions _defaultLLMOptions() =>
      LLMGenerationOptionsConvenience.defaults();

  /// Mirrors Swift `RAToolCallingOptions.defaults()`
  /// (ToolCallingTypes.swift:148-154).
  static ToolCallingOptions _defaultToolOptions() => ToolCallingOptions(
    maxToolCalls: 5,
    autoExecute: true,
    format: ToolCallFormatName.TOOL_CALL_FORMAT_NAME_JSON,
  );
}

/// Run-loop knobs derived from [ToolCallingOptions]. Mirrors Swift's
/// `RAToolCallingOptions` extension (ToolCallingTypes.swift:157-171).
extension ToolCallingOptionsRunLoop on ToolCallingOptions {
  /// Effective maximum tool calls; non-positive values fall back to 5.
  int get maxToolCallCount {
    final explicit = hasMaxToolCalls() ? maxToolCalls : 0;
    return explicit > 0 ? explicit : 5;
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
      toJSONString(
        ToolValue(objectValue: ToolValueObject(fields: object.entries)),
      );
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
