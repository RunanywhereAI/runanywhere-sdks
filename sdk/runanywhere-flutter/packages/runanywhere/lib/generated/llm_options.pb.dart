///
//  Generated code. Do not modify.
//  source: llm_options.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'structured_output.pb.dart' as $0;

import 'model_types.pbenum.dart' as $1;
import 'llm_options.pbenum.dart';

export 'llm_options.pbenum.dart';

class LLMGenerationOptions extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'LLMGenerationOptions', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.int>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'maxTokens', $pb.PbFieldType.O3)
    ..a<$core.double>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'temperature', $pb.PbFieldType.OF)
    ..a<$core.double>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'topP', $pb.PbFieldType.OF)
    ..a<$core.int>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'topK', $pb.PbFieldType.O3)
    ..a<$core.double>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'repetitionPenalty', $pb.PbFieldType.OF)
    ..pPS(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'stopSequences')
    ..aOB(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'streamingEnabled')
    ..e<$1.InferenceFramework>(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'preferredFramework', $pb.PbFieldType.OE, defaultOrMaker: $1.InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED, valueOf: $1.InferenceFramework.valueOf, enumValues: $1.InferenceFramework.values)
    ..aOS(9, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'systemPrompt')
    ..aOS(10, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'jsonSchema')
    ..aOM<ThinkingTagPattern>(11, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'thinkingPattern', subBuilder: ThinkingTagPattern.create)
    ..e<ExecutionTarget>(12, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'executionTarget', $pb.PbFieldType.OE, defaultOrMaker: ExecutionTarget.EXECUTION_TARGET_UNSPECIFIED, valueOf: ExecutionTarget.valueOf, enumValues: ExecutionTarget.values)
    ..aOM<$0.StructuredOutputOptions>(13, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'structuredOutput', subBuilder: $0.StructuredOutputOptions.create)
    ..hasRequiredFields = false
  ;

  LLMGenerationOptions._() : super();
  factory LLMGenerationOptions({
    $core.int? maxTokens,
    $core.double? temperature,
    $core.double? topP,
    $core.int? topK,
    $core.double? repetitionPenalty,
    $core.Iterable<$core.String>? stopSequences,
    $core.bool? streamingEnabled,
    $1.InferenceFramework? preferredFramework,
    $core.String? systemPrompt,
    $core.String? jsonSchema,
    ThinkingTagPattern? thinkingPattern,
    ExecutionTarget? executionTarget,
    $0.StructuredOutputOptions? structuredOutput,
  }) {
    final _result = create();
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
    if (repetitionPenalty != null) {
      _result.repetitionPenalty = repetitionPenalty;
    }
    if (stopSequences != null) {
      _result.stopSequences.addAll(stopSequences);
    }
    if (streamingEnabled != null) {
      _result.streamingEnabled = streamingEnabled;
    }
    if (preferredFramework != null) {
      _result.preferredFramework = preferredFramework;
    }
    if (systemPrompt != null) {
      _result.systemPrompt = systemPrompt;
    }
    if (jsonSchema != null) {
      _result.jsonSchema = jsonSchema;
    }
    if (thinkingPattern != null) {
      _result.thinkingPattern = thinkingPattern;
    }
    if (executionTarget != null) {
      _result.executionTarget = executionTarget;
    }
    if (structuredOutput != null) {
      _result.structuredOutput = structuredOutput;
    }
    return _result;
  }
  factory LLMGenerationOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LLMGenerationOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LLMGenerationOptions clone() => LLMGenerationOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LLMGenerationOptions copyWith(void Function(LLMGenerationOptions) updates) => super.copyWith((message) => updates(message as LLMGenerationOptions)) as LLMGenerationOptions; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static LLMGenerationOptions create() => LLMGenerationOptions._();
  LLMGenerationOptions createEmptyInstance() => create();
  static $pb.PbList<LLMGenerationOptions> createRepeated() => $pb.PbList<LLMGenerationOptions>();
  @$core.pragma('dart2js:noInline')
  static LLMGenerationOptions getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LLMGenerationOptions>(create);
  static LLMGenerationOptions? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get maxTokens => $_getIZ(0);
  @$pb.TagNumber(1)
  set maxTokens($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMaxTokens() => $_has(0);
  @$pb.TagNumber(1)
  void clearMaxTokens() => clearField(1);

  @$pb.TagNumber(2)
  $core.double get temperature => $_getN(1);
  @$pb.TagNumber(2)
  set temperature($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTemperature() => $_has(1);
  @$pb.TagNumber(2)
  void clearTemperature() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get topP => $_getN(2);
  @$pb.TagNumber(3)
  set topP($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTopP() => $_has(2);
  @$pb.TagNumber(3)
  void clearTopP() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get topK => $_getIZ(3);
  @$pb.TagNumber(4)
  set topK($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTopK() => $_has(3);
  @$pb.TagNumber(4)
  void clearTopK() => clearField(4);

  @$pb.TagNumber(5)
  $core.double get repetitionPenalty => $_getN(4);
  @$pb.TagNumber(5)
  set repetitionPenalty($core.double v) { $_setFloat(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasRepetitionPenalty() => $_has(4);
  @$pb.TagNumber(5)
  void clearRepetitionPenalty() => clearField(5);

  @$pb.TagNumber(6)
  $core.List<$core.String> get stopSequences => $_getList(5);

  @$pb.TagNumber(7)
  $core.bool get streamingEnabled => $_getBF(6);
  @$pb.TagNumber(7)
  set streamingEnabled($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasStreamingEnabled() => $_has(6);
  @$pb.TagNumber(7)
  void clearStreamingEnabled() => clearField(7);

  @$pb.TagNumber(8)
  $1.InferenceFramework get preferredFramework => $_getN(7);
  @$pb.TagNumber(8)
  set preferredFramework($1.InferenceFramework v) { setField(8, v); }
  @$pb.TagNumber(8)
  $core.bool hasPreferredFramework() => $_has(7);
  @$pb.TagNumber(8)
  void clearPreferredFramework() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get systemPrompt => $_getSZ(8);
  @$pb.TagNumber(9)
  set systemPrompt($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasSystemPrompt() => $_has(8);
  @$pb.TagNumber(9)
  void clearSystemPrompt() => clearField(9);

  @$pb.TagNumber(10)
  $core.String get jsonSchema => $_getSZ(9);
  @$pb.TagNumber(10)
  set jsonSchema($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasJsonSchema() => $_has(9);
  @$pb.TagNumber(10)
  void clearJsonSchema() => clearField(10);

  @$pb.TagNumber(11)
  ThinkingTagPattern get thinkingPattern => $_getN(10);
  @$pb.TagNumber(11)
  set thinkingPattern(ThinkingTagPattern v) { setField(11, v); }
  @$pb.TagNumber(11)
  $core.bool hasThinkingPattern() => $_has(10);
  @$pb.TagNumber(11)
  void clearThinkingPattern() => clearField(11);
  @$pb.TagNumber(11)
  ThinkingTagPattern ensureThinkingPattern() => $_ensure(10);

  @$pb.TagNumber(12)
  ExecutionTarget get executionTarget => $_getN(11);
  @$pb.TagNumber(12)
  set executionTarget(ExecutionTarget v) { setField(12, v); }
  @$pb.TagNumber(12)
  $core.bool hasExecutionTarget() => $_has(11);
  @$pb.TagNumber(12)
  void clearExecutionTarget() => clearField(12);

  @$pb.TagNumber(13)
  $0.StructuredOutputOptions get structuredOutput => $_getN(12);
  @$pb.TagNumber(13)
  set structuredOutput($0.StructuredOutputOptions v) { setField(13, v); }
  @$pb.TagNumber(13)
  $core.bool hasStructuredOutput() => $_has(12);
  @$pb.TagNumber(13)
  void clearStructuredOutput() => clearField(13);
  @$pb.TagNumber(13)
  $0.StructuredOutputOptions ensureStructuredOutput() => $_ensure(12);
}

class LLMGenerationResult extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'LLMGenerationResult', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'text')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'thinkingContent')
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'inputTokens', $pb.PbFieldType.O3)
    ..a<$core.int>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'tokensGenerated', $pb.PbFieldType.O3)
    ..aOS(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'modelUsed')
    ..a<$core.double>(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'generationTimeMs', $pb.PbFieldType.OD)
    ..a<$core.double>(7, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'ttftMs', $pb.PbFieldType.OD)
    ..a<$core.double>(8, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'tokensPerSecond', $pb.PbFieldType.OD)
    ..aOS(9, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'framework')
    ..aOS(10, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'finishReason')
    ..a<$core.int>(11, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'thinkingTokens', $pb.PbFieldType.O3)
    ..a<$core.int>(12, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'responseTokens', $pb.PbFieldType.O3)
    ..aOS(13, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'jsonOutput')
    ..aOM<PerformanceMetrics>(14, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'performance', subBuilder: PerformanceMetrics.create)
    ..e<ExecutionTarget>(15, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'executedOn', $pb.PbFieldType.OE, defaultOrMaker: ExecutionTarget.EXECUTION_TARGET_UNSPECIFIED, valueOf: ExecutionTarget.valueOf, enumValues: ExecutionTarget.values)
    ..hasRequiredFields = false
  ;

  LLMGenerationResult._() : super();
  factory LLMGenerationResult({
    $core.String? text,
    $core.String? thinkingContent,
    $core.int? inputTokens,
    $core.int? tokensGenerated,
    $core.String? modelUsed,
    $core.double? generationTimeMs,
    $core.double? ttftMs,
    $core.double? tokensPerSecond,
    $core.String? framework,
    $core.String? finishReason,
    $core.int? thinkingTokens,
    $core.int? responseTokens,
    $core.String? jsonOutput,
    PerformanceMetrics? performance,
    ExecutionTarget? executedOn,
  }) {
    final _result = create();
    if (text != null) {
      _result.text = text;
    }
    if (thinkingContent != null) {
      _result.thinkingContent = thinkingContent;
    }
    if (inputTokens != null) {
      _result.inputTokens = inputTokens;
    }
    if (tokensGenerated != null) {
      _result.tokensGenerated = tokensGenerated;
    }
    if (modelUsed != null) {
      _result.modelUsed = modelUsed;
    }
    if (generationTimeMs != null) {
      _result.generationTimeMs = generationTimeMs;
    }
    if (ttftMs != null) {
      _result.ttftMs = ttftMs;
    }
    if (tokensPerSecond != null) {
      _result.tokensPerSecond = tokensPerSecond;
    }
    if (framework != null) {
      _result.framework = framework;
    }
    if (finishReason != null) {
      _result.finishReason = finishReason;
    }
    if (thinkingTokens != null) {
      _result.thinkingTokens = thinkingTokens;
    }
    if (responseTokens != null) {
      _result.responseTokens = responseTokens;
    }
    if (jsonOutput != null) {
      _result.jsonOutput = jsonOutput;
    }
    if (performance != null) {
      _result.performance = performance;
    }
    if (executedOn != null) {
      _result.executedOn = executedOn;
    }
    return _result;
  }
  factory LLMGenerationResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LLMGenerationResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LLMGenerationResult clone() => LLMGenerationResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LLMGenerationResult copyWith(void Function(LLMGenerationResult) updates) => super.copyWith((message) => updates(message as LLMGenerationResult)) as LLMGenerationResult; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static LLMGenerationResult create() => LLMGenerationResult._();
  LLMGenerationResult createEmptyInstance() => create();
  static $pb.PbList<LLMGenerationResult> createRepeated() => $pb.PbList<LLMGenerationResult>();
  @$core.pragma('dart2js:noInline')
  static LLMGenerationResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LLMGenerationResult>(create);
  static LLMGenerationResult? _defaultInstance;

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
  $core.int get inputTokens => $_getIZ(2);
  @$pb.TagNumber(3)
  set inputTokens($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasInputTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearInputTokens() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get tokensGenerated => $_getIZ(3);
  @$pb.TagNumber(4)
  set tokensGenerated($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTokensGenerated() => $_has(3);
  @$pb.TagNumber(4)
  void clearTokensGenerated() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get modelUsed => $_getSZ(4);
  @$pb.TagNumber(5)
  set modelUsed($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasModelUsed() => $_has(4);
  @$pb.TagNumber(5)
  void clearModelUsed() => clearField(5);

  @$pb.TagNumber(6)
  $core.double get generationTimeMs => $_getN(5);
  @$pb.TagNumber(6)
  set generationTimeMs($core.double v) { $_setDouble(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasGenerationTimeMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearGenerationTimeMs() => clearField(6);

  @$pb.TagNumber(7)
  $core.double get ttftMs => $_getN(6);
  @$pb.TagNumber(7)
  set ttftMs($core.double v) { $_setDouble(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasTtftMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearTtftMs() => clearField(7);

  @$pb.TagNumber(8)
  $core.double get tokensPerSecond => $_getN(7);
  @$pb.TagNumber(8)
  set tokensPerSecond($core.double v) { $_setDouble(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasTokensPerSecond() => $_has(7);
  @$pb.TagNumber(8)
  void clearTokensPerSecond() => clearField(8);

  @$pb.TagNumber(9)
  $core.String get framework => $_getSZ(8);
  @$pb.TagNumber(9)
  set framework($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasFramework() => $_has(8);
  @$pb.TagNumber(9)
  void clearFramework() => clearField(9);

  @$pb.TagNumber(10)
  $core.String get finishReason => $_getSZ(9);
  @$pb.TagNumber(10)
  set finishReason($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasFinishReason() => $_has(9);
  @$pb.TagNumber(10)
  void clearFinishReason() => clearField(10);

  @$pb.TagNumber(11)
  $core.int get thinkingTokens => $_getIZ(10);
  @$pb.TagNumber(11)
  set thinkingTokens($core.int v) { $_setSignedInt32(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasThinkingTokens() => $_has(10);
  @$pb.TagNumber(11)
  void clearThinkingTokens() => clearField(11);

  @$pb.TagNumber(12)
  $core.int get responseTokens => $_getIZ(11);
  @$pb.TagNumber(12)
  set responseTokens($core.int v) { $_setSignedInt32(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasResponseTokens() => $_has(11);
  @$pb.TagNumber(12)
  void clearResponseTokens() => clearField(12);

  @$pb.TagNumber(13)
  $core.String get jsonOutput => $_getSZ(12);
  @$pb.TagNumber(13)
  set jsonOutput($core.String v) { $_setString(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasJsonOutput() => $_has(12);
  @$pb.TagNumber(13)
  void clearJsonOutput() => clearField(13);

  @$pb.TagNumber(14)
  PerformanceMetrics get performance => $_getN(13);
  @$pb.TagNumber(14)
  set performance(PerformanceMetrics v) { setField(14, v); }
  @$pb.TagNumber(14)
  $core.bool hasPerformance() => $_has(13);
  @$pb.TagNumber(14)
  void clearPerformance() => clearField(14);
  @$pb.TagNumber(14)
  PerformanceMetrics ensurePerformance() => $_ensure(13);

  @$pb.TagNumber(15)
  ExecutionTarget get executedOn => $_getN(14);
  @$pb.TagNumber(15)
  set executedOn(ExecutionTarget v) { setField(15, v); }
  @$pb.TagNumber(15)
  $core.bool hasExecutedOn() => $_has(14);
  @$pb.TagNumber(15)
  void clearExecutedOn() => clearField(15);
}

class LLMConfiguration extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'LLMConfiguration', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.int>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'contextLength', $pb.PbFieldType.O3)
    ..a<$core.double>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'temperature', $pb.PbFieldType.OF)
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'maxTokens', $pb.PbFieldType.O3)
    ..aOS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'systemPrompt')
    ..aOB(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'streaming')
    ..hasRequiredFields = false
  ;

  LLMConfiguration._() : super();
  factory LLMConfiguration({
    $core.int? contextLength,
    $core.double? temperature,
    $core.int? maxTokens,
    $core.String? systemPrompt,
    $core.bool? streaming,
  }) {
    final _result = create();
    if (contextLength != null) {
      _result.contextLength = contextLength;
    }
    if (temperature != null) {
      _result.temperature = temperature;
    }
    if (maxTokens != null) {
      _result.maxTokens = maxTokens;
    }
    if (systemPrompt != null) {
      _result.systemPrompt = systemPrompt;
    }
    if (streaming != null) {
      _result.streaming = streaming;
    }
    return _result;
  }
  factory LLMConfiguration.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LLMConfiguration.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LLMConfiguration clone() => LLMConfiguration()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LLMConfiguration copyWith(void Function(LLMConfiguration) updates) => super.copyWith((message) => updates(message as LLMConfiguration)) as LLMConfiguration; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static LLMConfiguration create() => LLMConfiguration._();
  LLMConfiguration createEmptyInstance() => create();
  static $pb.PbList<LLMConfiguration> createRepeated() => $pb.PbList<LLMConfiguration>();
  @$core.pragma('dart2js:noInline')
  static LLMConfiguration getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LLMConfiguration>(create);
  static LLMConfiguration? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get contextLength => $_getIZ(0);
  @$pb.TagNumber(1)
  set contextLength($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasContextLength() => $_has(0);
  @$pb.TagNumber(1)
  void clearContextLength() => clearField(1);

  @$pb.TagNumber(2)
  $core.double get temperature => $_getN(1);
  @$pb.TagNumber(2)
  set temperature($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTemperature() => $_has(1);
  @$pb.TagNumber(2)
  void clearTemperature() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get maxTokens => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxTokens($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMaxTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxTokens() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get systemPrompt => $_getSZ(3);
  @$pb.TagNumber(4)
  set systemPrompt($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSystemPrompt() => $_has(3);
  @$pb.TagNumber(4)
  void clearSystemPrompt() => clearField(4);

  @$pb.TagNumber(5)
  $core.bool get streaming => $_getBF(4);
  @$pb.TagNumber(5)
  set streaming($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasStreaming() => $_has(4);
  @$pb.TagNumber(5)
  void clearStreaming() => clearField(5);
}

class GenerationHints extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'GenerationHints', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.double>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'temperature', $pb.PbFieldType.OF)
    ..a<$core.int>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'maxTokens', $pb.PbFieldType.O3)
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'systemRole')
    ..hasRequiredFields = false
  ;

  GenerationHints._() : super();
  factory GenerationHints({
    $core.double? temperature,
    $core.int? maxTokens,
    $core.String? systemRole,
  }) {
    final _result = create();
    if (temperature != null) {
      _result.temperature = temperature;
    }
    if (maxTokens != null) {
      _result.maxTokens = maxTokens;
    }
    if (systemRole != null) {
      _result.systemRole = systemRole;
    }
    return _result;
  }
  factory GenerationHints.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GenerationHints.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GenerationHints clone() => GenerationHints()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GenerationHints copyWith(void Function(GenerationHints) updates) => super.copyWith((message) => updates(message as GenerationHints)) as GenerationHints; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static GenerationHints create() => GenerationHints._();
  GenerationHints createEmptyInstance() => create();
  static $pb.PbList<GenerationHints> createRepeated() => $pb.PbList<GenerationHints>();
  @$core.pragma('dart2js:noInline')
  static GenerationHints getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GenerationHints>(create);
  static GenerationHints? _defaultInstance;

  @$pb.TagNumber(1)
  $core.double get temperature => $_getN(0);
  @$pb.TagNumber(1)
  set temperature($core.double v) { $_setFloat(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTemperature() => $_has(0);
  @$pb.TagNumber(1)
  void clearTemperature() => clearField(1);

  @$pb.TagNumber(2)
  $core.int get maxTokens => $_getIZ(1);
  @$pb.TagNumber(2)
  set maxTokens($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMaxTokens() => $_has(1);
  @$pb.TagNumber(2)
  void clearMaxTokens() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get systemRole => $_getSZ(2);
  @$pb.TagNumber(3)
  set systemRole($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSystemRole() => $_has(2);
  @$pb.TagNumber(3)
  void clearSystemRole() => clearField(3);
}

class ThinkingTagPattern extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ThinkingTagPattern', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'openingTag')
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'closingTag')
    ..hasRequiredFields = false
  ;

  ThinkingTagPattern._() : super();
  factory ThinkingTagPattern({
    $core.String? openingTag,
    $core.String? closingTag,
  }) {
    final _result = create();
    if (openingTag != null) {
      _result.openingTag = openingTag;
    }
    if (closingTag != null) {
      _result.closingTag = closingTag;
    }
    return _result;
  }
  factory ThinkingTagPattern.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ThinkingTagPattern.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ThinkingTagPattern clone() => ThinkingTagPattern()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ThinkingTagPattern copyWith(void Function(ThinkingTagPattern) updates) => super.copyWith((message) => updates(message as ThinkingTagPattern)) as ThinkingTagPattern; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ThinkingTagPattern create() => ThinkingTagPattern._();
  ThinkingTagPattern createEmptyInstance() => create();
  static $pb.PbList<ThinkingTagPattern> createRepeated() => $pb.PbList<ThinkingTagPattern>();
  @$core.pragma('dart2js:noInline')
  static ThinkingTagPattern getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ThinkingTagPattern>(create);
  static ThinkingTagPattern? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get openingTag => $_getSZ(0);
  @$pb.TagNumber(1)
  set openingTag($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasOpeningTag() => $_has(0);
  @$pb.TagNumber(1)
  void clearOpeningTag() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get closingTag => $_getSZ(1);
  @$pb.TagNumber(2)
  set closingTag($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasClosingTag() => $_has(1);
  @$pb.TagNumber(2)
  void clearClosingTag() => clearField(2);
}

class StreamToken extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'StreamToken', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'text')
    ..aInt64(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'timestampMs')
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'index', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  StreamToken._() : super();
  factory StreamToken({
    $core.String? text,
    $fixnum.Int64? timestampMs,
    $core.int? index,
  }) {
    final _result = create();
    if (text != null) {
      _result.text = text;
    }
    if (timestampMs != null) {
      _result.timestampMs = timestampMs;
    }
    if (index != null) {
      _result.index = index;
    }
    return _result;
  }
  factory StreamToken.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StreamToken.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StreamToken clone() => StreamToken()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StreamToken copyWith(void Function(StreamToken) updates) => super.copyWith((message) => updates(message as StreamToken)) as StreamToken; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static StreamToken create() => StreamToken._();
  StreamToken createEmptyInstance() => create();
  static $pb.PbList<StreamToken> createRepeated() => $pb.PbList<StreamToken>();
  @$core.pragma('dart2js:noInline')
  static StreamToken getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StreamToken>(create);
  static StreamToken? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampMs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampMs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTimestampMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampMs() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get index => $_getIZ(2);
  @$pb.TagNumber(3)
  set index($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasIndex() => $_has(2);
  @$pb.TagNumber(3)
  void clearIndex() => clearField(3);
}

class PerformanceMetrics extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'PerformanceMetrics', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aInt64(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'latencyMs')
    ..aInt64(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'memoryBytes')
    ..a<$core.double>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'throughputTokensPerSec', $pb.PbFieldType.OF)
    ..a<$core.int>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'promptTokens', $pb.PbFieldType.O3)
    ..a<$core.int>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'completionTokens', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  PerformanceMetrics._() : super();
  factory PerformanceMetrics({
    $fixnum.Int64? latencyMs,
    $fixnum.Int64? memoryBytes,
    $core.double? throughputTokensPerSec,
    $core.int? promptTokens,
    $core.int? completionTokens,
  }) {
    final _result = create();
    if (latencyMs != null) {
      _result.latencyMs = latencyMs;
    }
    if (memoryBytes != null) {
      _result.memoryBytes = memoryBytes;
    }
    if (throughputTokensPerSec != null) {
      _result.throughputTokensPerSec = throughputTokensPerSec;
    }
    if (promptTokens != null) {
      _result.promptTokens = promptTokens;
    }
    if (completionTokens != null) {
      _result.completionTokens = completionTokens;
    }
    return _result;
  }
  factory PerformanceMetrics.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PerformanceMetrics.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PerformanceMetrics clone() => PerformanceMetrics()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PerformanceMetrics copyWith(void Function(PerformanceMetrics) updates) => super.copyWith((message) => updates(message as PerformanceMetrics)) as PerformanceMetrics; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static PerformanceMetrics create() => PerformanceMetrics._();
  PerformanceMetrics createEmptyInstance() => create();
  static $pb.PbList<PerformanceMetrics> createRepeated() => $pb.PbList<PerformanceMetrics>();
  @$core.pragma('dart2js:noInline')
  static PerformanceMetrics getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PerformanceMetrics>(create);
  static PerformanceMetrics? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get latencyMs => $_getI64(0);
  @$pb.TagNumber(1)
  set latencyMs($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasLatencyMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearLatencyMs() => clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get memoryBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set memoryBytes($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMemoryBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearMemoryBytes() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get throughputTokensPerSec => $_getN(2);
  @$pb.TagNumber(3)
  set throughputTokensPerSec($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasThroughputTokensPerSec() => $_has(2);
  @$pb.TagNumber(3)
  void clearThroughputTokensPerSec() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get promptTokens => $_getIZ(3);
  @$pb.TagNumber(4)
  set promptTokens($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasPromptTokens() => $_has(3);
  @$pb.TagNumber(4)
  void clearPromptTokens() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get completionTokens => $_getIZ(4);
  @$pb.TagNumber(5)
  set completionTokens($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasCompletionTokens() => $_has(4);
  @$pb.TagNumber(5)
  void clearCompletionTokens() => clearField(5);
}

