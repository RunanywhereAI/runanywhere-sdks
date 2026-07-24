// This is a generated file - do not edit.
//
// Generated from segmentation.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:async' as $async;
import 'dart:core' as $core;

import 'package:fixnum/fixnum.dart' as $fixnum;
import 'package:protobuf/protobuf.dart' as $pb;

import 'segmentation.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'segmentation.pbenum.dart';

class SegmentationImage extends $pb.GeneratedMessage {
  factory SegmentationImage({
    $core.List<$core.int>? data,
    $core.int? width,
    $core.int? height,
    SegmentationPixelFormat? pixelFormat,
  }) {
    final result = create();
    if (data != null) result.data = data;
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (pixelFormat != null) result.pixelFormat = pixelFormat;
    return result;
  }

  SegmentationImage._();

  factory SegmentationImage.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SegmentationImage.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SegmentationImage',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..a<$core.List<$core.int>>(
        1, _omitFieldNames ? '' : 'data', $pb.PbFieldType.OY)
    ..aI(2, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(3, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..aE<SegmentationPixelFormat>(4, _omitFieldNames ? '' : 'pixelFormat',
        enumValues: SegmentationPixelFormat.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SegmentationImage clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SegmentationImage copyWith(void Function(SegmentationImage) updates) =>
      super.copyWith((message) => updates(message as SegmentationImage))
          as SegmentationImage;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SegmentationImage create() => SegmentationImage._();
  @$core.override
  SegmentationImage createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SegmentationImage getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SegmentationImage>(create);
  static SegmentationImage? _defaultInstance;

  @$pb.TagNumber(1)
  $core.List<$core.int> get data => $_getN(0);
  @$pb.TagNumber(1)
  set data($core.List<$core.int> value) => $_setBytes(0, value);
  @$pb.TagNumber(1)
  $core.bool hasData() => $_has(0);
  @$pb.TagNumber(1)
  void clearData() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get width => $_getIZ(1);
  @$pb.TagNumber(2)
  set width($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasWidth() => $_has(1);
  @$pb.TagNumber(2)
  void clearWidth() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get height => $_getIZ(2);
  @$pb.TagNumber(3)
  set height($core.int value) => $_setUnsignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasHeight() => $_has(2);
  @$pb.TagNumber(3)
  void clearHeight() => $_clearField(3);

  @$pb.TagNumber(4)
  SegmentationPixelFormat get pixelFormat => $_getN(3);
  @$pb.TagNumber(4)
  set pixelFormat(SegmentationPixelFormat value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasPixelFormat() => $_has(3);
  @$pb.TagNumber(4)
  void clearPixelFormat() => $_clearField(4);
}

class SegmentationOptions extends $pb.GeneratedMessage {
  factory SegmentationOptions({
    $core.bool? includeDiagnosticRgba,
  }) {
    final result = create();
    if (includeDiagnosticRgba != null)
      result.includeDiagnosticRgba = includeDiagnosticRgba;
    return result;
  }

  SegmentationOptions._();

  factory SegmentationOptions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SegmentationOptions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SegmentationOptions',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'includeDiagnosticRgba')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SegmentationOptions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SegmentationOptions copyWith(void Function(SegmentationOptions) updates) =>
      super.copyWith((message) => updates(message as SegmentationOptions))
          as SegmentationOptions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SegmentationOptions create() => SegmentationOptions._();
  @$core.override
  SegmentationOptions createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SegmentationOptions getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SegmentationOptions>(create);
  static SegmentationOptions? _defaultInstance;

  /// When true, also return a deterministic class-colour RGBA image. The
  /// canonical class_mask_u16_le remains the machine-readable result.
  @$pb.TagNumber(1)
  $core.bool get includeDiagnosticRgba => $_getBF(0);
  @$pb.TagNumber(1)
  set includeDiagnosticRgba($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasIncludeDiagnosticRgba() => $_has(0);
  @$pb.TagNumber(1)
  void clearIncludeDiagnosticRgba() => $_clearField(1);
}

class SegmentationRequest extends $pb.GeneratedMessage {
  factory SegmentationRequest({
    SegmentationImage? image,
    SegmentationOptions? options,
  }) {
    final result = create();
    if (image != null) result.image = image;
    if (options != null) result.options = options;
    return result;
  }

  SegmentationRequest._();

  factory SegmentationRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SegmentationRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SegmentationRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOM<SegmentationImage>(1, _omitFieldNames ? '' : 'image',
        subBuilder: SegmentationImage.create)
    ..aOM<SegmentationOptions>(2, _omitFieldNames ? '' : 'options',
        subBuilder: SegmentationOptions.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SegmentationRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SegmentationRequest copyWith(void Function(SegmentationRequest) updates) =>
      super.copyWith((message) => updates(message as SegmentationRequest))
          as SegmentationRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SegmentationRequest create() => SegmentationRequest._();
  @$core.override
  SegmentationRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SegmentationRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SegmentationRequest>(create);
  static SegmentationRequest? _defaultInstance;

  @$pb.TagNumber(1)
  SegmentationImage get image => $_getN(0);
  @$pb.TagNumber(1)
  set image(SegmentationImage value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasImage() => $_has(0);
  @$pb.TagNumber(1)
  void clearImage() => $_clearField(1);
  @$pb.TagNumber(1)
  SegmentationImage ensureImage() => $_ensure(0);

  @$pb.TagNumber(2)
  SegmentationOptions get options => $_getN(1);
  @$pb.TagNumber(2)
  set options(SegmentationOptions value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasOptions() => $_has(1);
  @$pb.TagNumber(2)
  void clearOptions() => $_clearField(2);
  @$pb.TagNumber(2)
  SegmentationOptions ensureOptions() => $_ensure(1);
}

class SegmentationClassSummary extends $pb.GeneratedMessage {
  factory SegmentationClassSummary({
    $core.int? classId,
    $fixnum.Int64? pixelCount,
    $core.double? fraction,
    $core.String? label,
  }) {
    final result = create();
    if (classId != null) result.classId = classId;
    if (pixelCount != null) result.pixelCount = pixelCount;
    if (fraction != null) result.fraction = fraction;
    if (label != null) result.label = label;
    return result;
  }

  SegmentationClassSummary._();

  factory SegmentationClassSummary.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SegmentationClassSummary.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SegmentationClassSummary',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'classId', fieldType: $pb.PbFieldType.OU3)
    ..a<$fixnum.Int64>(
        2, _omitFieldNames ? '' : 'pixelCount', $pb.PbFieldType.OU6,
        defaultOrMaker: $fixnum.Int64.ZERO)
    ..aD(3, _omitFieldNames ? '' : 'fraction', fieldType: $pb.PbFieldType.OF)
    ..aOS(4, _omitFieldNames ? '' : 'label')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SegmentationClassSummary clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SegmentationClassSummary copyWith(
          void Function(SegmentationClassSummary) updates) =>
      super.copyWith((message) => updates(message as SegmentationClassSummary))
          as SegmentationClassSummary;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SegmentationClassSummary create() => SegmentationClassSummary._();
  @$core.override
  SegmentationClassSummary createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SegmentationClassSummary getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SegmentationClassSummary>(create);
  static SegmentationClassSummary? _defaultInstance;

  @$pb.TagNumber(1)
  $core.int get classId => $_getIZ(0);
  @$pb.TagNumber(1)
  set classId($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasClassId() => $_has(0);
  @$pb.TagNumber(1)
  void clearClassId() => $_clearField(1);

  @$pb.TagNumber(2)
  $fixnum.Int64 get pixelCount => $_getI64(1);
  @$pb.TagNumber(2)
  set pixelCount($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPixelCount() => $_has(1);
  @$pb.TagNumber(2)
  void clearPixelCount() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.double get fraction => $_getN(2);
  @$pb.TagNumber(3)
  set fraction($core.double value) => $_setFloat(2, value);
  @$pb.TagNumber(3)
  $core.bool hasFraction() => $_has(2);
  @$pb.TagNumber(3)
  void clearFraction() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get label => $_getSZ(3);
  @$pb.TagNumber(4)
  set label($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasLabel() => $_has(3);
  @$pb.TagNumber(4)
  void clearLabel() => $_clearField(4);
}

class SegmentationResult extends $pb.GeneratedMessage {
  factory SegmentationResult({
    $core.int? width,
    $core.int? height,
    $core.List<$core.int>? classMaskU16Le,
    $core.List<$core.int>? diagnosticRgba,
    $core.Iterable<SegmentationClassSummary>? classSummaries,
    $fixnum.Int64? processingTimeMs,
    $core.String? modelId,
  }) {
    final result = create();
    if (width != null) result.width = width;
    if (height != null) result.height = height;
    if (classMaskU16Le != null) result.classMaskU16Le = classMaskU16Le;
    if (diagnosticRgba != null) result.diagnosticRgba = diagnosticRgba;
    if (classSummaries != null) result.classSummaries.addAll(classSummaries);
    if (processingTimeMs != null) result.processingTimeMs = processingTimeMs;
    if (modelId != null) result.modelId = modelId;
    return result;
  }

  SegmentationResult._();

  factory SegmentationResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SegmentationResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SegmentationResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aI(1, _omitFieldNames ? '' : 'width', fieldType: $pb.PbFieldType.OU3)
    ..aI(2, _omitFieldNames ? '' : 'height', fieldType: $pb.PbFieldType.OU3)
    ..a<$core.List<$core.int>>(
        3, _omitFieldNames ? '' : 'classMaskU16Le', $pb.PbFieldType.OY)
    ..a<$core.List<$core.int>>(
        4, _omitFieldNames ? '' : 'diagnosticRgba', $pb.PbFieldType.OY)
    ..pPM<SegmentationClassSummary>(5, _omitFieldNames ? '' : 'classSummaries',
        subBuilder: SegmentationClassSummary.create)
    ..aInt64(6, _omitFieldNames ? '' : 'processingTimeMs')
    ..aOS(7, _omitFieldNames ? '' : 'modelId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SegmentationResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SegmentationResult copyWith(void Function(SegmentationResult) updates) =>
      super.copyWith((message) => updates(message as SegmentationResult))
          as SegmentationResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SegmentationResult create() => SegmentationResult._();
  @$core.override
  SegmentationResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SegmentationResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SegmentationResult>(create);
  static SegmentationResult? _defaultInstance;

  /// Both masks always describe the source image dimensions, not the model's
  /// internal 512x512 input or 128x128 logits grid.
  @$pb.TagNumber(1)
  $core.int get width => $_getIZ(0);
  @$pb.TagNumber(1)
  set width($core.int value) => $_setUnsignedInt32(0, value);
  @$pb.TagNumber(1)
  $core.bool hasWidth() => $_has(0);
  @$pb.TagNumber(1)
  void clearWidth() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.int get height => $_getIZ(1);
  @$pb.TagNumber(2)
  set height($core.int value) => $_setUnsignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasHeight() => $_has(1);
  @$pb.TagNumber(2)
  void clearHeight() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.List<$core.int> get classMaskU16Le => $_getN(2);
  @$pb.TagNumber(3)
  set classMaskU16Le($core.List<$core.int> value) => $_setBytes(2, value);
  @$pb.TagNumber(3)
  $core.bool hasClassMaskU16Le() => $_has(2);
  @$pb.TagNumber(3)
  void clearClassMaskU16Le() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.List<$core.int> get diagnosticRgba => $_getN(3);
  @$pb.TagNumber(4)
  set diagnosticRgba($core.List<$core.int> value) => $_setBytes(3, value);
  @$pb.TagNumber(4)
  $core.bool hasDiagnosticRgba() => $_has(3);
  @$pb.TagNumber(4)
  void clearDiagnosticRgba() => $_clearField(4);

  @$pb.TagNumber(5)
  $pb.PbList<SegmentationClassSummary> get classSummaries => $_getList(4);

  @$pb.TagNumber(6)
  $fixnum.Int64 get processingTimeMs => $_getI64(5);
  @$pb.TagNumber(6)
  set processingTimeMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasProcessingTimeMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearProcessingTimeMs() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get modelId => $_getSZ(6);
  @$pb.TagNumber(7)
  set modelId($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasModelId() => $_has(6);
  @$pb.TagNumber(7)
  void clearModelId() => $_clearField(7);
}

class SemanticSegmentationApi {
  final $pb.RpcClient _client;

  SemanticSegmentationApi(this._client);

  $async.Future<SegmentationResult> segment(
          $pb.ClientContext? ctx, SegmentationRequest request) =>
      _client.invoke<SegmentationResult>(ctx, 'SemanticSegmentation', 'Segment',
          request, SegmentationResult());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
