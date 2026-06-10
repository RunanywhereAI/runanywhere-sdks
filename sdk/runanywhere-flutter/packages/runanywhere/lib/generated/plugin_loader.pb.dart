// This is a generated file - do not edit.
//
// Generated from plugin_loader.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

/// A loaded/registered plugin. `path` is empty for plugins the native registry
/// reports by name only (it does not persist load paths) — proto3 string
/// default "" matches the current `path: ""` placeholder.
class PluginInfo extends $pb.GeneratedMessage {
  factory PluginInfo({
    $core.String? name,
    $core.String? path,
  }) {
    final result = create();
    if (name != null) result.name = name;
    if (path != null) result.path = path;
    return result;
  }

  PluginInfo._();

  factory PluginInfo.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PluginInfo.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PluginInfo',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOS(1, _omitFieldNames ? '' : 'name')
    ..aOS(2, _omitFieldNames ? '' : 'path')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PluginInfo clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PluginInfo copyWith(void Function(PluginInfo) updates) =>
      super.copyWith((message) => updates(message as PluginInfo)) as PluginInfo;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PluginInfo create() => PluginInfo._();
  @$core.override
  PluginInfo createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PluginInfo getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PluginInfo>(create);
  static PluginInfo? _defaultInstance;

  @$pb.TagNumber(1)
  $core.String get name => $_getSZ(0);
  @$pb.TagNumber(1)
  set name($core.String value) => $_setString(0, value);
  @$pb.TagNumber(1)
  $core.bool hasName() => $_has(0);
  @$pb.TagNumber(1)
  void clearName() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get path => $_getSZ(1);
  @$pb.TagNumber(2)
  set path($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasPath() => $_has(1);
  @$pb.TagNumber(2)
  void clearPath() => $_clearField(2);
}

/// Result of the plugin-list bridge calls (registeredNames / listLoaded).
class PluginInfoList extends $pb.GeneratedMessage {
  factory PluginInfoList({
    $core.Iterable<PluginInfo>? plugins,
  }) {
    final result = create();
    if (plugins != null) result.plugins.addAll(plugins);
    return result;
  }

  PluginInfoList._();

  factory PluginInfoList.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PluginInfoList.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PluginInfoList',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pPM<PluginInfo>(1, _omitFieldNames ? '' : 'plugins',
        subBuilder: PluginInfo.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PluginInfoList clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PluginInfoList copyWith(void Function(PluginInfoList) updates) =>
      super.copyWith((message) => updates(message as PluginInfoList))
          as PluginInfoList;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PluginInfoList create() => PluginInfoList._();
  @$core.override
  PluginInfoList createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PluginInfoList getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PluginInfoList>(create);
  static PluginInfoList? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<PluginInfo> get plugins => $_getList(0);
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
