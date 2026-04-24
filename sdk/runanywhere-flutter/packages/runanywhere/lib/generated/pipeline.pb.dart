//
//  Generated code. Do not modify.
//  source: pipeline.proto
//
// @dart = 2.12

// ignore_for_file: always_use_package_imports
// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'pipeline.pbenum.dart';

export 'pipeline.pbenum.dart';

/// A pipeline is a labelled DAG of operators connected by typed edges. There
/// are no cycles. Every input edge has a resolvable producer; every output
/// edge has at least one consumer.
class PipelineSpec extends $pb.GeneratedMessage {
  factory PipelineSpec({
    $core.String? name,
    $core.Iterable<OperatorSpec>? operators,
    $core.Iterable<EdgeSpec>? edges,
    PipelineOptions? options,
  }) {
    final $result = create();
    if (name != null) {
      $result.name = name;
    }
    if (operators != null) {
      $result.operators.addAll(operators);
    }
    if (edges != null) {
      $result.edges.addAll(edges);
    }
    if (options != null) {
      $result.options = options;
    }
    return $result;
  }
  PipelineSpec._() : super();
  factory PipelineSpec.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PipelineSpec.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PipelineSpec', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..pc<OperatorSpec>(2, _omitFieldNames ? '' : 'operators', $pb.PbFieldType.PM, subBuilder: OperatorSpec.create)
    ..pc<EdgeSpec>(3, _omitFieldNames ? '' : 'edges', $pb.PbFieldType.PM, subBuilder: EdgeSpec.create)
    ..aOM<PipelineOptions>(4, _omitFieldNames ? '' : 'options', subBuilder: PipelineOptions.create)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PipelineSpec clone() => PipelineSpec()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PipelineSpec copyWith(void Function(PipelineSpec) updates) => super.copyWith((message) => updates(message as PipelineSpec)) as PipelineSpec;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PipelineSpec create() => PipelineSpec._();
  PipelineSpec createEmptyInstance() => create();
  static $pb.PbList<PipelineSpec> createRepeated() => $pb.PbList<PipelineSpec>();
  @$core.pragma('dart2js:noInline')
  static PipelineSpec getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PipelineSpec>(create);
  static PipelineSpec? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  @$pb.TagNumber(2)
  $core.List<OperatorSpec> get operators => $_getList(1);

  @$pb.TagNumber(3)
  $core.List<EdgeSpec> get edges => $_getList(2);

