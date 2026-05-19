// This is a generated file - do not edit.
//
// Generated from thinking_tag_pattern.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// ---------------------------------------------------------------------------
/// Pattern used to extract a model's "thinking" / reasoning block from its
/// raw output. Used by Qwen3 and LFM2 family models that emit
/// <think>...</think> wrappers. Shared by LLM generation options (per-call
/// override) and ModelInfo catalog metadata (default pattern for a model).
/// ---------------------------------------------------------------------------
class ThinkingTagPattern extends $pb.GeneratedMessage {
  factory ThinkingTagPattern({
    $core.String? openTag,
    $core.String? closeTag,
  }) {
    final result = create();
    if (openTag != null) result.openTag = openTag;
    if (closeTag != null) result.closeTag = closeTag;
    return result;
  }

  ThinkingTagPattern._();

  factory ThinkingTagPattern.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ThinkingTagPattern.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ThinkingTagPattern',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'openTag')
    ..aOS(2, _omitFieldNames ? '' : 'closeTag')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ThinkingTagPattern clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ThinkingTagPattern copyWith(void Function(ThinkingTagPattern) updates) =>
      super.copyWith((message) => updates(message as ThinkingTagPattern))
          as ThinkingTagPattern;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ThinkingTagPattern create() => ThinkingTagPattern._();
  @$core.override
  ThinkingTagPattern createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ThinkingTagPattern getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ThinkingTagPattern>(create);
  static ThinkingTagPattern? _defaultInstance;

  /// Opening tag string. Default if empty: "<think>".
  @$pb.TagNumber(1)
  $core.String get openTag => $_getSZ(0);
  @$pb.TagNumber(1)
  set openTag($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasOpenTag() => $_has(0);
  @$pb.TagNumber(1)
  void clearOpenTag() => $_clearField(1);

  /// Closing tag string. Default if empty: "</think>".
  @$pb.TagNumber(2)
  $core.String get closeTag => $_getSZ(1);
  @$pb.TagNumber(2)
  set closeTag($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasCloseTag() => $_has(1);
  @$pb.TagNumber(2)
  void clearCloseTag() => $_clearField(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
