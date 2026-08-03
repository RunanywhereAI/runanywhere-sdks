// SPDX-License-Identifier: Apache-2.0
//
// `RunAnywhere.llm` — text generation, tool calling, and structured output.

import 'dart:async';
import 'package:runanywhere/foundation/errors/sdk_exception.dart';
import 'package:runanywhere/generated/llm_options.pb.dart'
    show LLMGenerationOptions;
import 'package:runanywhere/generated/llm_service.pb.dart'
    show LLMGenerateRequest, LLMStreamEvent;
import 'package:runanywhere/generated/structured_output.pb.dart'
    show JSONSchema;
import 'package:runanywhere/generated/tool_calling.pb.dart'
    show ToolCall, ToolDefinition, ToolResult;
import 'package:runanywhere/generated/tool_calling.pbenum.dart'
    show ToolChoiceMode;
import 'package:runanywhere/generated/voice_events.pbenum.dart' as voice_pb;
import 'package:runanywhere/native/dart_bridge.dart';
import 'package:runanywhere/native/dart_bridge_llm.dart';
import 'package:runanywhere/public/api/internal/model_gate.dart';
import 'package:runanywhere/public/api/types/events.dart';
import 'package:runanywhere/public/api/types/inputs.dart';
import 'package:runanywhere/public/api/types/options.dart';
import 'package:runanywhere/public/api/types/results.dart';
import 'package:runanywhere/public/capabilities/runanywhere_tools.dart';
import 'package:runanywhere/public/extensions/runanywhere_structured_output.dart';

/// Executor invoked when the model calls a registered tool.
///
/// Receives the decoded call arguments and returns a JSON-encodable result.
typedef ToolRunner = ToolExecutor;

/// Text generation.
class LlmApi {
  /// Bind the namespace. Reach it through `RunAnywhere.llm`.
  const LlmApi();

  /// Tool registry backing `options.tools` and the auto-execute loop.
  ToolsApi get tools => const ToolsApi();

  /// Generate a completion for [prompt].
  ///
  /// ```dart
  /// final result = await RunAnywhere.llm.generate('Say hello');
  /// print(result.text);
  /// ```
  ///
  /// Throws [SDKException] when no model is loadable or generation fails.
  Future<GenerationResult> generate(
    String prompt, {
    LlmOptions? options,
  }) async {
    final request = await _request(prompt: prompt, options: options);
    if (_usesTools(request)) {
      // Tool execution needs the session ABI: it is what calls back into the
      // registered executors and continues the loop.
      return _generateWithTools(prompt, request);
    }
    final result = await DartBridgeLLM.shared.generateProto(request);
    return GenerationResult.fromLlm(result, requestId: request.requestId);
  }

  /// Generate a completion for a conversation.
  ///
  /// The last message is the live turn; earlier messages become history and a
  /// leading system message becomes the system prompt.
  ///
  /// Throws [SDKException] when no model is loadable or generation fails.
  Future<GenerationResult> generateChat(
    List<ChatMessage> messages, {
    LlmOptions? options,
  }) async {
    final request = await _chatRequest(messages, options);
    if (_usesTools(request)) {
      return _generateWithTools(
        request.prompt,
        request,
        history: messages
            .where((m) => m.role != ChatRole.system)
            .map((m) => m.content)
            .toList()
          ..removeLast(),
      );
    }
    final result = await DartBridgeLLM.shared.generateProto(request);
    return GenerationResult.fromLlm(result, requestId: request.requestId);
  }

  /// Stream a completion for [prompt] token by token.
  ///
  /// When [options] puts tools in play the turn arrives as a single token
  /// event: the tool-execution loop has no incremental native stream.
  ///
  /// ```dart
  /// await for (final e in RunAnywhere.llm.generateStream('Say hello')) {
  ///   if (e is GenerationToken) stdout.write(e.text);
  /// }
  /// ```
  ///
  /// Throws [SDKException] into the consumer when generation fails.
  Stream<GenerationEvent> generateStream(
    String prompt, {
    LlmOptions? options,
  }) => _stream(() => _request(prompt: prompt, options: options));

