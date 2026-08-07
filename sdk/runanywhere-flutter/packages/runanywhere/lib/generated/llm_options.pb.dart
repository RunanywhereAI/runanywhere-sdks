// This is a generated file - do not edit.
//
// Generated from llm_options.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'errors.pb.dart' as $4;
import 'llm_options.pbenum.dart';
import 'model_types.pbenum.dart' as $5;
import 'structured_output.pb.dart' as $1;
import 'thinking_tag_pattern.pb.dart' as $0;
import 'token_usage.pb.dart' as $3;
import 'tool_calling.pb.dart' as $2;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'llm_options.pbenum.dart';

class LLMGenerationOptions extends $pb.GeneratedMessage {
  factory LLMGenerationOptions({
    $core.int? maxOutputTokens,
    $core.double? temperature,
    $core.double? topP,
    $core.int? topK,
    $core.double? repeatPenalty,
    $core.Iterable<$core.String>? stopSequences,
    $5.InferenceFramework? preferredFramework,
    $core.String? systemPrompt,
    $0.ReasoningOptions? reasoning,
    ExecutionTarget? executionTarget,
    $1.StructuredOutputOptions? structuredOutput,
    $fixnum.Int64? seed,
    $core.double? frequencyPenalty,
    $core.double? presencePenalty,
    $core.int? repeatLastN,
    $core.double? minP,
    $core.bool? echoPrompt,
    $2.ToolCallingOptions? toolCalling,
  }) {
    final result = create();
    if (maxOutputTokens != null) result.maxOutputTokens = maxOutputTokens;
    if (temperature != null) result.temperature = temperature;
    if (topP != null) result.topP = topP;
    if (topK != null) result.topK = topK;
    if (repeatPenalty != null) result.repeatPenalty = repeatPenalty;
    if (stopSequences != null) result.stopSequences.addAll(stopSequences);
    if (preferredFramework != null)
      result.preferredFramework = preferredFramework;
    if (systemPrompt != null) result.systemPrompt = systemPrompt;
    if (reasoning != null) result.reasoning = reasoning;
    if (executionTarget != null) result.executionTarget = executionTarget;
    if (structuredOutput != null) result.structuredOutput = structuredOutput;
    if (seed != null) result.seed = seed;
    if (frequencyPenalty != null) result.frequencyPenalty = frequencyPenalty;
    if (presencePenalty != null) result.presencePenalty = presencePenalty;
    if (repeatLastN != null) result.repeatLastN = repeatLastN;
    if (minP != null) result.minP = minP;
    if (echoPrompt != null) result.echoPrompt = echoPrompt;
    if (toolCalling != null) result.toolCalling = toolCalling;
    return result;
  }

  LLMGenerationOptions._();

