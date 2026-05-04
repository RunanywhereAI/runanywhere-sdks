//
//  Generated code. Do not modify.
//  source: llm_service.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'llm_service.pbenum.dart';

export 'llm_service.pbenum.dart';

class LLMGenerateRequest extends $pb.GeneratedMessage {
  factory LLMGenerateRequest({
    $core.String? prompt,
    $core.int? maxTokens,
    $core.double? temperature,
    $core.double? topP,
    $core.int? topK,
    $core.String? systemPrompt,
    $core.bool? emitThoughts,
    $core.double? repetitionPenalty,
    $core.Iterable<$core.String>? stopSequences,
    $core.bool? streamingEnabled,
    $core.String? preferredFramework,
    $core.String? jsonSchema,
    $core.String? executionTarget,
  }) {
    final $result = create();
    if (prompt != null) {
      $result.prompt = prompt;
    }
    if (maxTokens != null) {
      $result.maxTokens = maxTokens;
    }
    if (temperature != null) {
      $result.temperature = temperature;
    }
    if (topP != null) {
      $result.topP = topP;
    }
    if (topK != null) {
      $result.topK = topK;
    }
    if (systemPrompt != null) {
      $result.systemPrompt = systemPrompt;
    }
    if (emitThoughts != null) {
      $result.emitThoughts = emitThoughts;
    }
    if (repetitionPenalty != null) {
      $result.repetitionPenalty = repetitionPenalty;
    }
    if (stopSequences != null) {
      $result.stopSequences.addAll(stopSequences);
    }
    if (streamingEnabled != null) {
      $result.streamingEnabled = streamingEnabled;
    }
    if (preferredFramework != null) {
      $result.preferredFramework = preferredFramework;
    }
    if (jsonSchema != null) {
      $result.jsonSchema = jsonSchema;
    }
    if (executionTarget != null) {
      $result.executionTarget = executionTarget;
    }
    return $result;
  }
  LLMGenerateRequest._() : super();
  factory LLMGenerateRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LLMGenerateRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LLMGenerateRequest', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'prompt')
    ..a<$core.int>(2, _omitFieldNames ? '' : 'maxTokens', $pb.PbFieldType.O3)
    ..a<$core.double>(3, _omitFieldNames ? '' : 'temperature', $pb.PbFieldType.OF)
    ..a<$core.double>(4, _omitFieldNames ? '' : 'topP', $pb.PbFieldType.OF)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'topK', $pb.PbFieldType.O3)
    ..aOS(6, _omitFieldNames ? '' : 'systemPrompt')
    ..aOB(7, _omitFieldNames ? '' : 'emitThoughts')
    ..a<$core.double>(8, _omitFieldNames ? '' : 'repetitionPenalty', $pb.PbFieldType.OF)
    ..pPS(9, _omitFieldNames ? '' : 'stopSequences')
    ..aOB(10, _omitFieldNames ? '' : 'streamingEnabled')
    ..aOS(11, _omitFieldNames ? '' : 'preferredFramework')
    ..aOS(12, _omitFieldNames ? '' : 'jsonSchema')
    ..aOS(13, _omitFieldNames ? '' : 'executionTarget')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LLMGenerateRequest clone() => LLMGenerateRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LLMGenerateRequest copyWith(void Function(LLMGenerateRequest) updates) => super.copyWith((message) => updates(message as LLMGenerateRequest)) as LLMGenerateRequest;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LLMGenerateRequest create() => LLMGenerateRequest._();
  LLMGenerateRequest createEmptyInstance() => create();
  static $pb.PbList<LLMGenerateRequest> createRepeated() => $pb.PbList<LLMGenerateRequest>();
  @$core.pragma('dart2js:noInline')
  static LLMGenerateRequest getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LLMGenerateRequest>(create);
  static LLMGenerateRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get prompt => $_getSZ(0);
  @$pb.TagNumber(1)
  set prompt($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasPrompt() => $_has(0);
  @$pb.TagNumber(1)
  void clearPrompt() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get maxTokens => $_getIZ(1);
  @$pb.TagNumber(2)
  set maxTokens($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMaxTokens() => $_has(1);
  @$pb.TagNumber(2)
  void clearMaxTokens() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get temperature => $_getN(2);
  @$pb.TagNumber(3)
  set temperature($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTemperature() => $_has(2);
  @$pb.TagNumber(3)
  void clearTemperature() => clearField(3);

  @$pb.TagNumber(4)
  $core.double get topP => $_getN(3);
  @$pb.TagNumber(4)
  set topP($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTopP() => $_has(3);
  @$pb.TagNumber(4)
  void clearTopP() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get topK => $_getIZ(4);
  @$pb.TagNumber(5)
  set topK($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasTopK() => $_has(4);
  @$pb.TagNumber(5)
  void clearTopK() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get systemPrompt => $_getSZ(5);
  @$pb.TagNumber(6)
  set systemPrompt($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasSystemPrompt() => $_has(5);
  @$pb.TagNumber(6)
  void clearSystemPrompt() => clearField(6);

  @$pb.TagNumber(7)
  $core.bool get emitThoughts => $_getBF(6);
  @$pb.TagNumber(7)
  set emitThoughts($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasEmitThoughts() => $_has(6);
  @$pb.TagNumber(7)
  void clearEmitThoughts() => clearField(7);

  /// Additional LLMGenerationOptions fields kept inline to avoid a codegen
  /// package cycle between service stubs and option messages.
  @$pb.TagNumber(8)
  $core.double get repetitionPenalty => $_getN(7);
  @$pb.TagNumber(8)
  set repetitionPenalty($core.double v) { $_setFloat(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasRepetitionPenalty() => $_has(7);
  @$pb.TagNumber(8)
  void clearRepetitionPenalty() => clearField(8);

  @$pb.TagNumber(9)
  $core.List<$core.String> get stopSequences => $_getList(8);

  @$pb.TagNumber(10)
  $core.bool get streamingEnabled => $_getBF(9);
  @$pb.TagNumber(10)
  set streamingEnabled($core.bool v) { $_setBool(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasStreamingEnabled() => $_has(9);
  @$pb.TagNumber(10)
  void clearStreamingEnabled() => clearField(10);

  @$pb.TagNumber(11)
  $core.String get preferredFramework => $_getSZ(10);
  @$pb.TagNumber(11)
  set preferredFramework($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasPreferredFramework() => $_has(10);
  @$pb.TagNumber(11)
  void clearPreferredFramework() => clearField(11);

  @$pb.TagNumber(12)
  $core.String get jsonSchema => $_getSZ(11);
  @$pb.TagNumber(12)
  set jsonSchema($core.String v) { $_setString(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasJsonSchema() => $_has(11);
  @$pb.TagNumber(12)
  void clearJsonSchema() => clearField(12);

  @$pb.TagNumber(13)
  $core.String get executionTarget => $_getSZ(12);
  @$pb.TagNumber(13)
  set executionTarget($core.String v) { $_setString(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasExecutionTarget() => $_has(12);
  @$pb.TagNumber(13)
  void clearExecutionTarget() => clearField(13);
}

/// Aggregate result carried on the terminal LLMStreamEvent. This intentionally
/// duplicates the scalar result fields instead of importing llm_options.proto:
/// Square Wire treats files with/without go_package as different Kotlin
/// packages, and that import creates a package cycle through sdk_events.
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
  }) {
    final $result = create();
    if (text != null) {
      $result.text = text;
    }
    if (thinkingContent != null) {
      $result.thinkingContent = thinkingContent;
    }
    if (promptTokens != null) {
      $result.promptTokens = promptTokens;
    }
    if (completionTokens != null) {
      $result.completionTokens = completionTokens;
    }
    if (totalTokens != null) {
      $result.totalTokens = totalTokens;
    }
    if (totalTimeMs != null) {
      $result.totalTimeMs = totalTimeMs;
    }
    if (timeToFirstTokenMs != null) {
      $result.timeToFirstTokenMs = timeToFirstTokenMs;
    }
    if (tokensPerSecond != null) {
      $result.tokensPerSecond = tokensPerSecond;
    }
    if (finishReason != null) {
      $result.finishReason = finishReason;
    }
    return $result;
  }
  LLMStreamFinalResult._() : super();
  factory LLMStreamFinalResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LLMStreamFinalResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LLMStreamFinalResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOS(2, _omitFieldNames ? '' : 'thinkingContent')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'promptTokens', $pb.PbFieldType.O3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'completionTokens', $pb.PbFieldType.O3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'totalTokens', $pb.PbFieldType.O3)
    ..aInt64(6, _omitFieldNames ? '' : 'totalTimeMs')
    ..aInt64(7, _omitFieldNames ? '' : 'timeToFirstTokenMs')
    ..a<$core.double>(8, _omitFieldNames ? '' : 'tokensPerSecond', $pb.PbFieldType.OF)
    ..aOS(9, _omitFieldNames ? '' : 'finishReason')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LLMStreamFinalResult clone() => LLMStreamFinalResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LLMStreamFinalResult copyWith(void Function(LLMStreamFinalResult) updates) => super.copyWith((message) => updates(message as LLMStreamFinalResult)) as LLMStreamFinalResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LLMStreamFinalResult create() => LLMStreamFinalResult._();
  LLMStreamFinalResult createEmptyInstance() => create();
  static $pb.PbList<LLMStreamFinalResult> createRepeated() => $pb.PbList<LLMStreamFinalResult>();
  @$core.pragma('dart2js:noInline')
  static LLMStreamFinalResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LLMStreamFinalResult>(create);
  static LLMStreamFinalResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get thinkingContent => $_getSZ(1);
  @$pb.TagNumber(2)
  set thinkingContent($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasThinkingContent() => $_has(1);
  @$pb.TagNumber(2)
  void clearThinkingContent() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get promptTokens => $_getIZ(2);
  @$pb.TagNumber(3)
  set promptTokens($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasPromptTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearPromptTokens() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get completionTokens => $_getIZ(3);
  @$pb.TagNumber(4)
  set completionTokens($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasCompletionTokens() => $_has(3);
  @$pb.TagNumber(4)
  void clearCompletionTokens() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get totalTokens => $_getIZ(4);
  @$pb.TagNumber(5)
  set totalTokens($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasTotalTokens() => $_has(4);
  @$pb.TagNumber(5)
  void clearTotalTokens() => clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get totalTimeMs => $_getI64(5);
  @$pb.TagNumber(6)
  set totalTimeMs($fixnum.Int64 v) { $_setInt64(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTotalTimeMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearTotalTimeMs() => clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get timeToFirstTokenMs => $_getI64(6);
  @$pb.TagNumber(7)
  set timeToFirstTokenMs($fixnum.Int64 v) { $_setInt64(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasTimeToFirstTokenMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearTimeToFirstTokenMs() => clearField(7);

  @$pb.TagNumber(8)
  $core.double get tokensPerSecond => $_getN(7);
  @$pb.TagNumber(8)
  set tokensPerSecond($core.double v) { $_setFloat(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasTokensPerSecond() => $_has(7);
  @$pb.TagNumber(8)
  void clearTokensPerSecond() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get finishReason => $_getSZ(8);
  @$pb.TagNumber(9)
  set finishReason($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasFinishReason() => $_has(8);
  @$pb.TagNumber(9)
  void clearFinishReason() => clearField(9);
}

/// v2 close-out Phase G-2: unified per-token streaming event. Replaces
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
    LLMTokenKind? kind,
    $core.int? tokenId,
    $core.double? logprob,
    $core.String? finishReason,
    $core.String? errorMessage,
    LLMStreamFinalResult? result,
    $core.int? errorCode,
  }) {
    final $result = create();
    if (seq != null) {
      $result.seq = seq;
    }
    if (timestampUs != null) {
      $result.timestampUs = timestampUs;
    }
    if (token != null) {
      $result.token = token;
    }
    if (isFinal != null) {
      $result.isFinal = isFinal;
    }
    if (kind != null) {
      $result.kind = kind;
    }
    if (tokenId != null) {
      $result.tokenId = tokenId;
    }
    if (logprob != null) {
      $result.logprob = logprob;
    }
    if (finishReason != null) {
      $result.finishReason = finishReason;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    if (result != null) {
      $result.result = result;
    }
    if (errorCode != null) {
      $result.errorCode = errorCode;
    }
    return $result;
  }
  LLMStreamEvent._() : super();
  factory LLMStreamEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LLMStreamEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LLMStreamEvent', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, _omitFieldNames ? '' : 'seq', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(2, _omitFieldNames ? '' : 'timestampUs')
    ..aOS(3, _omitFieldNames ? '' : 'token')
    ..aOB(4, _omitFieldNames ? '' : 'isFinal')
    ..e<LLMTokenKind>(5, _omitFieldNames ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: LLMTokenKind.LLM_TOKEN_KIND_UNSPECIFIED, valueOf: LLMTokenKind.valueOf, enumValues: LLMTokenKind.values)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'tokenId', $pb.PbFieldType.OU3)
    ..a<$core.double>(7, _omitFieldNames ? '' : 'logprob', $pb.PbFieldType.OF)
    ..aOS(8, _omitFieldNames ? '' : 'finishReason')
    ..aOS(9, _omitFieldNames ? '' : 'errorMessage')
    ..aOM<LLMStreamFinalResult>(10, _omitFieldNames ? '' : 'result', subBuilder: LLMStreamFinalResult.create)
    ..a<$core.int>(11, _omitFieldNames ? '' : 'errorCode', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LLMStreamEvent clone() => LLMStreamEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LLMStreamEvent copyWith(void Function(LLMStreamEvent) updates) => super.copyWith((message) => updates(message as LLMStreamEvent)) as LLMStreamEvent;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LLMStreamEvent create() => LLMStreamEvent._();
  LLMStreamEvent createEmptyInstance() => create();
  static $pb.PbList<LLMStreamEvent> createRepeated() => $pb.PbList<LLMStreamEvent>();
  @$core.pragma('dart2js:noInline')
  static LLMStreamEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LLMStreamEvent>(create);
  static LLMStreamEvent? _defaultInstance;

  /// Monotonic per-process sequence number. Useful for frontends that
  /// need to detect gaps or out-of-order delivery.
  @$pb.TagNumber(1)
  $fixnum.Int64 get seq => $_getI64(0);
  @$pb.TagNumber(1)
  set seq($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => clearField(1);

  /// Wall-clock timestamp captured at the C++ edge, in microseconds
  /// since Unix epoch. Frontends may re-timestamp for UI display.
  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampUs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampUs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTimestampUs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampUs() => clearField(2);

  /// Generated token text. Empty on terminal events where only
  /// finish_reason or error_message is populated.
  @$pb.TagNumber(3)
  $core.String get token => $_getSZ(2);
  @$pb.TagNumber(3)
  set token($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasToken() => $_has(2);
  @$pb.TagNumber(3)
  void clearToken() => clearField(3);

  /// True on the last event of a generation.
  @$pb.TagNumber(4)
  $core.bool get isFinal => $_getBF(3);
  @$pb.TagNumber(4)
  set isFinal($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasIsFinal() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsFinal() => clearField(4);

  /// Token semantic category (answer / thought / tool-call).
  @$pb.TagNumber(5)
  LLMTokenKind get kind => $_getN(4);
  @$pb.TagNumber(5)
  set kind(LLMTokenKind v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasKind() => $_has(4);
  @$pb.TagNumber(5)
  void clearKind() => clearField(5);

  /// Backend-provided token id when the engine exposes it; 0 = unset
  /// (proto3 scalar default).
  @$pb.TagNumber(6)
  $core.int get tokenId => $_getIZ(5);
  @$pb.TagNumber(6)
  set tokenId($core.int v) { $_setUnsignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTokenId() => $_has(5);
  @$pb.TagNumber(6)
  void clearTokenId() => clearField(6);

  /// Per-token log-probability when supported; 0.0 = unset.
  @$pb.TagNumber(7)
  $core.double get logprob => $_getN(6);
  @$pb.TagNumber(7)
  set logprob($core.double v) { $_setFloat(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasLogprob() => $_has(6);
  @$pb.TagNumber(7)
  void clearLogprob() => clearField(7);

  /// Reason the stream stopped: "stop", "length", "cancelled", "error",
  /// "" = unset (proto3 scalar default). Only populated when is_final.
  @$pb.TagNumber(8)
  $core.String get finishReason => $_getSZ(7);
  @$pb.TagNumber(8)
  set finishReason($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasFinishReason() => $_has(7);
  @$pb.TagNumber(8)
  void clearFinishReason() => clearField(8);

  /// Error message on failure events (kind may be unset, is_final true).
  /// Empty on success.
  @$pb.TagNumber(9)
  $core.String get errorMessage => $_getSZ(8);
  @$pb.TagNumber(9)
  set errorMessage($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasErrorMessage() => $_has(8);
  @$pb.TagNumber(9)
  void clearErrorMessage() => clearField(9);

  /// Final aggregate result. Only populated on terminal events
  /// (is_final=true) when the backend can report result metrics.
  @$pb.TagNumber(10)
  LLMStreamFinalResult get result => $_getN(9);
  @$pb.TagNumber(10)
  set result(LLMStreamFinalResult v) { setField(10, v); }
  @$pb.TagNumber(10)
  $core.bool hasResult() => $_has(9);
  @$pb.TagNumber(10)
  void clearResult() => clearField(10);
  @$pb.TagNumber(10)
  LLMStreamFinalResult ensureResult() => $_ensure(9);

  /// Numeric backend status code when the terminal event represents a
  /// failure. 0 = unset/success.
  @$pb.TagNumber(11)
  $core.int get errorCode => $_getIZ(10);
  @$pb.TagNumber(11)
  set errorCode($core.int v) { $_setSignedInt32(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasErrorCode() => $_has(10);
  @$pb.TagNumber(11)
  void clearErrorCode() => clearField(11);
}

class LLMApi {
  $pb.RpcClient _client;
  LLMApi(this._client);

  $async.Future<LLMStreamEvent> generate($pb.ClientContext? ctx, LLMGenerateRequest request) =>
    _client.invoke<LLMStreamEvent>(ctx, 'LLM', 'Generate', request, LLMStreamEvent())
  ;
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
