// This is a generated file - do not edit.
//
// Generated from llm_service.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'chat.pb.dart' as $1;
import 'errors.pb.dart' as $3;
import 'llm_options.pb.dart' as $0;
import 'llm_service.pbenum.dart';
import 'tool_calling.pb.dart' as $2;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'llm_service.pbenum.dart';

/// The single request envelope for both unary and streaming generation.
class LLMGenerateRequest extends $pb.GeneratedMessage {
  factory LLMGenerateRequest({
    $core.String? requestId,
    $core.String? modelId,
    $core.String? conversationId,
    $0.LLMGenerationOptions? options,
    $core.Iterable<$1.ChatMessage>? messages,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (modelId != null) result.modelId = modelId;
    if (conversationId != null) result.conversationId = conversationId;
    if (options != null) result.options = options;
    if (messages != null) result.messages.addAll(messages);
    return result;
  }

  LLMGenerateRequest._();

  factory LLMGenerateRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LLMGenerateRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LLMGenerateRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(14, _omitFieldNames ? '' : 'requestId')
    ..aOS(15, _omitFieldNames ? '' : 'modelId')
    ..aOS(16, _omitFieldNames ? '' : 'conversationId')
    ..aOM<$0.LLMGenerationOptions>(26, _omitFieldNames ? '' : 'options',
        subBuilder: $0.LLMGenerationOptions.create)
    ..pPM<$1.ChatMessage>(28, _omitFieldNames ? '' : 'messages',
        subBuilder: $1.ChatMessage.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LLMGenerateRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LLMGenerateRequest copyWith(void Function(LLMGenerateRequest) updates) =>
      super.copyWith((message) => updates(message as LLMGenerateRequest))
          as LLMGenerateRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LLMGenerateRequest create() => LLMGenerateRequest._();
  @$core.override
  LLMGenerateRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LLMGenerateRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LLMGenerateRequest>(create);
  static LLMGenerateRequest? _defaultInstance;

  /// Correlation id, echoed on every LLMStreamEvent for this call. Empty =
  /// commons generates one, which is the normal case and matches industry
  /// practice (provider-generated: OpenAI `id`, Anthropic `request-id`). A
  /// non-empty caller value is honoured verbatim.
  @$pb.TagNumber(14)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(14)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(14)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(14)
  void clearRequestId() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(15)
  set modelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(15)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(15)
  void clearModelId() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.String get conversationId => $_getSZ(2);
  @$pb.TagNumber(16)
  set conversationId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(16)
  $core.bool hasConversationId() => $_has(2);
  @$pb.TagNumber(16)
  void clearConversationId() => $_clearField(16);

  @$pb.TagNumber(26)
  $0.LLMGenerationOptions get options => $_getN(3);
  @$pb.TagNumber(26)
  set options($0.LLMGenerationOptions value) => $_setField(26, value);
  @$pb.TagNumber(26)
  $core.bool hasOptions() => $_has(3);
  @$pb.TagNumber(26)
  void clearOptions() => $_clearField(26);
  @$pb.TagNumber(26)
  $0.LLMGenerationOptions ensureOptions() => $_ensure(3);

  /// The whole conversation, oldest first, ending with the turn the model
  /// must answer. Never empty. System turns belong in
  /// options.system_prompt, not here.
  @$pb.TagNumber(28)
  $pb.PbList<$1.ChatMessage> get messages => $_getList(4);
}

/// LLMStreamFinalResult is deleted: the stream terminates with the same
/// LLMGenerationResult type the unary call returns (see `result` below), so
/// one mapper serves both paths instead of two near-identical ones.
///
/// Exactly one terminal event per stream: event_kind == COMPLETED (with
/// `result` set) or == ERROR (with `error` set). `event_kind` is the primary
/// discriminator.
class LLMStreamEvent extends $pb.GeneratedMessage {
  factory LLMStreamEvent({
    $fixnum.Int64? seq,
    $core.String? token,
    LLMStreamEventKind? eventKind,
    $core.String? requestId,
    $2.ToolCall? toolCall,
    $3.SDKError? error,
    $core.String? partialJson,
    $0.FinishReason? finishReason,
    $0.LLMGenerationResult? result,
  }) {
    final result$ = create();
    if (seq != null) result$.seq = seq;
    if (token != null) result$.token = token;
    if (eventKind != null) result$.eventKind = eventKind;
    if (requestId != null) result$.requestId = requestId;
    if (toolCall != null) result$.toolCall = toolCall;
    if (error != null) result$.error = error;
    if (partialJson != null) result$.partialJson = partialJson;
    if (finishReason != null) result$.finishReason = finishReason;
    if (result != null) result$.result = result;
    return result$;
  }

  LLMStreamEvent._();

  factory LLMStreamEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LLMStreamEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LLMStreamEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aOS(3, _omitFieldNames ? '' : 'token')
    ..aE<LLMStreamEventKind>(12, _omitFieldNames ? '' : 'eventKind',
        enumValues: LLMStreamEventKind.values)
    ..aOS(13, _omitFieldNames ? '' : 'requestId')
    ..aOM<$2.ToolCall>(18, _omitFieldNames ? '' : 'toolCall',
        subBuilder: $2.ToolCall.create)
    ..aOM<$3.SDKError>(19, _omitFieldNames ? '' : 'error',
        subBuilder: $3.SDKError.create)
    ..aOS(20, _omitFieldNames ? '' : 'partialJson')
    ..aE<$0.FinishReason>(21, _omitFieldNames ? '' : 'finishReason',
        enumValues: $0.FinishReason.values)
    ..aOM<$0.LLMGenerationResult>(22, _omitFieldNames ? '' : 'result',
        subBuilder: $0.LLMGenerationResult.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LLMStreamEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LLMStreamEvent copyWith(void Function(LLMStreamEvent) updates) =>
      super.copyWith((message) => updates(message as LLMStreamEvent))
          as LLMStreamEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LLMStreamEvent create() => LLMStreamEvent._();
  @$core.override
  LLMStreamEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LLMStreamEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LLMStreamEvent>(create);
  static LLMStreamEvent? _defaultInstance;

  /// Monotonic sequence for tool-calling session streams (#607).
  @$pb.TagNumber(1)
  $fixnum.Int64 get seq => $_getI64(0);
  @$pb.TagNumber(1)
  set seq($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => $_clearField(1);

  /// The delta. Answer text when event_kind == TOKEN, reasoning text when
  /// event_kind == THINKING.
  @$pb.TagNumber(3)
  $core.String get token => $_getSZ(1);
  @$pb.TagNumber(3)
  set token($core.String value) => $_setString(1, value);
  @$pb.TagNumber(3)
  $core.bool hasToken() => $_has(1);
  @$pb.TagNumber(3)
  void clearToken() => $_clearField(3);

  @$pb.TagNumber(12)
  LLMStreamEventKind get eventKind => $_getN(2);
  @$pb.TagNumber(12)
  set eventKind(LLMStreamEventKind value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasEventKind() => $_has(2);
  @$pb.TagNumber(12)
  void clearEventKind() => $_clearField(12);

  /// Correlation id, echoed from the request on every event.
  @$pb.TagNumber(13)
  $core.String get requestId => $_getSZ(3);
  @$pb.TagNumber(13)
  set requestId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(13)
  $core.bool hasRequestId() => $_has(3);
  @$pb.TagNumber(13)
  void clearRequestId() => $_clearField(13);

  /// Present exactly when event_kind == TOOL_CALL.
  @$pb.TagNumber(18)
  $2.ToolCall get toolCall => $_getN(4);
  @$pb.TagNumber(18)
  set toolCall($2.ToolCall value) => $_setField(18, value);
  @$pb.TagNumber(18)
  $core.bool hasToolCall() => $_has(4);
  @$pb.TagNumber(18)
  void clearToolCall() => $_clearField(18);
  @$pb.TagNumber(18)
  $2.ToolCall ensureToolCall() => $_ensure(4);

  /// Present exactly when event_kind == ERROR.
  @$pb.TagNumber(19)
  $3.SDKError get error => $_getN(5);
  @$pb.TagNumber(19)
  set error($3.SDKError value) => $_setField(19, value);
  @$pb.TagNumber(19)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(19)
  void clearError() => $_clearField(19);
  @$pb.TagNumber(19)
  $3.SDKError ensureError() => $_ensure(5);

  /// Largest complete JSON value visible in the output so far, when
  /// LLMGenerationOptions.structured_output is set.
  @$pb.TagNumber(20)
  $core.String get partialJson => $_getSZ(6);
  @$pb.TagNumber(20)
  set partialJson($core.String value) => $_setString(6, value);
  @$pb.TagNumber(20)
  $core.bool hasPartialJson() => $_has(6);
  @$pb.TagNumber(20)
  void clearPartialJson() => $_clearField(20);

  @$pb.TagNumber(21)
  $0.FinishReason get finishReason => $_getN(7);
  @$pb.TagNumber(21)
  set finishReason($0.FinishReason value) => $_setField(21, value);
  @$pb.TagNumber(21)
  $core.bool hasFinishReason() => $_has(7);
  @$pb.TagNumber(21)
  void clearFinishReason() => $_clearField(21);

  /// Present exactly when event_kind == COMPLETED.
  @$pb.TagNumber(22)
  $0.LLMGenerationResult get result => $_getN(8);
  @$pb.TagNumber(22)
  set result($0.LLMGenerationResult value) => $_setField(22, value);
  @$pb.TagNumber(22)
  $core.bool hasResult() => $_has(8);
  @$pb.TagNumber(22)
  void clearResult() => $_clearField(22);
  @$pb.TagNumber(22)
  $0.LLMGenerationResult ensureResult() => $_ensure(8);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
