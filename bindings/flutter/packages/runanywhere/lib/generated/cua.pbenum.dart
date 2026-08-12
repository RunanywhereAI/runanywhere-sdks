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

/// Model-agnostic action type parsed from a CUA model's output. Values match
/// the C enum `rac_cua_action_type_t` (rac_cua.h) one-for-one.
class CuaActionType extends $pb.ProtobufEnum {
  static const CuaActionType CUA_ACTION_TYPE_UNSPECIFIED =
      CuaActionType._(0, _omitEnumNames ? '' : 'CUA_ACTION_TYPE_UNSPECIFIED');
  static const CuaActionType CUA_ACTION_TYPE_LEFT_CLICK =
      CuaActionType._(1, _omitEnumNames ? '' : 'CUA_ACTION_TYPE_LEFT_CLICK');
  static const CuaActionType CUA_ACTION_TYPE_RIGHT_CLICK =
      CuaActionType._(2, _omitEnumNames ? '' : 'CUA_ACTION_TYPE_RIGHT_CLICK');
  static const CuaActionType CUA_ACTION_TYPE_DOUBLE_CLICK =
      CuaActionType._(3, _omitEnumNames ? '' : 'CUA_ACTION_TYPE_DOUBLE_CLICK');
  static const CuaActionType CUA_ACTION_TYPE_TRIPLE_CLICK =
      CuaActionType._(4, _omitEnumNames ? '' : 'CUA_ACTION_TYPE_TRIPLE_CLICK');
  static const CuaActionType CUA_ACTION_TYPE_MOUSE_MOVE =
      CuaActionType._(5, _omitEnumNames ? '' : 'CUA_ACTION_TYPE_MOUSE_MOVE');
  static const CuaActionType CUA_ACTION_TYPE_LEFT_CLICK_DRAG = CuaActionType._(
      6, _omitEnumNames ? '' : 'CUA_ACTION_TYPE_LEFT_CLICK_DRAG');
  static const CuaActionType CUA_ACTION_TYPE_TYPE =
      CuaActionType._(7, _omitEnumNames ? '' : 'CUA_ACTION_TYPE_TYPE');
  static const CuaActionType CUA_ACTION_TYPE_KEY =
      CuaActionType._(8, _omitEnumNames ? '' : 'CUA_ACTION_TYPE_KEY');
  static const CuaActionType CUA_ACTION_TYPE_SCROLL =
      CuaActionType._(9, _omitEnumNames ? '' : 'CUA_ACTION_TYPE_SCROLL');
  static const CuaActionType CUA_ACTION_TYPE_HSCROLL =
      CuaActionType._(10, _omitEnumNames ? '' : 'CUA_ACTION_TYPE_HSCROLL');
  static const CuaActionType CUA_ACTION_TYPE_VISIT_URL =
      CuaActionType._(11, _omitEnumNames ? '' : 'CUA_ACTION_TYPE_VISIT_URL');
  static const CuaActionType CUA_ACTION_TYPE_HISTORY_BACK =
      CuaActionType._(12, _omitEnumNames ? '' : 'CUA_ACTION_TYPE_HISTORY_BACK');
  static const CuaActionType CUA_ACTION_TYPE_WEB_SEARCH =
      CuaActionType._(13, _omitEnumNames ? '' : 'CUA_ACTION_TYPE_WEB_SEARCH');
  static const CuaActionType CUA_ACTION_TYPE_READ_PAGE_ANSWER = CuaActionType._(
      14, _omitEnumNames ? '' : 'CUA_ACTION_TYPE_READ_PAGE_ANSWER');
  static const CuaActionType CUA_ACTION_TYPE_PAUSE_MEMORIZE = CuaActionType._(
      15, _omitEnumNames ? '' : 'CUA_ACTION_TYPE_PAUSE_MEMORIZE');
  static const CuaActionType CUA_ACTION_TYPE_ASK_USER =
      CuaActionType._(16, _omitEnumNames ? '' : 'CUA_ACTION_TYPE_ASK_USER');
  static const CuaActionType CUA_ACTION_TYPE_WAIT =
      CuaActionType._(17, _omitEnumNames ? '' : 'CUA_ACTION_TYPE_WAIT');
  static const CuaActionType CUA_ACTION_TYPE_TERMINATE =
      CuaActionType._(18, _omitEnumNames ? '' : 'CUA_ACTION_TYPE_TERMINATE');

  static const $core.List<CuaActionType> values = <CuaActionType>[
    CUA_ACTION_TYPE_UNSPECIFIED,
    CUA_ACTION_TYPE_LEFT_CLICK,
    CUA_ACTION_TYPE_RIGHT_CLICK,
    CUA_ACTION_TYPE_DOUBLE_CLICK,
    CUA_ACTION_TYPE_TRIPLE_CLICK,
    CUA_ACTION_TYPE_MOUSE_MOVE,
    CUA_ACTION_TYPE_LEFT_CLICK_DRAG,
    CUA_ACTION_TYPE_TYPE,
    CUA_ACTION_TYPE_KEY,
    CUA_ACTION_TYPE_SCROLL,
    CUA_ACTION_TYPE_HSCROLL,
    CUA_ACTION_TYPE_VISIT_URL,
    CUA_ACTION_TYPE_HISTORY_BACK,
    CUA_ACTION_TYPE_WEB_SEARCH,
    CUA_ACTION_TYPE_READ_PAGE_ANSWER,
    CUA_ACTION_TYPE_PAUSE_MEMORIZE,
    CUA_ACTION_TYPE_ASK_USER,
    CUA_ACTION_TYPE_WAIT,
    CUA_ACTION_TYPE_TERMINATE,
  ];

  static final $core.List<CuaActionType?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 18);
  static CuaActionType? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const CuaActionType._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
