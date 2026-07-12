// This is a generated file - do not edit.
//
// Generated from llm_service.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'chat.pb.dart' as $1;
import 'llm_options.pb.dart' as $0;
import 'llm_service.pbenum.dart';
import 'tool_calling.pb.dart' as $2;
import 'voice_events.pbenum.dart' as $3;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'llm_service.pbenum.dart';

/// Generation settings live exclusively in `options`. Reserved field numbers
/// prevent unsafe wire reuse.
class LLMGenerateRequest extends $pb.GeneratedMessage {
  factory LLMGenerateRequest({
    $core.String? prompt,
    $core.bool? emitThoughts,
    $core.String? requestId,
    $core.String? modelId,
    $core.String? conversationId,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
    $0.LLMGenerationOptions? options,
    $core.Iterable<$1.ChatMessage>? history,
  }) {
    final result = create();
    if (prompt != null) result.prompt = prompt;
    if (emitThoughts != null) result.emitThoughts = emitThoughts;
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
    ..aOB(7, _omitFieldNames ? '' : 'emitThoughts')
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

  @$pb.TagNumber(7)
  $core.bool get emitThoughts => $_getBF(1);
  @$pb.TagNumber(7)
  set emitThoughts($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(7)
  $core.bool hasEmitThoughts() => $_has(1);
  @$pb.TagNumber(7)
  void clearEmitThoughts() => $_clearField(7);

  @$pb.TagNumber(14)
  $core.String get requestId => $_getSZ(2);
  @$pb.TagNumber(14)
  set requestId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(14)
  $core.bool hasRequestId() => $_has(2);
  @$pb.TagNumber(14)
  void clearRequestId() => $_clearField(14);

  @$pb.TagNumber(15)
  $core.String get modelId => $_getSZ(3);
  @$pb.TagNumber(15)
  set modelId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(15)
  $core.bool hasModelId() => $_has(3);
  @$pb.TagNumber(15)
  void clearModelId() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.String get conversationId => $_getSZ(4);
  @$pb.TagNumber(16)
  set conversationId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(16)
  $core.bool hasConversationId() => $_has(4);
  @$pb.TagNumber(16)
  void clearConversationId() => $_clearField(16);

  @$pb.TagNumber(25)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(5);

  /// Canonical generation settings. When absent, commons applies its SDK
  /// defaults; callers that need explicit controls populate this message.
  @$pb.TagNumber(26)
  $0.LLMGenerationOptions get options => $_getN(6);
  @$pb.TagNumber(26)
  set options($0.LLMGenerationOptions value) => $_setField(26, value);
  @$pb.TagNumber(26)
  $core.bool hasOptions() => $_has(6);
  @$pb.TagNumber(26)
  void clearOptions() => $_clearField(26);
  @$pb.TagNumber(26)
  $0.LLMGenerationOptions ensureOptions() => $_ensure(6);

  /// Prior conversation turns (excludes the current `prompt`, which
  /// stays the live user turn, and `options.system_prompt`, which stays
  /// separate).
  /// Alternating user/assistant ChatMessages in chronological order. An engine
  /// that owns its chat template renders {system_prompt, history, prompt} from
  /// its model's markers; engines that don't simply ignore this field.
  @$pb.TagNumber(27)
  $pb.PbList<$1.ChatMessage> get history => $_getList(7);
}

/// Aggregate terminal payload emitted by LLMStreamEvent. It intentionally keeps
/// stream-native token, timing, and error fields distinct from the unary
/// LLMGenerationResult shape.
class LLMStreamFinalResult extends $pb.GeneratedMessage {
  factory LLMStreamFinalResult({
    $core.String? text,
    $core.String? thinkingContent,
    $core.int? promptTokens,
    $core.int? completionTokens,
    $core.int? totalTokens,
    $fixnum.Int64? totalTimeMs,
    $fixnum.Int64? timeToFirstTokenMs,
    $core.double? tokensPerSecond,
    $core.String? finishReason,
    $core.int? errorCode,
    $core.String? errorMessage,
    $fixnum.Int64? promptEvalTimeMs,
    $fixnum.Int64? decodeTimeMs,
    $core.Iterable<$2.ToolCall>? toolCalls,
    $core.Iterable<$2.ToolResult>? toolResults,
  }) {
    final result = create();
    if (text != null) result.text = text;
    if (thinkingContent != null) result.thinkingContent = thinkingContent;
    if (promptTokens != null) result.promptTokens = promptTokens;
    if (completionTokens != null) result.completionTokens = completionTokens;
    if (totalTokens != null) result.totalTokens = totalTokens;
    if (totalTimeMs != null) result.totalTimeMs = totalTimeMs;
    if (timeToFirstTokenMs != null)
      result.timeToFirstTokenMs = timeToFirstTokenMs;
    if (tokensPerSecond != null) result.tokensPerSecond = tokensPerSecond;
    if (finishReason != null) result.finishReason = finishReason;
    if (errorCode != null) result.errorCode = errorCode;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (promptEvalTimeMs != null) result.promptEvalTimeMs = promptEvalTimeMs;
    if (decodeTimeMs != null) result.decodeTimeMs = decodeTimeMs;
    if (toolCalls != null) result.toolCalls.addAll(toolCalls);
    if (toolResults != null) result.toolResults.addAll(toolResults);
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
    ..aI(3, _omitFieldNames ? '' : 'promptTokens')
    ..aI(4, _omitFieldNames ? '' : 'completionTokens')
    ..aI(5, _omitFieldNames ? '' : 'totalTokens')
    ..aInt64(6, _omitFieldNames ? '' : 'totalTimeMs')
    ..aInt64(7, _omitFieldNames ? '' : 'timeToFirstTokenMs')
    ..aD(8, _omitFieldNames ? '' : 'tokensPerSecond',
        fieldType: $pb.PbFieldType.OF)
    ..aOS(9, _omitFieldNames ? '' : 'finishReason')
    ..aI(10, _omitFieldNames ? '' : 'errorCode')
    ..aOS(11, _omitFieldNames ? '' : 'errorMessage')
    ..aInt64(12, _omitFieldNames ? '' : 'promptEvalTimeMs')
    ..aInt64(13, _omitFieldNames ? '' : 'decodeTimeMs')
    ..pPM<$2.ToolCall>(14, _omitFieldNames ? '' : 'toolCalls',
        subBuilder: $2.ToolCall.create)
    ..pPM<$2.ToolResult>(15, _omitFieldNames ? '' : 'toolResults',
        subBuilder: $2.ToolResult.create)
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

  @$pb.TagNumber(3)
  $core.int get promptTokens => $_getIZ(2);
  @$pb.TagNumber(3)
  set promptTokens($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPromptTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearPromptTokens() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get completionTokens => $_getIZ(3);
  @$pb.TagNumber(4)
  set completionTokens($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCompletionTokens() => $_has(3);
  @$pb.TagNumber(4)
  void clearCompletionTokens() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get totalTokens => $_getIZ(4);
  @$pb.TagNumber(5)
  set totalTokens($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTotalTokens() => $_has(4);
  @$pb.TagNumber(5)
  void clearTotalTokens() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get totalTimeMs => $_getI64(5);
  @$pb.TagNumber(6)
  set totalTimeMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTotalTimeMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearTotalTimeMs() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get timeToFirstTokenMs => $_getI64(6);
  @$pb.TagNumber(7)
  set timeToFirstTokenMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasTimeToFirstTokenMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearTimeToFirstTokenMs() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.double get tokensPerSecond => $_getN(7);
  @$pb.TagNumber(8)
  set tokensPerSecond($core.double value) => $_setFloat(7, value);
  @$pb.TagNumber(8)
  $core.bool hasTokensPerSecond() => $_has(7);
  @$pb.TagNumber(8)
  void clearTokensPerSecond() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get finishReason => $_getSZ(8);
  @$pb.TagNumber(9)
  set finishReason($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasFinishReason() => $_has(8);
  @$pb.TagNumber(9)
  void clearFinishReason() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.int get errorCode => $_getIZ(9);
  @$pb.TagNumber(10)
  set errorCode($core.int value) => $_setSignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasErrorCode() => $_has(9);
  @$pb.TagNumber(10)
  void clearErrorCode() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get errorMessage => $_getSZ(10);
  @$pb.TagNumber(11)
  set errorMessage($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasErrorMessage() => $_has(10);
  @$pb.TagNumber(11)
  void clearErrorMessage() => $_clearField(11);

  @$pb.TagNumber(12)
  $fixnum.Int64 get promptEvalTimeMs => $_getI64(11);
  @$pb.TagNumber(12)
  set promptEvalTimeMs($fixnum.Int64 value) => $_setInt64(11, value);
  @$pb.TagNumber(12)
  $core.bool hasPromptEvalTimeMs() => $_has(11);
  @$pb.TagNumber(12)
  void clearPromptEvalTimeMs() => $_clearField(12);

  @$pb.TagNumber(13)
  $fixnum.Int64 get decodeTimeMs => $_getI64(12);
  @$pb.TagNumber(13)
  set decodeTimeMs($fixnum.Int64 value) => $_setInt64(12, value);
  @$pb.TagNumber(13)
  $core.bool hasDecodeTimeMs() => $_has(12);
  @$pb.TagNumber(13)
  void clearDecodeTimeMs() => $_clearField(13);

  /// Tool calls actually executed during the streaming session (mirrors
  /// LLMGenerationResult.tool_calls / .tool_results in llm_options.proto).
  /// Populated only on terminal events when the backend completed at least
  /// one tool call.
  @$pb.TagNumber(14)
  $pb.PbList<$2.ToolCall> get toolCalls => $_getList(13);

  @$pb.TagNumber(15)
  $pb.PbList<$2.ToolResult> get toolResults => $_getList(14);
}

/// Unified per-token streaming event. Replaces
/// LLMToken (deleted) and the per-SDK hand-rolled AsyncThrowingStream /
/// callbackFlow / StreamController / tokenQueue. One serialized event
/// per generated token. Mirrors VoiceEvent's seq + timestamp_us pattern
/// from voice_events.proto so frontends can reuse gap-detection logic.
class LLMStreamEvent extends $pb.GeneratedMessage {
  factory LLMStreamEvent({
    $fixnum.Int64? seq,
    $fixnum.Int64? timestampUs,
    $core.String? token,
    $core.bool? isFinal,
    $3.TokenKind? kind,
    $core.int? tokenId,
    $core.double? logprob,
    $core.String? finishReason,
    $core.String? errorMessage,
    LLMStreamFinalResult? result,
    $core.int? errorCode,
    LLMStreamEventKind? eventKind,
    $core.String? requestId,
    $core.String? conversationId,
    $core.int? promptTokensProcessed,
    $core.int? completionTokensGenerated,
    $fixnum.Int64? elapsedMs,
    $2.ToolCall? toolCall,
  }) {
    final result$ = create();
    if (seq != null) result$.seq = seq;
    if (timestampUs != null) result$.timestampUs = timestampUs;
    if (token != null) result$.token = token;
    if (isFinal != null) result$.isFinal = isFinal;
    if (kind != null) result$.kind = kind;
    if (tokenId != null) result$.tokenId = tokenId;
    if (logprob != null) result$.logprob = logprob;
    if (finishReason != null) result$.finishReason = finishReason;
    if (errorMessage != null) result$.errorMessage = errorMessage;
    if (result != null) result$.result = result;
    if (errorCode != null) result$.errorCode = errorCode;
    if (eventKind != null) result$.eventKind = eventKind;
    if (requestId != null) result$.requestId = requestId;
    if (conversationId != null) result$.conversationId = conversationId;
    if (promptTokensProcessed != null)
      result$.promptTokensProcessed = promptTokensProcessed;
    if (completionTokensGenerated != null)
      result$.completionTokensGenerated = completionTokensGenerated;
    if (elapsedMs != null) result$.elapsedMs = elapsedMs;
    if (toolCall != null) result$.toolCall = toolCall;
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
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(3, _omitFieldNames ? '' : 'token')
    ..aOB(4, _omitFieldNames ? '' : 'isFinal')
    ..aE<$3.TokenKind>(5, _omitFieldNames ? '' : 'kind',
        enumValues: $3.TokenKind.values)
    ..aI(6, _omitFieldNames ? '' : 'tokenId', fieldType: $pb.PbFieldType.OU3)
    ..aD(7, _omitFieldNames ? '' : 'logprob', fieldType: $pb.PbFieldType.OF)
    ..aOS(8, _omitFieldNames ? '' : 'finishReason')
    ..aOS(9, _omitFieldNames ? '' : 'errorMessage')
    ..aOM<LLMStreamFinalResult>(10, _omitFieldNames ? '' : 'result',
        subBuilder: LLMStreamFinalResult.create)
    ..aI(11, _omitFieldNames ? '' : 'errorCode')
    ..aE<LLMStreamEventKind>(12, _omitFieldNames ? '' : 'eventKind',
        enumValues: LLMStreamEventKind.values)
    ..aOS(13, _omitFieldNames ? '' : 'requestId')
    ..aOS(14, _omitFieldNames ? '' : 'conversationId')
    ..aI(15, _omitFieldNames ? '' : 'promptTokensProcessed')
    ..aI(16, _omitFieldNames ? '' : 'completionTokensGenerated')
    ..aInt64(17, _omitFieldNames ? '' : 'elapsedMs')
    ..aOM<$2.ToolCall>(18, _omitFieldNames ? '' : 'toolCall',
        subBuilder: $2.ToolCall.create)
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

  /// Monotonic per-process sequence number. Useful for frontends that
  /// need to detect gaps or out-of-order delivery.
  @$pb.TagNumber(1)
  $fixnum.Int64 get seq => $_getI64(0);
  @$pb.TagNumber(1)
  set seq($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => $_clearField(1);

  /// Wall-clock timestamp captured at the C++ edge, in microseconds
  /// since Unix epoch. Frontends may re-timestamp for UI display.
  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampUs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampUs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestampUs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampUs() => $_clearField(2);

  /// Generated token text. Empty on terminal events where only
  /// finish_reason or error_message is populated.
  @$pb.TagNumber(3)
  $core.String get token => $_getSZ(2);
  @$pb.TagNumber(3)
  set token($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasToken() => $_has(2);
  @$pb.TagNumber(3)
  void clearToken() => $_clearField(3);

  /// True on the last event of a generation.
  @$pb.TagNumber(4)
  $core.bool get isFinal => $_getBF(3);
  @$pb.TagNumber(4)
  set isFinal($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasIsFinal() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsFinal() => $_clearField(4);

  /// Token semantic category (answer / thought / tool-call).
  /// Canonical TokenKind from voice_events.proto.
  @$pb.TagNumber(5)
  $3.TokenKind get kind => $_getN(4);
  @$pb.TagNumber(5)
  set kind($3.TokenKind value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasKind() => $_has(4);
  @$pb.TagNumber(5)
  void clearKind() => $_clearField(5);

  /// Backend-provided token id when the engine exposes it; 0 = unset
  /// (proto3 scalar default).
  @$pb.TagNumber(6)
  $core.int get tokenId => $_getIZ(5);
  @$pb.TagNumber(6)
  set tokenId($core.int value) => $_setUnsignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTokenId() => $_has(5);
  @$pb.TagNumber(6)
  void clearTokenId() => $_clearField(6);

  /// Per-token log-probability when supported; 0.0 = unset.
  @$pb.TagNumber(7)
  $core.double get logprob => $_getN(6);
  @$pb.TagNumber(7)
  set logprob($core.double value) => $_setFloat(6, value);
  @$pb.TagNumber(7)
  $core.bool hasLogprob() => $_has(6);
  @$pb.TagNumber(7)
  void clearLogprob() => $_clearField(7);

  /// Reason the stream stopped: "stop", "length", "cancelled", "error",
  /// "" = unset (proto3 scalar default). Only populated when is_final.
  @$pb.TagNumber(8)
  $core.String get finishReason => $_getSZ(7);
  @$pb.TagNumber(8)
  set finishReason($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasFinishReason() => $_has(7);
  @$pb.TagNumber(8)
  void clearFinishReason() => $_clearField(8);

  /// Error message on failure events (kind may be unset, is_final true).
  /// Empty on success.
  @$pb.TagNumber(9)
  $core.String get errorMessage => $_getSZ(8);
  @$pb.TagNumber(9)
  set errorMessage($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasErrorMessage() => $_has(8);
  @$pb.TagNumber(9)
  void clearErrorMessage() => $_clearField(9);

  /// Final aggregate result. Only populated on terminal events
  /// (is_final=true) when the backend can report result metrics.
  @$pb.TagNumber(10)
  LLMStreamFinalResult get result => $_getN(9);
  @$pb.TagNumber(10)
  set result(LLMStreamFinalResult value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasResult() => $_has(9);
  @$pb.TagNumber(10)
  void clearResult() => $_clearField(10);
  @$pb.TagNumber(10)
  LLMStreamFinalResult ensureResult() => $_ensure(9);

  /// Numeric backend status code when the terminal event represents a
  /// failure. 0 = unset/success.
  @$pb.TagNumber(11)
  $core.int get errorCode => $_getIZ(10);
  @$pb.TagNumber(11)
  set errorCode($core.int value) => $_setSignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasErrorCode() => $_has(10);
  @$pb.TagNumber(11)
  void clearErrorCode() => $_clearField(11);

  /// Event classification distinct from token semantic kind.
  @$pb.TagNumber(12)
  LLMStreamEventKind get eventKind => $_getN(11);
  @$pb.TagNumber(12)
  set eventKind(LLMStreamEventKind value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasEventKind() => $_has(11);
  @$pb.TagNumber(12)
  void clearEventKind() => $_clearField(12);

  /// Request/session correlation fields.
  @$pb.TagNumber(13)
  $core.String get requestId => $_getSZ(12);
  @$pb.TagNumber(13)
  set requestId($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasRequestId() => $_has(12);
  @$pb.TagNumber(13)
  void clearRequestId() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get conversationId => $_getSZ(13);
  @$pb.TagNumber(14)
  set conversationId($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasConversationId() => $_has(13);
  @$pb.TagNumber(14)
  void clearConversationId() => $_clearField(14);

  /// Running counters for progress UIs.
  @$pb.TagNumber(15)
  $core.int get promptTokensProcessed => $_getIZ(14);
  @$pb.TagNumber(15)
  set promptTokensProcessed($core.int value) => $_setSignedInt32(14, value);
  @$pb.TagNumber(15)
  $core.bool hasPromptTokensProcessed() => $_has(14);
  @$pb.TagNumber(15)
  void clearPromptTokensProcessed() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.int get completionTokensGenerated => $_getIZ(15);
  @$pb.TagNumber(16)
  set completionTokensGenerated($core.int value) => $_setSignedInt32(15, value);
  @$pb.TagNumber(16)
  $core.bool hasCompletionTokensGenerated() => $_has(15);
  @$pb.TagNumber(16)
  void clearCompletionTokensGenerated() => $_clearField(16);

  @$pb.TagNumber(17)
  $fixnum.Int64 get elapsedMs => $_getI64(16);
  @$pb.TagNumber(17)
  set elapsedMs($fixnum.Int64 value) => $_setInt64(16, value);
  @$pb.TagNumber(17)
  $core.bool hasElapsedMs() => $_has(16);
  @$pb.TagNumber(17)
  void clearElapsedMs() => $_clearField(17);

  /// Structured tool-call payload emitted when event_kind is
  /// LLM_STREAM_EVENT_KIND_TOOL_CALL.
  @$pb.TagNumber(18)
  $2.ToolCall get toolCall => $_getN(17);
  @$pb.TagNumber(18)
  set toolCall($2.ToolCall value) => $_setField(18, value);
  @$pb.TagNumber(18)
  $core.bool hasToolCall() => $_has(17);
  @$pb.TagNumber(18)
  void clearToolCall() => $_clearField(18);
  @$pb.TagNumber(18)
  $2.ToolCall ensureToolCall() => $_ensure(17);
}

class LLMApi {
  final $pb.RpcClient _client;

  LLMApi(this._client);

  /// Server-streaming: emits one LLMStreamEvent per generated token
  /// until is_final=true. Cancellation aborts the underlying generation
  /// via the existing rac_llm_cancel() C ABI.
  ///
  /// Tool-driven streaming is not supported on this entry point even when
  /// options.tool_calling is populated. Use the non-streaming tool-session
  /// generation path for tool calling.
  $async.Future<LLMStreamEvent> generate(
          $pb.ClientContext? ctx, LLMGenerateRequest request) =>
      _client.invoke<LLMStreamEvent>(
          ctx, 'LLM', 'Generate', request, LLMStreamEvent());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