  @$pb.TagNumber(4)
  PipelineOptions get options => $_getN(3);
  @$pb.TagNumber(4)
  set options(PipelineOptions v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasOptions() => $_has(3);
  @$pb.TagNumber(4)
  void clearOptions() => clearField(4);
  @$pb.TagNumber(4)
  PipelineOptions ensureOptions() => $_ensure(3);
}

class OperatorSpec extends $pb.GeneratedMessage {
  factory OperatorSpec({
    $core.String? name,
    $core.String? type,
    $core.Map<$core.String, $core.String>? params,
    $core.String? pinnedEngine,
    $core.String? modelId,
    DeviceAffinity? device,
  }) {
    final $result = create();
    if (name != null) {
      $result.name = name;
    }
    if (type != null) {
      $result.type = type;
    }
    if (params != null) {
      $result.params.addAll(params);
    }
    if (pinnedEngine != null) {
      $result.pinnedEngine = pinnedEngine;
    }
    if (modelId != null) {
      $result.modelId = modelId;
    }
    if (device != null) {
      $result.device = device;
    }
    return $result;
  }
  OperatorSpec._() : super();
  factory OperatorSpec.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory OperatorSpec.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'OperatorSpec', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'type')
    ..m<$core.String, $core.String>(3, _omitFieldNames ? '' : 'params', entryClassName: 'OperatorSpec.ParamsEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('runanywhere.v1'))
    ..aOS(4, _omitFieldNames ? '' : 'pinnedEngine')
    ..aOS(5, _omitFieldNames ? '' : 'modelId')
    ..e<DeviceAffinity>(6, _omitFieldNames ? '' : 'device', $pb.PbFieldType.OE, defaultOrMaker: DeviceAffinity.DEVICE_AFFINITY_UNSPECIFIED, valueOf: DeviceAffinity.valueOf, enumValues: DeviceAffinity.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  OperatorSpec clone() => OperatorSpec()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  OperatorSpec copyWith(void Function(OperatorSpec) updates) => super.copyWith((message) => updates(message as OperatorSpec)) as OperatorSpec;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static OperatorSpec create() => OperatorSpec._();
  OperatorSpec createEmptyInstance() => create();
  static $pb.PbList<OperatorSpec> createRepeated() => $pb.PbList<OperatorSpec>();
  @$core.pragma('dart2js:noInline')
  static OperatorSpec getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<OperatorSpec>(create);
  static OperatorSpec? _defaultInstance;

  /// Unique within the spec, used as the prefix in edge endpoints like
  /// "stt.final" or "llm.token".
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => clearField(1);

  /// The primitive the operator implements: "generate_text", "transcribe",
  /// "synthesize", "detect_voice", "embed", "rerank", "tokenize", "window",
  /// or a solution-declared custom operator ("AudioSource", "AudioSink",
  /// "SentenceDetector", "VectorSearch", "ContextBuild").
  @$pb.TagNumber(2)
  $core.String get type => $_getSZ(1);
  @$pb.TagNumber(2)
  set type($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => clearField(2);

  /// Free-form parameters interpreted by the operator. The C++ loader
  /// validates required keys per type before instantiating.
  @$pb.TagNumber(3)
  $core.Map<$core.String, $core.String> get params => $_getMap(2);

  /// Optional override of the engine that will serve this operator. When
  /// empty, the L3 router picks based on capability + model format.
  @$pb.TagNumber(4)
  $core.String get pinnedEngine => $_getSZ(3);
  @$pb.TagNumber(4)
  set pinnedEngine($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasPinnedEngine() => $_has(3);
  @$pb.TagNumber(4)
  void clearPinnedEngine() => clearField(4);

  /// Optional model identifier (resolved against the model registry).
  @$pb.TagNumber(5)
  $core.String get modelId => $_getSZ(4);
  @$pb.TagNumber(5)
  set modelId($core.String v) { $_setString(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasModelId() => $_has(4);
  @$pb.TagNumber(5)
  void clearModelId() => clearField(5);

  /// Affinity hint: run this operator on CPU, GPU, or Neural Engine. The
  /// scheduler may override if the requested device is unavailable.
  @$pb.TagNumber(6)
  DeviceAffinity get device => $_getN(5);
  @$pb.TagNumber(6)
  set device(DeviceAffinity v) { setField(6, v); }
  @$pb.TagNumber(6)
  $core.bool hasDevice() => $_has(5);
  @$pb.TagNumber(6)
  void clearDevice() => clearField(6);
}

class EdgeSpec extends $pb.GeneratedMessage {
  factory EdgeSpec({
    $core.String? from,
    $core.String? to,
    $core.int? capacity,
    EdgePolicy? policy,
  }) {
    final $result = create();
    if (from != null) {
      $result.from = from;
    }
    if (to != null) {
      $result.to = to;
    }
    if (capacity != null) {
      $result.capacity = capacity;
    }
    if (policy != null) {
      $result.policy = policy;
    }
    return $result;
  }
  EdgeSpec._() : super();
  factory EdgeSpec.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory EdgeSpec.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'EdgeSpec', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'from')
    ..aOS(2, _omitFieldNames ? '' : 'to')
    ..a<$core.int>(3, _omitFieldNames ? '' : 'capacity', $pb.PbFieldType.OU3)
    ..e<EdgePolicy>(4, _omitFieldNames ? '' : 'policy', $pb.PbFieldType.OE, defaultOrMaker: EdgePolicy.EDGE_POLICY_UNSPECIFIED, valueOf: EdgePolicy.valueOf, enumValues: EdgePolicy.values)
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  EdgeSpec clone() => EdgeSpec()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  EdgeSpec copyWith(void Function(EdgeSpec) updates) => super.copyWith((message) => updates(message as EdgeSpec)) as EdgeSpec;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EdgeSpec create() => EdgeSpec._();
  EdgeSpec createEmptyInstance() => create();
  static $pb.PbList<EdgeSpec> createRepeated() => $pb.PbList<EdgeSpec>();
  @$core.pragma('dart2js:noInline')
  static EdgeSpec getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EdgeSpec>(create);
  static EdgeSpec? _defaultInstance;

  /// Endpoints are formatted "<operator_name>.<port_name>".
  /// Source port names are operator-specific output channels; sink port
  /// names are operator-specific input channels. Typing is enforced by the
  /// pipeline validator.
  @$pb.TagNumber(1)
  $core.String get from => $_getSZ(0);
  @$pb.TagNumber(1)
  set from($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasFrom() => $_has(0);
  @$pb.TagNumber(1)
  void clearFrom() => clearField(1);

  @$pb.TagNumber(2)
  $core.String get to => $_getSZ(1);
  @$pb.TagNumber(2)
  set to($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasTo() => $_has(1);
  @$pb.TagNumber(2)
  void clearTo() => clearField(2);

  /// Channel depth override. Proto3 scalars have no presence bit, so the
  /// sentinel value 0 means "use the per-edge default (16 for PCM, 256 for
  /// tokens, 32 for sentences)". uint32 keeps the wire representation
  /// identical to int32 on the happy path while making negative inputs
  /// statically unrepresentable.
  @$pb.TagNumber(3)
  $core.int get capacity => $_getIZ(2);
  @$pb.TagNumber(3)
  set capacity($core.int v) { $_setUnsignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasCapacity() => $_has(2);
  @$pb.TagNumber(3)
  void clearCapacity() => clearField(3);

  @$pb.TagNumber(4)
  EdgePolicy get policy => $_getN(3);
  @$pb.TagNumber(4)
  set policy(EdgePolicy v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasPolicy() => $_has(3);
  @$pb.TagNumber(4)
  void clearPolicy() => clearField(4);
}

class PipelineOptions extends $pb.GeneratedMessage {
  factory PipelineOptions({
    $core.int? latencyBudgetMs,
    $core.bool? emitMetrics,
    $core.bool? strictValidation,
  }) {
    final $result = create();
    if (latencyBudgetMs != null) {
      $result.latencyBudgetMs = latencyBudgetMs;
    }
    if (emitMetrics != null) {
      $result.emitMetrics = emitMetrics;
    }
    if (strictValidation != null) {
      $result.strictValidation = strictValidation;
    }
    return $result;
  }
  PipelineOptions._() : super();
  factory PipelineOptions.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory PipelineOptions.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'PipelineOptions', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..a<$core.int>(1, _omitFieldNames ? '' : 'latencyBudgetMs', $pb.PbFieldType.O3)
    ..aOB(2, _omitFieldNames ? '' : 'emitMetrics')
    ..aOB(3, _omitFieldNames ? '' : 'strictValidation')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  PipelineOptions clone() => PipelineOptions()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  PipelineOptions copyWith(void Function(PipelineOptions) updates) => super.copyWith((message) => updates(message as PipelineOptions)) as PipelineOptions;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PipelineOptions create() => PipelineOptions._();
  PipelineOptions createEmptyInstance() => create();
  static $pb.PbList<PipelineOptions> createRepeated() => $pb.PbList<PipelineOptions>();
  @$core.pragma('dart2js:noInline')
  static PipelineOptions getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<PipelineOptions>(create);
  static PipelineOptions? _defaultInstance;

  /// Maximum end-to-end latency budget in milliseconds. The pipeline emits
  /// a MetricsEvent with is_over_budget=true if exceeded.
  @$pb.TagNumber(1)
  $core.int get latencyBudgetMs => $_getIZ(0);
  @$pb.TagNumber(1)
  set latencyBudgetMs($core.int v) { $_setSignedInt32(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasLatencyBudgetMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearLatencyBudgetMs() => clearField(1);

  /// When true, the pipeline emits MetricsEvent on every VAD barge-in and
  /// on pipeline stop.
  @$pb.TagNumber(2)
  $core.bool get emitMetrics => $_getBF(1);
  @$pb.TagNumber(2)
  set emitMetrics($core.bool v) { $_setBool(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasEmitMetrics() => $_has(1);
  @$pb.TagNumber(2)
  void clearEmitMetrics() => clearField(2);

  /// When true, the pipeline validates the DAG for deadlocks and
  /// disconnected edges before running.
  @$pb.TagNumber(3)
  $core.bool get strictValidation => $_getBF(2);
  @$pb.TagNumber(3)
  set strictValidation($core.bool v) { $_setBool(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasStrictValidation() => $_has(2);
  @$pb.TagNumber(3)
  void clearStrictValidation() => clearField(3);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
