///
//  Generated code. Do not modify.
//  source: llm_service.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'llm_service.pbenum.dart';

export 'llm_service.pbenum.dart';

class LLMGenerateRequest extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'LLMGenerateRequest', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'prompt')
    ..a<$core.int>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'maxTokens', $pb.PbFieldType.O3)
    ..a<$core.double>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'temperature', $pb.PbFieldType.OF)
    ..a<$core.double>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'topP', $pb.PbFieldType.OF)
    ..a<$core.int>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'topK', $pb.PbFieldType.O3)
    ..aOS(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'systemPrompt')
    ..aOB(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'emitThoughts')
    ..hasRequiredFields = false
  ;

  LLMGenerateRequest._() : super();
  factory LLMGenerateRequest({
    $core.String? prompt,
    $core.int? maxTokens,
    $core.double? temperature,
    $core.double? topP,
    $core.int? topK,
    $core.String? systemPrompt,
    $core.bool? emitThoughts,
  }) {
    final _result = create();
    if (prompt != null) {
      _result.prompt = prompt;
    }
    if (maxTokens != null) {
      _result.maxTokens = maxTokens;
    }
    if (temperature != null) {
      _result.temperature = temperature;
    }
    if (topP != null) {
      _result.topP = topP;
    }
    if (topK != null) {
      _result.topK = topK;
    }
    if (systemPrompt != null) {
      _result.systemPrompt = systemPrompt;
    }
    if (emitThoughts != null) {
      _result.emitThoughts = emitThoughts;
    }
    return _result;
  }
  factory LLMGenerateRequest.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LLMGenerateRequest.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LLMGenerateRequest clone() => LLMGenerateRequest()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LLMGenerateRequest copyWith(void Function(LLMGenerateRequest) updates) => super.copyWith((message) => updates(message as LLMGenerateRequest)) as LLMGenerateRequest; // ignore: deprecated_member_use
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
}

class LLMStreamEvent extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'LLMStreamEvent', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$fixnum.Int64>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'seq', $pb.PbFieldType.OU6, defaultOrMaker: $fixnum.Int64.ZERO)
    ..aInt64(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'timestampUs')
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'token')
    ..aOB(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'isFinal')
    ..e<LLMTokenKind>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: LLMTokenKind.LLM_TOKEN_KIND_UNSPECIFIED, valueOf: LLMTokenKind.valueOf, enumValues: LLMTokenKind.values)
    ..a<$core.int>(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'tokenId', $pb.PbFieldType.OU3)
    ..a<$core.double>(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'logprob', $pb.PbFieldType.OF)
    ..aOS(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'finishReason')
    ..aOS(9, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  LLMStreamEvent._() : super();
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
  }) {
    final _result = create();
    if (seq != null) {
      _result.seq = seq;
    }
    if (timestampUs != null) {
      _result.timestampUs = timestampUs;
    }
    if (token != null) {
      _result.token = token;
    }
    if (isFinal != null) {
      _result.isFinal = isFinal;
    }
    if (kind != null) {
      _result.kind = kind;
    }
    if (tokenId != null) {
      _result.tokenId = tokenId;
    }
    if (logprob != null) {
      _result.logprob = logprob;
    }
    if (finishReason != null) {
      _result.finishReason = finishReason;
    }
    if (errorMessage != null) {
      _result.errorMessage = errorMessage;
    }
    return _result;
  }
  factory LLMStreamEvent.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LLMStreamEvent.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LLMStreamEvent clone() => LLMStreamEvent()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LLMStreamEvent copyWith(void Function(LLMStreamEvent) updates) => super.copyWith((message) => updates(message as LLMStreamEvent)) as LLMStreamEvent; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static LLMStreamEvent create() => LLMStreamEvent._();
  LLMStreamEvent createEmptyInstance() => create();
  static $pb.PbList<LLMStreamEvent> createRepeated() => $pb.PbList<LLMStreamEvent>();
  @$core.pragma('dart2js:noInline')
  static LLMStreamEvent getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LLMStreamEvent>(create);
  static LLMStreamEvent? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get seq => $_getI64(0);
  @$pb.TagNumber(1)
  set seq($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasSeq() => $_has(0);
  @$pb.TagNumber(1)
  void clearSeq() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampUs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampUs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTimestampUs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampUs() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get token => $_getSZ(2);
  @$pb.TagNumber(3)
  set token($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasToken() => $_has(2);
  @$pb.TagNumber(3)
  void clearToken() => clearField(3);

  @$pb.TagNumber(4)
  $core.bool get isFinal => $_getBF(3);
  @$pb.TagNumber(4)
  set isFinal($core.bool v) { $_setBool(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasIsFinal() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsFinal() => clearField(4);

  @$pb.TagNumber(5)
  LLMTokenKind get kind => $_getN(4);
  @$pb.TagNumber(5)
  set kind(LLMTokenKind v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasKind() => $_has(4);
  @$pb.TagNumber(5)
  void clearKind() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get tokenId => $_getIZ(5);
  @$pb.TagNumber(6)
  set tokenId($core.int v) { $_setUnsignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasTokenId() => $_has(5);
  @$pb.TagNumber(6)
  void clearTokenId() => clearField(6);

  @$pb.TagNumber(7)
  $core.double get logprob => $_getN(6);
  @$pb.TagNumber(7)
  set logprob($core.double v) { $_setFloat(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasLogprob() => $_has(6);
  @$pb.TagNumber(7)
  void clearLogprob() => clearField(7);

  @$pb.TagNumber(8)
  $core.String get finishReason => $_getSZ(7);
  @$pb.TagNumber(8)
  set finishReason($core.String v) { $_setString(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasFinishReason() => $_has(7);
  @$pb.TagNumber(8)
  void clearFinishReason() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get errorMessage => $_getSZ(8);
  @$pb.TagNumber(9)
  set errorMessage($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasErrorMessage() => $_has(8);
  @$pb.TagNumber(9)
  void clearErrorMessage() => clearField(9);
}

class LLMApi {
  $pb.RpcClient _client;
  LLMApi(this._client);

  $async.Future<LLMStreamEvent> generate($pb.ClientContext? ctx, LLMGenerateRequest request) {
    var emptyResponse = LLMStreamEvent();
    return _client.invoke<LLMStreamEvent>(ctx, 'LLM', 'Generate', request, emptyResponse);
  }
}