  factory LLMGenerationOptions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LLMGenerationOptions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LLMGenerationOptions',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'maxOutputTokens')
    ..aD(2, _omitFieldNames ? '' : 'temperature', fieldType: $pb.PbFieldType.OF)
    ..aD(3, _omitFieldNames ? '' : 'topP', fieldType: $pb.PbFieldType.OF)
    ..aI(4, _omitFieldNames ? '' : 'topK')
    ..aD(5, _omitFieldNames ? '' : 'repeatPenalty',
        fieldType: $pb.PbFieldType.OF)
    ..pPS(6, _omitFieldNames ? '' : 'stopSequences')
    ..aE<$5.InferenceFramework>(8, _omitFieldNames ? '' : 'preferredFramework',
        enumValues: $5.InferenceFramework.values)
    ..aOS(9, _omitFieldNames ? '' : 'systemPrompt')
    ..aOM<$0.ReasoningOptions>(11, _omitFieldNames ? '' : 'reasoning',
        subBuilder: $0.ReasoningOptions.create)
    ..aE<ExecutionTarget>(12, _omitFieldNames ? '' : 'executionTarget',
        enumValues: ExecutionTarget.values)
    ..aOM<$1.StructuredOutputOptions>(
        13, _omitFieldNames ? '' : 'structuredOutput',
        subBuilder: $1.StructuredOutputOptions.create)
    ..aInt64(15, _omitFieldNames ? '' : 'seed')
    ..aD(16, _omitFieldNames ? '' : 'frequencyPenalty',
        fieldType: $pb.PbFieldType.OF)
    ..aD(17, _omitFieldNames ? '' : 'presencePenalty',
        fieldType: $pb.PbFieldType.OF)
    ..aI(18, _omitFieldNames ? '' : 'repeatLastN')
    ..aD(19, _omitFieldNames ? '' : 'minP', fieldType: $pb.PbFieldType.OF)
    ..aOB(22, _omitFieldNames ? '' : 'echoPrompt')
    ..aOM<$2.ToolCallingOptions>(24, _omitFieldNames ? '' : 'toolCalling',
        subBuilder: $2.ToolCallingOptions.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LLMGenerationOptions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LLMGenerationOptions copyWith(void Function(LLMGenerationOptions) updates) =>
      super.copyWith((message) => updates(message as LLMGenerationOptions))
          as LLMGenerationOptions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LLMGenerationOptions create() => LLMGenerationOptions._();
  @$core.override
  LLMGenerationOptions createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LLMGenerationOptions getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LLMGenerationOptions>(create);
  static LLMGenerationOptions? _defaultInstance;

  /// Every knob below has explicit presence: ABSENT means the annotated
  /// default applies, and any value the caller sets -- including 0 -- is
  /// honoured verbatim. Nothing treats 0 as unset.
  ///
  /// Sampler chain order is fixed: repeat_penalty -> top_k -> top_p ->
  /// min_p -> temperature (llama.cpp order, minus the samplers we do not
  /// expose). top_k/min_p/repeat_penalty default ON to match llama.cpp and
  /// Ollama, which both ship these on because small quantized models loop
  /// without them.
  @$pb.TagNumber(1)
  $core.int get maxOutputTokens => $_getIZ(0);
  @$pb.TagNumber(1)
  set maxOutputTokens($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMaxOutputTokens() => $_has(0);
  @$pb.TagNumber(1)
  void clearMaxOutputTokens() => $_clearField(1);

  /// 0.0 = greedy decoding, and is honoured as an explicit request.
  @$pb.TagNumber(2)
  $core.double get temperature => $_getN(1);
  @$pb.TagNumber(2)
  set temperature($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTemperature() => $_has(1);
  @$pb.TagNumber(2)
  void clearTemperature() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get topP => $_getN(2);
  @$pb.TagNumber(3)
  set topP($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTopP() => $_has(2);
  @$pb.TagNumber(3)
  void clearTopP() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get topK => $_getIZ(3);
  @$pb.TagNumber(4)
  set topK($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTopK() => $_has(3);
  @$pb.TagNumber(4)
  void clearTopK() => $_clearField(4);

  /// Industry name: llama.cpp and Ollama both spell this repeat_penalty.
  @$pb.TagNumber(5)
  $core.double get repeatPenalty => $_getN(4);
  @$pb.TagNumber(5)
  set repeatPenalty($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRepeatPenalty() => $_has(4);
  @$pb.TagNumber(5)
  void clearRepeatPenalty() => $_clearField(5);

  @$pb.TagNumber(6)
  $pb.PbList<$core.String> get stopSequences => $_getList(5);

  @$pb.TagNumber(8)
  $5.InferenceFramework get preferredFramework => $_getN(6);
  @$pb.TagNumber(8)
  set preferredFramework($5.InferenceFramework value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasPreferredFramework() => $_has(6);
  @$pb.TagNumber(8)
  void clearPreferredFramework() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get systemPrompt => $_getSZ(7);
  @$pb.TagNumber(9)
  set systemPrompt($core.String value) => $_setString(7, value);
  @$pb.TagNumber(9)
  $core.bool hasSystemPrompt() => $_has(7);
  @$pb.TagNumber(9)
  void clearSystemPrompt() => $_clearField(9);

  @$pb.TagNumber(11)
  $0.ReasoningOptions get reasoning => $_getN(8);
  @$pb.TagNumber(11)
  set reasoning($0.ReasoningOptions value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasReasoning() => $_has(8);
  @$pb.TagNumber(11)
  void clearReasoning() => $_clearField(11);
  @$pb.TagNumber(11)
  $0.ReasoningOptions ensureReasoning() => $_ensure(8);

  /// No consumer reads this today.
  @$pb.TagNumber(12)
  ExecutionTarget get executionTarget => $_getN(9);
  @$pb.TagNumber(12)
  set executionTarget(ExecutionTarget value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasExecutionTarget() => $_has(9);
  @$pb.TagNumber(12)
  void clearExecutionTarget() => $_clearField(12);

  @$pb.TagNumber(13)
  $1.StructuredOutputOptions get structuredOutput => $_getN(10);
  @$pb.TagNumber(13)
  set structuredOutput($1.StructuredOutputOptions value) =>
      $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasStructuredOutput() => $_has(10);
  @$pb.TagNumber(13)
  void clearStructuredOutput() => $_clearField(13);
  @$pb.TagNumber(13)
  $1.StructuredOutputOptions ensureStructuredOutput() => $_ensure(10);

  @$pb.TagNumber(15)
  $fixnum.Int64 get seed => $_getI64(11);
  @$pb.TagNumber(15)
  set seed($fixnum.Int64 value) => $_setInt64(11, value);
  @$pb.TagNumber(15)
  $core.bool hasSeed() => $_has(11);
  @$pb.TagNumber(15)
  void clearSeed() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.double get frequencyPenalty => $_getN(12);
  @$pb.TagNumber(16)
  set frequencyPenalty($core.double value) => $_setFloat(12, value);
  @$pb.TagNumber(16)
  $core.bool hasFrequencyPenalty() => $_has(12);
  @$pb.TagNumber(16)
  void clearFrequencyPenalty() => $_clearField(16);

  @$pb.TagNumber(17)
  $core.double get presencePenalty => $_getN(13);
  @$pb.TagNumber(17)
  set presencePenalty($core.double value) => $_setFloat(13, value);
  @$pb.TagNumber(17)
  $core.bool hasPresencePenalty() => $_has(13);
  @$pb.TagNumber(17)
  void clearPresencePenalty() => $_clearField(17);

  /// No engine reads repeat_last_n or echo_prompt.
  @$pb.TagNumber(18)
  $core.int get repeatLastN => $_getIZ(14);
  @$pb.TagNumber(18)
  set repeatLastN($core.int value) => $_setSignedInt32(14, value);
  @$pb.TagNumber(18)
  $core.bool hasRepeatLastN() => $_has(14);
  @$pb.TagNumber(18)
  void clearRepeatLastN() => $_clearField(18);

  @$pb.TagNumber(19)
  $core.double get minP => $_getN(15);
  @$pb.TagNumber(19)
  set minP($core.double value) => $_setFloat(15, value);
  @$pb.TagNumber(19)
  $core.bool hasMinP() => $_has(15);
  @$pb.TagNumber(19)
  void clearMinP() => $_clearField(19);

  @$pb.TagNumber(22)
  $core.bool get echoPrompt => $_getBF(16);
  @$pb.TagNumber(22)
  set echoPrompt($core.bool value) => $_setBool(16, value);
  @$pb.TagNumber(22)
  $core.bool hasEchoPrompt() => $_has(16);
  @$pb.TagNumber(22)
  void clearEchoPrompt() => $_clearField(22);

  @$pb.TagNumber(24)
  $2.ToolCallingOptions get toolCalling => $_getN(17);
  @$pb.TagNumber(24)
  set toolCalling($2.ToolCallingOptions value) => $_setField(24, value);
  @$pb.TagNumber(24)
  $core.bool hasToolCalling() => $_has(17);
  @$pb.TagNumber(24)
  void clearToolCalling() => $_clearField(24);
  @$pb.TagNumber(24)
  $2.ToolCallingOptions ensureToolCalling() => $_ensure(17);
}

class LLMGenerationResult extends $pb.GeneratedMessage {
  factory LLMGenerationResult({
    $core.String? text,
    $core.String? thinkingContent,
    $core.String? modelUsed,
    $core.double? generationTimeMs,
    $core.String? framework,
    $core.int? thinkingTokens,
    $core.int? responseTokens,
    $core.String? jsonOutput,
    PerformanceMetrics? performance,
    ExecutionTarget? executedOn,
    $1.StructuredOutputValidation? structuredOutputValidation,
    $core.int? cachedPromptTokens,
    $fixnum.Int64? promptEvalTimeMs,
    $fixnum.Int64? decodeTimeMs,
    $core.Iterable<$2.ToolCall>? toolCalls,
    $core.Iterable<$2.ToolResult>? toolResults,
    $3.TokenUsage? usage,
    $4.SDKError? error,
    FinishReason? finishReason,
    $core.String? stopSequence,
  }) {
    final result = create();
    if (text != null) result.text = text;
    if (thinkingContent != null) result.thinkingContent = thinkingContent;
    if (modelUsed != null) result.modelUsed = modelUsed;
    if (generationTimeMs != null) result.generationTimeMs = generationTimeMs;
    if (framework != null) result.framework = framework;
    if (thinkingTokens != null) result.thinkingTokens = thinkingTokens;
    if (responseTokens != null) result.responseTokens = responseTokens;
    if (jsonOutput != null) result.jsonOutput = jsonOutput;
    if (performance != null) result.performance = performance;
    if (executedOn != null) result.executedOn = executedOn;
    if (structuredOutputValidation != null)
      result.structuredOutputValidation = structuredOutputValidation;
    if (cachedPromptTokens != null)
      result.cachedPromptTokens = cachedPromptTokens;
    if (promptEvalTimeMs != null) result.promptEvalTimeMs = promptEvalTimeMs;
    if (decodeTimeMs != null) result.decodeTimeMs = decodeTimeMs;
    if (toolCalls != null) result.toolCalls.addAll(toolCalls);
    if (toolResults != null) result.toolResults.addAll(toolResults);
    if (usage != null) result.usage = usage;
    if (error != null) result.error = error;
    if (finishReason != null) result.finishReason = finishReason;
    if (stopSequence != null) result.stopSequence = stopSequence;
    return result;
  }

  LLMGenerationResult._();

  factory LLMGenerationResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LLMGenerationResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LLMGenerationResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOS(2, _omitFieldNames ? '' : 'thinkingContent')
    ..aOS(5, _omitFieldNames ? '' : 'modelUsed')
    ..aD(6, _omitFieldNames ? '' : 'generationTimeMs')
    ..aOS(9, _omitFieldNames ? '' : 'framework')
    ..aI(11, _omitFieldNames ? '' : 'thinkingTokens')
    ..aI(12, _omitFieldNames ? '' : 'responseTokens')
    ..aOS(13, _omitFieldNames ? '' : 'jsonOutput')
    ..aOM<PerformanceMetrics>(14, _omitFieldNames ? '' : 'performance',
        subBuilder: PerformanceMetrics.create)
    ..aE<ExecutionTarget>(15, _omitFieldNames ? '' : 'executedOn',
        enumValues: ExecutionTarget.values)
    ..aOM<$1.StructuredOutputValidation>(
        16, _omitFieldNames ? '' : 'structuredOutputValidation',
        subBuilder: $1.StructuredOutputValidation.create)
    ..aI(20, _omitFieldNames ? '' : 'cachedPromptTokens')
    ..aInt64(21, _omitFieldNames ? '' : 'promptEvalTimeMs')
    ..aInt64(22, _omitFieldNames ? '' : 'decodeTimeMs')
    ..pPM<$2.ToolCall>(23, _omitFieldNames ? '' : 'toolCalls',
        subBuilder: $2.ToolCall.create)
    ..pPM<$2.ToolResult>(24, _omitFieldNames ? '' : 'toolResults',
        subBuilder: $2.ToolResult.create)
    ..aOM<$3.TokenUsage>(25, _omitFieldNames ? '' : 'usage',
        subBuilder: $3.TokenUsage.create)
    ..aOM<$4.SDKError>(26, _omitFieldNames ? '' : 'error',
        subBuilder: $4.SDKError.create)
    ..aE<FinishReason>(27, _omitFieldNames ? '' : 'finishReason',
        enumValues: FinishReason.values)
    ..aOS(28, _omitFieldNames ? '' : 'stopSequence')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LLMGenerationResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LLMGenerationResult copyWith(void Function(LLMGenerationResult) updates) =>
      super.copyWith((message) => updates(message as LLMGenerationResult))
          as LLMGenerationResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LLMGenerationResult create() => LLMGenerationResult._();
  @$core.override
  LLMGenerationResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LLMGenerationResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LLMGenerationResult>(create);
  static LLMGenerationResult? _defaultInstance;

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

  @$pb.TagNumber(5)
  $core.String get modelUsed => $_getSZ(2);
  @$pb.TagNumber(5)
  set modelUsed($core.String value) => $_setString(2, value);
  @$pb.TagNumber(5)
  $core.bool hasModelUsed() => $_has(2);
  @$pb.TagNumber(5)
  void clearModelUsed() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.double get generationTimeMs => $_getN(3);
  @$pb.TagNumber(6)
  set generationTimeMs($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(6)
  $core.bool hasGenerationTimeMs() => $_has(3);
  @$pb.TagNumber(6)
  void clearGenerationTimeMs() => $_clearField(6);

  @$pb.TagNumber(9)
  $core.String get framework => $_getSZ(4);
  @$pb.TagNumber(9)
  set framework($core.String value) => $_setString(4, value);
  @$pb.TagNumber(9)
  $core.bool hasFramework() => $_has(4);
  @$pb.TagNumber(9)
  void clearFramework() => $_clearField(9);

  @$pb.TagNumber(11)
  $core.int get thinkingTokens => $_getIZ(5);
  @$pb.TagNumber(11)
  set thinkingTokens($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(11)
  $core.bool hasThinkingTokens() => $_has(5);
  @$pb.TagNumber(11)
  void clearThinkingTokens() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.int get responseTokens => $_getIZ(6);
  @$pb.TagNumber(12)
  set responseTokens($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(12)
  $core.bool hasResponseTokens() => $_has(6);
  @$pb.TagNumber(12)
  void clearResponseTokens() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.String get jsonOutput => $_getSZ(7);
  @$pb.TagNumber(13)
  set jsonOutput($core.String value) => $_setString(7, value);
  @$pb.TagNumber(13)
  $core.bool hasJsonOutput() => $_has(7);
  @$pb.TagNumber(13)
  void clearJsonOutput() => $_clearField(13);

  /// Nothing reads performance or executed_on.
  @$pb.TagNumber(14)
  PerformanceMetrics get performance => $_getN(8);
  @$pb.TagNumber(14)
  set performance(PerformanceMetrics value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasPerformance() => $_has(8);
  @$pb.TagNumber(14)
  void clearPerformance() => $_clearField(14);
  @$pb.TagNumber(14)
  PerformanceMetrics ensurePerformance() => $_ensure(8);

  @$pb.TagNumber(15)
  ExecutionTarget get executedOn => $_getN(9);
  @$pb.TagNumber(15)
  set executedOn(ExecutionTarget value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasExecutedOn() => $_has(9);
  @$pb.TagNumber(15)
  void clearExecutedOn() => $_clearField(15);

  @$pb.TagNumber(16)
  $1.StructuredOutputValidation get structuredOutputValidation => $_getN(10);
  @$pb.TagNumber(16)
  set structuredOutputValidation($1.StructuredOutputValidation value) =>
      $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasStructuredOutputValidation() => $_has(10);
  @$pb.TagNumber(16)
  void clearStructuredOutputValidation() => $_clearField(16);
  @$pb.TagNumber(16)
  $1.StructuredOutputValidation ensureStructuredOutputValidation() =>
      $_ensure(10);

  @$pb.TagNumber(20)
  $core.int get cachedPromptTokens => $_getIZ(11);
  @$pb.TagNumber(20)
  set cachedPromptTokens($core.int value) => $_setSignedInt32(11, value);
  @$pb.TagNumber(20)
  $core.bool hasCachedPromptTokens() => $_has(11);
  @$pb.TagNumber(20)
  void clearCachedPromptTokens() => $_clearField(20);

  @$pb.TagNumber(21)
  $fixnum.Int64 get promptEvalTimeMs => $_getI64(12);
  @$pb.TagNumber(21)
  set promptEvalTimeMs($fixnum.Int64 value) => $_setInt64(12, value);
  @$pb.TagNumber(21)
  $core.bool hasPromptEvalTimeMs() => $_has(12);
  @$pb.TagNumber(21)
  void clearPromptEvalTimeMs() => $_clearField(21);

  @$pb.TagNumber(22)
  $fixnum.Int64 get decodeTimeMs => $_getI64(13);
  @$pb.TagNumber(22)
  set decodeTimeMs($fixnum.Int64 value) => $_setInt64(13, value);
  @$pb.TagNumber(22)
  $core.bool hasDecodeTimeMs() => $_has(13);
  @$pb.TagNumber(22)
  void clearDecodeTimeMs() => $_clearField(22);

  @$pb.TagNumber(23)
  $pb.PbList<$2.ToolCall> get toolCalls => $_getList(14);

  @$pb.TagNumber(24)
  $pb.PbList<$2.ToolResult> get toolResults => $_getList(15);

  @$pb.TagNumber(25)
  $3.TokenUsage get usage => $_getN(16);
  @$pb.TagNumber(25)
  set usage($3.TokenUsage value) => $_setField(25, value);
  @$pb.TagNumber(25)
  $core.bool hasUsage() => $_has(16);
  @$pb.TagNumber(25)
  void clearUsage() => $_clearField(25);
  @$pb.TagNumber(25)
  $3.TokenUsage ensureUsage() => $_ensure(16);

  @$pb.TagNumber(26)
  $4.SDKError get error => $_getN(17);
  @$pb.TagNumber(26)
  set error($4.SDKError value) => $_setField(26, value);
  @$pb.TagNumber(26)
  $core.bool hasError() => $_has(17);
  @$pb.TagNumber(26)
  void clearError() => $_clearField(26);
  @$pb.TagNumber(26)
  $4.SDKError ensureError() => $_ensure(17);

  @$pb.TagNumber(27)
  FinishReason get finishReason => $_getN(18);
  @$pb.TagNumber(27)
  set finishReason(FinishReason value) => $_setField(27, value);
  @$pb.TagNumber(27)
  $core.bool hasFinishReason() => $_has(18);
  @$pb.TagNumber(27)
  void clearFinishReason() => $_clearField(27);

  /// Which of options.stop_sequences fired. Set only when finish_reason ==
  /// FINISH_REASON_STOP_SEQUENCE. Industry: Anthropic `stop_sequence`,
  /// llama.cpp `stopping_word`.
  @$pb.TagNumber(28)
  $core.String get stopSequence => $_getSZ(19);
  @$pb.TagNumber(28)
  set stopSequence($core.String value) => $_setString(19, value);
  @$pb.TagNumber(28)
  $core.bool hasStopSequence() => $_has(19);
  @$pb.TagNumber(28)
  void clearStopSequence() => $_clearField(28);
}

class LLMConfiguration extends $pb.GeneratedMessage {
  factory LLMConfiguration({
    $core.int? contextLength,
    $core.String? modelId,
    $5.InferenceFramework? preferredFramework,
    LLMGenerationOptions? defaultOptions,
  }) {
    final result = create();
    if (contextLength != null) result.contextLength = contextLength;
    if (modelId != null) result.modelId = modelId;
    if (preferredFramework != null)
      result.preferredFramework = preferredFramework;
    if (defaultOptions != null) result.defaultOptions = defaultOptions;
    return result;
  }

  LLMConfiguration._();

  factory LLMConfiguration.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LLMConfiguration.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LLMConfiguration',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'contextLength')
    ..aOS(6, _omitFieldNames ? '' : 'modelId')
    ..aE<$5.InferenceFramework>(7, _omitFieldNames ? '' : 'preferredFramework',
        enumValues: $5.InferenceFramework.values)
    ..aOM<LLMGenerationOptions>(8, _omitFieldNames ? '' : 'defaultOptions',
        subBuilder: LLMGenerationOptions.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LLMConfiguration clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LLMConfiguration copyWith(void Function(LLMConfiguration) updates) =>
      super.copyWith((message) => updates(message as LLMConfiguration))
          as LLMConfiguration;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LLMConfiguration create() => LLMConfiguration._();
  @$core.override
  LLMConfiguration createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LLMConfiguration getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LLMConfiguration>(create);
  static LLMConfiguration? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get contextLength => $_getIZ(0);
  @$pb.TagNumber(1)
  set contextLength($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasContextLength() => $_has(0);
  @$pb.TagNumber(1)
  void clearContextLength() => $_clearField(1);

  @$pb.TagNumber(6)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(6)
  set modelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(6)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(6)
  void clearModelId() => $_clearField(6);

  @$pb.TagNumber(7)
  $5.InferenceFramework get preferredFramework => $_getN(2);
  @$pb.TagNumber(7)
  set preferredFramework($5.InferenceFramework value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasPreferredFramework() => $_has(2);
  @$pb.TagNumber(7)
  void clearPreferredFramework() => $_clearField(7);

  /// Applied when a per-call LLMGenerationOptions leaves a field unset.
  @$pb.TagNumber(8)
  LLMGenerationOptions get defaultOptions => $_getN(3);
  @$pb.TagNumber(8)
  set defaultOptions(LLMGenerationOptions value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasDefaultOptions() => $_has(3);
  @$pb.TagNumber(8)
  void clearDefaultOptions() => $_clearField(8);
  @$pb.TagNumber(8)
  LLMGenerationOptions ensureDefaultOptions() => $_ensure(3);
}

class StreamToken extends $pb.GeneratedMessage {
  factory StreamToken({
    $core.String? text,
    $fixnum.Int64? timestampMs,
    $core.int? index,
  }) {
    final result = create();
    if (text != null) result.text = text;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (index != null) result.index = index;
    return result;
  }

  StreamToken._();

  factory StreamToken.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StreamToken.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StreamToken',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aInt64(2, _omitFieldNames ? '' : 'timestampMs')
    ..aI(3, _omitFieldNames ? '' : 'index')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StreamToken clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StreamToken copyWith(void Function(StreamToken) updates) =>
      super.copyWith((message) => updates(message as StreamToken))
          as StreamToken;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StreamToken create() => StreamToken._();
  @$core.override
  StreamToken createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StreamToken getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StreamToken>(create);
  static StreamToken? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampMs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestampMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampMs() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get index => $_getIZ(2);
  @$pb.TagNumber(3)
  set index($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIndex() => $_has(2);
  @$pb.TagNumber(3)
  void clearIndex() => $_clearField(3);
}

/// Referenced only by LLMGenerationResult.performance, which no SDK reads.
class PerformanceMetrics extends $pb.GeneratedMessage {
  factory PerformanceMetrics({
    $fixnum.Int64? latencyMs,
    $fixnum.Int64? memoryBytes,
    $3.TokenUsage? usage,
  }) {
    final result = create();
    if (latencyMs != null) result.latencyMs = latencyMs;
    if (memoryBytes != null) result.memoryBytes = memoryBytes;
    if (usage != null) result.usage = usage;
    return result;
  }

  PerformanceMetrics._();

  factory PerformanceMetrics.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PerformanceMetrics.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PerformanceMetrics',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'latencyMs')
    ..aInt64(2, _omitFieldNames ? '' : 'memoryBytes')
    ..aOM<$3.TokenUsage>(6, _omitFieldNames ? '' : 'usage',
        subBuilder: $3.TokenUsage.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PerformanceMetrics clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PerformanceMetrics copyWith(void Function(PerformanceMetrics) updates) =>
      super.copyWith((message) => updates(message as PerformanceMetrics))
          as PerformanceMetrics;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PerformanceMetrics create() => PerformanceMetrics._();
  @$core.override
  PerformanceMetrics createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PerformanceMetrics getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PerformanceMetrics>(create);
  static PerformanceMetrics? _defaultInstance;

  @$pb.TagNumber(1)
  $fixnum.Int64 get latencyMs => $_getI64(0);
  @$pb.TagNumber(1)
  set latencyMs($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLatencyMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearLatencyMs() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get memoryBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set memoryBytes($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMemoryBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearMemoryBytes() => $_clearField(2);

  @$pb.TagNumber(6)
  $3.TokenUsage get usage => $_getN(2);
  @$pb.TagNumber(6)
  set usage($3.TokenUsage value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasUsage() => $_has(2);
  @$pb.TagNumber(6)
  void clearUsage() => $_clearField(6);
  @$pb.TagNumber(6)
  $3.TokenUsage ensureUsage() => $_ensure(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
