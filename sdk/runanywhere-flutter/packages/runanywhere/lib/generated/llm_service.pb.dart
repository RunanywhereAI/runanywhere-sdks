//
//  Generated code. Do not modify.
//  source: llm_service.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

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
}

/// One token delta. Matches AssistantTokenEvent in voice_events.proto so
/// callers that already speak that type can reuse decoders.
class LLMToken extends $pb.GeneratedMessage {
  factory LLMToken({
    $core.String? text,
    $core.bool? isFinal,
    LLMTokenKind? kind,
    $core.double? logprob,
    $fixnum.Int64? emitUs,
  }) {
    final $result = create();
    if (text != null) {
      $result.text = text;
    }
    if (isFinal != null) {
      $result.isFinal = isFinal;
    }
    if (kind != null) {
      $result.kind = kind;
    }
    if (logprob != null) {
      $result.logprob = logprob;
    }
    if (emitUs != null) {
      $result.emitUs = emitUs;
    }
    return $result;
  }
  LLMToken._() : super();
  factory LLMToken.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LLMToken.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LLMToken', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOB(2, _omitFieldNames ? '' : 'isFinal')
    ..e<LLMTokenKind>(3, _omitFieldNames ? '' : 'kind', $pb.PbFieldType.OE, defaultOrMaker: LLMTokenKind.LLM_TOKEN_KIND_UNSPECIFIED, valueOf: LLMTokenKind.valueOf, enumValues: LLMTokenKind.values)
    ..a<$core.double>(4, _omitFieldNames ? '' : 'logprob', $pb.PbFieldType.OF)
    ..aInt64(5, _omitFieldNames ? '' : 'emitUs')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LLMToken clone() => LLMToken()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LLMToken copyWith(void Function(LLMToken) updates) => super.copyWith((message) => updates(message as LLMToken)) as LLMToken;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LLMToken create() => LLMToken._();
  LLMToken createEmptyInstance() => create();
  static $pb.PbList<LLMToken> createRepeated() => $pb.PbList<LLMToken>();
  @$core.pragma('dart2js:noInline')
  static LLMToken getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LLMToken>(create);
  static LLMToken? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => clearField(1);

  @$pb.TagNumber(2)
  $core.bool get isFinal => $_getBF(1);
  @$pb.TagNumber(2)
  set isFinal($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasIsFinal() => $_has(1);
  @$pb.TagNumber(2)
  void clearIsFinal() => clearField(2);

  @$pb.TagNumber(3)
  LLMTokenKind get kind => $_getN(2);
  @$pb.TagNumber(3)
  set kind(LLMTokenKind v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasKind() => $_has(2);
  @$pb.TagNumber(3)
  void clearKind() => clearField(3);

  /// Optional per-token logprob, populated when the engine supports it.
  /// 0.0 = no logprob available (proto3 scalar default).
  @$pb.TagNumber(4)
  $core.double get logprob => $_getN(3);
  @$pb.TagNumber(4)
  set logprob($core.double v) { $_setFloat(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasLogprob() => $_has(3);
  @$pb.TagNumber(4)
  void clearLogprob() => clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get emitUs => $_getI64(4);
  @$pb.TagNumber(5)
  set emitUs($fixnum.Int64 v) { $_setInt64(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasEmitUs() => $_has(4);
  @$pb.TagNumber(5)
  void clearEmitUs() => clearField(5);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
