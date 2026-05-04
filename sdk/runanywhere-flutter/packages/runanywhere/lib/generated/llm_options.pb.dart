//
//  Generated code. Do not modify.
//  source: llm_options.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'llm_options.pbenum.dart';
import 'model_types.pbenum.dart' as $1;
import 'structured_output.pb.dart' as $0;

export 'llm_options.pbenum.dart';

///  ---------------------------------------------------------------------------
///  Options for a single text generation invocation.
///
///  Field names match Swift LLMGenerationOptions exactly; consumers may treat
///  proto3 scalar defaults as "unset" (Swift handled this via Optionals — proto
///  represents optional reference fields explicitly via `optional` keyword).
///  ---------------------------------------------------------------------------
class LLMGenerationOptions extends $pb.GeneratedMessage {
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
    $core.bool? enableRealTimeTracking,
  }) {
    final $result = create();
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
    if (systemPrompt != null) {
      $result.systemPrompt = systemPrompt;
    }
    if (jsonSchema != null) {
      $result.jsonSchema = jsonSchema;
    }
    if (thinkingPattern != null) {
      $result.thinkingPattern = thinkingPattern;
    }
    if (executionTarget != null) {
      $result.executionTarget = executionTarget;
    }
    if (structuredOutput != null) {
      $result.structuredOutput = structuredOutput;
    }
    if (enableRealTimeTracking != null) {
      $result.enableRealTimeTracking = enableRealTimeTracking;
    }
    return $result;
  }
  LLMGenerationOptions._() : super();
  factory LLMGenerationOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LLMGenerationOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LLMGenerationOptions', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'maxTokens', $pb.PbFieldType.O3)
    ..a<$core.double>(2, _omitFieldNames ? '' : 'temperature', $pb.PbFieldType.OF)
    ..a<$core.double>(3, _omitFieldNames ? '' : 'topP', $pb.PbFieldType.OF)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'topK', $pb.PbFieldType.O3)
    ..a<$core.double>(5, _omitFieldNames ? '' : 'repetitionPenalty', $pb.PbFieldType.OF)
    ..pPS(6, _omitFieldNames ? '' : 'stopSequences')
    ..aOB(7, _omitFieldNames ? '' : 'streamingEnabled')
    ..e<$1.InferenceFramework>(8, _omitFieldNames ? '' : 'preferredFramework', $pb.PbFieldType.OE, defaultOrMaker: $1.InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED, valueOf: $1.InferenceFramework.valueOf, enumValues: $1.InferenceFramework.values)
    ..aOS(9, _omitFieldNames ? '' : 'systemPrompt')
    ..aOS(10, _omitFieldNames ? '' : 'jsonSchema')
    ..aOM<ThinkingTagPattern>(11, _omitFieldNames ? '' : 'thinkingPattern', subBuilder: ThinkingTagPattern.create)
    ..e<ExecutionTarget>(12, _omitFieldNames ? '' : 'executionTarget', $pb.PbFieldType.OE, defaultOrMaker: ExecutionTarget.EXECUTION_TARGET_UNSPECIFIED, valueOf: ExecutionTarget.valueOf, enumValues: ExecutionTarget.values)
    ..aOM<$0.StructuredOutputOptions>(13, _omitFieldNames ? '' : 'structuredOutput', subBuilder: $0.StructuredOutputOptions.create)
    ..aOB(14, _omitFieldNames ? '' : 'enableRealTimeTracking')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LLMGenerationOptions clone() => LLMGenerationOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LLMGenerationOptions copyWith(void Function(LLMGenerationOptions) updates) => super.copyWith((message) => updates(message as LLMGenerationOptions)) as LLMGenerationOptions;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LLMGenerationOptions create() => LLMGenerationOptions._();
  LLMGenerationOptions createEmptyInstance() => create();
  static $pb.PbList<LLMGenerationOptions> createRepeated() => $pb.PbList<LLMGenerationOptions>();
  @$core.pragma('dart2js:noInline')
  static LLMGenerationOptions getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LLMGenerationOptions>(create);
  static LLMGenerationOptions? _defaultInstance;

  /// Maximum number of tokens to generate. 0 (default) = unset → engine
  /// default (typically 100).
  @$pb.TagNumber(1)
  $core.int get maxTokens => $_getIZ(0);
  @$pb.TagNumber(1)
  set maxTokens($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasMaxTokens() => $_has(0);
  @$pb.TagNumber(1)
  void clearMaxTokens() => clearField(1);

  /// Sampling temperature (0.0 - 2.0). 0.0 = greedy decoding.
  @$pb.TagNumber(2)
  $core.double get temperature => $_getN(1);
  @$pb.TagNumber(2)
  set temperature($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTemperature() => $_has(1);
  @$pb.TagNumber(2)
  void clearTemperature() => clearField(2);

  /// Nucleus sampling (top-p). 1.0 = no nucleus truncation.
  @$pb.TagNumber(3)
  $core.double get topP => $_getN(2);
  @$pb.TagNumber(3)
  set topP($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTopP() => $_has(2);
  @$pb.TagNumber(3)
  void clearTopP() => clearField(3);

  /// Top-K sampling (Kotlin/Dart/RN field). 0 = disabled.
  @$pb.TagNumber(4)
  $core.int get topK => $_getIZ(3);
  @$pb.TagNumber(4)
  set topK($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTopK() => $_has(3);
  @$pb.TagNumber(4)
  void clearTopK() => clearField(4);

  /// Repetition penalty (Kotlin/Dart/RN field). 1.0 = no penalty.
  @$pb.TagNumber(5)
  $core.double get repetitionPenalty => $_getN(4);
  @$pb.TagNumber(5)
  set repetitionPenalty($core.double v) { $_setFloat(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasRepetitionPenalty() => $_has(4);
  @$pb.TagNumber(5)
  void clearRepetitionPenalty() => clearField(5);

  /// Stop sequences. Generation halts when any of these strings appears in
  /// the output stream.
  @$pb.TagNumber(6)
  $core.List<$core.String> get stopSequences => $_getList(5);

  /// Whether to stream tokens vs return result at end (Swift field).
  @$pb.TagNumber(7)
  $core.bool get streamingEnabled => $_getBF(6);
  @$pb.TagNumber(7)
  set streamingEnabled($core.bool v) { $_setBool(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasStreamingEnabled() => $_has(6);
  @$pb.TagNumber(7)
  void clearStreamingEnabled() => clearField(7);

  /// Preferred inference framework. UNSPECIFIED = pick automatically.
  @$pb.TagNumber(8)
  $1.InferenceFramework get preferredFramework => $_getN(7);
  @$pb.TagNumber(8)
  set preferredFramework($1.InferenceFramework v) { setField(8, v); }
  @$pb.TagNumber(8)
  $core.bool hasPreferredFramework() => $_has(7);
  @$pb.TagNumber(8)
  void clearPreferredFramework() => clearField(8);

  /// System prompt to define AI behavior and formatting rules.
  @$pb.TagNumber(9)
  $core.String get systemPrompt => $_getSZ(8);
  @$pb.TagNumber(9)
  set systemPrompt($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasSystemPrompt() => $_has(8);
  @$pb.TagNumber(9)
  void clearSystemPrompt() => clearField(9);

  /// Optional structured-output mode (JSON schema). Engine returns text
  /// that conforms to this schema. Swift wraps this in a StructuredOutputConfig
  /// struct with the Generatable.Type — proto carries just the schema string.
  @$pb.TagNumber(10)
  $core.String get jsonSchema => $_getSZ(9);
  @$pb.TagNumber(10)
  set jsonSchema($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasJsonSchema() => $_has(9);
  @$pb.TagNumber(10)
  void clearJsonSchema() => clearField(10);

  /// Optional thinking-tag pattern for extracting reasoning content from
  /// models like Qwen3 / LFM2 that emit <think>...</think> blocks.
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

  /// Routing hint: where this generation should run (on-device, cloud, or
  /// SDK-decided AUTO). Mirrors the Web SDK ExecutionTarget knob.
  @$pb.TagNumber(12)
  ExecutionTarget get executionTarget => $_getN(11);
  @$pb.TagNumber(12)
  set executionTarget(ExecutionTarget v) { setField(12, v); }
  @$pb.TagNumber(12)
  $core.bool hasExecutionTarget() => $_has(11);
  @$pb.TagNumber(12)
  void clearExecutionTarget() => clearField(12);

  /// Optional structured-output configuration. Detailed message lives in
  /// structured_output.proto so the schema/format details aren't duplicated
  /// here. When set, supersedes the simpler `json_schema` string above.
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

  /// Enable per-token/cost dashboard tracking for SDKs that surface live
  /// generation telemetry. No-op for backends without a telemetry sink.
  @$pb.TagNumber(14)
  $core.bool get enableRealTimeTracking => $_getBF(13);
  @$pb.TagNumber(14)
  set enableRealTimeTracking($core.bool v) { $_setBool(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasEnableRealTimeTracking() => $_has(13);
  @$pb.TagNumber(14)
  void clearEnableRealTimeTracking() => clearField(14);
}

/// ---------------------------------------------------------------------------
/// Result of a single text generation. Same fields as the Swift
/// LLMGenerationResult plus the fields RN/Web carry that Swift derives from
/// the rac_llm_stream_result_t C struct.
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
    $0.StructuredOutputValidation? structuredOutputValidation,
    $core.int? totalTokens,
    $core.String? errorMessage,
  }) {
    final $result = create();
    if (text != null) {
      $result.text = text;
    }
    if (thinkingContent != null) {
      $result.thinkingContent = thinkingContent;
    }
    if (inputTokens != null) {
      $result.inputTokens = inputTokens;
    }
    if (tokensGenerated != null) {
      $result.tokensGenerated = tokensGenerated;
    }
    if (modelUsed != null) {
      $result.modelUsed = modelUsed;
    }
    if (generationTimeMs != null) {
      $result.generationTimeMs = generationTimeMs;
    }
    if (ttftMs != null) {
      $result.ttftMs = ttftMs;
    }
    if (tokensPerSecond != null) {
      $result.tokensPerSecond = tokensPerSecond;
    }
    if (framework != null) {
      $result.framework = framework;
    }
    if (finishReason != null) {
      $result.finishReason = finishReason;
    }
    if (thinkingTokens != null) {
      $result.thinkingTokens = thinkingTokens;
    }
    if (responseTokens != null) {
      $result.responseTokens = responseTokens;
    }
    if (jsonOutput != null) {
      $result.jsonOutput = jsonOutput;
    }
    if (performance != null) {
      $result.performance = performance;
    }
    if (executedOn != null) {
      $result.executedOn = executedOn;
    }
    if (structuredOutputValidation != null) {
      $result.structuredOutputValidation = structuredOutputValidation;
    }
    if (totalTokens != null) {
      $result.totalTokens = totalTokens;
    }
    if (errorMessage != null) {
      $result.errorMessage = errorMessage;
    }
    return $result;
  }
  LLMGenerationResult._() : super();
  factory LLMGenerationResult.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LLMGenerationResult.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LLMGenerationResult', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aOS(2, _omitFieldNames ? '' : 'thinkingContent')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'inputTokens', $pb.PbFieldType.O3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'tokensGenerated', $pb.PbFieldType.O3)
    ..aOS(5, _omitFieldNames ? '' : 'modelUsed')
    ..a<$core.double>(6, _omitFieldNames ? '' : 'generationTimeMs', $pb.PbFieldType.OD)
    ..a<$core.double>(7, _omitFieldNames ? '' : 'ttftMs', $pb.PbFieldType.OD)
    ..a<$core.double>(8, _omitFieldNames ? '' : 'tokensPerSecond', $pb.PbFieldType.OD)
    ..aOS(9, _omitFieldNames ? '' : 'framework')
    ..aOS(10, _omitFieldNames ? '' : 'finishReason')
    ..a<$core.int>(11, _omitFieldNames ? '' : 'thinkingTokens', $pb.PbFieldType.O3)
    ..a<$core.int>(12, _omitFieldNames ? '' : 'responseTokens', $pb.PbFieldType.O3)
    ..aOS(13, _omitFieldNames ? '' : 'jsonOutput')
    ..aOM<PerformanceMetrics>(14, _omitFieldNames ? '' : 'performance', subBuilder: PerformanceMetrics.create)
    ..e<ExecutionTarget>(15, _omitFieldNames ? '' : 'executedOn', $pb.PbFieldType.OE, defaultOrMaker: ExecutionTarget.EXECUTION_TARGET_UNSPECIFIED, valueOf: ExecutionTarget.valueOf, enumValues: ExecutionTarget.values)
    ..aOM<$0.StructuredOutputValidation>(16, _omitFieldNames ? '' : 'structuredOutputValidation', subBuilder: $0.StructuredOutputValidation.create)
    ..a<$core.int>(17, _omitFieldNames ? '' : 'totalTokens', $pb.PbFieldType.O3)
    ..aOS(18, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LLMGenerationResult clone() => LLMGenerationResult()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LLMGenerationResult copyWith(void Function(LLMGenerationResult) updates) => super.copyWith((message) => updates(message as LLMGenerationResult)) as LLMGenerationResult;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LLMGenerationResult create() => LLMGenerationResult._();
  LLMGenerationResult createEmptyInstance() => create();
  static $pb.PbList<LLMGenerationResult> createRepeated() => $pb.PbList<LLMGenerationResult>();
  @$core.pragma('dart2js:noInline')
  static LLMGenerationResult getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LLMGenerationResult>(create);
  static LLMGenerationResult? _defaultInstance;

  /// Generated text (with thinking content removed if extracted).
  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => clearField(1);

  /// Optional thinking/reasoning content extracted from the response.
  @$pb.TagNumber(2)
  $core.String get thinkingContent => $_getSZ(1);
  @$pb.TagNumber(2)
  set thinkingContent($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasThinkingContent() => $_has(1);
  @$pb.TagNumber(2)
  void clearThinkingContent() => clearField(2);

  /// Number of input/prompt tokens (from tokenizer).
  @$pb.TagNumber(3)
  $core.int get inputTokens => $_getIZ(2);
  @$pb.TagNumber(3)
  set inputTokens($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasInputTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearInputTokens() => clearField(3);

  /// Number of tokens used (output / completion tokens).
  @$pb.TagNumber(4)
  $core.int get tokensGenerated => $_getIZ(3);
  @$pb.TagNumber(4)
  set tokensGenerated($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasTokensGenerated() => $_has(3);
  @$pb.TagNumber(4)
  void clearTokensGenerated() => clearField(4);

  /// Model used for generation.
  @$pb.TagNumber(5)
  $core.String get modelUsed => $_getSZ(4);
  @$pb.TagNumber(5)
  set modelUsed($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasModelUsed() => $_has(4);
  @$pb.TagNumber(5)
  void clearModelUsed() => clearField(5);

  /// Total wall-clock generation time in milliseconds.
  @$pb.TagNumber(6)
  $core.double get generationTimeMs => $_getN(5);
  @$pb.TagNumber(6)
  set generationTimeMs($core.double v) { $_setDouble(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasGenerationTimeMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearGenerationTimeMs() => clearField(6);

  /// Time-to-first-token in milliseconds (only set in streaming mode).
  @$pb.TagNumber(7)
  $core.double get ttftMs => $_getN(6);
  @$pb.TagNumber(7)
  set ttftMs($core.double v) { $_setDouble(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasTtftMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearTtftMs() => clearField(7);

  /// Tokens-per-second throughput.
  @$pb.TagNumber(8)
  $core.double get tokensPerSecond => $_getN(7);
  @$pb.TagNumber(8)
  set tokensPerSecond($core.double v) { $_setDouble(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasTokensPerSecond() => $_has(7);
  @$pb.TagNumber(8)
  void clearTokensPerSecond() => clearField(8);

  /// Framework that actually performed the generation. Optional because
  /// some C ABI paths don't surface it.
  @$pb.TagNumber(9)
  $core.String get framework => $_getSZ(8);
  @$pb.TagNumber(9)
  set framework($core.String v) { $_setString(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasFramework() => $_has(8);
  @$pb.TagNumber(9)
  void clearFramework() => clearField(9);

  /// Reason the generation stopped: "stop", "length", "cancelled", "error".
  /// Empty = unset.
  @$pb.TagNumber(10)
  $core.String get finishReason => $_getSZ(9);
  @$pb.TagNumber(10)
  set finishReason($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasFinishReason() => $_has(9);
  @$pb.TagNumber(10)
  void clearFinishReason() => clearField(10);

  /// Number of tokens used for thinking/reasoning. 0 = not applicable.
  @$pb.TagNumber(11)
  $core.int get thinkingTokens => $_getIZ(10);
  @$pb.TagNumber(11)
  set thinkingTokens($core.int v) { $_setSignedInt32(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasThinkingTokens() => $_has(10);
  @$pb.TagNumber(11)
  void clearThinkingTokens() => clearField(11);

  /// Number of tokens in the actual response content (vs thinking).
  @$pb.TagNumber(12)
  $core.int get responseTokens => $_getIZ(11);
  @$pb.TagNumber(12)
  set responseTokens($core.int v) { $_setSignedInt32(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasResponseTokens() => $_has(11);
  @$pb.TagNumber(12)
  void clearResponseTokens() => clearField(12);

  /// Optional JSON output (when structured-output mode was requested).
  /// Empty = no structured output.
  @$pb.TagNumber(13)
  $core.String get jsonOutput => $_getSZ(12);
  @$pb.TagNumber(13)
  set jsonOutput($core.String v) { $_setString(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasJsonOutput() => $_has(12);
  @$pb.TagNumber(13)
  void clearJsonOutput() => clearField(13);

  /// Optional aggregated performance metrics. Web SDK surfaces this as a
  /// separate object alongside the result; consumers may ignore it if they
  /// already use the per-field timings above.
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

  /// Where the generation actually ran (on-device, cloud, etc.). Useful
  /// when execution_target was AUTO and the SDK picked the route.
  @$pb.TagNumber(15)
  ExecutionTarget get executedOn => $_getN(14);
  @$pb.TagNumber(15)
  set executedOn(ExecutionTarget v) { setField(15, v); }
  @$pb.TagNumber(15)
  $core.bool hasExecutedOn() => $_has(14);
  @$pb.TagNumber(15)
  void clearExecutedOn() => clearField(15);

  /// Structured-output validation details, when a structured-output request
  /// was used. Mirrors the Swift/RN validation payload.
  @$pb.TagNumber(16)
  $0.StructuredOutputValidation get structuredOutputValidation => $_getN(15);
  @$pb.TagNumber(16)
  set structuredOutputValidation($0.StructuredOutputValidation v) { setField(16, v); }
  @$pb.TagNumber(16)
  $core.bool hasStructuredOutputValidation() => $_has(15);
  @$pb.TagNumber(16)
  void clearStructuredOutputValidation() => clearField(16);
  @$pb.TagNumber(16)
  $0.StructuredOutputValidation ensureStructuredOutputValidation() => $_ensure(15);

  /// Total tokens consumed (prompt + completion). Some C ABI paths expose
  /// this directly; consumers may also compute it from the per-field counts.
  @$pb.TagNumber(17)
  $core.int get totalTokens => $_getIZ(16);
  @$pb.TagNumber(17)
  set totalTokens($core.int v) { $_setSignedInt32(16, v); }
  @$pb.TagNumber(17)
  $core.bool hasTotalTokens() => $_has(16);
  @$pb.TagNumber(17)
  void clearTotalTokens() => clearField(17);

  /// Backend error text for result-producing APIs that return a terminal
  /// result envelope instead of throwing through the host language.
  @$pb.TagNumber(18)
  $core.String get errorMessage => $_getSZ(17);
  @$pb.TagNumber(18)
  set errorMessage($core.String v) { $_setString(17, v); }
  @$pb.TagNumber(18)
  $core.bool hasErrorMessage() => $_has(17);
  @$pb.TagNumber(18)
  void clearErrorMessage() => clearField(18);
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
    $1.InferenceFramework? preferredFramework,
  }) {
    final $result = create();
    if (contextLength != null) {
      $result.contextLength = contextLength;
    }
    if (temperature != null) {
      $result.temperature = temperature;
    }
    if (maxTokens != null) {
      $result.maxTokens = maxTokens;
    }
    if (systemPrompt != null) {
      $result.systemPrompt = systemPrompt;
    }
    if (streaming != null) {
      $result.streaming = streaming;
    }
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (preferredFramework != null) {
      $result.preferredFramework = preferredFramework;
    }
    return $result;
  }
  LLMConfiguration._() : super();
  factory LLMConfiguration.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory LLMConfiguration.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'LLMConfiguration', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'contextLength', $pb.PbFieldType.O3)
    ..a<$core.double>(2, _omitFieldNames ? '' : 'temperature', $pb.PbFieldType.OF)
    ..a<$core.int>(3, _omitFieldNames ? '' : 'maxTokens', $pb.PbFieldType.O3)
    ..aOS(4, _omitFieldNames ? '' : 'systemPrompt')
    ..aOB(5, _omitFieldNames ? '' : 'streaming')
    ..aOS(6, _omitFieldNames ? '' : 'modelId')
    ..e<$1.InferenceFramework>(7, _omitFieldNames ? '' : 'preferredFramework', $pb.PbFieldType.OE, defaultOrMaker: $1.InferenceFramework.INFERENCE_FRAMEWORK_UNSPECIFIED, valueOf: $1.InferenceFramework.valueOf, enumValues: $1.InferenceFramework.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  LLMConfiguration clone() => LLMConfiguration()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  LLMConfiguration copyWith(void Function(LLMConfiguration) updates) => super.copyWith((message) => updates(message as LLMConfiguration)) as LLMConfiguration;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static LLMConfiguration create() => LLMConfiguration._();
  LLMConfiguration createEmptyInstance() => create();
  static $pb.PbList<LLMConfiguration> createRepeated() => $pb.PbList<LLMConfiguration>();
  @$core.pragma('dart2js:noInline')
  static LLMConfiguration getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<LLMConfiguration>(create);
  static LLMConfiguration? _defaultInstance;

  /// Model context window length in tokens. 0 = use model default.
  @$pb.TagNumber(1)
  $core.int get contextLength => $_getIZ(0);
  @$pb.TagNumber(1)
  set contextLength($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasContextLength() => $_has(0);
  @$pb.TagNumber(1)
  void clearContextLength() => clearField(1);

  /// Default sampling temperature applied when a per-call value is unset.
  @$pb.TagNumber(2)
  $core.double get temperature => $_getN(1);
  @$pb.TagNumber(2)
  set temperature($core.double v) { $_setFloat(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTemperature() => $_has(1);
  @$pb.TagNumber(2)
  void clearTemperature() => clearField(2);

  /// Default max output tokens applied when a per-call value is unset.
  @$pb.TagNumber(3)
  $core.int get maxTokens => $_getIZ(2);
  @$pb.TagNumber(3)
  set maxTokens($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMaxTokens() => $_has(2);
  @$pb.TagNumber(3)
  void clearMaxTokens() => clearField(3);

  /// Default system prompt baked into the component. Empty = no default.
  @$pb.TagNumber(4)
  $core.String get systemPrompt => $_getSZ(3);
  @$pb.TagNumber(4)
  set systemPrompt($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasSystemPrompt() => $_has(3);
  @$pb.TagNumber(4)
  void clearSystemPrompt() => clearField(4);

  /// Whether streaming generation is enabled by default for this component.
  @$pb.TagNumber(5)
  $core.bool get streaming => $_getBF(4);
  @$pb.TagNumber(5)
  set streaming($core.bool v) { $_setBool(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasStreaming() => $_has(4);
  @$pb.TagNumber(5)
  void clearStreaming() => clearField(5);

  /// Model identifier/path resolved by the component loader. Present in the
  /// C ABI rac_llm_config_t and needed for generated-proto service handles.
  @$pb.TagNumber(6)
  $core.String get modelId => $_getSZ(5);
  @$pb.TagNumber(6)
  set modelId($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasModelId() => $_has(5);
  @$pb.TagNumber(6)
  void clearModelId() => clearField(6);

  /// Preferred inference framework for this component. UNSPECIFIED / absent
  /// means "auto".
  @$pb.TagNumber(7)
  $1.InferenceFramework get preferredFramework => $_getN(6);
  @$pb.TagNumber(7)
  set preferredFramework($1.InferenceFramework v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasPreferredFramework() => $_has(6);
  @$pb.TagNumber(7)
  void clearPreferredFramework() => clearField(7);
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
    final $result = create();
    if (temperature != null) {
      $result.temperature = temperature;
    }
    if (maxTokens != null) {
      $result.maxTokens = maxTokens;
    }
    if (systemRole != null) {
      $result.systemRole = systemRole;
    }
    return $result;
  }
  GenerationHints._() : super();
  factory GenerationHints.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory GenerationHints.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'GenerationHints', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.double>(1, _omitFieldNames ? '' : 'temperature', $pb.PbFieldType.OF)
    ..a<$core.int>(2, _omitFieldNames ? '' : 'maxTokens', $pb.PbFieldType.O3)
    ..aOS(3, _omitFieldNames ? '' : 'systemRole')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  GenerationHints clone() => GenerationHints()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  GenerationHints copyWith(void Function(GenerationHints) updates) => super.copyWith((message) => updates(message as GenerationHints)) as GenerationHints;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GenerationHints create() => GenerationHints._();
  GenerationHints createEmptyInstance() => create();
  static $pb.PbList<GenerationHints> createRepeated() => $pb.PbList<GenerationHints>();
  @$core.pragma('dart2js:noInline')
  static GenerationHints getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<GenerationHints>(create);
  static GenerationHints? _defaultInstance;

  /// Suggested sampling temperature.
  @$pb.TagNumber(1)
  $core.double get temperature => $_getN(0);
  @$pb.TagNumber(1)
  set temperature($core.double v) { $_setFloat(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasTemperature() => $_has(0);
  @$pb.TagNumber(1)
  void clearTemperature() => clearField(1);

  /// Suggested max output tokens.
  @$pb.TagNumber(2)
  $core.int get maxTokens => $_getIZ(1);
  @$pb.TagNumber(2)
  set maxTokens($core.int v) { $_setSignedInt32(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMaxTokens() => $_has(1);
  @$pb.TagNumber(2)
  void clearMaxTokens() => clearField(2);

  /// Suggested role to use for the system prompt (e.g. "system", "developer").
  /// Empty = engine default ("system").
  @$pb.TagNumber(3)
  $core.String get systemRole => $_getSZ(2);
  @$pb.TagNumber(3)
  set systemRole($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSystemRole() => $_has(2);
  @$pb.TagNumber(3)
  void clearSystemRole() => clearField(3);
}

/// ---------------------------------------------------------------------------
/// Pattern used to extract a model's "thinking" / reasoning block from its
/// raw output (Swift ThinkingTagPattern in LLMTypes.swift:344). Used by
/// Qwen3 and LFM2 family models that emit <think>...</think> wrappers.
/// ---------------------------------------------------------------------------
class ThinkingTagPattern extends $pb.GeneratedMessage {
  factory ThinkingTagPattern({
    $core.String? openingTag,
    $core.String? closingTag,
  }) {
    final $result = create();
    if (openingTag != null) {
      $result.openingTag = openingTag;
    }
    if (closingTag != null) {
      $result.closingTag = closingTag;
    }
    return $result;
  }
  ThinkingTagPattern._() : super();
  factory ThinkingTagPattern.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ThinkingTagPattern.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ThinkingTagPattern', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'openingTag')
    ..aOS(2, _omitFieldNames ? '' : 'closingTag')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ThinkingTagPattern clone() => ThinkingTagPattern()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ThinkingTagPattern copyWith(void Function(ThinkingTagPattern) updates) => super.copyWith((message) => updates(message as ThinkingTagPattern)) as ThinkingTagPattern;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ThinkingTagPattern create() => ThinkingTagPattern._();
  ThinkingTagPattern createEmptyInstance() => create();
  static $pb.PbList<ThinkingTagPattern> createRepeated() => $pb.PbList<ThinkingTagPattern>();
  @$core.pragma('dart2js:noInline')
  static ThinkingTagPattern getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ThinkingTagPattern>(create);
  static ThinkingTagPattern? _defaultInstance;

  /// Opening tag string. Default if empty: "<think>".
  @$pb.TagNumber(1)
  $core.String get openingTag => $_getSZ(0);
  @$pb.TagNumber(1)
  set openingTag($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasOpeningTag() => $_has(0);
  @$pb.TagNumber(1)
  void clearOpeningTag() => clearField(1);

  /// Closing tag string. Default if empty: "</think>".
  @$pb.TagNumber(2)
  $core.String get closingTag => $_getSZ(1);
  @$pb.TagNumber(2)
  set closingTag($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasClosingTag() => $_has(1);
  @$pb.TagNumber(2)
  void clearClosingTag() => clearField(2);
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
    final $result = create();
    if (text != null) {
      $result.text = text;
    }
    if (timestampMs != null) {
      $result.timestampMs = timestampMs;
    }
    if (index != null) {
      $result.index = index;
    }
    return $result;
  }
  StreamToken._() : super();
  factory StreamToken.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory StreamToken.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'StreamToken', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'text')
    ..aInt64(2, _omitFieldNames ? '' : 'timestampMs')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'index', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  StreamToken clone() => StreamToken()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  StreamToken copyWith(void Function(StreamToken) updates) => super.copyWith((message) => updates(message as StreamToken)) as StreamToken;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StreamToken create() => StreamToken._();
  StreamToken createEmptyInstance() => create();
  static $pb.PbList<StreamToken> createRepeated() => $pb.PbList<StreamToken>();
  @$core.pragma('dart2js:noInline')
  static StreamToken getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<StreamToken>(create);
  static StreamToken? _defaultInstance;

  /// Decoded text fragment for this token.
  @$pb.TagNumber(1)
  $core.String get text => $_getSZ(0);
  @$pb.TagNumber(1)
  set text($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasText() => $_has(0);
  @$pb.TagNumber(1)
  void clearText() => clearField(1);

  /// Wall-clock timestamp (ms since Unix epoch) the token was produced.
  @$pb.TagNumber(2)
  $fixnum.Int64 get timestampMs => $_getI64(1);
  @$pb.TagNumber(2)
  set timestampMs($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTimestampMs() => $_has(1);
  @$pb.TagNumber(2)
  void clearTimestampMs() => clearField(2);

  /// Sequence index within the current generation (0-based).
  @$pb.TagNumber(3)
  $core.int get index => $_getIZ(2);
  @$pb.TagNumber(3)
  set index($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasIndex() => $_has(2);
  @$pb.TagNumber(3)
  void clearIndex() => clearField(3);
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
    final $result = create();
    if (latencyMs != null) {
      $result.latencyMs = latencyMs;
    }
    if (memoryBytes != null) {
      $result.memoryBytes = memoryBytes;
    }
    if (throughputTokensPerSec != null) {
      $result.throughputTokensPerSec = throughputTokensPerSec;
    }
    if (promptTokens != null) {
      $result.promptTokens = promptTokens;
    }
    if (completionTokens != null) {
      $result.completionTokens = completionTokens;
    }
    return $result;
  }
  PerformanceMetrics._() : super();
  factory PerformanceMetrics.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PerformanceMetrics.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PerformanceMetrics', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aInt64(1, _omitFieldNames ? '' : 'latencyMs')
    ..aInt64(2, _omitFieldNames ? '' : 'memoryBytes')
    ..a<$core.double>(3, _omitFieldNames ? '' : 'throughputTokensPerSec', $pb.PbFieldType.OF)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'promptTokens', $pb.PbFieldType.O3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'completionTokens', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PerformanceMetrics clone() => PerformanceMetrics()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PerformanceMetrics copyWith(void Function(PerformanceMetrics) updates) => super.copyWith((message) => updates(message as PerformanceMetrics)) as PerformanceMetrics;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PerformanceMetrics create() => PerformanceMetrics._();
  PerformanceMetrics createEmptyInstance() => create();
  static $pb.PbList<PerformanceMetrics> createRepeated() => $pb.PbList<PerformanceMetrics>();
  @$core.pragma('dart2js:noInline')
  static PerformanceMetrics getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PerformanceMetrics>(create);
  static PerformanceMetrics? _defaultInstance;

  /// Total latency from request to last token, in milliseconds.
  @$pb.TagNumber(1)
  $fixnum.Int64 get latencyMs => $_getI64(0);
  @$pb.TagNumber(1)
  set latencyMs($fixnum.Int64 v) { $_setInt64(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasLatencyMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearLatencyMs() => clearField(1);

  /// Peak memory used by the inference engine, in bytes.
  @$pb.TagNumber(2)
  $fixnum.Int64 get memoryBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set memoryBytes($fixnum.Int64 v) { $_setInt64(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasMemoryBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearMemoryBytes() => clearField(2);

  /// Decode throughput in tokens/second.
  @$pb.TagNumber(3)
  $core.double get throughputTokensPerSec => $_getN(2);
  @$pb.TagNumber(3)
  set throughputTokensPerSec($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasThroughputTokensPerSec() => $_has(2);
  @$pb.TagNumber(3)
  void clearThroughputTokensPerSec() => clearField(3);

  /// Prompt (input) token count.
  @$pb.TagNumber(4)
  $core.int get promptTokens => $_getIZ(3);
  @$pb.TagNumber(4)
  set promptTokens($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasPromptTokens() => $_has(3);
  @$pb.TagNumber(4)
  void clearPromptTokens() => clearField(4);

  /// Completion (output) token count.
  @$pb.TagNumber(5)
  $core.int get completionTokens => $_getIZ(4);
  @$pb.TagNumber(5)
  set completionTokens($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasCompletionTokens() => $_has(4);
  @$pb.TagNumber(5)
  void clearCompletionTokens() => clearField(5);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
