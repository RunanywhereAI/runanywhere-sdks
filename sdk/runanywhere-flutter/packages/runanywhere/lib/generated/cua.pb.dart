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
///
/// COORDINATE CONTRACT: x/y are integers in the SAME pixel space as the
/// viewport you passed to parse_action, origin at the TOP-LEFT. That viewport
/// must be the pixel dimensions of the exact image you handed to the VLM — if
/// you downscaled the screenshot before sending it, pass the downscaled
/// dimensions. On a DPR-2/3/4 display, passing logical points while sending a
/// physical-pixel screenshot offsets every click by that factor, silently (see
/// examples/ios/.../ComputerUseAgentViewModel.swift for the correct
/// computation). parse_action has already rescaled out of the profile's own
/// space (1000x1000 for `fara`), so no further scaling is ever correct.
///
/// LEFT_CLICK_DRAG: x/y are the drag DESTINATION only. Fara emits no origin (it
/// drags from the current cursor), and a touch screen has no cursor, so the
/// HOST must supply the press point — typically the last MOUSE_MOVE target.
///
/// LENGTH: `text` and `reasoning` are TRUNCATED at 2047 bytes on a UTF-8 lead
/// byte by the fixed C buffers behind them (rac_cua_action_t.text[2048]); no
/// field records that truncation happened. This also caps a TERMINATE answer.
class CuaAction extends $pb.GeneratedMessage {
  factory CuaAction({
    CuaActionType? type,
    $core.int? x,
    $core.int? y,
    $core.int? scrollX,
    $core.int? scrollY,
    $core.double? waitSeconds,
    $core.String? text,
    $core.String? reasoning,
    $core.bool? isValid,
  }) {
    final result = create();
    if (type != null) result.type = type;
    if (x != null) result.x = x;
    if (y != null) result.y = y;
    if (scrollX != null) result.scrollX = scrollX;
    if (scrollY != null) result.scrollY = scrollY;
    if (waitSeconds != null) result.waitSeconds = waitSeconds;
    if (text != null) result.text = text;
    if (reasoning != null) result.reasoning = reasoning;
    if (isValid != null) result.isValid = isValid;
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
    ..aI(2, _omitFieldNames ? '' : 'x')
    ..aI(3, _omitFieldNames ? '' : 'y')
    ..aI(4, _omitFieldNames ? '' : 'scrollX')
    ..aI(5, _omitFieldNames ? '' : 'scrollY')
    ..aD(6, _omitFieldNames ? '' : 'waitSeconds')
    ..aOS(7, _omitFieldNames ? '' : 'text')
    ..aOS(8, _omitFieldNames ? '' : 'reasoning')
    ..aOB(9, _omitFieldNames ? '' : 'isValid')
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
  $core.int get x => $_getIZ(1);
  @$pb.TagNumber(2)
  set x($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasX() => $_has(1);
  @$pb.TagNumber(2)
  void clearX() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.int get y => $_getIZ(2);
  @$pb.TagNumber(3)
  set y($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasY() => $_has(2);
  @$pb.TagNumber(3)
  void clearY() => $_clearField(3);

  /// HSCROLL/SCROLL axis split. Value is the model's raw `pixels` output,
  /// copied verbatim per axis — the sign is UNVERIFIED against any real
  /// device trace, so no direction convention is asserted here.
  @$pb.TagNumber(4)
  $core.int get scrollX => $_getIZ(3);
  @$pb.TagNumber(4)
  set scrollX($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasScrollX() => $_has(3);
  @$pb.TagNumber(4)
  void clearScrollX() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get scrollY => $_getIZ(4);
  @$pb.TagNumber(5)
  set scrollY($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasScrollY() => $_has(4);
  @$pb.TagNumber(5)
  void clearScrollY() => $_clearField(5);

  /// WAIT: fractional seconds. Clamped by commons to [0, 100] because the
  /// value comes from untrusted model output; an unbounded parse would wedge
  /// the agent loop. 100s is a RunAnywhere-chosen ceiling, not inherited from
  /// any vendor API.
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
  $core.bool get isValid => $_getBF(8);
  @$pb.TagNumber(9)
  set isValid($core.bool value) => $_setBool(8, value);
  @$pb.TagNumber(9)
  $core.bool hasIsValid() => $_has(8);
  @$pb.TagNumber(9)
  void clearIsValid() => $_clearField(9);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
