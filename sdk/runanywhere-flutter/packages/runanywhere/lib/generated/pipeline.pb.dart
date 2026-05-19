// This is a generated file - do not edit.
//
// Generated from pipeline.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'pipeline.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

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
    final result = create();
    if (name != null) result.name = name;
    if (operators != null) result.operators.addAll(operators);
    if (edges != null) result.edges.addAll(edges);
    if (options != null) result.options = options;
    return result;
  }

  PipelineSpec._();

  factory PipelineSpec.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PipelineSpec.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PipelineSpec',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..pPM<OperatorSpec>(2, _omitFieldNames ? '' : 'operators',
        subBuilder: OperatorSpec.create)
    ..pPM<EdgeSpec>(3, _omitFieldNames ? '' : 'edges',
        subBuilder: EdgeSpec.create)
    ..aOM<PipelineOptions>(4, _omitFieldNames ? '' : 'options',
        subBuilder: PipelineOptions.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PipelineSpec clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PipelineSpec copyWith(void Function(PipelineSpec) updates) =>
      super.copyWith((message) => updates(message as PipelineSpec))
          as PipelineSpec;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PipelineSpec create() => PipelineSpec._();
  @$core.override
  PipelineSpec createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PipelineSpec getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PipelineSpec>(create);
  static PipelineSpec? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<OperatorSpec> get operators => $_getList(1);

  @$pb.TagNumber(3)
  $pb.PbList<EdgeSpec> get edges => $_getList(2);

  @$pb.TagNumber(4)
  PipelineOptions get options => $_getN(3);
  @$pb.TagNumber(4)
  set options(PipelineOptions value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasOptions() => $_has(3);
  @$pb.TagNumber(4)
  void clearOptions() => $_clearField(4);
  @$pb.TagNumber(4)
  PipelineOptions ensureOptions() => $_ensure(3);
}

class OperatorSpec extends $pb.GeneratedMessage {
  factory OperatorSpec({
    $core.String? name,
    $core.String? type,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? params,
    $core.String? pinnedEngine,
    $core.String? modelId,
    DeviceAffinity? device,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (type != null) result.type = type;
    if (params != null) result.params.addEntries(params);
    if (pinnedEngine != null) result.pinnedEngine = pinnedEngine;
    if (modelId != null) result.modelId = modelId;
    if (device != null) result.device = device;
    return result;
  }

  OperatorSpec._();

  factory OperatorSpec.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory OperatorSpec.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'OperatorSpec',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'type')
    ..m<$core.String, $core.String>(3, _omitFieldNames ? '' : 'params',
        entryClassName: 'OperatorSpec.ParamsEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..aOS(4, _omitFieldNames ? '' : 'pinnedEngine')
    ..aOS(5, _omitFieldNames ? '' : 'modelId')
    ..aE<DeviceAffinity>(6, _omitFieldNames ? '' : 'device',
        enumValues: DeviceAffinity.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OperatorSpec clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  OperatorSpec copyWith(void Function(OperatorSpec) updates) =>
      super.copyWith((message) => updates(message as OperatorSpec))
          as OperatorSpec;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static OperatorSpec create() => OperatorSpec._();
  @$core.override
  OperatorSpec createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static OperatorSpec getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<OperatorSpec>(create);
  static OperatorSpec? _defaultInstance;

  /// Unique within the spec, used as the prefix in edge endpoints like
  /// "stt.final" or "llm.token".
  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  /// The primitive the operator implements: "generate_text", "transcribe",
  /// "synthesize", "detect_voice", "embed", "rerank", "tokenize", "window",
  /// or a solution-declared custom operator ("AudioSource", "AudioSink",
  /// "SentenceDetector", "VectorSearch", "ContextBuild").
  @$pb.TagNumber(2)
  $core.String get type => $_getSZ(1);
  @$pb.TagNumber(2)
  set type($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasType() => $_has(1);
  @$pb.TagNumber(2)
  void clearType() => $_clearField(2);

  /// Free-form parameters interpreted by the operator. The C++ loader
  /// validates required keys per type before instantiating.
  @$pb.TagNumber(3)
  $pb.PbMap<$core.String, $core.String> get params => $_getMap(2);

  /// Optional override of the engine that will serve this operator. When
  /// empty, the L3 router picks based on capability + model format.
  @$pb.TagNumber(4)
  $core.String get pinnedEngine => $_getSZ(3);
  @$pb.TagNumber(4)
  set pinnedEngine($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasPinnedEngine() => $_has(3);
  @$pb.TagNumber(4)
  void clearPinnedEngine() => $_clearField(4);

  /// Optional model identifier (resolved against the model registry).
  @$pb.TagNumber(5)
  $core.String get modelId => $_getSZ(4);
  @$pb.TagNumber(5)
  set modelId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasModelId() => $_has(4);
  @$pb.TagNumber(5)
  void clearModelId() => $_clearField(5);

  /// Affinity hint: run this operator on CPU, GPU, or Neural Engine. The
  /// scheduler may override if the requested device is unavailable.
  @$pb.TagNumber(6)
  DeviceAffinity get device => $_getN(5);
  @$pb.TagNumber(6)
  set device(DeviceAffinity value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasDevice() => $_has(5);
  @$pb.TagNumber(6)
  void clearDevice() => $_clearField(6);
}

class EdgeSpec extends $pb.GeneratedMessage {
  factory EdgeSpec({
    $core.String? from,
    $core.String? to,
    $core.int? capacity,
    EdgePolicy? policy,
  }) {
    final result = create();
    if (from != null) result.from = from;
    if (to != null) result.to = to;
    if (capacity != null) result.capacity = capacity;
    if (policy != null) result.policy = policy;
    return result;
  }

  EdgeSpec._();

  factory EdgeSpec.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory EdgeSpec.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'EdgeSpec',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'from')
    ..aOS(2, _omitFieldNames ? '' : 'to')
    ..aI(3, _omitFieldNames ? '' : 'capacity', fieldType: $pb.PbFieldType.OU3)
    ..aE<EdgePolicy>(4, _omitFieldNames ? '' : 'policy',
        enumValues: EdgePolicy.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EdgeSpec clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  EdgeSpec copyWith(void Function(EdgeSpec) updates) =>
      super.copyWith((message) => updates(message as EdgeSpec)) as EdgeSpec;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static EdgeSpec create() => EdgeSpec._();
  @$core.override
  EdgeSpec createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static EdgeSpec getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<EdgeSpec>(create);
  static EdgeSpec? _defaultInstance;

  /// Endpoints are formatted "<operator_name>.<port_name>".
  /// Source port names are operator-specific output channels; sink port
  /// names are operator-specific input channels. Typing is enforced by the
  /// pipeline validator.
  @$pb.TagNumber(1)
  $core.String get from => $_getSZ(0);
  @$pb.TagNumber(1)
  set from($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasFrom() => $_has(0);
  @$pb.TagNumber(1)
  void clearFrom() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get to => $_getSZ(1);
  @$pb.TagNumber(2)
  set to($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasTo() => $_has(1);
  @$pb.TagNumber(2)
  void clearTo() => $_clearField(2);

  /// Channel depth override. Proto3 scalars have no presence bit, so the
  /// sentinel value 0 means "use the per-edge default (16 for PCM, 256 for
  /// tokens, 32 for sentences)". uint32 keeps the wire representation
  /// identical to int32 on the happy path while making negative inputs
  /// statically unrepresentable.
  @$pb.TagNumber(3)
  $core.int get capacity => $_getIZ(2);
  @$pb.TagNumber(3)
  set capacity($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCapacity() => $_has(2);
  @$pb.TagNumber(3)
  void clearCapacity() => $_clearField(3);

  @$pb.TagNumber(4)
  EdgePolicy get policy => $_getN(3);
  @$pb.TagNumber(4)
  set policy(EdgePolicy value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasPolicy() => $_has(3);
  @$pb.TagNumber(4)
  void clearPolicy() => $_clearField(4);
}

class PipelineOptions extends $pb.GeneratedMessage {
  factory PipelineOptions({
    $core.int? latencyBudgetMs,
    $core.bool? emitMetrics,
    $core.bool? strictValidation,
  }) {
    final result = create();
    if (latencyBudgetMs != null) result.latencyBudgetMs = latencyBudgetMs;
    if (emitMetrics != null) result.emitMetrics = emitMetrics;
    if (strictValidation != null) result.strictValidation = strictValidation;
    return result;
  }

  PipelineOptions._();

  factory PipelineOptions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PipelineOptions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PipelineOptions',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'latencyBudgetMs')
    ..aOB(2, _omitFieldNames ? '' : 'emitMetrics')
    ..aOB(3, _omitFieldNames ? '' : 'strictValidation')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PipelineOptions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PipelineOptions copyWith(void Function(PipelineOptions) updates) =>
      super.copyWith((message) => updates(message as PipelineOptions))
          as PipelineOptions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PipelineOptions create() => PipelineOptions._();
  @$core.override
  PipelineOptions createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PipelineOptions getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PipelineOptions>(create);
  static PipelineOptions? _defaultInstance;

  /// Maximum end-to-end latency budget in milliseconds. The pipeline emits
  /// a MetricsEvent with is_over_budget=true if exceeded.
  @$pb.TagNumber(1)
  $core.int get latencyBudgetMs => $_getIZ(0);
  @$pb.TagNumber(1)
  set latencyBudgetMs($core.int value) => $_setSignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasLatencyBudgetMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearLatencyBudgetMs() => $_clearField(1);

  /// When true, the pipeline emits MetricsEvent on every VAD barge-in and
  /// on pipeline stop.
  @$pb.TagNumber(2)
  $core.bool get emitMetrics => $_getBF(1);
  @$pb.TagNumber(2)
  set emitMetrics($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEmitMetrics() => $_has(1);
  @$pb.TagNumber(2)
  void clearEmitMetrics() => $_clearField(2);

  /// When true, the pipeline validates the DAG for deadlocks and
  /// disconnected edges before running.
  @$pb.TagNumber(3)
  $core.bool get strictValidation => $_getBF(2);
  @$pb.TagNumber(3)
  set strictValidation($core.bool value) => $_setBool(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStrictValidation() => $_has(2);
  @$pb.TagNumber(3)
  void clearStrictValidation() => $_clearField(3);
}

/// Result of compiling a PipelineSpec into a runnable graph.
class PipelineCompileResult extends $pb.GeneratedMessage {
  factory PipelineCompileResult({
    $core.String? handleId,
    PipelineStatus? status,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final result = create();
    if (handleId != null) result.handleId = handleId;
    if (status != null) result.status = status;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    return result;
  }

  PipelineCompileResult._();

  factory PipelineCompileResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PipelineCompileResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PipelineCompileResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'handleId')
    ..aE<PipelineStatus>(2, _omitFieldNames ? '' : 'status',
        enumValues: PipelineStatus.values)
    ..aOS(3, _omitFieldNames ? '' : 'errorMessage')
    ..aI(4, _omitFieldNames ? '' : 'errorCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PipelineCompileResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PipelineCompileResult copyWith(
          void Function(PipelineCompileResult) updates) =>
      super.copyWith((message) => updates(message as PipelineCompileResult))
          as PipelineCompileResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PipelineCompileResult create() => PipelineCompileResult._();
  @$core.override
  PipelineCompileResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PipelineCompileResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PipelineCompileResult>(create);
  static PipelineCompileResult? _defaultInstance;

  /// Opaque compiled-graph identifier. Empty on failure.
  @$pb.TagNumber(1)
  $core.String get handleId => $_getSZ(0);
  @$pb.TagNumber(1)
  set handleId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHandleId() => $_has(0);
  @$pb.TagNumber(1)
  void clearHandleId() => $_clearField(1);

  @$pb.TagNumber(2)
  PipelineStatus get status => $_getN(1);
  @$pb.TagNumber(2)
  set status(PipelineStatus value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasStatus() => $_has(1);
  @$pb.TagNumber(2)
  void clearStatus() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get errorMessage => $_getSZ(2);
  @$pb.TagNumber(3)
  set errorMessage($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasErrorMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearErrorMessage() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get errorCode => $_getIZ(3);
  @$pb.TagNumber(4)
  set errorCode($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasErrorCode() => $_has(3);
  @$pb.TagNumber(4)
  void clearErrorCode() => $_clearField(4);
}

/// Request to start a previously compiled pipeline.
class PipelineStartRequest extends $pb.GeneratedMessage {
  factory PipelineStartRequest({
    $core.String? handleId,
  }) {
    final result = create();
    if (handleId != null) result.handleId = handleId;
    return result;
  }

  PipelineStartRequest._();

  factory PipelineStartRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PipelineStartRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PipelineStartRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'handleId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PipelineStartRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PipelineStartRequest copyWith(void Function(PipelineStartRequest) updates) =>
      super.copyWith((message) => updates(message as PipelineStartRequest))
          as PipelineStartRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PipelineStartRequest create() => PipelineStartRequest._();
  @$core.override
  PipelineStartRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PipelineStartRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PipelineStartRequest>(create);
  static PipelineStartRequest? _defaultInstance;

  /// Identifier returned by Compile. Required.
  @$pb.TagNumber(1)
  $core.String get handleId => $_getSZ(0);
  @$pb.TagNumber(1)
  set handleId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHandleId() => $_has(0);
  @$pb.TagNumber(1)
  void clearHandleId() => $_clearField(1);
}

/// Live pipeline instance handle.
class PipelineHandle extends $pb.GeneratedMessage {
  factory PipelineHandle({
    $core.String? handleId,
    PipelineStatus? status,
    $core.String? state,
  }) {
    final result = create();
    if (handleId != null) result.handleId = handleId;
    if (status != null) result.status = status;
    if (state != null) result.state = state;
    return result;
  }

  PipelineHandle._();

  factory PipelineHandle.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PipelineHandle.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PipelineHandle',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'handleId')
    ..aE<PipelineStatus>(2, _omitFieldNames ? '' : 'status',
        enumValues: PipelineStatus.values)
    ..aOS(3, _omitFieldNames ? '' : 'state')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PipelineHandle clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PipelineHandle copyWith(void Function(PipelineHandle) updates) =>
      super.copyWith((message) => updates(message as PipelineHandle))
          as PipelineHandle;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PipelineHandle create() => PipelineHandle._();
  @$core.override
  PipelineHandle createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PipelineHandle getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PipelineHandle>(create);
  static PipelineHandle? _defaultInstance;

  /// Stable identifier for the started pipeline instance.
  @$pb.TagNumber(1)
  $core.String get handleId => $_getSZ(0);
  @$pb.TagNumber(1)
  set handleId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHandleId() => $_has(0);
  @$pb.TagNumber(1)
  void clearHandleId() => $_clearField(1);

  @$pb.TagNumber(2)
  PipelineStatus get status => $_getN(1);
  @$pb.TagNumber(2)
  set status(PipelineStatus value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasStatus() => $_has(1);
  @$pb.TagNumber(2)
  void clearStatus() => $_clearField(2);

  /// Optional engine-specific state string (e.g. "running", "stopped").
  @$pb.TagNumber(3)
  $core.String get state => $_getSZ(2);
  @$pb.TagNumber(3)
  set state($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasState() => $_has(2);
  @$pb.TagNumber(3)
  void clearState() => $_clearField(3);
}

/// Result of stopping a pipeline instance.
class PipelineStopResult extends $pb.GeneratedMessage {
  factory PipelineStopResult({
    $core.String? handleId,
    PipelineStatus? status,
    $core.String? errorMessage,
    $core.int? errorCode,
  }) {
    final result = create();
    if (handleId != null) result.handleId = handleId;
    if (status != null) result.status = status;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (errorCode != null) result.errorCode = errorCode;
    return result;
  }

  PipelineStopResult._();

  factory PipelineStopResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PipelineStopResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PipelineStopResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'handleId')
    ..aE<PipelineStatus>(2, _omitFieldNames ? '' : 'status',
        enumValues: PipelineStatus.values)
    ..aOS(3, _omitFieldNames ? '' : 'errorMessage')
    ..aI(4, _omitFieldNames ? '' : 'errorCode')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PipelineStopResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PipelineStopResult copyWith(void Function(PipelineStopResult) updates) =>
      super.copyWith((message) => updates(message as PipelineStopResult))
          as PipelineStopResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PipelineStopResult create() => PipelineStopResult._();
  @$core.override
  PipelineStopResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PipelineStopResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PipelineStopResult>(create);
  static PipelineStopResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get handleId => $_getSZ(0);
  @$pb.TagNumber(1)
  set handleId($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasHandleId() => $_has(0);
  @$pb.TagNumber(1)
  void clearHandleId() => $_clearField(1);

  @$pb.TagNumber(2)
  PipelineStatus get status => $_getN(1);
  @$pb.TagNumber(2)
  set status(PipelineStatus value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasStatus() => $_has(1);
  @$pb.TagNumber(2)
  void clearStatus() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get errorMessage => $_getSZ(2);
  @$pb.TagNumber(3)
  set errorMessage($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasErrorMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearErrorMessage() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get errorCode => $_getIZ(3);
  @$pb.TagNumber(4)
  set errorCode($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasErrorCode() => $_has(3);
  @$pb.TagNumber(4)
  void clearErrorCode() => $_clearField(4);
}

/// Logical pipeline service contract. Frontends pass a PipelineSpec, receive a
/// compiled-graph handle, then start and stop the live instance. Backend
/// execution, native runtime scheduling, and side effects remain adapter-owned.
class PipelineApi {
  final $pb.RpcClient _client;

  PipelineApi(this._client);

  /// Validate + compile a PipelineSpec into a runnable graph.
  $async.Future<PipelineCompileResult> compile(
          $pb.ClientContext? ctx, PipelineSpec request) =>
      _client.invoke<PipelineCompileResult>(
          ctx, 'Pipeline', 'Compile', request, PipelineCompileResult());

  /// Start a compiled pipeline; returns a live instance handle.
  $async.Future<PipelineHandle> start(
          $pb.ClientContext? ctx, PipelineStartRequest request) =>
      _client.invoke<PipelineHandle>(
          ctx, 'Pipeline', 'Start', request, PipelineHandle());

  /// Stop a running pipeline instance.
  $async.Future<PipelineStopResult> stop(
          $pb.ClientContext? ctx, PipelineHandle request) =>
      _client.invoke<PipelineStopResult>(
          ctx, 'Pipeline', 'Stop', request, PipelineStopResult());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
