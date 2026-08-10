// This is a generated file - do not edit.
//
// Generated from solutions.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'llm_options.pb.dart' as $0;
import 'solutions.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'solutions.pbenum.dart';

enum SolutionConfig_Config { voiceAgent, rag, agentLoop, timeSeries, notSet }

class SolutionConfig extends $pb.GeneratedMessage {
  factory SolutionConfig({
    VoiceAgentConfig? voiceAgent,
    RAGConfig? rag,
    AgentLoopConfig? agentLoop,
    TimeSeriesConfig? timeSeries,
  }) {
    final result = create();
    if (voiceAgent != null) result.voiceAgent = voiceAgent;
    if (rag != null) result.rag = rag;
    if (agentLoop != null) result.agentLoop = agentLoop;
    if (timeSeries != null) result.timeSeries = timeSeries;
    return result;
  }

  SolutionConfig._();

  factory SolutionConfig.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SolutionConfig.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, SolutionConfig_Config>
      _SolutionConfig_ConfigByTag = {
    1: SolutionConfig_Config.voiceAgent,
    2: SolutionConfig_Config.rag,
    4: SolutionConfig_Config.agentLoop,
    5: SolutionConfig_Config.timeSeries,
    0: SolutionConfig_Config.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SolutionConfig',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..oo(0, [1, 2, 4, 5])
    ..aOM<VoiceAgentConfig>(1, _omitFieldNames ? '' : 'voiceAgent',
        subBuilder: VoiceAgentConfig.create)
    ..aOM<RAGConfig>(2, _omitFieldNames ? '' : 'rag',
        subBuilder: RAGConfig.create)
    ..aOM<AgentLoopConfig>(4, _omitFieldNames ? '' : 'agentLoop',
        subBuilder: AgentLoopConfig.create)
    ..aOM<TimeSeriesConfig>(5, _omitFieldNames ? '' : 'timeSeries',
        subBuilder: TimeSeriesConfig.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SolutionConfig clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SolutionConfig copyWith(void Function(SolutionConfig) updates) =>
      super.copyWith((message) => updates(message as SolutionConfig))
          as SolutionConfig;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SolutionConfig create() => SolutionConfig._();
  @$core.override
  SolutionConfig createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SolutionConfig getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SolutionConfig>(create);
  static SolutionConfig? _defaultInstance;

  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  SolutionConfig_Config whichConfig() =>
      _SolutionConfig_ConfigByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(1)
  @$pb.TagNumber(2)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  void clearConfig() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  VoiceAgentConfig get voiceAgent => $_getN(0);
  @$pb.TagNumber(1)
  set voiceAgent(VoiceAgentConfig value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasVoiceAgent() => $_has(0);
  @$pb.TagNumber(1)
  void clearVoiceAgent() => $_clearField(1);
  @$pb.TagNumber(1)
  VoiceAgentConfig ensureVoiceAgent() => $_ensure(0);

  @$pb.TagNumber(2)
  RAGConfig get rag => $_getN(1);
  @$pb.TagNumber(2)
  set rag(RAGConfig value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasRag() => $_has(1);
  @$pb.TagNumber(2)
  void clearRag() => $_clearField(2);
  @$pb.TagNumber(2)
  RAGConfig ensureRag() => $_ensure(1);

  @$pb.TagNumber(4)
  AgentLoopConfig get agentLoop => $_getN(2);
  @$pb.TagNumber(4)
  set agentLoop(AgentLoopConfig value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasAgentLoop() => $_has(2);
  @$pb.TagNumber(4)
  void clearAgentLoop() => $_clearField(4);
  @$pb.TagNumber(4)
  AgentLoopConfig ensureAgentLoop() => $_ensure(2);

  @$pb.TagNumber(5)
  TimeSeriesConfig get timeSeries => $_getN(3);
  @$pb.TagNumber(5)
  set timeSeries(TimeSeriesConfig value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasTimeSeries() => $_has(3);
  @$pb.TagNumber(5)
  void clearTimeSeries() => $_clearField(5);
  @$pb.TagNumber(5)
  TimeSeriesConfig ensureTimeSeries() => $_ensure(3);
}

class SolutionHandle extends $pb.GeneratedMessage {
  factory SolutionHandle({
    $core.String? handleId,
    $core.String? solutionType,
    $fixnum.Int64? createdAtMs,
    $core.String? state,
  }) {
    final result = create();
    if (handleId != null) result.handleId = handleId;
    if (solutionType != null) result.solutionType = solutionType;
    if (createdAtMs != null) result.createdAtMs = createdAtMs;
    if (state != null) result.state = state;
    return result;
  }

  SolutionHandle._();

  factory SolutionHandle.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SolutionHandle.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SolutionHandle',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'handleId')
    ..aOS(2, _omitFieldNames ? '' : 'solutionType')
    ..aInt64(3, _omitFieldNames ? '' : 'createdAtMs')
    ..aOS(4, _omitFieldNames ? '' : 'state')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SolutionHandle clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SolutionHandle copyWith(void Function(SolutionHandle) updates) =>
      super.copyWith((message) => updates(message as SolutionHandle))
          as SolutionHandle;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SolutionHandle create() => SolutionHandle._();
  @$core.override
  SolutionHandle createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SolutionHandle getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SolutionHandle>(create);
  static SolutionHandle? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get handleId => $_getSZ(0);
  @$pb.TagNumber(1)
  set handleId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHandleId() => $_has(0);
  @$pb.TagNumber(1)
  void clearHandleId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get solutionType => $_getSZ(1);
  @$pb.TagNumber(2)
  set solutionType($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSolutionType() => $_has(1);
  @$pb.TagNumber(2)
  void clearSolutionType() => $_clearField(2);

  @$pb.TagNumber(3)
  $fixnum.Int64 get createdAtMs => $_getI64(2);
  @$pb.TagNumber(3)
  set createdAtMs($fixnum.Int64 value) => $_setInt64(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCreatedAtMs() => $_has(2);
  @$pb.TagNumber(3)
  void clearCreatedAtMs() => $_clearField(3);

  /// Engine-specific, e.g. "running" or "stopped".
  @$pb.TagNumber(4)
  $core.String get state => $_getSZ(3);
  @$pb.TagNumber(4)
  set state($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasState() => $_has(3);
  @$pb.TagNumber(4)
  void clearState() => $_clearField(4);
}

class VoiceAgentConfig extends $pb.GeneratedMessage {
  factory VoiceAgentConfig({
    $core.String? llmModelId,
    $core.String? sttModelId,
    $core.String? ttsModelId,
    $core.String? vadModelId,
    $core.String? ttsVoiceId,
    $core.int? sampleRateHz,
    $core.int? chunkMs,
    AudioSource? audioSource,
    $core.String? audioFilePath,
    $core.bool? enableBargeIn,
    $core.int? bargeInThresholdMs,
    $0.LLMGenerationOptions? generation,
    $core.int? maxContextTokens,
    $core.bool? emitPartials,
  }) {
    final result = create();
    if (llmModelId != null) result.llmModelId = llmModelId;
    if (sttModelId != null) result.sttModelId = sttModelId;
    if (ttsModelId != null) result.ttsModelId = ttsModelId;
    if (vadModelId != null) result.vadModelId = vadModelId;
    if (ttsVoiceId != null) result.ttsVoiceId = ttsVoiceId;
    if (sampleRateHz != null) result.sampleRateHz = sampleRateHz;
    if (chunkMs != null) result.chunkMs = chunkMs;
    if (audioSource != null) result.audioSource = audioSource;
    if (audioFilePath != null) result.audioFilePath = audioFilePath;
    if (enableBargeIn != null) result.enableBargeIn = enableBargeIn;
    if (bargeInThresholdMs != null)
      result.bargeInThresholdMs = bargeInThresholdMs;
    if (generation != null) result.generation = generation;
    if (maxContextTokens != null) result.maxContextTokens = maxContextTokens;
    if (emitPartials != null) result.emitPartials = emitPartials;
    return result;
  }

  VoiceAgentConfig._();

  factory VoiceAgentConfig.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VoiceAgentConfig.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VoiceAgentConfig',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'llmModelId')
    ..aOS(2, _omitFieldNames ? '' : 'sttModelId')
    ..aOS(3, _omitFieldNames ? '' : 'ttsModelId')
    ..aOS(4, _omitFieldNames ? '' : 'vadModelId')
    ..aOS(5, _omitFieldNames ? '' : 'ttsVoiceId')
    ..aI(6, _omitFieldNames ? '' : 'sampleRateHz')
    ..aI(7, _omitFieldNames ? '' : 'chunkMs')
    ..aE<AudioSource>(8, _omitFieldNames ? '' : 'audioSource',
        enumValues: AudioSource.values)
    ..aOS(9, _omitFieldNames ? '' : 'audioFilePath')
    ..aOB(10, _omitFieldNames ? '' : 'enableBargeIn')
    ..aI(11, _omitFieldNames ? '' : 'bargeInThresholdMs')
    ..aOM<$0.LLMGenerationOptions>(12, _omitFieldNames ? '' : 'generation',
        subBuilder: $0.LLMGenerationOptions.create)
    ..aI(13, _omitFieldNames ? '' : 'maxContextTokens')
    ..aOB(14, _omitFieldNames ? '' : 'emitPartials')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceAgentConfig clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceAgentConfig copyWith(void Function(VoiceAgentConfig) updates) =>
      super.copyWith((message) => updates(message as VoiceAgentConfig))
          as VoiceAgentConfig;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoiceAgentConfig create() => VoiceAgentConfig._();
  @$core.override
  VoiceAgentConfig createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VoiceAgentConfig getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VoiceAgentConfig>(create);
  static VoiceAgentConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get llmModelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set llmModelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLlmModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLlmModelId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get sttModelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sttModelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSttModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSttModelId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get ttsModelId => $_getSZ(2);
  @$pb.TagNumber(3)
  set ttsModelId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTtsModelId() => $_has(2);
  @$pb.TagNumber(3)
  void clearTtsModelId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get vadModelId => $_getSZ(3);
  @$pb.TagNumber(4)
  set vadModelId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasVadModelId() => $_has(3);
  @$pb.TagNumber(4)
  void clearVadModelId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get ttsVoiceId => $_getSZ(4);
  @$pb.TagNumber(5)
  set ttsVoiceId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTtsVoiceId() => $_has(4);
  @$pb.TagNumber(5)
  void clearTtsVoiceId() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get sampleRateHz => $_getIZ(5);
  @$pb.TagNumber(6)
  set sampleRateHz($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSampleRateHz() => $_has(5);
  @$pb.TagNumber(6)
  void clearSampleRateHz() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get chunkMs => $_getIZ(6);
  @$pb.TagNumber(7)
  set chunkMs($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasChunkMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearChunkMs() => $_clearField(7);

  /// audio_file_path applies when audio_source is FILE.
  @$pb.TagNumber(8)
  AudioSource get audioSource => $_getN(7);
  @$pb.TagNumber(8)
  set audioSource(AudioSource value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasAudioSource() => $_has(7);
  @$pb.TagNumber(8)
  void clearAudioSource() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get audioFilePath => $_getSZ(8);
  @$pb.TagNumber(9)
  set audioFilePath($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasAudioFilePath() => $_has(8);
  @$pb.TagNumber(9)
  void clearAudioFilePath() => $_clearField(9);

  /// Unset means enabled.
  @$pb.TagNumber(10)
  $core.bool get enableBargeIn => $_getBF(9);
  @$pb.TagNumber(10)
  set enableBargeIn($core.bool value) => $_setBool(9, value);
  @$pb.TagNumber(10)
  $core.bool hasEnableBargeIn() => $_has(9);
  @$pb.TagNumber(10)
  void clearEnableBargeIn() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.int get bargeInThresholdMs => $_getIZ(10);
  @$pb.TagNumber(11)
  set bargeInThresholdMs($core.int value) => $_setSignedInt32(10, value);
  @$pb.TagNumber(11)
  $core.bool hasBargeInThresholdMs() => $_has(10);
  @$pb.TagNumber(11)
  void clearBargeInThresholdMs() => $_clearField(11);

  @$pb.TagNumber(12)
  $0.LLMGenerationOptions get generation => $_getN(11);
  @$pb.TagNumber(12)
  set generation($0.LLMGenerationOptions value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasGeneration() => $_has(11);
  @$pb.TagNumber(12)
  void clearGeneration() => $_clearField(12);
  @$pb.TagNumber(12)
  $0.LLMGenerationOptions ensureGeneration() => $_ensure(11);

  @$pb.TagNumber(13)
  $core.int get maxContextTokens => $_getIZ(12);
  @$pb.TagNumber(13)
  set maxContextTokens($core.int value) => $_setSignedInt32(12, value);
  @$pb.TagNumber(13)
  $core.bool hasMaxContextTokens() => $_has(12);
  @$pb.TagNumber(13)
  void clearMaxContextTokens() => $_clearField(13);

  /// Emit partial transcripts as non-final user-said events.
  @$pb.TagNumber(14)
  $core.bool get emitPartials => $_getBF(13);
  @$pb.TagNumber(14)
  set emitPartials($core.bool value) => $_setBool(13, value);
  @$pb.TagNumber(14)
  $core.bool hasEmitPartials() => $_has(13);
  @$pb.TagNumber(14)
  void clearEmitPartials() => $_clearField(14);
}

class RAGConfig extends $pb.GeneratedMessage {
  factory RAGConfig({
    $core.String? embedModelId,
    $core.String? rerankModelId,
    $core.String? llmModelId,
    VectorStore? vectorStore,
    $core.String? vectorStorePath,
    $core.int? retrieveK,
    $core.int? rerankTop,
    $core.double? bm25K1,
    $core.double? bm25B,
    $core.int? rrfK,
    $core.String? promptTemplate,
  }) {
    final result = create();
    if (embedModelId != null) result.embedModelId = embedModelId;
    if (rerankModelId != null) result.rerankModelId = rerankModelId;
    if (llmModelId != null) result.llmModelId = llmModelId;
    if (vectorStore != null) result.vectorStore = vectorStore;
    if (vectorStorePath != null) result.vectorStorePath = vectorStorePath;
    if (retrieveK != null) result.retrieveK = retrieveK;
    if (rerankTop != null) result.rerankTop = rerankTop;
    if (bm25K1 != null) result.bm25K1 = bm25K1;
    if (bm25B != null) result.bm25B = bm25B;
    if (rrfK != null) result.rrfK = rrfK;
    if (promptTemplate != null) result.promptTemplate = promptTemplate;
    return result;
  }

  RAGConfig._();

  factory RAGConfig.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory RAGConfig.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'RAGConfig',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'embedModelId')
    ..aOS(2, _omitFieldNames ? '' : 'rerankModelId')
    ..aOS(3, _omitFieldNames ? '' : 'llmModelId')
    ..aE<VectorStore>(4, _omitFieldNames ? '' : 'vectorStore',
        enumValues: VectorStore.values)
    ..aOS(5, _omitFieldNames ? '' : 'vectorStorePath')
    ..aI(6, _omitFieldNames ? '' : 'retrieveK')
    ..aI(7, _omitFieldNames ? '' : 'rerankTop')
    ..aD(8, _omitFieldNames ? '' : 'bm25K1', fieldType: $pb.PbFieldType.OF)
    ..aD(9, _omitFieldNames ? '' : 'bm25B', fieldType: $pb.PbFieldType.OF)
    ..aI(10, _omitFieldNames ? '' : 'rrfK')
    ..aOS(11, _omitFieldNames ? '' : 'promptTemplate')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGConfig clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  RAGConfig copyWith(void Function(RAGConfig) updates) =>
      super.copyWith((message) => updates(message as RAGConfig)) as RAGConfig;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGConfig create() => RAGConfig._();
  @$core.override
  RAGConfig createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static RAGConfig getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RAGConfig>(create);
  static RAGConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get embedModelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set embedModelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasEmbedModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearEmbedModelId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get rerankModelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set rerankModelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasRerankModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearRerankModelId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get llmModelId => $_getSZ(2);
  @$pb.TagNumber(3)
  set llmModelId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasLlmModelId() => $_has(2);
  @$pb.TagNumber(3)
  void clearLlmModelId() => $_clearField(3);

  @$pb.TagNumber(4)
  VectorStore get vectorStore => $_getN(3);
  @$pb.TagNumber(4)
  set vectorStore(VectorStore value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasVectorStore() => $_has(3);
  @$pb.TagNumber(4)
  void clearVectorStore() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get vectorStorePath => $_getSZ(4);
  @$pb.TagNumber(5)
  set vectorStorePath($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasVectorStorePath() => $_has(4);
  @$pb.TagNumber(5)
  void clearVectorStorePath() => $_clearField(5);

  /// Retrieve this many candidates, then keep this many after reranking.
  @$pb.TagNumber(6)
  $core.int get retrieveK => $_getIZ(5);
  @$pb.TagNumber(6)
  set retrieveK($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasRetrieveK() => $_has(5);
  @$pb.TagNumber(6)
  void clearRetrieveK() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.int get rerankTop => $_getIZ(6);
  @$pb.TagNumber(7)
  set rerankTop($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasRerankTop() => $_has(6);
  @$pb.TagNumber(7)
  void clearRerankTop() => $_clearField(7);

  /// BM25 term-saturation and length-normalization parameters.
  @$pb.TagNumber(8)
  $core.double get bm25K1 => $_getN(7);
  @$pb.TagNumber(8)
  set bm25K1($core.double value) => $_setFloat(7, value);
  @$pb.TagNumber(8)
  $core.bool hasBm25K1() => $_has(7);
  @$pb.TagNumber(8)
  void clearBm25K1() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.double get bm25B => $_getN(8);
  @$pb.TagNumber(9)
  set bm25B($core.double value) => $_setFloat(8, value);
  @$pb.TagNumber(9)
  $core.bool hasBm25B() => $_has(8);
  @$pb.TagNumber(9)
  void clearBm25B() => $_clearField(9);

  /// Reciprocal-rank-fusion smoothing constant.
  @$pb.TagNumber(10)
  $core.int get rrfK => $_getIZ(9);
  @$pb.TagNumber(10)
  set rrfK($core.int value) => $_setSignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasRrfK() => $_has(9);
  @$pb.TagNumber(10)
  void clearRrfK() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get promptTemplate => $_getSZ(10);
  @$pb.TagNumber(11)
  set promptTemplate($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasPromptTemplate() => $_has(10);
  @$pb.TagNumber(11)
  void clearPromptTemplate() => $_clearField(11);
}

class AgentLoopConfig extends $pb.GeneratedMessage {
  factory AgentLoopConfig({
    $core.String? llmModelId,
    $core.String? systemPrompt,
    $core.Iterable<ToolSpec>? tools,
    $core.int? maxIterations,
    $core.int? maxContextTokens,
  }) {
    final result = create();
    if (llmModelId != null) result.llmModelId = llmModelId;
    if (systemPrompt != null) result.systemPrompt = systemPrompt;
    if (tools != null) result.tools.addAll(tools);
    if (maxIterations != null) result.maxIterations = maxIterations;
    if (maxContextTokens != null) result.maxContextTokens = maxContextTokens;
    return result;
  }

  AgentLoopConfig._();

  factory AgentLoopConfig.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AgentLoopConfig.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AgentLoopConfig',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'llmModelId')
    ..aOS(2, _omitFieldNames ? '' : 'systemPrompt')
    ..pPM<ToolSpec>(3, _omitFieldNames ? '' : 'tools',
        subBuilder: ToolSpec.create)
    ..aI(4, _omitFieldNames ? '' : 'maxIterations')
    ..aI(5, _omitFieldNames ? '' : 'maxContextTokens')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AgentLoopConfig clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AgentLoopConfig copyWith(void Function(AgentLoopConfig) updates) =>
      super.copyWith((message) => updates(message as AgentLoopConfig))
          as AgentLoopConfig;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AgentLoopConfig create() => AgentLoopConfig._();
  @$core.override
  AgentLoopConfig createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AgentLoopConfig getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<AgentLoopConfig>(create);
  static AgentLoopConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get llmModelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set llmModelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLlmModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLlmModelId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get systemPrompt => $_getSZ(1);
  @$pb.TagNumber(2)
  set systemPrompt($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSystemPrompt() => $_has(1);
  @$pb.TagNumber(2)
  void clearSystemPrompt() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbList<ToolSpec> get tools => $_getList(2);

  @$pb.TagNumber(4)
  $core.int get maxIterations => $_getIZ(3);
  @$pb.TagNumber(4)
  set maxIterations($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasMaxIterations() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxIterations() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get maxContextTokens => $_getIZ(4);
  @$pb.TagNumber(5)
  set maxContextTokens($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMaxContextTokens() => $_has(4);
  @$pb.TagNumber(5)
  void clearMaxContextTokens() => $_clearField(5);
}

class ToolSpec extends $pb.GeneratedMessage {
  factory ToolSpec({
    $core.String? name,
    $core.String? description,
    $core.String? jsonSchema,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (description != null) result.description = description;
    if (jsonSchema != null) result.jsonSchema = jsonSchema;
    return result;
  }

  ToolSpec._();

  factory ToolSpec.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ToolSpec.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ToolSpec',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'description')
    ..aOS(3, _omitFieldNames ? '' : 'jsonSchema')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolSpec clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ToolSpec copyWith(void Function(ToolSpec) updates) =>
      super.copyWith((message) => updates(message as ToolSpec)) as ToolSpec;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolSpec create() => ToolSpec._();
  @$core.override
  ToolSpec createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ToolSpec getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolSpec>(create);
  static ToolSpec? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get description => $_getSZ(1);
  @$pb.TagNumber(2)
  set description($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDescription() => $_has(1);
  @$pb.TagNumber(2)
  void clearDescription() => $_clearField(2);

  /// OpenAI-compatible parameters schema.
  @$pb.TagNumber(3)
  $core.String get jsonSchema => $_getSZ(2);
  @$pb.TagNumber(3)
  set jsonSchema($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasJsonSchema() => $_has(2);
  @$pb.TagNumber(3)
  void clearJsonSchema() => $_clearField(3);
}

class TimeSeriesConfig extends $pb.GeneratedMessage {
  factory TimeSeriesConfig({
    $core.String? anomalyModelId,
    $core.String? llmModelId,
    $core.int? windowSize,
    $core.int? stride,
    $core.double? anomalyThreshold,
  }) {
    final result = create();
    if (anomalyModelId != null) result.anomalyModelId = anomalyModelId;
    if (llmModelId != null) result.llmModelId = llmModelId;
    if (windowSize != null) result.windowSize = windowSize;
    if (stride != null) result.stride = stride;
    if (anomalyThreshold != null) result.anomalyThreshold = anomalyThreshold;
    return result;
  }

  TimeSeriesConfig._();

  factory TimeSeriesConfig.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TimeSeriesConfig.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TimeSeriesConfig',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'anomalyModelId')
    ..aOS(2, _omitFieldNames ? '' : 'llmModelId')
    ..aI(3, _omitFieldNames ? '' : 'windowSize')
    ..aI(4, _omitFieldNames ? '' : 'stride')
    ..aD(5, _omitFieldNames ? '' : 'anomalyThreshold',
        fieldType: $pb.PbFieldType.OF)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TimeSeriesConfig clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TimeSeriesConfig copyWith(void Function(TimeSeriesConfig) updates) =>
      super.copyWith((message) => updates(message as TimeSeriesConfig))
          as TimeSeriesConfig;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TimeSeriesConfig create() => TimeSeriesConfig._();
  @$core.override
  TimeSeriesConfig createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TimeSeriesConfig getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TimeSeriesConfig>(create);
  static TimeSeriesConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get anomalyModelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set anomalyModelId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAnomalyModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAnomalyModelId() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get llmModelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set llmModelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasLlmModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearLlmModelId() => $_clearField(2);

  /// Samples per window, and how far the window advances each step.
  @$pb.TagNumber(3)
  $core.int get windowSize => $_getIZ(2);
  @$pb.TagNumber(3)
  set windowSize($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasWindowSize() => $_has(2);
  @$pb.TagNumber(3)
  void clearWindowSize() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get stride => $_getIZ(3);
  @$pb.TagNumber(4)
  set stride($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasStride() => $_has(3);
  @$pb.TagNumber(4)
  void clearStride() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.double get anomalyThreshold => $_getN(4);
  @$pb.TagNumber(5)
  set anomalyThreshold($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAnomalyThreshold() => $_has(4);
  @$pb.TagNumber(5)
  void clearAnomalyThreshold() => $_clearField(5);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
