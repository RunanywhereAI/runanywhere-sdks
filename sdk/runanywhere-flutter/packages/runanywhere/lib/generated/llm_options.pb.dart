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

import 'llm_options.pbenum.dart';
import 'model_types.pbenum.dart' as $3;
import 'structured_output.pb.dart' as $1;
import 'thinking_tag_pattern.pb.dart' as $0;
import 'tool_calling.pb.dart' as $2;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'llm_options.pbenum.dart';

/// ---------------------------------------------------------------------------
/// Options for a single text generation invocation.
///
/// Field names match Swift LLMGenerationOptions exactly; consumers may treat
/// proto3 scalar defaults as "unset" (Swift handled this via Optionals — proto
/// represents optional reference fields explicitly via `optional` keyword).
/// ---------------------------------------------------------------------------
class LLMGenerationOptions extends $pb.GeneratedMessage {
  factory LLMGenerationOptions({
    $core.int? maxTokens,
    $core.double? temperature,
    $core.double? topP,
    $core.int? topK,
    $core.double? repetitionPenalty,
    $core.Iterable<$core.String>? stopSequences,
    $core.bool? streamingEnabled,
    $3.InferenceFramework? preferredFramework,
    $core.String? systemPrompt,
    $core.String? jsonSchema,
    $0.ThinkingTagPattern? thinkingPattern,
    ExecutionTarget? executionTarget,
    $1.StructuredOutputOptions? structuredOutput,
    $core.bool? enableRealTimeTracking,
    $fixnum.Int64? seed,
    $core.double? frequencyPenalty,
    $core.double? presencePenalty,
    $core.int? repeatLastN,
    $core.double? minP,
    $core.String? grammar,
    $core.String? responseFormat,
    $core.bool? echoPrompt,
    $core.int? nThreads,
    $2.ToolCallingOptions? toolCalling,
    $core.bool? disableThinking,
  }) {
    final result = create();
    if (maxTokens != null) result.maxTokens = maxTokens;
    if (temperature != null) result.temperature = temperature;
    if (topP != null) result.topP = topP;
    if (topK != null) result.topK = topK;
    if (repetitionPenalty != null) result.repetitionPenalty = repetitionPenalty;
    if (stopSequences != null) result.stopSequences.addAll(stopSequences);
    if (streamingEnabled != null) result.streamingEnabled = streamingEnabled;
    if (preferredFramework != null)
      result.preferredFramework = preferredFramework;
    if (systemPrompt != null) result.systemPrompt = systemPrompt;
    if (jsonSchema != null) result.jsonSchema = jsonSchema;
    if (thinkingPattern != null) result.thinkingPattern = thinkingPattern;
    if (executionTarget != null) result.executionTarget = executionTarget;
    if (structuredOutput != null) result.structuredOutput = structuredOutput;
    if (enableRealTimeTracking != null)
      result.enableRealTimeTracking = enableRealTimeTracking;
    if (seed != null) result.seed = seed;
    if (frequencyPenalty != null) result.frequencyPenalty = frequencyPenalty;
    if (presencePenalty != null) result.presencePenalty = presencePenalty;
    if (repeatLastN != null) result.repeatLastN = repeatLastN;
    if (minP != null) result.minP = minP;
    if (grammar != null) result.grammar = grammar;
    if (responseFormat != null) result.responseFormat = responseFormat;
    if (echoPrompt != null) result.echoPrompt = echoPrompt;
    if (nThreads != null) result.nThreads = nThreads;
    if (toolCalling != null) result.toolCalling = toolCalling;
    if (disableThinking != null) result.disableThinking = disableThinking;
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
    ..aI(1, _omitFieldNames ? '' : 'maxTokens')
    ..aD(2, _omitFieldNames ? '' : 'temperature', fieldType: $pb.PbFieldType.OF)
    ..aD(3, _omitFieldNames ? '' : 'topP', fieldType: $pb.PbFieldType.OF)
    ..aI(4, _omitFieldNames ? '' : 'topK')
    ..aD(5, _omitFieldNames ? '' : 'repetitionPenalty',
        fieldType: $pb.PbFieldType.OF)
    ..pPS(6, _omitFieldNames ? '' : 'stopSequences')
    ..aOB(7, _omitFieldNames ? '' : 'streamingEnabled')
    ..aE<$3.InferenceFramework>(8, _omitFieldNames ? '' : 'preferredFramework',
        enumValues: $3.InferenceFramework.values)
    ..aOS(9, _omitFieldNames ? '' : 'systemPrompt')
    ..aOS(10, _omitFieldNames ? '' : 'jsonSchema')
    ..aOM<$0.ThinkingTagPattern>(11, _omitFieldNames ? '' : 'thinkingPattern',
        subBuilder: $0.ThinkingTagPattern.create)
    ..aE<ExecutionTarget>(12, _omitFieldNames ? '' : 'executionTarget',
        enumValues: ExecutionTarget.values)
    ..aOM<$1.StructuredOutputOptions>(
        13, _omitFieldNames ? '' : 'structuredOutput',
        subBuilder: $1.StructuredOutputOptions.create)
    ..aOB(14, _omitFieldNames ? '' : 'enableRealTimeTracking')
    ..aInt64(15, _omitFieldNames ? '' : 'seed')
    ..aD(16, _omitFieldNames ? '' : 'frequencyPenalty',
        fieldType: $pb.PbFieldType.OF)
    ..aD(17, _omitFieldNames ? '' : 'presencePenalty',
        fieldType: $pb.PbFieldType.OF)
    ..aI(18, _omitFieldNames ? '' : 'repeatLastN')
    ..aD(19, _omitFieldNames ? '' : 'minP', fieldType: $pb.PbFieldType.OF)
    ..aOS(20, _omitFieldNames ? '' : 'grammar')
    ..aOS(21, _omitFieldNames ? '' : 'responseFormat')
    ..aOB(22, _omitFieldNames ? '' : 'echoPrompt')
    ..aI(23, _omitFieldNames ? '' : 'nThreads')
    ..aOM<$2.ToolCallingOptions>(24, _omitFieldNames ? '' : 'toolCalling',
        subBuilder: $2.ToolCallingOptions.create)
    ..aOB(25, _omitFieldNames ? '' : 'disableThinking')
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

  /// Maximum number of tokens to generate. 0 (default) = unset → engine
  /// default (typically 100).
  @$pb.TagNumber(1)
  $core.int get maxTokens => $_getIZ(0);
  @$pb.TagNumber(1)
  set maxTokens($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasMaxTokens() => $_has(0);
  @$pb.TagNumber(1)
  void clearMaxTokens() => $_clearField(1);

  /// Sampling temperature (0.0 - 2.0). 0.0 = greedy decoding.
  @$pb.TagNumber(2)
  $core.double get temperature => $_getN(1);
  @$pb.TagNumber(2)
  set temperature($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTemperature() => $_has(1);
  @$pb.TagNumber(2)
  void clearTemperature() => $_clearField(2);

  /// Nucleus sampling (top-p). 1.0 = no nucleus truncation.
  @$pb.TagNumber(3)
  $core.double get topP => $_getN(2);
  @$pb.TagNumber(3)
  set topP($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTopP() => $_has(2);
  @$pb.TagNumber(3)
  void clearTopP() => $_clearField(3);

  /// Top-K sampling (Kotlin/Dart/RN field). 0 = disabled.
  @$pb.TagNumber(4)
  $core.int get topK => $_getIZ(3);
  @$pb.TagNumber(4)
  set topK($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTopK() => $_has(3);
  @$pb.TagNumber(4)
  void clearTopK() => $_clearField(4);

  /// Repetition penalty (Kotlin/Dart/RN field). 1.0 = no penalty.
  @$pb.TagNumber(5)
  $core.double get repetitionPenalty => $_getN(4);
  @$pb.TagNumber(5)
  set repetitionPenalty($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRepetitionPenalty() => $_has(4);
  @$pb.TagNumber(5)
  void clearRepetitionPenalty() => $_clearField(5);

  /// Stop sequences. Generation halts when any of these strings appears in
  /// the output stream.
  @$pb.TagNumber(6)
  $pb.PbList<$core.String> get stopSequences => $_getList(5);

  /// Whether to stream tokens vs return result at end (Swift field).
  @$pb.TagNumber(7)
  $core.bool get streamingEnabled => $_getBF(6);
  @$pb.TagNumber(7)
  set streamingEnabled($core.bool value) => $_setBool(6, value);
  @$pb.TagNumber(7)
  $core.bool hasStreamingEnabled() => $_has(6);
  @$pb.TagNumber(7)
  void clearStreamingEnabled() => $_clearField(7);

  /// Preferred inference framework. UNSPECIFIED = pick automatically.
  @$pb.TagNumber(8)
  $3.InferenceFramework get preferredFramework => $_getN(7);
  @$pb.TagNumber(8)
  set preferredFramework($3.InferenceFramework value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasPreferredFramework() => $_has(7);
  @$pb.TagNumber(8)
  void clearPreferredFramework() => $_clearField(8);

  /// System prompt to define AI behavior and formatting rules.
  @$pb.TagNumber(9)
  $core.String get systemPrompt => $_getSZ(8);
  @$pb.TagNumber(9)
  set systemPrompt($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasSystemPrompt() => $_has(8);
  @$pb.TagNumber(9)
  void clearSystemPrompt() => $_clearField(9);

  /// Optional structured-output mode (JSON schema). Engine returns text
  /// that conforms to this schema. Swift wraps this in a StructuredOutputConfig
  /// struct with the Generatable.Type — proto carries just the schema string.
  @$pb.TagNumber(10)
  $core.String get jsonSchema => $_getSZ(9);
  @$pb.TagNumber(10)
  set jsonSchema($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasJsonSchema() => $_has(9);
  @$pb.TagNumber(10)
  void clearJsonSchema() => $_clearField(10);

  /// Optional thinking-tag pattern for extracting reasoning content from
  /// models like Qwen3 / LFM2 that emit <think>...</think> blocks.
  @$pb.TagNumber(11)
  $0.ThinkingTagPattern get thinkingPattern => $_getN(10);
  @$pb.TagNumber(11)
  set thinkingPattern($0.ThinkingTagPattern value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasThinkingPattern() => $_has(10);
  @$pb.TagNumber(11)
  void clearThinkingPattern() => $_clearField(11);
  @$pb.TagNumber(11)
  $0.ThinkingTagPattern ensureThinkingPattern() => $_ensure(10);

  /// Routing hint: where this generation should run (on-device, cloud, or
  /// SDK-decided AUTO). Mirrors the Web SDK ExecutionTarget knob.
  @$pb.TagNumber(12)
  ExecutionTarget get executionTarget => $_getN(11);
  @$pb.TagNumber(12)
  set executionTarget(ExecutionTarget value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasExecutionTarget() => $_has(11);
  @$pb.TagNumber(12)
  void clearExecutionTarget() => $_clearField(12);

  /// Optional structured-output configuration. Detailed message lives in
  /// structured_output.proto so the schema/format details aren't duplicated
  /// here. When set, supersedes the simpler `json_schema` string above.
  @$pb.TagNumber(13)
  $1.StructuredOutputOptions get structuredOutput => $_getN(12);
  @$pb.TagNumber(13)
  set structuredOutput($1.StructuredOutputOptions value) =>
      $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasStructuredOutput() => $_has(12);
  @$pb.TagNumber(13)
  void clearStructuredOutput() => $_clearField(13);
  @$pb.TagNumber(13)
  $1.StructuredOutputOptions ensureStructuredOutput() => $_ensure(12);

  /// Enable per-token/cost dashboard tracking for SDKs that surface live
  /// generation telemetry. No-op for backends without a telemetry sink.
  @$pb.TagNumber(14)
  $core.bool get enableRealTimeTracking => $_getBF(13);
  @$pb.TagNumber(14)
  set enableRealTimeTracking($core.bool value) => $_setBool(13, value);
  @$pb.TagNumber(14)
  $core.bool hasEnableRealTimeTracking() => $_has(13);
  @$pb.TagNumber(14)
  void clearEnableRealTimeTracking() => $_clearField(14);

  /// Deterministic sampling seed. 0 = backend/default random seed.
  @$pb.TagNumber(15)
  $fixnum.Int64 get seed => $_getI64(14);
  @$pb.TagNumber(15)
  set seed($fixnum.Int64 value) => $_setInt64(14, value);
  @$pb.TagNumber(15)
  $core.bool hasSeed() => $_has(14);
  @$pb.TagNumber(15)
  void clearSeed() => $_clearField(15);

  /// OpenAI-compatible sampling penalties. 0.0 = disabled.
  @$pb.TagNumber(16)
  $core.double get frequencyPenalty => $_getN(15);
  @$pb.TagNumber(16)
  set frequencyPenalty($core.double value) => $_setFloat(15, value);
  @$pb.TagNumber(16)
  $core.bool hasFrequencyPenalty() => $_has(15);
  @$pb.TagNumber(16)
  void clearFrequencyPenalty() => $_clearField(16);

  @$pb.TagNumber(17)
  $core.double get presencePenalty => $_getN(16);
  @$pb.TagNumber(17)
  set presencePenalty($core.double value) => $_setFloat(16, value);
  @$pb.TagNumber(17)
  $core.bool hasPresencePenalty() => $_has(16);
  @$pb.TagNumber(17)
  void clearPresencePenalty() => $_clearField(17);

  /// Repeat-penalty lookback window. 0 = backend default.
  @$pb.TagNumber(18)
  $core.int get repeatLastN => $_getIZ(17);
  @$pb.TagNumber(18)
  set repeatLastN($core.int value) => $_setSignedInt32(17, value);
  @$pb.TagNumber(18)
  $core.bool hasRepeatLastN() => $_has(17);
  @$pb.TagNumber(18)
  void clearRepeatLastN() => $_clearField(18);

  /// Minimum probability sampling. 0.0 = disabled.
  @$pb.TagNumber(19)
  $core.double get minP => $_getN(18);
  @$pb.TagNumber(19)
  set minP($core.double value) => $_setFloat(18, value);
  @$pb.TagNumber(19)
  $core.bool hasMinP() => $_has(18);
  @$pb.TagNumber(19)
  void clearMinP() => $_clearField(19);

  /// Grammar or constrained-decoding rule text (GBNF/regex/backend-specific).
  @$pb.TagNumber(20)
  $core.String get grammar => $_getSZ(19);
  @$pb.TagNumber(20)
  set grammar($core.String value) => $_setString(19, value);
  @$pb.TagNumber(20)
  $core.bool hasGrammar() => $_has(19);
  @$pb.TagNumber(20)
  void clearGrammar() => $_clearField(20);

  /// Caller-visible format hint: "text", "json_object", "json_schema", etc.
  @$pb.TagNumber(21)
  $core.String get responseFormat => $_getSZ(20);
  @$pb.TagNumber(21)
  set responseFormat($core.String value) => $_setString(20, value);
  @$pb.TagNumber(21)
  $core.bool hasResponseFormat() => $_has(20);
  @$pb.TagNumber(21)
  void clearResponseFormat() => $_clearField(21);

  /// Include prompt text in the result/stream when the backend supports echo.
  @$pb.TagNumber(22)
  $core.bool get echoPrompt => $_getBF(21);
  @$pb.TagNumber(22)
  set echoPrompt($core.bool value) => $_setBool(21, value);
  @$pb.TagNumber(22)
  $core.bool hasEchoPrompt() => $_has(21);
  @$pb.TagNumber(22)
  void clearEchoPrompt() => $_clearField(22);

  /// Per-request backend thread hint. 0 = backend/runtime default.
  @$pb.TagNumber(23)
  $core.int get nThreads => $_getIZ(22);
  @$pb.TagNumber(23)
  set nThreads($core.int value) => $_setSignedInt32(22, value);
  @$pb.TagNumber(23)
  $core.bool hasNThreads() => $_has(22);
  @$pb.TagNumber(23)
  void clearNThreads() => $_clearField(23);

  /// Tool-calling contract for this generation. The SDK owns executor
  /// functions; proto carries only definitions and parser options.
  @$pb.TagNumber(24)
  $2.ToolCallingOptions get toolCalling => $_getN(23);
  @$pb.TagNumber(24)
  set toolCalling($2.ToolCallingOptions value) => $_setField(24, value);
  @$pb.TagNumber(24)
  $core.bool hasToolCalling() => $_has(23);
  @$pb.TagNumber(24)
  void clearToolCalling() => $_clearField(24);
  @$pb.TagNumber(24)
  $2.ToolCallingOptions ensureToolCalling() => $_ensure(23);

  /// When true, suppress the model's thinking/reasoning phase for this
  /// generation (e.g. Qwen3 / LFM2 <think> blocks). Commons applies the
  /// model's no-think directive at the prompt level, so no app prepends
  /// "/no_think" by hand. Default false = the model's normal thinking
  /// behavior.
  @$pb.TagNumber(25)
  $core.bool get disableThinking => $_getBF(24);
  @$pb.TagNumber(25)
  set disableThinking($core.bool value) => $_setBool(24, value);
  @$pb.TagNumber(25)
  $core.bool hasDisableThinking() => $_has(24);
  @$pb.TagNumber(25)
  void clearDisableThinking() => $_clearField(25);
}

/// ---------------------------------------------------------------------------
/// Result of a single text generation shared by every SDK.
/// ---------------------------------------------------------------------------
class LLMGenerationResult extends $pb.GeneratedMessage {
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
    $1.StructuredOutputValidation? structuredOutputValidation,
    $core.int? totalTokens,
    $core.String? errorMessage,
    $core.int? errorCode,
    $core.int? cachedPromptTokens,
    $fixnum.Int64? promptEvalTimeMs,
    $fixnum.Int64? decodeTimeMs,
    $core.Iterable<$2.ToolCall>? toolCalls,
    $core.Iterable<$2.ToolResult>? toolResults,
  }) {
    final result = create();
    if (text != null) result.text = text;
    if (thinkingContent != null) result.thinkingContent = thinkingContent;
    if (inputTokens != null) result.inputTokens = inputTokens;
    if (tokensGenerated != null) result.tokensGenerated = tokensGenerated;
    if (modelUsed != null) result.modelUsed = modelUsed;
    if (generationTimeMs != null) result.generationTimeMs = generationTimeMs;
    if (ttftMs != null) result.ttftMs = ttftMs;
    if (tokensPerSecond != null) result.tokensPerSecond = tokensPerSecond;
    if (framework != null) result.framework = framework;
    if (finishReason != null) result.finishReason = finishReason;
    if (thinkingTokens != null) result.thinkingTokens = thinkingTokens;
    if (responseTokens != null) result.responseTokens = responseTokens;
    if (jsonOutput != null) result.jsonOutput = jsonOutput;
    if (performance != null) result.performance = performance;
    if (executedOn != null) result.executedOn = executedOn;
    if (structuredOutputValidation != null)
      result.structuredOutputValidation = structuredOutputValidation;
    if (totalTokens != null) result.totalTokens = totalTokens;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    if (cachedPromptTokens != null)
      result.cachedPromptTokens = cachedPromptTokens;
    if (promptEvalTimeMs != null) result.promptEvalTimeMs = promptEvalTimeMs;
    if (decodeTimeMs != null) result.decodeTimeMs = decodeTimeMs;
    if (toolCalls != null) result.toolCalls.addAll(toolCalls);
    if (toolResults != null) result.toolResults.addAll(toolResults);
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
    ..aI(3, _omitFieldNames ? '' : 'inputTokens')
    ..aI(4, _omitFieldNames ? '' : 'tokensGenerated')
    ..aOS(5, _omitFieldNames ? '' : 'modelUsed')
    ..aD(6, _omitFieldNames ? '' : 'generationTimeMs')
    ..aD(7, _omitFieldNames ? '' : 'ttftMs')
    ..aD(8, _omitFieldNames ? '' : 'tokensPerSecond')
    ..aOS(9, _omitFieldNames ? '' : 'framework')
    ..aOS(10, _omitFieldNames ? '' : 'finishReason')
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
    ..aI(17, _omitFieldNames ? '' : 'totalTokens')
    ..aOS(18, _omitFieldNames ? '' : 'errorMessage')
    ..aI(19, _omitFieldNames ? '' : 'errorCode')
    ..aI(20, _omitFieldNames ? '' : 'cachedPromptTokens')
    ..aInt64(21, _omitFieldNames ? '' : 'promptEvalTimeMs')
    ..aInt64(22, _omitFieldNames ? '' : 'decodeTimeMs')
    ..pPM<$2.ToolCall>(23, _omitFieldNames ? '' : 'toolCalls',
        subBuilder: $2.ToolCall.create)
    ..pPM<$2.ToolResult>(24, _omitFieldNames ? '' : 'toolResults',
        subBuilder: $2.ToolResult.create)
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

  /// Generated text (with thinking content removed if extracted).
  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  /// Optional thinking/reasoning content extracted from the response.
  @$pb.TagNumber(2)
  $core.String get thinkingContent => $_getSZ(1);
  @$pb.TagNumber(2)
  set thinkingContent($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasThinkingContent() => $_has(1);
  @$pb.TagNumber(2)
  void clearThinkingContent() => $_clearField(2);

  /// Number of input/prompt tokens (from tokenizer).
  @$pb.TagNumber(3)
  $core.int get inputTokens => $_getIZ(2);
  @$pb.TagNumber(3)
  set inputTokens($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasInputTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearInputTokens() => $_clearField(3);

  /// Number of tokens used (output / completion tokens).
  @$pb.TagNumber(4)
  $core.int get tokensGenerated => $_getIZ(3);
  @$pb.TagNumber(4)
  set tokensGenerated($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTokensGenerated() => $_has(3);
  @$pb.TagNumber(4)
  void clearTokensGenerated() => $_clearField(4);

  /// Model used for generation.
  @$pb.TagNumber(5)
  $core.String get modelUsed => $_getSZ(4);
  @$pb.TagNumber(5)
  set modelUsed($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasModelUsed() => $_has(4);
  @$pb.TagNumber(5)
  void clearModelUsed() => $_clearField(5);

  /// Total wall-clock generation time in milliseconds.
  @$pb.TagNumber(6)
  $core.double get generationTimeMs => $_getN(5);
  @$pb.TagNumber(6)
  set generationTimeMs($core.double value) => $_setDouble(5, value);
  @$pb.TagNumber(6)
  $core.bool hasGenerationTimeMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearGenerationTimeMs() => $_clearField(6);

  /// Time-to-first-token in milliseconds (only set in streaming mode).
  @$pb.TagNumber(7)
  $core.double get ttftMs => $_getN(6);
  @$pb.TagNumber(7)
  set ttftMs($core.double value) => $_setDouble(6, value);
  @$pb.TagNumber(7)
  $core.bool hasTtftMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearTtftMs() => $_clearField(7);

  /// Tokens-per-second throughput.
  @$pb.TagNumber(8)
  $core.double get tokensPerSecond => $_getN(7);
  @$pb.TagNumber(8)
  set tokensPerSecond($core.double value) => $_setDouble(7, value);
  @$pb.TagNumber(8)
  $core.bool hasTokensPerSecond() => $_has(7);
  @$pb.TagNumber(8)
  void clearTokensPerSecond() => $_clearField(8);

  /// Framework that actually performed the generation. Optional because
  /// some C ABI paths don't surface it.
  @$pb.TagNumber(9)
  $core.String get framework => $_getSZ(8);
  @$pb.TagNumber(9)
  set framework($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasFramework() => $_has(8);
  @$pb.TagNumber(9)
  void clearFramework() => $_clearField(9);

  /// Reason the generation stopped: "stop", "length", "cancelled", "error".
  /// Empty = unset.
  @$pb.TagNumber(10)
  $core.String get finishReason => $_getSZ(9);
  @$pb.TagNumber(10)
  set finishReason($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasFinishReason() => $_has(9);
  @$pb.TagNumber(10)
  void clearFinishReason() => $_clearField(10);

  /// Number of tokens used for thinking/reasoning. 0 = not applicable.
  @$pb.TagNumber(11)
  $core.int get thinkingTokens => $_getIZ(10);
  @$pb.TagNumber(11)
  set thinkingTokens($core.int value) => $_setSignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasThinkingTokens() => $_has(10);
  @$pb.TagNumber(11)
  void clearThinkingTokens() => $_clearField(11);

  /// Number of tokens in the actual response content (vs thinking).
  @$pb.TagNumber(12)
  $core.int get responseTokens => $_getIZ(11);
  @$pb.TagNumber(12)
  set responseTokens($core.int value) => $_setSignedInt32(11, value);
  @$pb.TagNumber(12)
  $core.bool hasResponseTokens() => $_has(11);
  @$pb.TagNumber(12)
  void clearResponseTokens() => $_clearField(12);

  /// Optional JSON output (when structured-output mode was requested).
  /// Empty = no structured output.
  @$pb.TagNumber(13)
  $core.String get jsonOutput => $_getSZ(12);
  @$pb.TagNumber(13)
  set jsonOutput($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasJsonOutput() => $_has(12);
  @$pb.TagNumber(13)
  void clearJsonOutput() => $_clearField(13);

  /// Optional aggregated performance metrics. Web SDK surfaces this as a
  /// separate object alongside the result; consumers may ignore it if they
  /// already use the per-field timings above.
  @$pb.TagNumber(14)
  PerformanceMetrics get performance => $_getN(13);
  @$pb.TagNumber(14)
  set performance(PerformanceMetrics value) => $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasPerformance() => $_has(13);
  @$pb.TagNumber(14)
  void clearPerformance() => $_clearField(14);
  @$pb.TagNumber(14)
  PerformanceMetrics ensurePerformance() => $_ensure(13);

  /// Where the generation actually ran (on-device, cloud, etc.). Useful
  /// when execution_target was AUTO and the SDK picked the route.
  @$pb.TagNumber(15)
  ExecutionTarget get executedOn => $_getN(14);
  @$pb.TagNumber(15)
  set executedOn(ExecutionTarget value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasExecutedOn() => $_has(14);
  @$pb.TagNumber(15)
  void clearExecutedOn() => $_clearField(15);

  /// Structured-output validation details, when a structured-output request
  /// was used. Mirrors the Swift/RN validation payload.
  @$pb.TagNumber(16)
  $1.StructuredOutputValidation get structuredOutputValidation => $_getN(15);
  @$pb.TagNumber(16)
  set structuredOutputValidation($1.StructuredOutputValidation value) =>
      $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasStructuredOutputValidation() => $_has(15);
  @$pb.TagNumber(16)
  void clearStructuredOutputValidation() => $_clearField(16);
  @$pb.TagNumber(16)
  $1.StructuredOutputValidation ensureStructuredOutputValidation() =>
      $_ensure(15);

  /// Total tokens consumed (prompt + completion). Some C ABI paths expose
  /// this directly; consumers may also compute it from the per-field counts.
  @$pb.TagNumber(17)
  $core.int get totalTokens => $_getIZ(16);
  @$pb.TagNumber(17)
  set totalTokens($core.int value) => $_setSignedInt32(16, value);
  @$pb.TagNumber(17)
  $core.bool hasTotalTokens() => $_has(16);
  @$pb.TagNumber(17)
  void clearTotalTokens() => $_clearField(17);

  /// Backend error text for result-producing APIs that return a terminal
  /// result envelope instead of throwing through the host language.
  @$pb.TagNumber(18)
  $core.String get errorMessage => $_getSZ(17);
  @$pb.TagNumber(18)
  set errorMessage($core.String value) => $_setString(17, value);
  @$pb.TagNumber(18)
  $core.bool hasErrorMessage() => $_has(17);
  @$pb.TagNumber(18)
  void clearErrorMessage() => $_clearField(18);

  /// Numeric backend status code when a result envelope carries an error.
  @$pb.TagNumber(19)
  $core.int get errorCode => $_getIZ(18);
  @$pb.TagNumber(19)
  set errorCode($core.int value) => $_setSignedInt32(18, value);
  @$pb.TagNumber(19)
  $core.bool hasErrorCode() => $_has(18);
  @$pb.TagNumber(19)
  void clearErrorCode() => $_clearField(19);

  /// Prompt/cache accounting surfaced by llama.cpp/CoreML-style backends.
  @$pb.TagNumber(20)
  $core.int get cachedPromptTokens => $_getIZ(19);
  @$pb.TagNumber(20)
  set cachedPromptTokens($core.int value) => $_setSignedInt32(19, value);
  @$pb.TagNumber(20)
  $core.bool hasCachedPromptTokens() => $_has(19);
  @$pb.TagNumber(20)
  void clearCachedPromptTokens() => $_clearField(20);

  @$pb.TagNumber(21)
  $fixnum.Int64 get promptEvalTimeMs => $_getI64(20);
  @$pb.TagNumber(21)
  set promptEvalTimeMs($fixnum.Int64 value) => $_setInt64(20, value);
  @$pb.TagNumber(21)
  $core.bool hasPromptEvalTimeMs() => $_has(20);
  @$pb.TagNumber(21)
  void clearPromptEvalTimeMs() => $_clearField(21);

  @$pb.TagNumber(22)
  $fixnum.Int64 get decodeTimeMs => $_getI64(21);
  @$pb.TagNumber(22)
  set decodeTimeMs($fixnum.Int64 value) => $_setInt64(21, value);
  @$pb.TagNumber(22)
  $core.bool hasDecodeTimeMs() => $_has(21);
  @$pb.TagNumber(22)
  void clearDecodeTimeMs() => $_clearField(22);

  /// Tool calls parsed from the final assistant response, if any.
  @$pb.TagNumber(23)
  $pb.PbList<$2.ToolCall> get toolCalls => $_getList(22);

  /// Tool results incorporated during auto-execute loops.
  @$pb.TagNumber(24)
  $pb.PbList<$2.ToolResult> get toolResults => $_getList(23);
}

/// Request envelope for one non-streaming LLM generation call. This is the
/// proto-owned DTO SDKs can use instead of parallel prompt/options tuples.
class LLMGenerationRequest extends $pb.GeneratedMessage {
  factory LLMGenerationRequest({
    $core.String? requestId,
    $core.String? modelId,
    $core.String? prompt,
    LLMGenerationOptions? options,
    $core.Iterable<$core.String>? contextChunks,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? metadata,
    $core.String? conversationId,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (modelId != null) result.modelId = modelId;
    if (prompt != null) result.prompt = prompt;
    if (options != null) result.options = options;
    if (contextChunks != null) result.contextChunks.addAll(contextChunks);
    if (metadata != null) result.metadata.addEntries(metadata);
    if (conversationId != null) result.conversationId = conversationId;
    return result;
  }

  LLMGenerationRequest._();

  factory LLMGenerationRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LLMGenerationRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LLMGenerationRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..aOS(3, _omitFieldNames ? '' : 'prompt')
    ..aOM<LLMGenerationOptions>(4, _omitFieldNames ? '' : 'options',
        subBuilder: LLMGenerationOptions.create)
    ..pPS(5, _omitFieldNames ? '' : 'contextChunks')
    ..m<$core.String, $core.String>(6, _omitFieldNames ? '' : 'metadata',
        entryClassName: 'LLMGenerationRequest.MetadataEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..aOS(7, _omitFieldNames ? '' : 'conversationId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LLMGenerationRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LLMGenerationRequest copyWith(void Function(LLMGenerationRequest) updates) =>
      super.copyWith((message) => updates(message as LLMGenerationRequest))
          as LLMGenerationRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LLMGenerationRequest create() => LLMGenerationRequest._();
  @$core.override
  LLMGenerationRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LLMGenerationRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LLMGenerationRequest>(create);
  static LLMGenerationRequest? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get prompt => $_getSZ(2);
  @$pb.TagNumber(3)
  set prompt($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPrompt() => $_has(2);
  @$pb.TagNumber(3)
  void clearPrompt() => $_clearField(3);

  @$pb.TagNumber(4)
  LLMGenerationOptions get options => $_getN(3);
  @$pb.TagNumber(4)
  set options(LLMGenerationOptions value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasOptions() => $_has(3);
  @$pb.TagNumber(4)
  void clearOptions() => $_clearField(4);
  @$pb.TagNumber(4)
  LLMGenerationOptions ensureOptions() => $_ensure(3);

  @$pb.TagNumber(5)
  $pb.PbList<$core.String> get contextChunks => $_getList(4);

  @$pb.TagNumber(6)
  $pb.PbMap<$core.String, $core.String> get metadata => $_getMap(5);

  @$pb.TagNumber(7)
  $core.String get conversationId => $_getSZ(6);
  @$pb.TagNumber(7)
  set conversationId($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasConversationId() => $_has(6);
  @$pb.TagNumber(7)
  void clearConversationId() => $_clearField(7);
}

class LLMGenerationStatus extends $pb.GeneratedMessage {
  factory LLMGenerationStatus({
    $core.String? requestId,
    LLMGenerationState? state,
    $core.int? promptTokensProcessed,
    $core.int? completionTokensGenerated,
    $core.double? progress,
    $fixnum.Int64? elapsedMs,
    $core.String? message,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final result = create();
    if (requestId != null) result.requestId = requestId;
    if (state != null) result.state = state;
    if (promptTokensProcessed != null)
      result.promptTokensProcessed = promptTokensProcessed;
    if (completionTokensGenerated != null)
      result.completionTokensGenerated = completionTokensGenerated;
    if (progress != null) result.progress = progress;
    if (elapsedMs != null) result.elapsedMs = elapsedMs;
    if (message != null) result.message = message;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    return result;
  }

  LLMGenerationStatus._();

  factory LLMGenerationStatus.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory LLMGenerationStatus.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'LLMGenerationStatus',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'requestId')
    ..aE<LLMGenerationState>(2, _omitFieldNames ? '' : 'state',
        enumValues: LLMGenerationState.values)
    ..aI(3, _omitFieldNames ? '' : 'promptTokensProcessed')
    ..aI(4, _omitFieldNames ? '' : 'completionTokensGenerated')
    ..aD(5, _omitFieldNames ? '' : 'progress', fieldType: $pb.PbFieldType.OF)
    ..aInt64(6, _omitFieldNames ? '' : 'elapsedMs')
    ..aOS(7, _omitFieldNames ? '' : 'message')
    ..aOS(8, _omitFieldNames ? '' : 'errorMessage')
    ..aI(9, _omitFieldNames ? '' : 'errorCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LLMGenerationStatus clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  LLMGenerationStatus copyWith(void Function(LLMGenerationStatus) updates) =>
      super.copyWith((message) => updates(message as LLMGenerationStatus))
          as LLMGenerationStatus;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LLMGenerationStatus create() => LLMGenerationStatus._();
  @$core.override
  LLMGenerationStatus createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static LLMGenerationStatus getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<LLMGenerationStatus>(create);
  static LLMGenerationStatus? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get requestId => $_getSZ(0);
  @$pb.TagNumber(1)
  set requestId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasRequestId() => $_has(0);
  @$pb.TagNumber(1)
  void clearRequestId() => $_clearField(1);

  @$pb.TagNumber(2)
  LLMGenerationState get state => $_getN(1);
  @$pb.TagNumber(2)
  set state(LLMGenerationState value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasState() => $_has(1);
  @$pb.TagNumber(2)
  void clearState() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get promptTokensProcessed => $_getIZ(2);
  @$pb.TagNumber(3)
  set promptTokensProcessed($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPromptTokensProcessed() => $_has(2);
  @$pb.TagNumber(3)
  void clearPromptTokensProcessed() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get completionTokensGenerated => $_getIZ(3);
  @$pb.TagNumber(4)
  set completionTokensGenerated($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCompletionTokensGenerated() => $_has(3);
  @$pb.TagNumber(4)
  void clearCompletionTokensGenerated() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get progress => $_getN(4);
  @$pb.TagNumber(5)
  set progress($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasProgress() => $_has(4);
  @$pb.TagNumber(5)
  void clearProgress() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get elapsedMs => $_getI64(5);
  @$pb.TagNumber(6)
  set elapsedMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasElapsedMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearElapsedMs() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get message => $_getSZ(6);
  @$pb.TagNumber(7)
  set message($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasMessage() => $_has(6);
  @$pb.TagNumber(7)
  void clearMessage() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get errorMessage => $_getSZ(7);
  @$pb.TagNumber(8)
  set errorMessage($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasErrorMessage() => $_has(7);
  @$pb.TagNumber(8)
  void clearErrorMessage() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.int get errorCode => $_getIZ(8);
  @$pb.TagNumber(9)
  set errorCode($core.int value) => $_setSignedInt32(8, value);
  @$pb.TagNumber(9)
  $core.bool hasErrorCode() => $_has(8);
  @$pb.TagNumber(9)
  void clearErrorCode() => $_clearField(9);
}

/// ---------------------------------------------------------------------------
/// Lightweight LLM configuration used at component-init time (Swift
/// LLMConfiguration in LLMTypes.swift:15). Distinct from LLMGenerationOptions
/// — this is the "load the model" knob set, not the per-call sampling knobs.
/// ---------------------------------------------------------------------------
class LLMConfiguration extends $pb.GeneratedMessage {
  factory LLMConfiguration({
    $core.int? contextLength,
    $core.double? temperature,
    $core.int? maxTokens,
    $core.String? systemPrompt,
    $core.bool? streaming,
    $core.String? modelId,
    $3.InferenceFramework? preferredFramework,
  }) {
    final result = create();
    if (contextLength != null) result.contextLength = contextLength;
    if (temperature != null) result.temperature = temperature;
    if (maxTokens != null) result.maxTokens = maxTokens;
    if (systemPrompt != null) result.systemPrompt = systemPrompt;
    if (streaming != null) result.streaming = streaming;
    if (modelId != null) result.modelId = modelId;
    if (preferredFramework != null)
      result.preferredFramework = preferredFramework;
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
    ..aD(2, _omitFieldNames ? '' : 'temperature', fieldType: $pb.PbFieldType.OF)
    ..aI(3, _omitFieldNames ? '' : 'maxTokens')
    ..aOS(4, _omitFieldNames ? '' : 'systemPrompt')
    ..aOB(5, _omitFieldNames ? '' : 'streaming')
    ..aOS(6, _omitFieldNames ? '' : 'modelId')
    ..aE<$3.InferenceFramework>(7, _omitFieldNames ? '' : 'preferredFramework',
        enumValues: $3.InferenceFramework.values)
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

  /// Model context window length in tokens. 0 = use model default.
  @$pb.TagNumber(1)
  $core.int get contextLength => $_getIZ(0);
  @$pb.TagNumber(1)
  set contextLength($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasContextLength() => $_has(0);
  @$pb.TagNumber(1)
  void clearContextLength() => $_clearField(1);

  /// Default sampling temperature applied when a per-call value is unset.
  @$pb.TagNumber(2)
  $core.double get temperature => $_getN(1);
  @$pb.TagNumber(2)
  set temperature($core.double value) => $_setFloat(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTemperature() => $_has(1);
  @$pb.TagNumber(2)
  void clearTemperature() => $_clearField(2);

  /// Default max output tokens applied when a per-call value is unset.
  @$pb.TagNumber(3)
  $core.int get maxTokens => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxTokens($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasMaxTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxTokens() => $_clearField(3);

  /// Default system prompt baked into the component. Empty = no default.
  @$pb.TagNumber(4)
  $core.String get systemPrompt => $_getSZ(3);
  @$pb.TagNumber(4)
  set systemPrompt($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSystemPrompt() => $_has(3);
  @$pb.TagNumber(4)
  void clearSystemPrompt() => $_clearField(4);

  /// Whether streaming generation is enabled by default for this component.
  @$pb.TagNumber(5)
  $core.bool get streaming => $_getBF(4);
  @$pb.TagNumber(5)
  set streaming($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasStreaming() => $_has(4);
  @$pb.TagNumber(5)
  void clearStreaming() => $_clearField(5);

  /// Model identifier/path resolved by the component loader. Present in the
  /// C ABI rac_llm_config_t and needed for generated-proto service handles.
  @$pb.TagNumber(6)
  $core.String get modelId => $_getSZ(5);
  @$pb.TagNumber(6)
  set modelId($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasModelId() => $_has(5);
  @$pb.TagNumber(6)
  void clearModelId() => $_clearField(6);

  /// Preferred inference framework for this component. UNSPECIFIED / absent
  /// means "auto".
  @$pb.TagNumber(7)
  $3.InferenceFramework get preferredFramework => $_getN(6);
  @$pb.TagNumber(7)
  set preferredFramework($3.InferenceFramework value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasPreferredFramework() => $_has(6);
  @$pb.TagNumber(7)
  void clearPreferredFramework() => $_clearField(7);
}

/// ---------------------------------------------------------------------------
/// Per-prompt generation hints (Swift GenerationHints in LLMTypes.swift:550).
/// Carried alongside a prompt as a "soft" override of LLMConfiguration
/// defaults when the engine has no explicit LLMGenerationOptions to use.
/// ---------------------------------------------------------------------------
class GenerationHints extends $pb.GeneratedMessage {
  factory GenerationHints({
    $core.double? temperature,
    $core.int? maxTokens,
    $core.String? systemRole,
  }) {
    final result = create();
    if (temperature != null) result.temperature = temperature;
    if (maxTokens != null) result.maxTokens = maxTokens;
    if (systemRole != null) result.systemRole = systemRole;
    return result;
  }

  GenerationHints._();

  factory GenerationHints.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GenerationHints.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GenerationHints',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aD(1, _omitFieldNames ? '' : 'temperature', fieldType: $pb.PbFieldType.OF)
    ..aI(2, _omitFieldNames ? '' : 'maxTokens')
    ..aOS(3, _omitFieldNames ? '' : 'systemRole')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GenerationHints clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GenerationHints copyWith(void Function(GenerationHints) updates) =>
      super.copyWith((message) => updates(message as GenerationHints))
          as GenerationHints;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GenerationHints create() => GenerationHints._();
  @$core.override
  GenerationHints createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GenerationHints getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GenerationHints>(create);
  static GenerationHints? _defaultInstance;

  /// Suggested sampling temperature.
  @$pb.TagNumber(1)
  $core.double get temperature => $_getN(0);
  @$pb.TagNumber(1)
  set temperature($core.double value) => $_setFloat(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTemperature() => $_has(0);
  @$pb.TagNumber(1)
  void clearTemperature() => $_clearField(1);

  /// Suggested max output tokens.
  @$pb.TagNumber(2)
  $core.int get maxTokens => $_getIZ(1);
  @$pb.TagNumber(2)
  set maxTokens($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMaxTokens() => $_has(1);
  @$pb.TagNumber(2)
  void clearMaxTokens() => $_clearField(2);

  /// Suggested role to use for the system prompt (e.g. "system", "developer").
  /// Empty = engine default ("system").
  @$pb.TagNumber(3)
  $core.String get systemRole => $_getSZ(2);
  @$pb.TagNumber(3)
  set systemRole($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSystemRole() => $_has(2);
  @$pb.TagNumber(3)
  void clearSystemRole() => $_clearField(3);
}

/// ---------------------------------------------------------------------------
/// Single streamed token (Swift StreamToken in LLMTypes.swift:563). Emitted
/// once per token in streaming mode.
/// ---------------------------------------------------------------------------
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

  /// Decoded text fragment for this token.
  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => $_clearField(1);

  /// Wall-clock timestamp (ms since Unix epoch) the token was produced.
  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampMs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampMs($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTimestampMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampMs() => $_clearField(2);

  /// Sequence index within the current generation (0-based).
  @$pb.TagNumber(3)
  $core.int get index => $_getIZ(2);
  @$pb.TagNumber(3)
  set index($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasIndex() => $_has(2);
  @$pb.TagNumber(3)
  void clearIndex() => $_clearField(3);
}

/// ---------------------------------------------------------------------------
/// Aggregated performance metrics for a generation (Web SDK
/// PerformanceMetrics in types/models.ts:57). Higher-level summary that
/// rolls up the timing fields scattered across LLMGenerationResult.
/// ---------------------------------------------------------------------------
class PerformanceMetrics extends $pb.GeneratedMessage {
  factory PerformanceMetrics({
    $fixnum.Int64? latencyMs,
    $fixnum.Int64? memoryBytes,
    $core.double? throughputTokensPerSec,
    $core.int? promptTokens,
    $core.int? completionTokens,
  }) {
    final result = create();
    if (latencyMs != null) result.latencyMs = latencyMs;
    if (memoryBytes != null) result.memoryBytes = memoryBytes;
    if (throughputTokensPerSec != null)
      result.throughputTokensPerSec = throughputTokensPerSec;
    if (promptTokens != null) result.promptTokens = promptTokens;
    if (completionTokens != null) result.completionTokens = completionTokens;
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
    ..aD(3, _omitFieldNames ? '' : 'throughputTokensPerSec',
        fieldType: $pb.PbFieldType.OF)
    ..aI(4, _omitFieldNames ? '' : 'promptTokens')
    ..aI(5, _omitFieldNames ? '' : 'completionTokens')
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

  /// Total latency from request to last token, in milliseconds.
  @$pb.TagNumber(1)
  $fixnum.Int64 get latencyMs => $_getI64(0);
  @$pb.TagNumber(1)
  set latencyMs($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLatencyMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearLatencyMs() => $_clearField(1);

  /// Peak memory used by the inference engine, in bytes.
  @$pb.TagNumber(2)
  $fixnum.Int64 get memoryBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set memoryBytes($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMemoryBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearMemoryBytes() => $_clearField(2);

  /// Decode throughput in tokens/second.
  @$pb.TagNumber(3)
  $core.double get throughputTokensPerSec => $_getN(2);
  @$pb.TagNumber(3)
  set throughputTokensPerSec($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasThroughputTokensPerSec() => $_has(2);
  @$pb.TagNumber(3)
  void clearThroughputTokensPerSec() => $_clearField(3);

  /// Prompt (input) token count.
  @$pb.TagNumber(4)
  $core.int get promptTokens => $_getIZ(3);
  @$pb.TagNumber(4)
  set promptTokens($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPromptTokens() => $_has(3);
  @$pb.TagNumber(4)
  void clearPromptTokens() => $_clearField(4);

  /// Completion (output) token count.
  @$pb.TagNumber(5)
  $core.int get completionTokens => $_getIZ(4);
  @$pb.TagNumber(5)
  set completionTokens($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasCompletionTokens() => $_has(4);
  @$pb.TagNumber(5)
  void clearCompletionTokens() => $_clearField(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
