///
//  Generated code. Do not modify.
//  source: errors.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'errors.pbenum.dart';

export 'errors.pbenum.dart';

class ErrorContext extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'ErrorContext', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..m<$core.String, $core.String>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'metadata', entryClassName: 'ErrorContext.MetadataEntry', keyFieldType: $pb.PbFieldType.OS, valueFieldType: $pb.PbFieldType.OS, packageName: const $pb.PackageName('runanywhere.v1'))
    ..aOS(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sourceFile')
    ..a<$core.int>(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'sourceLine', $pb.PbFieldType.O3)
    ..aOS(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'operation')
    ..hasRequiredFields = false
  ;

  ErrorContext._() : super();
  factory ErrorContext({
    $core.Map<$core.String, $core.String>? metadata,
    $core.String? sourceFile,
    $core.int? sourceLine,
    $core.String? operation,
  }) {
    final _result = create();
    if (metadata != null) {
      _result.metadata.addAll(metadata);
    }
    if (sourceFile != null) {
      _result.sourceFile = sourceFile;
    }
    if (sourceLine != null) {
      _result.sourceLine = sourceLine;
    }
    if (operation != null) {
      _result.operation = operation;
    }
    return _result;
  }
  factory ErrorContext.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ErrorContext.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ErrorContext clone() => ErrorContext()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ErrorContext copyWith(void Function(ErrorContext) updates) => super.copyWith((message) => updates(message as ErrorContext)) as ErrorContext; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static ErrorContext create() => ErrorContext._();
  ErrorContext createEmptyInstance() => create();
  static $pb.PbList<ErrorContext> createRepeated() => $pb.PbList<ErrorContext>();
  @$core.pragma('dart2js:noInline')
  static ErrorContext getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ErrorContext>(create);
  static ErrorContext? _defaultInstance;

  @$pb.TagNumber(1)
  $core.Map<$core.String, $core.String> get metadata => $_getMap(0);

  @$pb.TagNumber(2)
  $core.String get sourceFile => $_getSZ(1);
  @$pb.TagNumber(2)
  set sourceFile($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasSourceFile() => $_has(1);
  @$pb.TagNumber(2)
  void clearSourceFile() => clearField(2);

  @$pb.TagNumber(3)
  $core.int get sourceLine => $_getIZ(2);
  @$pb.TagNumber(3)
  set sourceLine($core.int v) { $_setSignedInt32(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasSourceLine() => $_has(2);
  @$pb.TagNumber(3)
  void clearSourceLine() => clearField(3);

  @$pb.TagNumber(4)
  $core.String get operation => $_getSZ(3);
  @$pb.TagNumber(4)
  set operation($core.String v) { $_setString(3, v); }
  @$pb.TagNumber(4)
  $core.bool hasOperation() => $_has(3);
  @$pb.TagNumber(4)
  void clearOperation() => clearField(4);
}

class SDKError extends $pb.GeneratedMessage {
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'SDKError', package: const $pb.PackageName(const $core.bool.fromEnvironment('protobuf.omit_message_names') ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..e<ErrorCode>(1, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'code', $pb.PbFieldType.OE, defaultOrMaker: ErrorCode.ERROR_CODE_UNSPECIFIED, valueOf: ErrorCode.valueOf, enumValues: ErrorCode.values)
    ..e<ErrorCategory>(2, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'category', $pb.PbFieldType.OE, defaultOrMaker: ErrorCategory.ERROR_CATEGORY_UNSPECIFIED, valueOf: ErrorCategory.valueOf, enumValues: ErrorCategory.values)
    ..aOS(3, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'message')
    ..aOM<ErrorContext>(4, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'context', subBuilder: ErrorContext.create)
    ..a<$core.int>(5, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'cAbiCode', $pb.PbFieldType.O3)
    ..aOS(6, const $core.bool.fromEnvironment('protobuf.omit_field_names') ? '' : 'nestedMessage')
    ..hasRequiredFields = false
  ;

  SDKError._() : super();
  factory SDKError({
    ErrorCode? code,
    ErrorCategory? category,
    $core.String? message,
    ErrorContext? context,
    $core.int? cAbiCode,
    $core.String? nestedMessage,
  }) {
    final _result = create();
    if (code != null) {
      _result.code = code;
    }
    if (category != null) {
      _result.category = category;
    }
    if (message != null) {
      _result.message = message;
    }
    if (context != null) {
      _result.context = context;
    }
    if (cAbiCode != null) {
      _result.cAbiCode = cAbiCode;
    }
    if (nestedMessage != null) {
      _result.nestedMessage = nestedMessage;
    }
    return _result;
  }
  factory SDKError.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory SDKError.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  SDKError clone() => SDKError()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  SDKError copyWith(void Function(SDKError) updates) => super.copyWith((message) => updates(message as SDKError)) as SDKError; // ignore: deprecated_member_use
  $pb.BuilderInfo get info_ => _i;
  @$core.pragma('dart2js:noInline')
  static SDKError create() => SDKError._();
  SDKError createEmptyInstance() => create();
  static $pb.PbList<SDKError> createRepeated() => $pb.PbList<SDKError>();
  @$core.pragma('dart2js:noInline')
  static SDKError getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SDKError>(create);
  static SDKError? _defaultInstance;

  @$pb.TagNumber(1)
  ErrorCode get code => $_getN(0);
  @$pb.TagNumber(1)
  set code(ErrorCode v) { setField(1, v); }
  @$pb.TagNumber(1)
  $core.bool hasCode() => $_has(0);
  @$pb.TagNumber(1)
  void clearCode() => clearField(1);

  @$pb.TagNumber(2)
  ErrorCategory get category => $_getN(1);
  @$pb.TagNumber(2)
  set category(ErrorCategory v) { setField(2, v); }
  @$pb.TagNumber(2)
  $core.bool hasCategory() => $_has(1);
  @$pb.TagNumber(2)
  void clearCategory() => clearField(2);

  @$pb.TagNumber(3)
  $core.String get message => $_getSZ(2);
  @$pb.TagNumber(3)
  set message($core.String v) { $_setString(2, v); }
  @$pb.TagNumber(3)
  $core.bool hasMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearMessage() => clearField(3);

  @$pb.TagNumber(4)
  ErrorContext get context => $_getN(3);
  @$pb.TagNumber(4)
  set context(ErrorContext v) { setField(4, v); }
  @$pb.TagNumber(4)
  $core.bool hasContext() => $_has(3);
  @$pb.TagNumber(4)
  void clearContext() => clearField(4);
  @$pb.TagNumber(4)
  ErrorContext ensureContext() => $_ensure(3);

  @$pb.TagNumber(5)
  $core.int get cAbiCode => $_getIZ(4);
  @$pb.TagNumber(5)
  set cAbiCode($core.int v) { $_setSignedInt32(4, v); }
  @$pb.TagNumber(5)
  $core.bool hasCAbiCode() => $_has(4);
  @$pb.TagNumber(5)
  void clearCAbiCode() => clearField(5);

  @$pb.TagNumber(6)
  $core.String get nestedMessage => $_getSZ(5);
  @$pb.TagNumber(6)
  set nestedMessage($core.String v) { $_setString(5, v); }
  @$pb.TagNumber(6)
  $core.bool hasNestedMessage() => $_has(5);
  @$pb.TagNumber(6)
  void clearNestedMessage() => clearField(6);
}

