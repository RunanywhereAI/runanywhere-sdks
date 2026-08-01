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
import 'errors.pb.dart' as $4;
import 'llm_options.pb.dart' as $0;
import 'llm_service.pbenum.dart';
import 'token_usage.pb.dart' as $3;
import 'tool_calling.pb.dart' as $2;
import 'voice_events.pbenum.dart' as $5;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'llm_service.pbenum.dart';

/// The single request envelope for both unary and streaming generation.
class LLMGenerateRequest extends $pb.GeneratedMessage {
  factory LLMGenerateRequest({
    $core.String? prompt,
    $core.String? requestId,
    $core.String? modelId,
    $core.String? conversationId,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
    $0.LLMGenerationOptions? options,
    $core.Iterable<$1.ChatMessage>? history,
  }) {
    final result = create();
    if (prompt != null) result.prompt = prompt;
    if (requestId != null) result.requestId = requestId;
    if (modelId != null) result.modelId = modelId;
    if (conversationId != null) result.conversationId = conversationId;
    if (metadata != null) result.metadata.addEntries(metadata);
    if (options != null) result.options = options;
    if (history != null) result.history.addAll(history);
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
    ..aOS(1, _omitFieldNames ? '' : 'prompt')
    ..aOS(14, _omitFieldNames ? '' : 'requestId')
    ..aOS(15, _omitFieldNames ? '' : 'modelId')
    ..aOS(16, _omitFieldNames ? '' : 'conversationId')
    ..m<$core.String, $core.String>(25, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'LLMGenerateRequest.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..aOM<$0.LLMGenerationOptions>(26, _omitFieldNames ? '' : 'options',
        subBuilder: $0.LLMGenerationOptions.create)
    ..pPM<$1.ChatMessage>(27, _omitFieldNames ? '' : 'history',
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

  @$pb.TagNumber(1)
  $core.String get prompt => $_getSZ(0);
  @$pb.TagNumber(1)
  set prompt($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasPrompt() => $_has(0);
  @$pb.TagNumber(1)
  void clearPrompt() => $_clearField(1);

  @$pb.TagNumber(14)
  $core.String get requestId => $_getSZ(1);
  @$pb.TagNumber(14)
  set requestId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(14)
  $core.bool hasRequestId() => $_has(1);
  @$pb.TagNumber(14)
  void clearRequestId() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.String get modelId => $_getSZ(2);
  @$pb.TagNumber(15)
  set modelId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(15)
  $core.bool hasModelId() => $_has(2);
  @$pb.TagNumber(15)
  void clearModelId() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.String get conversationId => $_getSZ(3);
  @$pb.TagNumber(16)
  set conversationId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(16)
  $core.bool hasConversationId() => $_has(3);
  @$pb.TagNumber(16)
  void clearConversationId() => $_clearField(16);

  @$pb.TagNumber(25)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(4);

  @$pb.TagNumber(26)
  $0.LLMGenerationOptions get options => $_getN(5);
  @$pb.TagNumber(26)
  set options($0.LLMGenerationOptions value) => $_setField(26, value);
  @$pb.TagNumber(26)
  $core.bool hasOptions() => $_has(5);
  @$pb.TagNumber(26)
  void clearOptions() => $_clearField(26);
  @$pb.TagNumber(26)
  $0.LLMGenerationOptions ensureOptions() => $_ensure(5);

  /// Prior turns, excluding `prompt` (the live user turn) and
  /// options.system_prompt.
  @$pb.TagNumber(27)
  $pb.PbList<$1.ChatMessage> get history => $_getList(6);
}

class LLMStreamFinalResult extends $pb.GeneratedMessage {
  factory LLMStreamFinalResult({
    $core.String? text,
    $core.String? thinkingContent,
    $fixnum.Int64? totalTimeMs,
    $fixnum.Int64? timeToFirstTokenMs,
    $core.String? finishReason,
    $fixnum.Int64? promptEvalTimeMs,
    $fixnum.Int64? decodeTimeMs,
    $core.Iterable<$2.ToolCall>? toolCalls,
    $core.Iterable<$2.ToolResult>? toolResults,
    $3.TokenUsage? usage,
    $4.SDKError? error,
  }) {
    final result = create();
    if (text != null) result.text = text;
    if (thinkingContent != null) result.thinkingContent = thinkingContent;
    if (totalTimeMs != null) result.totalTimeMs = totalTimeMs;
    if (timeToFirstTokenMs != null)
      result.timeToFirstTokenMs = timeToFirstTokenMs;
    if (finishReason != null) result.finishReason = finishReason;
    if (promptEvalTimeMs != null) result.promptEvalTimeMs = promptEvalTimeMs;
    if (decodeTimeMs != null) result.decodeTimeMs = decodeTimeMs;
    if (toolCalls != null) result.toolCalls.addAll(toolCalls);
    if (toolResults != null) result.toolResults.addAll(toolResults);
    if (usage != null) result.usage = usage;
    if (error != null) result.error = error;
    return result;
  }

  LLMStreamFinalResult._();

  factory LLMStreamFinalResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LLMStreamFinalResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LLMStreamFinalResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOS(2, _omitFieldNames ? '' : 'thinkingContent')
    ..aInt64(6, _omitFieldNames ? '' : 'totalTimeMs')
    ..aInt64(7, _omitFieldNames ? '' : 'timeToFirstTokenMs')
    ..aOS(9, _omitFieldNames ? '' : 'finishReason')
    ..aInt64(12, _omitFieldNames ? '' : 'promptEvalTimeMs')
    ..aInt64(13, _omitFieldNames ? '' : 'decodeTimeMs')
    ..pPM<$2.ToolCall>(14, _omitFieldNames ? '' : 'toolCalls',
        subBuilder: $2.ToolCall.create)
    ..pPM<$2.ToolResult>(15, _omitFieldNames ? '' : 'toolResults',
        subBuilder: $2.ToolResult.create)
    ..aOM<$3.TokenUsage>(16, _omitFieldNames ? '' : 'usage',
        subBuilder: $3.TokenUsage.create)
    ..aOM<$4.SDKError>(17, _omitFieldNames ? '' : 'error',
        subBuilder: $4.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LLMStreamFinalResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LLMStreamFinalResult copyWith(void Function(LLMStreamFinalResult) updates) =>
      super.copyWith((message) => updates(message as LLMStreamFinalResult))
          as LLMStreamFinalResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LLMStreamFinalResult create() => LLMStreamFinalResult._();
  @$core.override
  LLMStreamFinalResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LLMStreamFinalResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LLMStreamFinalResult>(create);
  static LLMStreamFinalResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get thinkingContent => $_getSZ(1);
  @$pb.TagNumber(2)
  set thinkingContent($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasThinkingContent() => $_has(1);
  @$pb.TagNumber(2)
  void clearThinkingContent() => $_clearField(2);

  @$pb.TagNumber(6)
  $fixnum.Int64 get totalTimeMs => $_getI64(2);
  @$pb.TagNumber(6)
  set totalTimeMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(6)
  $core.bool hasTotalTimeMs() => $_has(2);
  @$pb.TagNumber(6)
  void clearTotalTimeMs() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get timeToFirstTokenMs => $_getI64(3);
  @$pb.TagNumber(7)
  set timeToFirstTokenMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(7)
  $core.bool hasTimeToFirstTokenMs() => $_has(3);
  @$pb.TagNumber(7)
  void clearTimeToFirstTokenMs() => $_clearField(7);

  @$pb.TagNumber(9)
  $core.String get finishReason => $_getSZ(4);
  @$pb.TagNumber(9)
  set finishReason($core.String value) => $_setString(4, value);
  @$pb.TagNumber(9)
  $core.bool hasFinishReason() => $_has(4);
  @$pb.TagNumber(9)
  void clearFinishReason() => $_clearField(9);

  @$pb.TagNumber(12)
  $fixnum.Int64 get promptEvalTimeMs => $_getI64(5);
  @$pb.TagNumber(12)
  set promptEvalTimeMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(12)
  $core.bool hasPromptEvalTimeMs() => $_has(5);
  @$pb.TagNumber(12)
  void clearPromptEvalTimeMs() => $_clearField(12);

  @$pb.TagNumber(13)
  $fixnum.Int64 get decodeTimeMs => $_getI64(6);
  @$pb.TagNumber(13)
  set decodeTimeMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(13)
  $core.bool hasDecodeTimeMs() => $_has(6);
  @$pb.TagNumber(13)
  void clearDecodeTimeMs() => $_clearField(13);

  @$pb.TagNumber(14)
  $pb.PbList<$2.ToolCall> get toolCalls => $_getList(7);

  @$pb.TagNumber(15)
  $pb.PbList<$2.ToolResult> get toolResults => $_getList(8);

  @$pb.TagNumber(16)
  $3.TokenUsage get usage => $_getN(9);
  @$pb.TagNumber(16)
  set usage($3.TokenUsage value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasUsage() => $_has(9);
  @$pb.TagNumber(16)
  void clearUsage() => $_clearField(16);
  @$pb.TagNumber(16)
  $3.TokenUsage ensureUsage() => $_ensure(9);

  @$pb.TagNumber(17)
  $4.SDKError get error => $_getN(10);
  @$pb.TagNumber(17)
  set error($4.SDKError value) => $_setField(17, value);
  @$pb.TagNumber(17)
  $core.bool hasError() => $_has(10);
  @$pb.TagNumber(17)
  void clearError() => $_clearField(17);
  @$pb.TagNumber(17)
  $4.SDKError ensureError() => $_ensure(10);
}

/// `result` is populated only on the terminal event.
class LLMStreamEvent extends $pb.GeneratedMessage {
  factory LLMStreamEvent({
    $fixnum.Int64? timestampUs,
    $core.String? token,
    $core.bool? isFinal,
    $5.TokenKind? kind,
    $core.int? tokenId,
    $core.double? logprob,
    $core.String? finishReason,
    LLMStreamFinalResult? result,
    LLMStreamEventKind? eventKind,
    $core.String? requestId,
    $core.String? conversationId,
    $core.int? promptTokensProcessed,
    $core.int? completionTokensGenerated,
    $fixnum.Int64? elapsedMs,
    $2.ToolCall? toolCall,
    $4.SDKError? error,
  }) {
    final result$ = create();
    if (timestampUs != null) result$.timestampUs = timestampUs;
    if (token != null) result$.token = token;
    if (isFinal != null) result$.isFinal = isFinal;
    if (kind != null) result$.kind = kind;
    if (tokenId != null) result$.tokenId = tokenId;
    if (logprob != null) result$.logprob = logprob;
    if (finishReason != null) result$.finishReason = finishReason;
    if (result != null) result$.result = result;
    if (eventKind != null) result$.eventKind = eventKind;
    if (requestId != null) result$.requestId = requestId;
    if (conversationId != null) result$.conversationId = conversationId;
    if (promptTokensProcessed != null)
      result$.promptTokensProcessed = promptTokensProcessed;
    if (completionTokensGenerated != null)
      result$.completionTokensGenerated = completionTokensGenerated;
    if (elapsedMs != null) result$.elapsedMs = elapsedMs;
    if (toolCall != null) result$.toolCall = toolCall;
    if (error != null) result$.error = error;
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
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(3, _omitFieldNames ? '' : 'token')
    ..aOB(4, _omitFieldNames ? '' : 'isFinal')
    ..aE<$5.TokenKind>(5, _omitFieldNames ? '' : 'kind',
        enumValues: $5.TokenKind.values)
    ..aI(6, _omitFieldNames ? '' : 'tokenId', fieldType: $pb.PbFieldType.OU3)
    ..aD(7, _omitFieldNames ? '' : 'logprob', fieldType: $pb.PbFieldType.OF)
    ..aOS(8, _omitFieldNames ? '' : 'finishReason')
    ..aOM<LLMStreamFinalResult>(10, _omitFieldNames ? '' : 'result',
        subBuilder: LLMStreamFinalResult.create)
    ..aE<LLMStreamEventKind>(12, _omitFieldNames ? '' : 'eventKind',
        enumValues: LLMStreamEventKind.values)
    ..aOS(13, _omitFieldNames ? '' : 'requestId')
    ..aOS(14, _omitFieldNames ? '' : 'conversationId')
    ..aI(15, _omitFieldNames ? '' : 'promptTokensProcessed')
    ..aI(16, _omitFieldNames ? '' : 'completionTokensGenerated')
    ..aInt64(17, _omitFieldNames ? '' : 'elapsedMs')
    ..aOM<$2.ToolCall>(18, _omitFieldNames ? '' : 'toolCall',
        subBuilder: $2.ToolCall.create)
    ..aOM<$4.SDKError>(19, _omitFieldNames ? '' : 'error',
        subBuilder: $4.SDKError.create)
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

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampUs => $_getI64(0);
  @$pb.TagNumber(2)
  set timestampUs($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestampUs() => $_has(0);
  @$pb.TagNumber(2)
  void clearTimestampUs() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get token => $_getSZ(1);
  @$pb.TagNumber(3)
  set token($core.String value) => $_setString(1, value);
  @$pb.TagNumber(3)
  $core.bool hasToken() => $_has(1);
  @$pb.TagNumber(3)
  void clearToken() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.bool get isFinal => $_getBF(2);
  @$pb.TagNumber(4)
  set isFinal($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(4)
  $core.bool hasIsFinal() => $_has(2);
  @$pb.TagNumber(4)
  void clearIsFinal() => $_clearField(4);

  @$pb.TagNumber(5)
  $5.TokenKind get kind => $_getN(3);
  @$pb.TagNumber(5)
  set kind($5.TokenKind value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasKind() => $_has(3);
  @$pb.TagNumber(5)
  void clearKind() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get tokenId => $_getIZ(4);
  @$pb.TagNumber(6)
  set tokenId($core.int value) => $_setUnsignedInt32(4, value);
  @$pb.TagNumber(6)
  $core.bool hasTokenId() => $_has(4);
  @$pb.TagNumber(6)
  void clearTokenId() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.double get logprob => $_getN(5);
  @$pb.TagNumber(7)
  set logprob($core.double value) => $_setFloat(5, value);
  @$pb.TagNumber(7)
  $core.bool hasLogprob() => $_has(5);
  @$pb.TagNumber(7)
  void clearLogprob() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get finishReason => $_getSZ(6);
  @$pb.TagNumber(8)
  set finishReason($core.String value) => $_setString(6, value);
  @$pb.TagNumber(8)
  $core.bool hasFinishReason() => $_has(6);
  @$pb.TagNumber(8)
  void clearFinishReason() => $_clearField(8);

  @$pb.TagNumber(10)
  LLMStreamFinalResult get result => $_getN(7);
  @$pb.TagNumber(10)
  set result(LLMStreamFinalResult value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasResult() => $_has(7);
  @$pb.TagNumber(10)
  void clearResult() => $_clearField(10);
  @$pb.TagNumber(10)
  LLMStreamFinalResult ensureResult() => $_ensure(7);

  @$pb.TagNumber(12)
  LLMStreamEventKind get eventKind => $_getN(8);
  @$pb.TagNumber(12)
  set eventKind(LLMStreamEventKind value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasEventKind() => $_has(8);
  @$pb.TagNumber(12)
  void clearEventKind() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get requestId => $_getSZ(9);
  @$pb.TagNumber(13)
  set requestId($core.String value) => $_setString(9, value);
  @$pb.TagNumber(13)
  $core.bool hasRequestId() => $_has(9);
  @$pb.TagNumber(13)
  void clearRequestId() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get conversationId => $_getSZ(10);
  @$pb.TagNumber(14)
  set conversationId($core.String value) => $_setString(10, value);
  @$pb.TagNumber(14)
  $core.bool hasConversationId() => $_has(10);
  @$pb.TagNumber(14)
  void clearConversationId() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.int get promptTokensProcessed => $_getIZ(11);
  @$pb.TagNumber(15)
  set promptTokensProcessed($core.int value) => $_setSignedInt32(11, value);
  @$pb.TagNumber(15)
  $core.bool hasPromptTokensProcessed() => $_has(11);
  @$pb.TagNumber(15)
  void clearPromptTokensProcessed() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.int get completionTokensGenerated => $_getIZ(12);
  @$pb.TagNumber(16)
  set completionTokensGenerated($core.int value) => $_setSignedInt32(12, value);
  @$pb.TagNumber(16)
  $core.bool hasCompletionTokensGenerated() => $_has(12);
  @$pb.TagNumber(16)
  void clearCompletionTokensGenerated() => $_clearField(16);

  @$pb.TagNumber(17)
  $fixnum.Int64 get elapsedMs => $_getI64(13);
  @$pb.TagNumber(17)
  set elapsedMs($fixnum.Int64 value) => $_setInt64(13, value);
  @$pb.TagNumber(17)
  $core.bool hasElapsedMs() => $_has(13);
  @$pb.TagNumber(17)
  void clearElapsedMs() => $_clearField(17);

  @$pb.TagNumber(18)
  $2.ToolCall get toolCall => $_getN(14);
  @$pb.TagNumber(18)
  set toolCall($2.ToolCall value) => $_setField(18, value);
  @$pb.TagNumber(18)
  $core.bool hasToolCall() => $_has(14);
  @$pb.TagNumber(18)
  void clearToolCall() => $_clearField(18);
  @$pb.TagNumber(18)
  $2.ToolCall ensureToolCall() => $_ensure(14);

  @$pb.TagNumber(19)
  $4.SDKError get error => $_getN(15);
  @$pb.TagNumber(19)
  set error($4.SDKError value) => $_setField(19, value);
  @$pb.TagNumber(19)
  $core.bool hasError() => $_has(15);
  @$pb.TagNumber(19)
  void clearError() => $_clearField(19);
  @$pb.TagNumber(19)
  $4.SDKError ensureError() => $_ensure(15);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