  /// Stream a completion for a conversation token by token.
  ///
  /// Throws [SDKException] into the consumer when generation fails.
  Stream<GenerationEvent> generateChatStream(
    List<ChatMessage> messages, {
    LlmOptions? options,
  }) => _stream(() => _chatRequest(messages, options));

  /// Generate a completion constrained to [schema].
  ///
  /// Throws [SDKException] when generation fails or the output cannot be
  /// parsed against the schema.
  Future<StructuredResult> generateStructured(
    String prompt,
    JSONSchema schema, {
    LlmOptions? options,
  }) async {
    await ModelGate.ensureLoaded(
      modelId: options?.model,
      category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    );
    final effective = options ?? LlmOptions();
    final proto = await RunAnywhereStructuredOutput.generateStructured(
      prompt: prompt,
      schema: schema,
      options: effective.toProto(
        registeredTools: RunAnywhereTools.shared.getRegisteredTools(),
      ),
    );
    return StructuredResult.fromProto(
      proto,
      GenerationResult(
        text: proto.hasRawText() ? proto.rawText : '',
        model: await ModelGate.currentId(
              ModelCategory.MODEL_CATEGORY_LANGUAGE,
            ) ??
            '',
      ),
    );
  }

  /// Cancel the in-flight generation on this namespace, if any.
  void cancel() {
    if (!DartBridge.isInitialized) return;
    DartBridgeLLM.shared.cancelProto();
  }

  static bool _usesTools(LLMGenerateRequest request) {
    if (!request.hasOptions() || !request.options.hasToolCalling()) {
      return false;
    }
    final calling = request.options.toolCalling;
    return calling.tools.isNotEmpty &&
        calling.toolChoice != ToolChoiceMode.TOOL_CHOICE_MODE_NONE;
  }

  Future<GenerationResult> _generateWithTools(
    String prompt,
    LLMGenerateRequest request, {
    List<String> history = const <String>[],
  }) async {
    final result = await RunAnywhereTools.shared.generateWithTools(
      prompt,
      llmOptions: request.options,
      options: request.options.toolCalling,
      history: history,
    );
    if (result.hasErrorMessage()) {
      throw SDKException.generationFailed(result.errorMessage);
    }
    return GenerationResult(
      text: result.text,
      thinkingText: result.hasThinkingContent() && result.thinkingContent.isNotEmpty
          ? result.thinkingContent
          : null,
      toolCalls: List<ToolCall>.unmodifiable(result.toolCalls),
      toolResults: List<ToolResult>.unmodifiable(result.toolResults),
      finishReason: result.toolCalls.isEmpty
          ? FinishReason.stop
          : FinishReason.toolCalls,
      inputTokens: result.usage.inputTokens,
      outputTokens: result.usage.outputTokens,
      tokensPerSecond: result.usage.tokensPerSecond,
      requestId: request.requestId,
      model:
          await ModelGate.currentId(ModelCategory.MODEL_CATEGORY_LANGUAGE) ?? '',
    );
  }

  Stream<GenerationEvent> _stream(
    Future<LLMGenerateRequest> Function() build,
  ) {
    final controller = StreamController<GenerationEvent>();
    controller.onListen = () {
      unawaited(_pump(controller, build));
    };
    controller.onCancel = cancel;
    return controller.stream;
  }

