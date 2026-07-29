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

import 'thinking_tag_pattern.pbenum.dart';

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'thinking_tag_pattern.pbenum.dart';

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

class ReasoningOptions extends $pb.GeneratedMessage {
  factory ReasoningOptions({
    ReasoningMode? mode,
    $core.bool? includeInOutput,
    ThinkingTagPattern? pattern,
  }) {
    final result = create();
    if (mode != null) result.mode = mode;
    if (includeInOutput != null) result.includeInOutput = includeInOutput;
    if (pattern != null) result.pattern = pattern;
    return result;
  }

  ReasoningOptions._();

  factory ReasoningOptions.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ReasoningOptions.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ReasoningOptions',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<ReasoningMode>(1, _omitFieldNames ? '' : 'mode',
        enumValues: ReasoningMode.values)
    ..aOB(2, _omitFieldNames ? '' : 'includeInOutput')
    ..aOM<ThinkingTagPattern>(3, _omitFieldNames ? '' : 'pattern',
        subBuilder: ThinkingTagPattern.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReasoningOptions clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ReasoningOptions copyWith(void Function(ReasoningOptions) updates) =>
      super.copyWith((message) => updates(message as ReasoningOptions))
          as ReasoningOptions;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ReasoningOptions create() => ReasoningOptions._();
  @$core.override
  ReasoningOptions createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ReasoningOptions getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ReasoningOptions>(create);
  static ReasoningOptions? _defaultInstance;

  @$pb.TagNumber(1)
  ReasoningMode get mode => $_getN(0);
  @$pb.TagNumber(1)
  set mode(ReasoningMode value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasMode() => $_has(0);
  @$pb.TagNumber(1)
  void clearMode() => $_clearField(1);

  /// Emit thought tokens/content to the caller (stream TokenKind.THOUGHT
  /// events and result thinking_content). False = thinking is stripped.
  @$pb.TagNumber(2)
  $core.bool get includeInOutput => $_getBF(1);
  @$pb.TagNumber(2)
  set includeInOutput($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIncludeInOutput() => $_has(1);
  @$pb.TagNumber(2)
  void clearIncludeInOutput() => $_clearField(2);

  /// Tag override for models whose thinking markers differ from the
  /// catalog default.
  @$pb.TagNumber(3)
  ThinkingTagPattern get pattern => $_getN(2);
  @$pb.TagNumber(3)
  set pattern(ThinkingTagPattern value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasPattern() => $_has(2);
  @$pb.TagNumber(3)
  void clearPattern() => $_clearField(3);
  @$pb.TagNumber(3)
  ThinkingTagPattern ensurePattern() => $_ensure(2);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
