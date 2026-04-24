//
//  Generated code. Do not modify.
//  source: solutions.proto
//
// @dart = 2.12

// ignore_for_file: always_use_package_imports
// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'solutions.pbenum.dart';

export 'solutions.pbenum.dart';

enum SolutionConfig_Config {
  voiceAgent, 
  rag, 
  wakeWord, 
  agentLoop, 
  timeSeries, 
  notSet
}

/// Top-level union dispatched to the matching solution loader.
class SolutionConfig extends $pb.GeneratedMessage {
  factory SolutionConfig({
    VoiceAgentConfig? voiceAgent,
    RAGConfig? rag,
    WakeWordConfig? wakeWord,
    AgentLoopConfig? agentLoop,
    TimeSeriesConfig? timeSeries,
  }) {
    final $result = create();
    if (voiceAgent != null) {
      $result.voiceAgent = voiceAgent;
    }
    if (rag != null) {
      $result.rag = rag;
    }
    if (wakeWord != null) {
      $result.wakeWord = wakeWord;
    }
    if (agentLoop != null) {
      $result.agentLoop = agentLoop;
    }
    if (timeSeries != null) {
      $result.timeSeries = timeSeries;
    }
    return $result;
  }
  SolutionConfig._() : super();
  factory SolutionConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SolutionConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static const $core.Map<$core.int, SolutionConfig_Config> _SolutionConfig_ConfigByTag = {
    1 : SolutionConfig_Config.voiceAgent,
    2 : SolutionConfig_Config.rag,
    3 : SolutionConfig_Config.wakeWord,
    4 : SolutionConfig_Config.agentLoop,
    5 : SolutionConfig_Config.timeSeries,
    0 : SolutionConfig_Config.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'SolutionConfig', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..oo(0, [1, 2, 3, 4, 5])
    ..aOM<VoiceAgentConfig>(1, _omitFieldNames ? '' : 'voiceAgent', subBuilder: VoiceAgentConfig.create)
    ..aOM<RAGConfig>(2, _omitFieldNames ? '' : 'rag', subBuilder: RAGConfig.create)
    ..aOM<WakeWordConfig>(3, _omitFieldNames ? '' : 'wakeWord', subBuilder: WakeWordConfig.create)
    ..aOM<AgentLoopConfig>(4, _omitFieldNames ? '' : 'agentLoop', subBuilder: AgentLoopConfig.create)
    ..aOM<TimeSeriesConfig>(5, _omitFieldNames ? '' : 'timeSeries', subBuilder: TimeSeriesConfig.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SolutionConfig clone() => SolutionConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SolutionConfig copyWith(void Function(SolutionConfig) updates) => super.copyWith((message) => updates(message as SolutionConfig)) as SolutionConfig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SolutionConfig create() => SolutionConfig._();
  SolutionConfig createEmptyInstance() => create();
  static $pb.PbList<SolutionConfig> createRepeated() => $pb.PbList<SolutionConfig>();
  @$core.pragma('dart2js:noInline')
  static SolutionConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SolutionConfig>(create);
  static SolutionConfig? _defaultInstance;

  SolutionConfig_Config whichConfig() => _SolutionConfig_ConfigByTag[$_whichOneof(0)]!;
  void clearConfig() => clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  VoiceAgentConfig get voiceAgent => $_getN(0);
  @$pb.TagNumber(1)
  set voiceAgent(VoiceAgentConfig v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasVoiceAgent() => $_has(0);
  @$pb.TagNumber(1)
  void clearVoiceAgent() => clearField(1);
  @$pb.TagNumber(1)
  VoiceAgentConfig ensureVoiceAgent() => $_ensure(0);

  @$pb.TagNumber(2)
  RAGConfig get rag => $_getN(1);
  @$pb.TagNumber(2)
  set rag(RAGConfig v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasRag() => $_has(1);
  @$pb.TagNumber(2)
  void clearRag() => clearField(2);
  @$pb.TagNumber(2)
  RAGConfig ensureRag() => $_ensure(1);

  @$pb.TagNumber(3)
  WakeWordConfig get wakeWord => $_getN(2);
  @$pb.TagNumber(3)
  set wakeWord(WakeWordConfig v) { setField(3, v); }
  @$pb.TagNumber(3)
  $core.bool hasWakeWord() => $_has(2);
  @$pb.TagNumber(3)
  void clearWakeWord() => clearField(3);
  @$pb.TagNumber(3)
  WakeWordConfig ensureWakeWord() => $_ensure(2);

  @$pb.TagNumber(4)
  AgentLoopConfig get agentLoop => $_getN(3);
  @$pb.TagNumber(4)
  set agentLoop(AgentLoopConfig v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasAgentLoop() => $_has(3);
  @$pb.TagNumber(4)
  void clearAgentLoop() => clearField(4);
  @$pb.TagNumber(4)
  AgentLoopConfig ensureAgentLoop() => $_ensure(3);

  @$pb.TagNumber(5)
  TimeSeriesConfig get timeSeries => $_getN(4);
  @$pb.TagNumber(5)
  set timeSeries(TimeSeriesConfig v) { setField(5, v); }
  @$pb.TagNumber(5)
  $core.bool hasTimeSeries() => $_has(4);
  @$pb.TagNumber(5)
  void clearTimeSeries() => clearField(5);
  @$pb.TagNumber(5)
  TimeSeriesConfig ensureTimeSeries() => $_ensure(4);
}

/// ---------------------------------------------------------------------------
/// VoiceAgent — the canonical streaming voice AI loop.
/// ---------------------------------------------------------------------------
class VoiceAgentConfig extends $pb.GeneratedMessage {
  factory VoiceAgentConfig({
    $core.String? llmModelId,
    $core.String? sttModelId,
    $core.String? ttsModelId,
    $core.String? vadModelId,
    $core.int? sampleRateHz,
    $core.int? chunkMs,
    AudioSource? audioSource,
    $core.bool? enableBargeIn,
    $core.int? bargeInThresholdMs,
    $core.String? systemPrompt,
    $core.int? maxContextTokens,
    $core.double? temperature,
    $core.bool? emitPartials,
    $core.bool? emitThoughts,
    $core.String? audioFilePath,
  }) {
    final $result = create();
    if (llmModelId != null) {
      $result.llmModelId = llmModelId;
    }
    if (sttModelId != null) {
      $result.sttModelId = sttModelId;
    }
    if (ttsModelId != null) {
      $result.ttsModelId = ttsModelId;
    }
    if (vadModelId != null) {
      $result.vadModelId = vadModelId;
    }
    if (sampleRateHz != null) {
      $result.sampleRateHz = sampleRateHz;
    }
    if (chunkMs != null) {
      $result.chunkMs = chunkMs;
    }
    if (audioSource != null) {
      $result.audioSource = audioSource;
    }
    if (enableBargeIn != null) {
      $result.enableBargeIn = enableBargeIn;
    }
    if (bargeInThresholdMs != null) {
      $result.bargeInThresholdMs = bargeInThresholdMs;
    }
    if (systemPrompt != null) {
      $result.systemPrompt = systemPrompt;
    }
    if (maxContextTokens != null) {
      $result.maxContextTokens = maxContextTokens;
    }
    if (temperature != null) {
      $result.temperature = temperature;
    }
    if (emitPartials != null) {
      $result.emitPartials = emitPartials;
    }
    if (emitThoughts != null) {
      $result.emitThoughts = emitThoughts;
    }
    if (audioFilePath != null) {
      $result.audioFilePath = audioFilePath;
    }
    return $result;
  }
  VoiceAgentConfig._() : super();
  factory VoiceAgentConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory VoiceAgentConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'VoiceAgentConfig', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'llmModelId')
    ..aOS(2, _omitFieldNames ? '' : 'sttModelId')
    ..aOS(3, _omitFieldNames ? '' : 'ttsModelId')
    ..aOS(4, _omitFieldNames ? '' : 'vadModelId')
    ..a<$core.int>(5, _omitFieldNames ? '' : 'sampleRateHz', $pb.PbFieldType.O3)
    ..a<$core.int>(6, _omitFieldNames ? '' : 'chunkMs', $pb.PbFieldType.O3)
    ..e<AudioSource>(7, _omitFieldNames ? '' : 'audioSource', $pb.PbFieldType.OE, defaultOrMaker: AudioSource.AUDIO_SOURCE_UNSPECIFIED, valueOf: AudioSource.valueOf, enumValues: AudioSource.values)
    ..aOB(8, _omitFieldNames ? '' : 'enableBargeIn')
    ..a<$core.int>(9, _omitFieldNames ? '' : 'bargeInThresholdMs', $pb.PbFieldType.O3)
    ..aOS(10, _omitFieldNames ? '' : 'systemPrompt')
    ..a<$core.int>(11, _omitFieldNames ? '' : 'maxContextTokens', $pb.PbFieldType.O3)
    ..a<$core.double>(12, _omitFieldNames ? '' : 'temperature', $pb.PbFieldType.OF)
    ..aOB(13, _omitFieldNames ? '' : 'emitPartials')
    ..aOB(14, _omitFieldNames ? '' : 'emitThoughts')
    ..aOS(15, _omitFieldNames ? '' : 'audioFilePath')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  VoiceAgentConfig clone() => VoiceAgentConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  VoiceAgentConfig copyWith(void Function(VoiceAgentConfig) updates) => super.copyWith((message) => updates(message as VoiceAgentConfig)) as VoiceAgentConfig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoiceAgentConfig create() => VoiceAgentConfig._();
  VoiceAgentConfig createEmptyInstance() => create();
  static $pb.PbList<VoiceAgentConfig> createRepeated() => $pb.PbList<VoiceAgentConfig>();
  @$core.pragma('dart2js:noInline')
  static VoiceAgentConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<VoiceAgentConfig>(create);
  static VoiceAgentConfig? _defaultInstance;

  /// Model identifiers — resolved against the model registry.
  @$pb.TagNumber(1)
  $core.String get llmModelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set llmModelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasLlmModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLlmModelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get sttModelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sttModelId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSttModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSttModelId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get ttsModelId => $_getSZ(2);
  @$pb.TagNumber(3)
  set ttsModelId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasTtsModelId() => $_has(2);
  @$pb.TagNumber(3)
  void clearTtsModelId() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get vadModelId => $_getSZ(3);
  @$pb.TagNumber(4)
  set vadModelId($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasVadModelId() => $_has(3);
  @$pb.TagNumber(4)
  void clearVadModelId() => clearField(4);

  /// Audio configuration.
  @$pb.TagNumber(5)
  $core.int get sampleRateHz => $_getIZ(4);
  @$pb.TagNumber(5)
  set sampleRateHz($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSampleRateHz() => $_has(4);
  @$pb.TagNumber(5)
  void clearSampleRateHz() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get chunkMs => $_getIZ(5);
  @$pb.TagNumber(6)
  set chunkMs($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasChunkMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearChunkMs() => clearField(6);

  @$pb.TagNumber(7)
  AudioSource get audioSource => $_getN(6);
  @$pb.TagNumber(7)
  set audioSource(AudioSource v) { setField(7, v); }
  @$pb.TagNumber(7)
  $core.bool hasAudioSource() => $_has(6);
  @$pb.TagNumber(7)
  void clearAudioSource() => clearField(7);

  /// Barge-in behavior.
  @$pb.TagNumber(8)
  $core.bool get enableBargeIn => $_getBF(7);
  @$pb.TagNumber(8)
  set enableBargeIn($core.bool v) { $_setBool(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasEnableBargeIn() => $_has(7);
  @$pb.TagNumber(8)
  void clearEnableBargeIn() => clearField(8);

  @$pb.TagNumber(9)
  $core.int get bargeInThresholdMs => $_getIZ(8);
  @$pb.TagNumber(9)
  set bargeInThresholdMs($core.int v) { $_setSignedInt32(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasBargeInThresholdMs() => $_has(8);
  @$pb.TagNumber(9)
  void clearBargeInThresholdMs() => clearField(9);

  /// LLM behavior.
  @$pb.TagNumber(10)
  $core.String get systemPrompt => $_getSZ(9);
  @$pb.TagNumber(10)
  set systemPrompt($core.String v) { $_setString(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasSystemPrompt() => $_has(9);
  @$pb.TagNumber(10)
  void clearSystemPrompt() => clearField(10);

  @$pb.TagNumber(11)
  $core.int get maxContextTokens => $_getIZ(10);
  @$pb.TagNumber(11)
  set maxContextTokens($core.int v) { $_setSignedInt32(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasMaxContextTokens() => $_has(10);
  @$pb.TagNumber(11)
  void clearMaxContextTokens() => clearField(11);

  @$pb.TagNumber(12)
  $core.double get temperature => $_getN(11);
  @$pb.TagNumber(12)
  set temperature($core.double v) { $_setFloat(11, v); }
  @$pb.TagNumber(12)
  $core.bool hasTemperature() => $_has(11);
  @$pb.TagNumber(12)
  void clearTemperature() => clearField(12);

  /// Emit partial transcripts as UserSaidEvent{is_final=false}.
  @$pb.TagNumber(13)
  $core.bool get emitPartials => $_getBF(12);
  @$pb.TagNumber(13)
  set emitPartials($core.bool v) { $_setBool(12, v); }
  @$pb.TagNumber(13)
  $core.bool hasEmitPartials() => $_has(12);
  @$pb.TagNumber(13)
  void clearEmitPartials() => clearField(13);

  /// Emit thought tokens (qwen3, deepseek-r1) separately from answer tokens.
  @$pb.TagNumber(14)
  $core.bool get emitThoughts => $_getBF(13);
  @$pb.TagNumber(14)
  set emitThoughts($core.bool v) { $_setBool(13, v); }
  @$pb.TagNumber(14)
  $core.bool hasEmitThoughts() => $_has(13);
  @$pb.TagNumber(14)
  void clearEmitThoughts() => clearField(14);

  /// Absolute path to an audio file. Required when `audio_source` is
  /// `AUDIO_SOURCE_FILE`; ignored for MICROPHONE / CALLBACK sources.
  @$pb.TagNumber(15)
  $core.String get audioFilePath => $_getSZ(14);
  @$pb.TagNumber(15)
  set audioFilePath($core.String v) { $_setString(14, v); }
  @$pb.TagNumber(15)
  $core.bool hasAudioFilePath() => $_has(14);
  @$pb.TagNumber(15)
  void clearAudioFilePath() => clearField(15);
}

/// ---------------------------------------------------------------------------
/// RAG — retrieve → rerank → prompt → LLM.
/// ---------------------------------------------------------------------------
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
    final $result = create();
    if (embedModelId != null) {
      $result.embedModelId = embedModelId;
    }
    if (rerankModelId != null) {
      $result.rerankModelId = rerankModelId;
    }
    if (llmModelId != null) {
      $result.llmModelId = llmModelId;
    }
    if (vectorStore != null) {
      $result.vectorStore = vectorStore;
    }
    if (vectorStorePath != null) {
      $result.vectorStorePath = vectorStorePath;
    }
    if (retrieveK != null) {
      $result.retrieveK = retrieveK;
    }
    if (rerankTop != null) {
      $result.rerankTop = rerankTop;
    }
    if (bm25K1 != null) {
      $result.bm25K1 = bm25K1;
    }
    if (bm25B != null) {
      $result.bm25B = bm25B;
    }
    if (rrfK != null) {
      $result.rrfK = rrfK;
    }
    if (promptTemplate != null) {
      $result.promptTemplate = promptTemplate;
    }
    return $result;
  }
  RAGConfig._() : super();
  factory RAGConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory RAGConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'RAGConfig', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'embedModelId')
    ..aOS(2, _omitFieldNames ? '' : 'rerankModelId')
    ..aOS(3, _omitFieldNames ? '' : 'llmModelId')
    ..e<VectorStore>(4, _omitFieldNames ? '' : 'vectorStore', $pb.PbFieldType.OE, defaultOrMaker: VectorStore.VECTOR_STORE_UNSPECIFIED, valueOf: VectorStore.valueOf, enumValues: VectorStore.values)
    ..aOS(5, _omitFieldNames ? '' : 'vectorStorePath')
    ..a<$core.int>(6, _omitFieldNames ? '' : 'retrieveK', $pb.PbFieldType.O3)
    ..a<$core.int>(7, _omitFieldNames ? '' : 'rerankTop', $pb.PbFieldType.O3)
    ..a<$core.double>(8, _omitFieldNames ? '' : 'bm25K1', $pb.PbFieldType.OF)
    ..a<$core.double>(9, _omitFieldNames ? '' : 'bm25B', $pb.PbFieldType.OF)
    ..a<$core.int>(10, _omitFieldNames ? '' : 'rrfK', $pb.PbFieldType.O3)
    ..aOS(11, _omitFieldNames ? '' : 'promptTemplate')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  RAGConfig clone() => RAGConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  RAGConfig copyWith(void Function(RAGConfig) updates) => super.copyWith((message) => updates(message as RAGConfig)) as RAGConfig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static RAGConfig create() => RAGConfig._();
  RAGConfig createEmptyInstance() => create();
  static $pb.PbList<RAGConfig> createRepeated() => $pb.PbList<RAGConfig>();
  @$core.pragma('dart2js:noInline')
  static RAGConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<RAGConfig>(create);
  static RAGConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get embedModelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set embedModelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasEmbedModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearEmbedModelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get rerankModelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set rerankModelId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasRerankModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearRerankModelId() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get llmModelId => $_getSZ(2);
  @$pb.TagNumber(3)
  set llmModelId($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasLlmModelId() => $_has(2);
  @$pb.TagNumber(3)
  void clearLlmModelId() => clearField(3);

  /// Vector store — USearch (in-process HNSW, default) or remote pgvector.
  @$pb.TagNumber(4)
  VectorStore get vectorStore => $_getN(3);
  @$pb.TagNumber(4)
  set vectorStore(VectorStore v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasVectorStore() => $_has(3);
  @$pb.TagNumber(4)
  void clearVectorStore() => clearField(4);

  @$pb.TagNumber(5)
  $core.String get vectorStorePath => $_getSZ(4);
  @$pb.TagNumber(5)
  set vectorStorePath($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasVectorStorePath() => $_has(4);
  @$pb.TagNumber(5)
  void clearVectorStorePath() => clearField(5);

  @$pb.TagNumber(6)
  $core.int get retrieveK => $_getIZ(5);
  @$pb.TagNumber(6)
  set retrieveK($core.int v) { $_setSignedInt32(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasRetrieveK() => $_has(5);
  @$pb.TagNumber(6)
  void clearRetrieveK() => clearField(6);

  @$pb.TagNumber(7)
  $core.int get rerankTop => $_getIZ(6);
  @$pb.TagNumber(7)
  set rerankTop($core.int v) { $_setSignedInt32(6, v); }
  @$pb.TagNumber(7)
  $core.bool hasRerankTop() => $_has(6);
  @$pb.TagNumber(7)
  void clearRerankTop() => clearField(7);

  /// BM25 parameters.
  @$pb.TagNumber(8)
  $core.double get bm25K1 => $_getN(7);
  @$pb.TagNumber(8)
  set bm25K1($core.double v) { $_setFloat(7, v); }
  @$pb.TagNumber(8)
  $core.bool hasBm25K1() => $_has(7);
  @$pb.TagNumber(8)
  void clearBm25K1() => clearField(8);

  @$pb.TagNumber(9)
  $core.double get bm25B => $_getN(8);
  @$pb.TagNumber(9)
  set bm25B($core.double v) { $_setFloat(8, v); }
  @$pb.TagNumber(9)
  $core.bool hasBm25B() => $_has(8);
  @$pb.TagNumber(9)
  void clearBm25B() => clearField(9);

  /// RRF fusion parameter.
  @$pb.TagNumber(10)
  $core.int get rrfK => $_getIZ(9);
  @$pb.TagNumber(10)
  set rrfK($core.int v) { $_setSignedInt32(9, v); }
  @$pb.TagNumber(10)
  $core.bool hasRrfK() => $_has(9);
  @$pb.TagNumber(10)
  void clearRrfK() => clearField(10);

  /// Prompt template. Supports {{context}} and {{query}} placeholders.
  @$pb.TagNumber(11)
  $core.String get promptTemplate => $_getSZ(10);
  @$pb.TagNumber(11)
  set promptTemplate($core.String v) { $_setString(10, v); }
  @$pb.TagNumber(11)
  $core.bool hasPromptTemplate() => $_has(10);
  @$pb.TagNumber(11)
  void clearPromptTemplate() => clearField(11);
}

/// ---------------------------------------------------------------------------
/// Wake word — always-on listener that emits a pulse on keyword detection.
/// ---------------------------------------------------------------------------
class WakeWordConfig extends $pb.GeneratedMessage {
  factory WakeWordConfig({
    $core.String? modelId,
    $core.String? keyword,
    $core.double? threshold,
    $core.int? preRollMs,
    $core.int? sampleRateHz,
  }) {
    final $result = create();
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (keyword != null) {
      $result.keyword = keyword;
    }
    if (threshold != null) {
      $result.threshold = threshold;
    }
    if (preRollMs != null) {
      $result.preRollMs = preRollMs;
    }
    if (sampleRateHz != null) {
      $result.sampleRateHz = sampleRateHz;
    }
    return $result;
  }
  WakeWordConfig._() : super();
  factory WakeWordConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory WakeWordConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'WakeWordConfig', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'modelId')
    ..aOS(2, _omitFieldNames ? '' : 'keyword')
    ..a<$core.double>(3, _omitFieldNames ? '' : 'threshold', $pb.PbFieldType.OF)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'preRollMs', $pb.PbFieldType.O3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'sampleRateHz', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  WakeWordConfig clone() => WakeWordConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  WakeWordConfig copyWith(void Function(WakeWordConfig) updates) => super.copyWith((message) => updates(message as WakeWordConfig)) as WakeWordConfig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static WakeWordConfig create() => WakeWordConfig._();
  WakeWordConfig createEmptyInstance() => create();
  static $pb.PbList<WakeWordConfig> createRepeated() => $pb.PbList<WakeWordConfig>();
  @$core.pragma('dart2js:noInline')
  static WakeWordConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<WakeWordConfig>(create);
  static WakeWordConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get modelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set modelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearModelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get keyword => $_getSZ(1);
  @$pb.TagNumber(2)
  set keyword($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasKeyword() => $_has(1);
  @$pb.TagNumber(2)
  void clearKeyword() => clearField(2);

  @$pb.TagNumber(3)
  $core.double get threshold => $_getN(2);
  @$pb.TagNumber(3)
  set threshold($core.double v) { $_setFloat(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasThreshold() => $_has(2);
  @$pb.TagNumber(3)
  void clearThreshold() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get preRollMs => $_getIZ(3);
  @$pb.TagNumber(4)
  set preRollMs($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasPreRollMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearPreRollMs() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get sampleRateHz => $_getIZ(4);
  @$pb.TagNumber(5)
  set sampleRateHz($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasSampleRateHz() => $_has(4);
  @$pb.TagNumber(5)
  void clearSampleRateHz() => clearField(5);
}

/// ---------------------------------------------------------------------------
/// Agent loop — multi-turn LLM with tool calling.
/// ---------------------------------------------------------------------------
class AgentLoopConfig extends $pb.GeneratedMessage {
  factory AgentLoopConfig({
    $core.String? llmModelId,
    $core.String? systemPrompt,
    $core.Iterable<ToolSpec>? tools,
    $core.int? maxIterations,
    $core.int? maxContextTokens,
  }) {
    final $result = create();
    if (llmModelId != null) {
      $result.llmModelId = llmModelId;
    }
    if (systemPrompt != null) {
      $result.systemPrompt = systemPrompt;
    }
    if (tools != null) {
      $result.tools.addAll(tools);
    }
    if (maxIterations != null) {
      $result.maxIterations = maxIterations;
    }
    if (maxContextTokens != null) {
      $result.maxContextTokens = maxContextTokens;
    }
    return $result;
  }
  AgentLoopConfig._() : super();
  factory AgentLoopConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory AgentLoopConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'AgentLoopConfig', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'llmModelId')
    ..aOS(2, _omitFieldNames ? '' : 'systemPrompt')
    ..pc<ToolSpec>(3, _omitFieldNames ? '' : 'tools', $pb.PbFieldType.PM, subBuilder: ToolSpec.create)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'maxIterations', $pb.PbFieldType.O3)
    ..a<$core.int>(5, _omitFieldNames ? '' : 'maxContextTokens', $pb.PbFieldType.O3)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  AgentLoopConfig clone() => AgentLoopConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  AgentLoopConfig copyWith(void Function(AgentLoopConfig) updates) => super.copyWith((message) => updates(message as AgentLoopConfig)) as AgentLoopConfig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AgentLoopConfig create() => AgentLoopConfig._();
  AgentLoopConfig createEmptyInstance() => create();
  static $pb.PbList<AgentLoopConfig> createRepeated() => $pb.PbList<AgentLoopConfig>();
  @$core.pragma('dart2js:noInline')
  static AgentLoopConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AgentLoopConfig>(create);
  static AgentLoopConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get llmModelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set llmModelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasLlmModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearLlmModelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get systemPrompt => $_getSZ(1);
  @$pb.TagNumber(2)
  set systemPrompt($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSystemPrompt() => $_has(1);
  @$pb.TagNumber(2)
  void clearSystemPrompt() => clearField(2);

  @$pb.TagNumber(3)
  $core.List<ToolSpec> get tools => $_getList(2);

  @$pb.TagNumber(4)
  $core.int get maxIterations => $_getIZ(3);
  @$pb.TagNumber(4)
  set maxIterations($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasMaxIterations() => $_has(3);
  @$pb.TagNumber(4)
  void clearMaxIterations() => clearField(4);

  @$pb.TagNumber(5)
  $core.int get maxContextTokens => $_getIZ(4);
  @$pb.TagNumber(5)
  set maxContextTokens($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasMaxContextTokens() => $_has(4);
  @$pb.TagNumber(5)
  void clearMaxContextTokens() => clearField(5);
}

class ToolSpec extends $pb.GeneratedMessage {
  factory ToolSpec({
    $core.String? name,
    $core.String? description,
    $core.String? jsonSchema,
  }) {
    final $result = create();
    if (name != null) {
      $result.name = name;
    }
    if (description != null) {
      $result.description = description;
    }
    if (jsonSchema != null) {
      $result.jsonSchema = jsonSchema;
    }
    return $result;
  }
  ToolSpec._() : super();
  factory ToolSpec.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ToolSpec.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ToolSpec', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'description')
    ..aOS(3, _omitFieldNames ? '' : 'jsonSchema')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ToolSpec clone() => ToolSpec()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ToolSpec copyWith(void Function(ToolSpec) updates) => super.copyWith((message) => updates(message as ToolSpec)) as ToolSpec;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ToolSpec create() => ToolSpec._();
  ToolSpec createEmptyInstance() => create();
  static $pb.PbList<ToolSpec> createRepeated() => $pb.PbList<ToolSpec>();
  @$core.pragma('dart2js:noInline')
  static ToolSpec getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ToolSpec>(create);
  static ToolSpec? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get description => $_getSZ(1);
  @$pb.TagNumber(2)
  set description($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasDescription() => $_has(1);
  @$pb.TagNumber(2)
  void clearDescription() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get jsonSchema => $_getSZ(2);
  @$pb.TagNumber(3)
  set jsonSchema($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasJsonSchema() => $_has(2);
  @$pb.TagNumber(3)
  void clearJsonSchema() => clearField(3);
}

/// ---------------------------------------------------------------------------
/// Time series — window + anomaly_detect + generate_text.
/// ---------------------------------------------------------------------------
class TimeSeriesConfig extends $pb.GeneratedMessage {
  factory TimeSeriesConfig({
    $core.String? anomalyModelId,
    $core.String? llmModelId,
    $core.int? windowSize,
    $core.int? stride,
    $core.double? anomalyThreshold,
  }) {
    final $result = create();
    if (anomalyModelId != null) {
      $result.anomalyModelId = anomalyModelId;
    }
    if (llmModelId != null) {
      $result.llmModelId = llmModelId;
    }
    if (windowSize != null) {
      $result.windowSize = windowSize;
    }
    if (stride != null) {
      $result.stride = stride;
    }
    if (anomalyThreshold != null) {
      $result.anomalyThreshold = anomalyThreshold;
    }
    return $result;
  }
  TimeSeriesConfig._() : super();
  factory TimeSeriesConfig.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory TimeSeriesConfig.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'TimeSeriesConfig', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'anomalyModelId')
    ..aOS(2, _omitFieldNames ? '' : 'llmModelId')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'windowSize', $pb.PbFieldType.O3)
    ..a<$core.int>(4, _omitFieldNames ? '' : 'stride', $pb.PbFieldType.O3)
    ..a<$core.double>(5, _omitFieldNames ? '' : 'anomalyThreshold', $pb.PbFieldType.OF)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  TimeSeriesConfig clone() => TimeSeriesConfig()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  TimeSeriesConfig copyWith(void Function(TimeSeriesConfig) updates) => super.copyWith((message) => updates(message as TimeSeriesConfig)) as TimeSeriesConfig;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TimeSeriesConfig create() => TimeSeriesConfig._();
  TimeSeriesConfig createEmptyInstance() => create();
  static $pb.PbList<TimeSeriesConfig> createRepeated() => $pb.PbList<TimeSeriesConfig>();
  @$core.pragma('dart2js:noInline')
  static TimeSeriesConfig getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<TimeSeriesConfig>(create);
  static TimeSeriesConfig? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get anomalyModelId => $_getSZ(0);
  @$pb.TagNumber(1)
  set anomalyModelId($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasAnomalyModelId() => $_has(0);
  @$pb.TagNumber(1)
  void clearAnomalyModelId() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get llmModelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set llmModelId($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasLlmModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearLlmModelId() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get windowSize => $_getIZ(2);
  @$pb.TagNumber(3)
  set windowSize($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasWindowSize() => $_has(2);
  @$pb.TagNumber(3)
  void clearWindowSize() => clearField(3);

  @$pb.TagNumber(4)
  $core.int get stride => $_getIZ(3);
  @$pb.TagNumber(4)
  set stride($core.int v) { $_setSignedInt32(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasStride() => $_has(3);
  @$pb.TagNumber(4)
  void clearStride() => clearField(4);

  @$pb.TagNumber(5)
  $core.double get anomalyThreshold => $_getN(4);
  @$pb.TagNumber(5)
  set anomalyThreshold($core.double v) { $_setFloat(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasAnomalyThreshold() => $_has(4);
  @$pb.TagNumber(5)
  void clearAnomalyThreshold() => clearField(5);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
