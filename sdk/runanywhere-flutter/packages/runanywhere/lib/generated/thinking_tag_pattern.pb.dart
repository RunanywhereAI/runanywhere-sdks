//
//  Generated code. Do not modify.
//  source: thinking_tag_pattern.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

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
    final $result = create();
    if (openTag != null) {
      $result.openTag = openTag;
    }
    if (closeTag != null) {
      $result.closeTag = closeTag;
    }
    return $result;
  }
  ThinkingTagPattern._() : super();
  factory ThinkingTagPattern.fromBuffer($core.List<$core.int> i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromBuffer(i, r);
  factory ThinkingTagPattern.fromJson($core.String i, [$pb.ExtensionRegistry r = $pb.ExtensionRegistry.EMPTY]) => create()..mergeFromJson(i, r);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(_omitMessageNames ? '' : 'ThinkingTagPattern', package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'), createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'openTag')
    ..aOS(2, _omitFieldNames ? '' : 'closeTag')
    ..hasRequiredFields = false
  ;

  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.deepCopy] instead. '
  'Will be removed in next major version')
  ThinkingTagPattern clone() => ThinkingTagPattern()..mergeFromMessage(this);
  @$core.Deprecated(
  'Using this can add significant overhead to your binary. '
  'Use [GeneratedMessageGenericExtensions.rebuild] instead. '
  'Will be removed in next major version')
  ThinkingTagPattern copyWith(void Function(ThinkingTagPattern) updates) => super.copyWith((message) => updates(message as ThinkingTagPattern)) as ThinkingTagPattern;

  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ThinkingTagPattern create() => ThinkingTagPattern._();
  ThinkingTagPattern createEmptyInstance() => create();
  static $pb.PbList<ThinkingTagPattern> createRepeated() => $pb.PbList<ThinkingTagPattern>();
  @$core.pragma('dart2js:noInline')
  static ThinkingTagPattern getDefault() => _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<ThinkingTagPattern>(create);
  static ThinkingTagPattern? _defaultInstance;

  /// Opening tag string. Default if empty: "<think>".
  @$pb.TagNumber(1)
  $core.String get openTag => $_getSZ(0);
  @$pb.TagNumber(1)
  set openTag($core.String v) { $_setString(0, v); }
  @$pb.TagNumber(1)
  $core.bool hasOpenTag() => $_has(0);
  @$pb.TagNumber(1)
  void clearOpenTag() => clearField(1);

  /// Closing tag string. Default if empty: "</think>".
  @$pb.TagNumber(2)
  $core.String get closeTag => $_getSZ(1);
  @$pb.TagNumber(2)
  set closeTag($core.String v) { $_setString(1, v); }
  @$pb.TagNumber(2)
  $core.bool hasCloseTag() => $_has(1);
  @$pb.TagNumber(2)
  void clearCloseTag() => clearField(2);
}


const _omitFieldNames = $core.bool.fromEnvironment('protobuf.omit_field_names');
const _omitMessageNames = $core.bool.fromEnvironment('protobuf.omit_message_names');
