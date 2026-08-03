// This is a generated file - do not edit.
//
// Generated from cua.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

import 'cua.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'cua.pbenum.dart';

/// A single parsed CUA action. Coordinates are already scaled to the caller's
/// viewport. `text` is the action's primary string argument, keyed by `type`:
/// TYPE->text, VISIT_URL->url, WEB_SEARCH->query, TERMINATE->answer,
/// ASK_USER/READ_PAGE_ANSWER->question, PAUSE_MEMORIZE->fact, KEY->space-joined
/// keys. `reasoning` holds any chain-of-thought preceding the tool_call.
class CuaAction extends $pb.GeneratedMessage {
  factory CuaAction({
    CuaActionType? type,
    $core.bool? coordinateValid,
    $core.int? x,
    $core.int? y,
    $core.int? scrollPixels,
    $core.double? waitSeconds,
    $core.String? text,
    $core.String? reasoning,
    $core.bool? parseOk,
  }) {
    final result = create();
    if (type != null) result.type = type;
    if (coordinateValid != null) result.coordinateValid = coordinateValid;
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (scrollPixels != null) result.scrollPixels = scrollPixels;
    if (waitSeconds != null) result.waitSeconds = waitSeconds;
    if (text != null) result.text = text;
    if (reasoning != null) result.reasoning = reasoning;
    if (parseOk != null) result.parseOk = parseOk;
    return result;
  }

  CuaAction._();

  factory CuaAction.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CuaAction.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CuaAction',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<CuaActionType>(1, _omitFieldNames ? '' : 'type',
        enumValues: CuaActionType.values)
    ..aOB(2, _omitFieldNames ? '' : 'coordinateValid')
    ..aI(3, _omitFieldNames ? '' : 'x')
    ..aI(4, _omitFieldNames ? '' : 'y')
    ..aI(5, _omitFieldNames ? '' : 'scrollPixels')
    ..aD(6, _omitFieldNames ? '' : 'waitSeconds')
    ..aOS(7, _omitFieldNames ? '' : 'text')
    ..aOS(8, _omitFieldNames ? '' : 'reasoning')
    ..aOB(9, _omitFieldNames ? '' : 'parseOk')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CuaAction clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CuaAction copyWith(void Function(CuaAction) updates) =>
      super.copyWith((message) => updates(message as CuaAction)) as CuaAction;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CuaAction create() => CuaAction._();
  @$core.override
  CuaAction createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CuaAction getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<CuaAction>(create);
  static CuaAction? _defaultInstance;

  @$pb.TagNumber(1)
  CuaActionType get type => $_getN(0);
  @$pb.TagNumber(1)
  set type(CuaActionType value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasType() => $_has(0);
  @$pb.TagNumber(1)
  void clearType() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get coordinateValid => $_getBF(1);
  @$pb.TagNumber(2)
  set coordinateValid($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCoordinateValid() => $_has(1);
  @$pb.TagNumber(2)
  void clearCoordinateValid() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get x => $_getIZ(2);
  @$pb.TagNumber(3)
  set x($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasX() => $_has(2);
  @$pb.TagNumber(3)
  void clearX() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.int get y => $_getIZ(3);
  @$pb.TagNumber(4)
  set y($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasY() => $_has(3);
  @$pb.TagNumber(4)
  void clearY() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get scrollPixels => $_getIZ(4);
  @$pb.TagNumber(5)
  set scrollPixels($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasScrollPixels() => $_has(4);
  @$pb.TagNumber(5)
  void clearScrollPixels() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.double get waitSeconds => $_getN(5);
  @$pb.TagNumber(6)
  set waitSeconds($core.double value) => $_setDouble(5, value);
  @$pb.TagNumber(6)
  $core.bool hasWaitSeconds() => $_has(5);
  @$pb.TagNumber(6)
  void clearWaitSeconds() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get text => $_getSZ(6);
  @$pb.TagNumber(7)
  set text($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasText() => $_has(6);
  @$pb.TagNumber(7)
  void clearText() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get reasoning => $_getSZ(7);
  @$pb.TagNumber(8)
  set reasoning($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasReasoning() => $_has(7);
  @$pb.TagNumber(8)
  void clearReasoning() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.bool get parseOk => $_getBF(8);
  @$pb.TagNumber(9)
  set parseOk($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasParseOk() => $_has(8);
  @$pb.TagNumber(9)
  void clearParseOk() => $_clearField(9);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