  Future<void> _pump(
    StreamController<GenerationEvent> controller,
    Future<LLMGenerateRequest> Function() build,
  ) async {
    try {
      final request = await build();
      controller.add(GenerationStarted(request.requestId));
      if (_usesTools(request)) {
        // The tool-execution loop lives behind the session ABI, which has no
        // token stream: the turn is delivered as one chunk once tools resolve.
        final result = await _generateWithTools(request.prompt, request);
        if (result.text.isNotEmpty) {
          controller.add(GenerationToken(result.text));
        }
        for (final call in result.toolCalls) {
          controller.add(GenerationToolCall(call));
        }
        controller.add(GenerationCompleted(result));
        return;
      }
      final model =
          await ModelGate.currentId(ModelCategory.MODEL_CATEGORY_LANGUAGE) ?? '';
      final buffer = StringBuffer();
      final thinking = StringBuffer();
      LLMStreamEvent? terminal;

      await for (final event in DartBridgeLLM.shared.generateStreamProto(
        request,
      )) {
        if (event.token.isNotEmpty) {
          final kind = event.kind == voice_pb.TokenKind.TOKEN_KIND_THOUGHT
              ? TokenKind.thought
              : TokenKind.text;
          if (kind == TokenKind.thought) {
            thinking.write(event.token);
          } else {
            buffer.write(event.token);
          }
          controller.add(GenerationToken(event.token, kind: kind));
        }
        if (event.isFinal) {
          terminal = event;
          break;
        }
      }

      if (terminal != null && terminal.hasError()) {
        throw SDKException.generationFailed(terminal.error.message);
      }

      final result = terminal != null && terminal.hasResult()
          ? GenerationResult.fromStreamFinal(
              terminal.result,
              requestId: request.requestId,
              model: model,
            )
          : GenerationResult(
              text: buffer.toString(),
              thinkingText: thinking.isEmpty ? null : thinking.toString(),
              finishReason: _finish(terminal?.finishReason),
              outputTokens: 0,
              requestId: request.requestId,
              model: model,
            );
      for (final call in result.toolCalls) {
        controller.add(GenerationToolCall(call));
      }
      controller.add(GenerationCompleted(result));
    } catch (error, stack) {
      controller.addError(
        error is SDKException ? error : SDKException.generationFailed('$error'),
        stack,
      );
    } finally {
      await controller.close();
    }
  }

  static FinishReason _finish(String? wire) {
    switch (wire) {
      case 'length':
        return FinishReason.length;
      case 'cancelled':
        return FinishReason.cancelled;
      default:
        return FinishReason.stop;
    }
  }

  Future<LLMGenerateRequest> _request({
    required String prompt,
    LlmOptions? options,
  }) async {
    await ModelGate.ensureLoaded(
      modelId: options?.model,
      category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    );
    return LLMGenerateRequest(
      prompt: prompt,
      requestId: _requestId(),
      options: _options(options),
    );
  }

  Future<LLMGenerateRequest> _chatRequest(
    List<ChatMessage> messages,
    LlmOptions? options,
  ) async {
    if (messages.isEmpty) {
      throw SDKException.invalidInput('messages must not be empty');
    }
    await ModelGate.ensureLoaded(
      modelId: options?.model,
      category: ModelCategory.MODEL_CATEGORY_LANGUAGE,
    );

    final system = messages
        .where((m) => m.role == ChatRole.system)
        .map((m) => m.content)
        .join('\n');
    final turns = messages.where((m) => m.role != ChatRole.system).toList();
    if (turns.isEmpty) {
      throw SDKException.invalidInput('messages must carry a non-system turn');
    }
    final live = turns.removeLast();

    final proto = _options(options);
    if (system.isNotEmpty && !proto.hasSystemPrompt()) {
      proto.systemPrompt = system;
    }
    return LLMGenerateRequest(
      prompt: live.content,
      requestId: _requestId(),
      options: proto,
      history: turns.map((m) => m.toProto()),
    );
  }

  LLMGenerationOptions _options(LlmOptions? options) =>
      (options ?? LlmOptions()).toProto(
        registeredTools: RunAnywhereTools.shared.getRegisteredTools(),
      );

  static String _requestId() =>
      'llm-${DateTime.now().microsecondsSinceEpoch}';
}

/// Registry of tools the model may call.
class ToolsApi {
  /// Bind the namespace. Reach it through `RunAnywhere.llm.tools`.
  const ToolsApi();

  /// Register [tool] and the [executor] that runs it.
  ///
  /// ```dart
  /// RunAnywhere.llm.tools.register(weatherTool, (args) async => {'c': 21});
  /// ```
  void register(ToolDefinition tool, ToolRunner executor) =>
      RunAnywhereTools.shared.registerTool(tool, executor);

  /// Remove the tool registered under [name].
  void unregister(String name) =>
      RunAnywhereTools.shared.unregisterTool(name);

  /// Every registered tool definition.
  List<ToolDefinition> list() => RunAnywhereTools.shared.getRegisteredTools();
}
