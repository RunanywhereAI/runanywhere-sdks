// This is a generated file - do not edit.
//
// Generated from sdk_events.proto.

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

import 'component_types.pbenum.dart' as $6;
import 'download_service.pb.dart' as $1;
import 'errors.pb.dart' as $4;
import 'hardware_profile.pb.dart' as $3;
import 'model_types.pb.dart' as $0;
import 'sdk_events.pbenum.dart';
import 'storage_types.pb.dart' as $2;
import 'voice_events.pb.dart' as $5;

export 'package:protobuf/protobuf.dart' show GeneratedMessageGenericExtensions;

export 'sdk_events.pbenum.dart';

/// ---------------------------------------------------------------------------
/// SDK lifecycle / initialization stage events. Mirrors
///   RN  events.ts:38-43 (SDKInitializationEvent: 5 variants)
/// Plus integrated "configurationLoaded" source field. NOT to be confused
/// with `ComponentInitializationEvent` (per-component lifecycle).
/// ---------------------------------------------------------------------------
class InitializationEvent extends $pb.GeneratedMessage {
  factory InitializationEvent({
    InitializationStage? stage,
    $core.String? source,
    $core.String? error,
    $core.String? version,
  }) {
    final result = create();
    if (stage != null) result.stage = stage;
    if (source != null) result.source = source;
    if (error != null) result.error = error;
    if (version != null) result.version = version;
    return result;
  }

  InitializationEvent._();

  factory InitializationEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory InitializationEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'InitializationEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<InitializationStage>(1, _omitFieldNames ? '' : 'stage',
        enumValues: InitializationStage.values)
    ..aOS(2, _omitFieldNames ? '' : 'source')
    ..aOS(3, _omitFieldNames ? '' : 'error')
    ..aOS(4, _omitFieldNames ? '' : 'version')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InitializationEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  InitializationEvent copyWith(void Function(InitializationEvent) updates) =>
      super.copyWith((message) => updates(message as InitializationEvent))
          as InitializationEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static InitializationEvent create() => InitializationEvent._();
  @$core.override
  InitializationEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static InitializationEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<InitializationEvent>(create);
  static InitializationEvent? _defaultInstance;

  @$pb.TagNumber(1)
  InitializationStage get stage => $_getN(0);
  @$pb.TagNumber(1)
  set stage(InitializationStage value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasStage() => $_has(0);
  @$pb.TagNumber(1)
  void clearStage() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get source => $_getSZ(1);
  @$pb.TagNumber(2)
  set source($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSource() => $_has(1);
  @$pb.TagNumber(2)
  void clearSource() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get error => $_getSZ(2);
  @$pb.TagNumber(3)
  set error($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(3)
  void clearError() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get version => $_getSZ(3);
  @$pb.TagNumber(4)
  set version($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasVersion() => $_has(3);
  @$pb.TagNumber(4)
  void clearVersion() => $_clearField(4);
}

/// ---------------------------------------------------------------------------
/// Configuration events — fetch / load / sync / settings retrieval / privacy /
/// routing-policy / analytics-status changes. Mirrors RN
///   events.ts:49-66 (SDKConfigurationEvent: 17 variants).
/// ---------------------------------------------------------------------------
class ConfigurationEvent extends $pb.GeneratedMessage {
  factory ConfigurationEvent({
    ConfigurationEventKind? kind,
    $core.String? source,
    $core.String? error,
    $core.Iterable<$core.String>? changedKeys,
    $core.String? settingsJson,
    $core.String? routingPolicy,
    $core.String? privacyMode,
    $core.bool? analyticsEnabled,
    $core.String? oldValueJson,
    $core.String? newValueJson,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (source != null) result.source = source;
    if (error != null) result.error = error;
    if (changedKeys != null) result.changedKeys.addAll(changedKeys);
    if (settingsJson != null) result.settingsJson = settingsJson;
    if (routingPolicy != null) result.routingPolicy = routingPolicy;
    if (privacyMode != null) result.privacyMode = privacyMode;
    if (analyticsEnabled != null) result.analyticsEnabled = analyticsEnabled;
    if (oldValueJson != null) result.oldValueJson = oldValueJson;
    if (newValueJson != null) result.newValueJson = newValueJson;
    return result;
  }

  ConfigurationEvent._();

  factory ConfigurationEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ConfigurationEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ConfigurationEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<ConfigurationEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: ConfigurationEventKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'source')
    ..aOS(3, _omitFieldNames ? '' : 'error')
    ..pPS(4, _omitFieldNames ? '' : 'changedKeys')
    ..aOS(5, _omitFieldNames ? '' : 'settingsJson')
    ..aOS(6, _omitFieldNames ? '' : 'routingPolicy')
    ..aOS(7, _omitFieldNames ? '' : 'privacyMode')
    ..aOB(8, _omitFieldNames ? '' : 'analyticsEnabled')
    ..aOS(9, _omitFieldNames ? '' : 'oldValueJson')
    ..aOS(10, _omitFieldNames ? '' : 'newValueJson')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigurationEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ConfigurationEvent copyWith(void Function(ConfigurationEvent) updates) =>
      super.copyWith((message) => updates(message as ConfigurationEvent))
          as ConfigurationEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ConfigurationEvent create() => ConfigurationEvent._();
  @$core.override
  ConfigurationEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ConfigurationEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ConfigurationEvent>(create);
  static ConfigurationEvent? _defaultInstance;

  @$pb.TagNumber(1)
  ConfigurationEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(ConfigurationEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  /// Source of configuration (`fetchCompleted.source`, `loaded.source`, …).
  @$pb.TagNumber(2)
  $core.String get source => $_getSZ(1);
  @$pb.TagNumber(2)
  set source($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSource() => $_has(1);
  @$pb.TagNumber(2)
  void clearSource() => $_clearField(2);

  /// Populated on FAILED variants (fetchFailed / syncFailed).
  @$pb.TagNumber(3)
  $core.String get error => $_getSZ(2);
  @$pb.TagNumber(3)
  set error($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(3)
  void clearError() => $_clearField(3);

  /// List of changed top-level keys (configurationUpdated). Kept as
  /// strings since each SDK uses different KV value types; analytics
  /// only cares about which keys moved.
  @$pb.TagNumber(4)
  $pb.PbList<$core.String> get changedKeys => $_getList(3);

  /// For settings_retrieved — the resulting settings serialized as JSON.
  /// Avoids embedding DefaultGenerationSettings here (lives in llm_options
  /// / config protos).
  @$pb.TagNumber(5)
  $core.String get settingsJson => $_getSZ(4);
  @$pb.TagNumber(5)
  set settingsJson($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSettingsJson() => $_has(4);
  @$pb.TagNumber(5)
  void clearSettingsJson() => $_clearField(5);

  /// For routing_policy_retrieved (RN events.ts:62 — `policy: string`).
  @$pb.TagNumber(6)
  $core.String get routingPolicy => $_getSZ(5);
  @$pb.TagNumber(6)
  set routingPolicy($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasRoutingPolicy() => $_has(5);
  @$pb.TagNumber(6)
  void clearRoutingPolicy() => $_clearField(6);

  /// For privacy_mode_retrieved (RN events.ts:64).
  @$pb.TagNumber(7)
  $core.String get privacyMode => $_getSZ(6);
  @$pb.TagNumber(7)
  set privacyMode($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasPrivacyMode() => $_has(6);
  @$pb.TagNumber(7)
  void clearPrivacyMode() => $_clearField(7);

  /// For analytics_status_retrieved (RN events.ts:66 — `enabled: boolean`).
  @$pb.TagNumber(8)
  $core.bool get analyticsEnabled => $_getBF(7);
  @$pb.TagNumber(8)
  set analyticsEnabled($core.bool value) => $_setBool(7, value);
  @$pb.TagNumber(8)
  $core.bool hasAnalyticsEnabled() => $_has(7);
  @$pb.TagNumber(8)
  void clearAnalyticsEnabled() => $_clearField(8);

  /// Old / new value pairs for config_changed (canonical primitive
  /// representation). Both stored as JSON-encoded strings to avoid
  /// dragging a dynamic-typed `Value` into the schema.
  @$pb.TagNumber(9)
  $core.String get oldValueJson => $_getSZ(8);
  @$pb.TagNumber(9)
  set oldValueJson($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasOldValueJson() => $_has(8);
  @$pb.TagNumber(9)
  void clearOldValueJson() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get newValueJson => $_getSZ(9);
  @$pb.TagNumber(10)
  set newValueJson($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasNewValueJson() => $_has(9);
  @$pb.TagNumber(10)
  void clearNewValueJson() => $_clearField(10);
}

/// ---------------------------------------------------------------------------
/// Per-component initialization lifecycle. Mirrors RN
///   events.ts:270-312 (ComponentInitializationEvent: 16 variants).
/// Distinct from `InitializationEvent` (overall SDK lifecycle).
/// ---------------------------------------------------------------------------
class ComponentInitializationEvent extends $pb.GeneratedMessage {
  factory ComponentInitializationEvent({
    ComponentInitializationEventKind? kind,
    SDKComponent? component,
    $core.String? modelId,
    $fixnum.Int64? sizeBytes,
    $core.double? progress,
    $core.String? error,
    $core.String? oldState,
    $core.String? newState,
    $core.Iterable<SDKComponent>? components,
    $core.Iterable<SDKComponent>? readyComponents,
    $core.Iterable<SDKComponent>? pendingComponents,
    $core.bool? initSuccess,
    $core.int? readyCount,
    $core.int? failedCount,
    $6.ComponentLifecycleState? previousLifecycleState,
    $6.ComponentLifecycleState? currentLifecycleState,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (component != null) result.component = component;
    if (modelId != null) result.modelId = modelId;
    if (sizeBytes != null) result.sizeBytes = sizeBytes;
    if (progress != null) result.progress = progress;
    if (error != null) result.error = error;
    if (oldState != null) result.oldState = oldState;
    if (newState != null) result.newState = newState;
    if (components != null) result.components.addAll(components);
    if (readyComponents != null) result.readyComponents.addAll(readyComponents);
    if (pendingComponents != null)
      result.pendingComponents.addAll(pendingComponents);
    if (initSuccess != null) result.initSuccess = initSuccess;
    if (readyCount != null) result.readyCount = readyCount;
    if (failedCount != null) result.failedCount = failedCount;
    if (previousLifecycleState != null)
      result.previousLifecycleState = previousLifecycleState;
    if (currentLifecycleState != null)
      result.currentLifecycleState = currentLifecycleState;
    return result;
  }

  ComponentInitializationEvent._();

  factory ComponentInitializationEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ComponentInitializationEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ComponentInitializationEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<ComponentInitializationEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: ComponentInitializationEventKind.values)
    ..aE<SDKComponent>(2, _omitFieldNames ? '' : 'component',
        enumValues: SDKComponent.values)
    ..aOS(3, _omitFieldNames ? '' : 'modelId')
    ..aInt64(4, _omitFieldNames ? '' : 'sizeBytes')
    ..aD(5, _omitFieldNames ? '' : 'progress', fieldType: $pb.PbFieldType.OF)
    ..aOS(6, _omitFieldNames ? '' : 'error')
    ..aOS(7, _omitFieldNames ? '' : 'oldState')
    ..aOS(8, _omitFieldNames ? '' : 'newState')
    ..pc<SDKComponent>(
        9, _omitFieldNames ? '' : 'components', $pb.PbFieldType.KE,
        valueOf: SDKComponent.valueOf,
        enumValues: SDKComponent.values,
        defaultEnumValue: SDKComponent.SDK_COMPONENT_UNSPECIFIED)
    ..pc<SDKComponent>(
        10, _omitFieldNames ? '' : 'readyComponents', $pb.PbFieldType.KE,
        valueOf: SDKComponent.valueOf,
        enumValues: SDKComponent.values,
        defaultEnumValue: SDKComponent.SDK_COMPONENT_UNSPECIFIED)
    ..pc<SDKComponent>(
        11, _omitFieldNames ? '' : 'pendingComponents', $pb.PbFieldType.KE,
        valueOf: SDKComponent.valueOf,
        enumValues: SDKComponent.values,
        defaultEnumValue: SDKComponent.SDK_COMPONENT_UNSPECIFIED)
    ..aOB(12, _omitFieldNames ? '' : 'initSuccess')
    ..aI(13, _omitFieldNames ? '' : 'readyCount')
    ..aI(14, _omitFieldNames ? '' : 'failedCount')
    ..aE<$6.ComponentLifecycleState>(
        15, _omitFieldNames ? '' : 'previousLifecycleState',
        enumValues: $6.ComponentLifecycleState.values)
    ..aE<$6.ComponentLifecycleState>(
        16, _omitFieldNames ? '' : 'currentLifecycleState',
        enumValues: $6.ComponentLifecycleState.values)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ComponentInitializationEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ComponentInitializationEvent copyWith(
          void Function(ComponentInitializationEvent) updates) =>
      super.copyWith(
              (message) => updates(message as ComponentInitializationEvent))
          as ComponentInitializationEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ComponentInitializationEvent create() =>
      ComponentInitializationEvent._();
  @$core.override
  ComponentInitializationEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ComponentInitializationEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ComponentInitializationEvent>(create);
  static ComponentInitializationEvent? _defaultInstance;

  @$pb.TagNumber(1)
  ComponentInitializationEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(ComponentInitializationEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  /// Single-component events (componentChecking / componentReady / …).
  @$pb.TagNumber(2)
  SDKComponent get component => $_getN(1);
  @$pb.TagNumber(2)
  set component(SDKComponent value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasComponent() => $_has(1);
  @$pb.TagNumber(2)
  void clearComponent() => $_clearField(2);

  /// For COMPONENT_CHECKING / COMPONENT_INITIALIZING / COMPONENT_READY /
  /// download events.
  @$pb.TagNumber(3)
  $core.String get modelId => $_getSZ(2);
  @$pb.TagNumber(3)
  set modelId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasModelId() => $_has(2);
  @$pb.TagNumber(3)
  void clearModelId() => $_clearField(3);

  /// For COMPONENT_DOWNLOAD_REQUIRED — RN events.ts:285.
  @$pb.TagNumber(4)
  $fixnum.Int64 get sizeBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set sizeBytes($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasSizeBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearSizeBytes() => $_clearField(4);

  /// For COMPONENT_DOWNLOAD_PROGRESS — 0.0..1.0.
  @$pb.TagNumber(5)
  $core.double get progress => $_getN(4);
  @$pb.TagNumber(5)
  set progress($core.double value) => $_setFloat(4, value);
  @$pb.TagNumber(5)
  $core.bool hasProgress() => $_has(4);
  @$pb.TagNumber(5)
  void clearProgress() => $_clearField(5);

  /// For COMPONENT_FAILED / *_FAILED.
  @$pb.TagNumber(6)
  $core.String get error => $_getSZ(5);
  @$pb.TagNumber(6)
  set error($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(6)
  void clearError() => $_clearField(6);

  /// For COMPONENT_STATE_CHANGED — RN events.ts:274-278.
  @$pb.TagNumber(7)
  $core.String get oldState => $_getSZ(6);
  @$pb.TagNumber(7)
  set oldState($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasOldState() => $_has(6);
  @$pb.TagNumber(7)
  void clearOldState() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get newState => $_getSZ(7);
  @$pb.TagNumber(8)
  set newState($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasNewState() => $_has(7);
  @$pb.TagNumber(8)
  void clearNewState() => $_clearField(8);

  /// For multi-component events (initializationStarted / parallel/sequential /
  /// someComponentsReady).
  @$pb.TagNumber(9)
  $pb.PbList<SDKComponent> get components => $_getList(8);

  @$pb.TagNumber(10)
  $pb.PbList<SDKComponent> get readyComponents => $_getList(9);

  @$pb.TagNumber(11)
  $pb.PbList<SDKComponent> get pendingComponents => $_getList(10);

  /// For INITIALIZATION_COMPLETED — InitializationResult summary
  /// (success bool + count). Full result travels via dedicated RPC.
  @$pb.TagNumber(12)
  $core.bool get initSuccess => $_getBF(11);
  @$pb.TagNumber(12)
  set initSuccess($core.bool value) => $_setBool(11, value);
  @$pb.TagNumber(12)
  $core.bool hasInitSuccess() => $_has(11);
  @$pb.TagNumber(12)
  void clearInitSuccess() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.int get readyCount => $_getIZ(12);
  @$pb.TagNumber(13)
  set readyCount($core.int value) => $_setSignedInt32(12, value);
  @$pb.TagNumber(13)
  $core.bool hasReadyCount() => $_has(12);
  @$pb.TagNumber(13)
  void clearReadyCount() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.int get failedCount => $_getIZ(13);
  @$pb.TagNumber(14)
  set failedCount($core.int value) => $_setSignedInt32(13, value);
  @$pb.TagNumber(14)
  $core.bool hasFailedCount() => $_has(13);
  @$pb.TagNumber(14)
  void clearFailedCount() => $_clearField(14);

  /// Typed equivalents of old_state/new_state for SDKs that want generated
  /// enum-backed component lifecycle state instead of parsing strings.
  @$pb.TagNumber(15)
  $6.ComponentLifecycleState get previousLifecycleState => $_getN(14);
  @$pb.TagNumber(15)
  set previousLifecycleState($6.ComponentLifecycleState value) =>
      $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasPreviousLifecycleState() => $_has(14);
  @$pb.TagNumber(15)
  void clearPreviousLifecycleState() => $_clearField(15);

  @$pb.TagNumber(16)
  $6.ComponentLifecycleState get currentLifecycleState => $_getN(15);
  @$pb.TagNumber(16)
  set currentLifecycleState($6.ComponentLifecycleState value) =>
      $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasCurrentLifecycleState() => $_has(15);
  @$pb.TagNumber(16)
  void clearCurrentLifecycleState() => $_clearField(16);
}

/// Snapshot of a component's current model-backed lifecycle state.
class ComponentLifecycleSnapshot extends $pb.GeneratedMessage {
  factory ComponentLifecycleSnapshot({
    SDKComponent? component,
    $6.ComponentLifecycleState? state,
    $core.String? modelId,
    $fixnum.Int64? updatedAtMs,
    $core.String? errorMessage,
    $0.ModelCategory? category,
    $0.InferenceFramework? framework,
    $core.String? resolvedPath,
    $fixnum.Int64? loadedAtUnixMs,
    $0.ModelInfo? model,
  }) {
    final result = create();
    if (component != null) result.component = component;
    if (state != null) result.state = state;
    if (modelId != null) result.modelId = modelId;
    if (updatedAtMs != null) result.updatedAtMs = updatedAtMs;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (category != null) result.category = category;
    if (framework != null) result.framework = framework;
    if (resolvedPath != null) result.resolvedPath = resolvedPath;
    if (loadedAtUnixMs != null) result.loadedAtUnixMs = loadedAtUnixMs;
    if (model != null) result.model = model;
    return result;
  }

  ComponentLifecycleSnapshot._();

  factory ComponentLifecycleSnapshot.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ComponentLifecycleSnapshot.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ComponentLifecycleSnapshot',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<SDKComponent>(1, _omitFieldNames ? '' : 'component',
        enumValues: SDKComponent.values)
    ..aE<$6.ComponentLifecycleState>(2, _omitFieldNames ? '' : 'state',
        enumValues: $6.ComponentLifecycleState.values)
    ..aOS(3, _omitFieldNames ? '' : 'modelId')
    ..aInt64(4, _omitFieldNames ? '' : 'updatedAtMs')
    ..aOS(5, _omitFieldNames ? '' : 'errorMessage')
    ..aE<$0.ModelCategory>(6, _omitFieldNames ? '' : 'category',
        enumValues: $0.ModelCategory.values)
    ..aE<$0.InferenceFramework>(7, _omitFieldNames ? '' : 'framework',
        enumValues: $0.InferenceFramework.values)
    ..aOS(8, _omitFieldNames ? '' : 'resolvedPath')
    ..aInt64(9, _omitFieldNames ? '' : 'loadedAtUnixMs')
    ..aOM<$0.ModelInfo>(10, _omitFieldNames ? '' : 'model',
        subBuilder: $0.ModelInfo.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ComponentLifecycleSnapshot clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ComponentLifecycleSnapshot copyWith(
          void Function(ComponentLifecycleSnapshot) updates) =>
      super.copyWith(
              (message) => updates(message as ComponentLifecycleSnapshot))
          as ComponentLifecycleSnapshot;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ComponentLifecycleSnapshot create() => ComponentLifecycleSnapshot._();
  @$core.override
  ComponentLifecycleSnapshot createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ComponentLifecycleSnapshot getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ComponentLifecycleSnapshot>(create);
  static ComponentLifecycleSnapshot? _defaultInstance;

  @$pb.TagNumber(1)
  SDKComponent get component => $_getN(0);
  @$pb.TagNumber(1)
  set component(SDKComponent value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasComponent() => $_has(0);
  @$pb.TagNumber(1)
  void clearComponent() => $_clearField(1);

  @$pb.TagNumber(2)
  $6.ComponentLifecycleState get state => $_getN(1);
  @$pb.TagNumber(2)
  set state($6.ComponentLifecycleState value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasState() => $_has(1);
  @$pb.TagNumber(2)
  void clearState() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get modelId => $_getSZ(2);
  @$pb.TagNumber(3)
  set modelId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasModelId() => $_has(2);
  @$pb.TagNumber(3)
  void clearModelId() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get updatedAtMs => $_getI64(3);
  @$pb.TagNumber(4)
  set updatedAtMs($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasUpdatedAtMs() => $_has(3);
  @$pb.TagNumber(4)
  void clearUpdatedAtMs() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get errorMessage => $_getSZ(4);
  @$pb.TagNumber(5)
  set errorMessage($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasErrorMessage() => $_has(4);
  @$pb.TagNumber(5)
  void clearErrorMessage() => $_clearField(5);

  @$pb.TagNumber(6)
  $0.ModelCategory get category => $_getN(5);
  @$pb.TagNumber(6)
  set category($0.ModelCategory value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasCategory() => $_has(5);
  @$pb.TagNumber(6)
  void clearCategory() => $_clearField(6);

  @$pb.TagNumber(7)
  $0.InferenceFramework get framework => $_getN(6);
  @$pb.TagNumber(7)
  set framework($0.InferenceFramework value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasFramework() => $_has(6);
  @$pb.TagNumber(7)
  void clearFramework() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get resolvedPath => $_getSZ(7);
  @$pb.TagNumber(8)
  set resolvedPath($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasResolvedPath() => $_has(7);
  @$pb.TagNumber(8)
  void clearResolvedPath() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get loadedAtUnixMs => $_getI64(8);
  @$pb.TagNumber(9)
  set loadedAtUnixMs($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasLoadedAtUnixMs() => $_has(8);
  @$pb.TagNumber(9)
  void clearLoadedAtUnixMs() => $_clearField(9);

  @$pb.TagNumber(10)
  $0.ModelInfo get model => $_getN(9);
  @$pb.TagNumber(10)
  set model($0.ModelInfo value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasModel() => $_has(9);
  @$pb.TagNumber(10)
  void clearModel() => $_clearField(10);
  @$pb.TagNumber(10)
  $0.ModelInfo ensureModel() => $_ensure(9);
}

class ComponentLifecycleSnapshotRequest extends $pb.GeneratedMessage {
  factory ComponentLifecycleSnapshotRequest({
    SDKComponent? component,
    $core.bool? includeModel,
  }) {
    final result = create();
    if (component != null) result.component = component;
    if (includeModel != null) result.includeModel = includeModel;
    return result;
  }

  ComponentLifecycleSnapshotRequest._();

  factory ComponentLifecycleSnapshotRequest.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ComponentLifecycleSnapshotRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ComponentLifecycleSnapshotRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<SDKComponent>(1, _omitFieldNames ? '' : 'component',
        enumValues: SDKComponent.values)
    ..aOB(2, _omitFieldNames ? '' : 'includeModel')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ComponentLifecycleSnapshotRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ComponentLifecycleSnapshotRequest copyWith(
          void Function(ComponentLifecycleSnapshotRequest) updates) =>
      super.copyWith((message) =>
              updates(message as ComponentLifecycleSnapshotRequest))
          as ComponentLifecycleSnapshotRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ComponentLifecycleSnapshotRequest create() =>
      ComponentLifecycleSnapshotRequest._();
  @$core.override
  ComponentLifecycleSnapshotRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ComponentLifecycleSnapshotRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ComponentLifecycleSnapshotRequest>(
          create);
  static ComponentLifecycleSnapshotRequest? _defaultInstance;

  @$pb.TagNumber(1)
  SDKComponent get component => $_getN(0);
  @$pb.TagNumber(1)
  set component(SDKComponent value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasComponent() => $_has(0);
  @$pb.TagNumber(1)
  void clearComponent() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.bool get includeModel => $_getBF(1);
  @$pb.TagNumber(2)
  set includeModel($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasIncludeModel() => $_has(1);
  @$pb.TagNumber(2)
  void clearIncludeModel() => $_clearField(2);
}

class ComponentLifecycleSnapshotResult extends $pb.GeneratedMessage {
  factory ComponentLifecycleSnapshotResult({
    $core.bool? success,
    $core.Iterable<ComponentLifecycleSnapshot>? snapshots,
    $core.String? errorMessage,
  }) {
    final result = create();
    if (success != null) result.success = success;
    if (snapshots != null) result.snapshots.addAll(snapshots);
    if (errorMessage != null) result.errorMessage = errorMessage;
    return result;
  }

  ComponentLifecycleSnapshotResult._();

  factory ComponentLifecycleSnapshotResult.fromBuffer(
          $core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ComponentLifecycleSnapshotResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ComponentLifecycleSnapshotResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'success')
    ..pPM<ComponentLifecycleSnapshot>(2, _omitFieldNames ? '' : 'snapshots',
        subBuilder: ComponentLifecycleSnapshot.create)
    ..aOS(3, _omitFieldNames ? '' : 'errorMessage')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ComponentLifecycleSnapshotResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ComponentLifecycleSnapshotResult copyWith(
          void Function(ComponentLifecycleSnapshotResult) updates) =>
      super.copyWith(
              (message) => updates(message as ComponentLifecycleSnapshotResult))
          as ComponentLifecycleSnapshotResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ComponentLifecycleSnapshotResult create() =>
      ComponentLifecycleSnapshotResult._();
  @$core.override
  ComponentLifecycleSnapshotResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ComponentLifecycleSnapshotResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ComponentLifecycleSnapshotResult>(
          create);
  static ComponentLifecycleSnapshotResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get success => $_getBF(0);
  @$pb.TagNumber(1)
  set success($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasSuccess() => $_has(0);
  @$pb.TagNumber(1)
  void clearSuccess() => $_clearField(1);

  @$pb.TagNumber(2)
  $pb.PbList<ComponentLifecycleSnapshot> get snapshots => $_getList(1);

  @$pb.TagNumber(3)
  $core.String get errorMessage => $_getSZ(2);
  @$pb.TagNumber(3)
  set errorMessage($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasErrorMessage() => $_has(2);
  @$pb.TagNumber(3)
  void clearErrorMessage() => $_clearField(3);
}

enum ComponentLifecycleEvent_Payload {
  modelLoadResult,
  modelUnloadResult,
  modelDeleteResult,
  downloadProgress,
  storageAvailability,
  storageDeleteResult,
  snapshot,
  snapshotResult,
  storageDeletePlan,
  notSet
}

/// Operation-aware lifecycle event. The oneof arms intentionally reference the
/// operation result/progress protos from this contract slice instead of adding
/// another broad event taxonomy.
class ComponentLifecycleEvent extends $pb.GeneratedMessage {
  factory ComponentLifecycleEvent({
    SDKComponent? component,
    $6.ComponentLifecycleState? previousState,
    $6.ComponentLifecycleState? currentState,
    $core.String? modelId,
    $fixnum.Int64? timestampMs,
    $0.ModelLoadResult? modelLoadResult,
    $0.ModelUnloadResult? modelUnloadResult,
    $0.ModelDeleteResult? modelDeleteResult,
    $1.DownloadProgress? downloadProgress,
    $2.StorageAvailabilityResult? storageAvailability,
    $2.StorageDeleteResult? storageDeleteResult,
    ComponentLifecycleSnapshot? snapshot,
    ComponentLifecycleSnapshotResult? snapshotResult,
    $2.StorageDeletePlan? storageDeletePlan,
  }) {
    final result = create();
    if (component != null) result.component = component;
    if (previousState != null) result.previousState = previousState;
    if (currentState != null) result.currentState = currentState;
    if (modelId != null) result.modelId = modelId;
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (modelLoadResult != null) result.modelLoadResult = modelLoadResult;
    if (modelUnloadResult != null) result.modelUnloadResult = modelUnloadResult;
    if (modelDeleteResult != null) result.modelDeleteResult = modelDeleteResult;
    if (downloadProgress != null) result.downloadProgress = downloadProgress;
    if (storageAvailability != null)
      result.storageAvailability = storageAvailability;
    if (storageDeleteResult != null)
      result.storageDeleteResult = storageDeleteResult;
    if (snapshot != null) result.snapshot = snapshot;
    if (snapshotResult != null) result.snapshotResult = snapshotResult;
    if (storageDeletePlan != null) result.storageDeletePlan = storageDeletePlan;
    return result;
  }

  ComponentLifecycleEvent._();

  factory ComponentLifecycleEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ComponentLifecycleEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ComponentLifecycleEvent_Payload>
      _ComponentLifecycleEvent_PayloadByTag = {
    10: ComponentLifecycleEvent_Payload.modelLoadResult,
    11: ComponentLifecycleEvent_Payload.modelUnloadResult,
    12: ComponentLifecycleEvent_Payload.modelDeleteResult,
    13: ComponentLifecycleEvent_Payload.downloadProgress,
    14: ComponentLifecycleEvent_Payload.storageAvailability,
    15: ComponentLifecycleEvent_Payload.storageDeleteResult,
    16: ComponentLifecycleEvent_Payload.snapshot,
    17: ComponentLifecycleEvent_Payload.snapshotResult,
    18: ComponentLifecycleEvent_Payload.storageDeletePlan,
    0: ComponentLifecycleEvent_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ComponentLifecycleEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..oo(0, [10, 11, 12, 13, 14, 15, 16, 17, 18])
    ..aE<SDKComponent>(1, _omitFieldNames ? '' : 'component',
        enumValues: SDKComponent.values)
    ..aE<$6.ComponentLifecycleState>(2, _omitFieldNames ? '' : 'previousState',
        enumValues: $6.ComponentLifecycleState.values)
    ..aE<$6.ComponentLifecycleState>(3, _omitFieldNames ? '' : 'currentState',
        enumValues: $6.ComponentLifecycleState.values)
    ..aOS(4, _omitFieldNames ? '' : 'modelId')
    ..aInt64(5, _omitFieldNames ? '' : 'timestampMs')
    ..aOM<$0.ModelLoadResult>(10, _omitFieldNames ? '' : 'modelLoadResult',
        subBuilder: $0.ModelLoadResult.create)
    ..aOM<$0.ModelUnloadResult>(11, _omitFieldNames ? '' : 'modelUnloadResult',
        subBuilder: $0.ModelUnloadResult.create)
    ..aOM<$0.ModelDeleteResult>(12, _omitFieldNames ? '' : 'modelDeleteResult',
        subBuilder: $0.ModelDeleteResult.create)
    ..aOM<$1.DownloadProgress>(13, _omitFieldNames ? '' : 'downloadProgress',
        subBuilder: $1.DownloadProgress.create)
    ..aOM<$2.StorageAvailabilityResult>(
        14, _omitFieldNames ? '' : 'storageAvailability',
        subBuilder: $2.StorageAvailabilityResult.create)
    ..aOM<$2.StorageDeleteResult>(
        15, _omitFieldNames ? '' : 'storageDeleteResult',
        subBuilder: $2.StorageDeleteResult.create)
    ..aOM<ComponentLifecycleSnapshot>(16, _omitFieldNames ? '' : 'snapshot',
        subBuilder: ComponentLifecycleSnapshot.create)
    ..aOM<ComponentLifecycleSnapshotResult>(
        17, _omitFieldNames ? '' : 'snapshotResult',
        subBuilder: ComponentLifecycleSnapshotResult.create)
    ..aOM<$2.StorageDeletePlan>(18, _omitFieldNames ? '' : 'storageDeletePlan',
        subBuilder: $2.StorageDeletePlan.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ComponentLifecycleEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ComponentLifecycleEvent copyWith(
          void Function(ComponentLifecycleEvent) updates) =>
      super.copyWith((message) => updates(message as ComponentLifecycleEvent))
          as ComponentLifecycleEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ComponentLifecycleEvent create() => ComponentLifecycleEvent._();
  @$core.override
  ComponentLifecycleEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ComponentLifecycleEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ComponentLifecycleEvent>(create);
  static ComponentLifecycleEvent? _defaultInstance;

  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  ComponentLifecycleEvent_Payload whichPayload() =>
      _ComponentLifecycleEvent_PayloadByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(13)
  @$pb.TagNumber(14)
  @$pb.TagNumber(15)
  @$pb.TagNumber(16)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  void clearPayload() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  SDKComponent get component => $_getN(0);
  @$pb.TagNumber(1)
  set component(SDKComponent value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasComponent() => $_has(0);
  @$pb.TagNumber(1)
  void clearComponent() => $_clearField(1);

  @$pb.TagNumber(2)
  $6.ComponentLifecycleState get previousState => $_getN(1);
  @$pb.TagNumber(2)
  set previousState($6.ComponentLifecycleState value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasPreviousState() => $_has(1);
  @$pb.TagNumber(2)
  void clearPreviousState() => $_clearField(2);

  @$pb.TagNumber(3)
  $6.ComponentLifecycleState get currentState => $_getN(2);
  @$pb.TagNumber(3)
  set currentState($6.ComponentLifecycleState value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasCurrentState() => $_has(2);
  @$pb.TagNumber(3)
  void clearCurrentState() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get modelId => $_getSZ(3);
  @$pb.TagNumber(4)
  set modelId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasModelId() => $_has(3);
  @$pb.TagNumber(4)
  void clearModelId() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get timestampMs => $_getI64(4);
  @$pb.TagNumber(5)
  set timestampMs($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasTimestampMs() => $_has(4);
  @$pb.TagNumber(5)
  void clearTimestampMs() => $_clearField(5);

  @$pb.TagNumber(10)
  $0.ModelLoadResult get modelLoadResult => $_getN(5);
  @$pb.TagNumber(10)
  set modelLoadResult($0.ModelLoadResult value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasModelLoadResult() => $_has(5);
  @$pb.TagNumber(10)
  void clearModelLoadResult() => $_clearField(10);
  @$pb.TagNumber(10)
  $0.ModelLoadResult ensureModelLoadResult() => $_ensure(5);

  @$pb.TagNumber(11)
  $0.ModelUnloadResult get modelUnloadResult => $_getN(6);
  @$pb.TagNumber(11)
  set modelUnloadResult($0.ModelUnloadResult value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasModelUnloadResult() => $_has(6);
  @$pb.TagNumber(11)
  void clearModelUnloadResult() => $_clearField(11);
  @$pb.TagNumber(11)
  $0.ModelUnloadResult ensureModelUnloadResult() => $_ensure(6);

  @$pb.TagNumber(12)
  $0.ModelDeleteResult get modelDeleteResult => $_getN(7);
  @$pb.TagNumber(12)
  set modelDeleteResult($0.ModelDeleteResult value) => $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasModelDeleteResult() => $_has(7);
  @$pb.TagNumber(12)
  void clearModelDeleteResult() => $_clearField(12);
  @$pb.TagNumber(12)
  $0.ModelDeleteResult ensureModelDeleteResult() => $_ensure(7);

  @$pb.TagNumber(13)
  $1.DownloadProgress get downloadProgress => $_getN(8);
  @$pb.TagNumber(13)
  set downloadProgress($1.DownloadProgress value) => $_setField(13, value);
  @$pb.TagNumber(13)
  $core.bool hasDownloadProgress() => $_has(8);
  @$pb.TagNumber(13)
  void clearDownloadProgress() => $_clearField(13);
  @$pb.TagNumber(13)
  $1.DownloadProgress ensureDownloadProgress() => $_ensure(8);

  @$pb.TagNumber(14)
  $2.StorageAvailabilityResult get storageAvailability => $_getN(9);
  @$pb.TagNumber(14)
  set storageAvailability($2.StorageAvailabilityResult value) =>
      $_setField(14, value);
  @$pb.TagNumber(14)
  $core.bool hasStorageAvailability() => $_has(9);
  @$pb.TagNumber(14)
  void clearStorageAvailability() => $_clearField(14);
  @$pb.TagNumber(14)
  $2.StorageAvailabilityResult ensureStorageAvailability() => $_ensure(9);

  @$pb.TagNumber(15)
  $2.StorageDeleteResult get storageDeleteResult => $_getN(10);
  @$pb.TagNumber(15)
  set storageDeleteResult($2.StorageDeleteResult value) =>
      $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasStorageDeleteResult() => $_has(10);
  @$pb.TagNumber(15)
  void clearStorageDeleteResult() => $_clearField(15);
  @$pb.TagNumber(15)
  $2.StorageDeleteResult ensureStorageDeleteResult() => $_ensure(10);

  @$pb.TagNumber(16)
  ComponentLifecycleSnapshot get snapshot => $_getN(11);
  @$pb.TagNumber(16)
  set snapshot(ComponentLifecycleSnapshot value) => $_setField(16, value);
  @$pb.TagNumber(16)
  $core.bool hasSnapshot() => $_has(11);
  @$pb.TagNumber(16)
  void clearSnapshot() => $_clearField(16);
  @$pb.TagNumber(16)
  ComponentLifecycleSnapshot ensureSnapshot() => $_ensure(11);

  @$pb.TagNumber(17)
  ComponentLifecycleSnapshotResult get snapshotResult => $_getN(12);
  @$pb.TagNumber(17)
  set snapshotResult(ComponentLifecycleSnapshotResult value) =>
      $_setField(17, value);
  @$pb.TagNumber(17)
  $core.bool hasSnapshotResult() => $_has(12);
  @$pb.TagNumber(17)
  void clearSnapshotResult() => $_clearField(17);
  @$pb.TagNumber(17)
  ComponentLifecycleSnapshotResult ensureSnapshotResult() => $_ensure(12);

  @$pb.TagNumber(18)
  $2.StorageDeletePlan get storageDeletePlan => $_getN(13);
  @$pb.TagNumber(18)
  set storageDeletePlan($2.StorageDeletePlan value) => $_setField(18, value);
  @$pb.TagNumber(18)
  $core.bool hasStorageDeletePlan() => $_has(13);
  @$pb.TagNumber(18)
  void clearStorageDeletePlan() => $_clearField(18);
  @$pb.TagNumber(18)
  $2.StorageDeletePlan ensureStorageDeletePlan() => $_ensure(13);
}

/// SDK session lifecycle independent of voice-agent turn sessions.
class SessionEvent extends $pb.GeneratedMessage {
  factory SessionEvent({
    SessionEventKind? kind,
    $core.String? sessionId,
    $core.String? userId,
    $core.String? reason,
    $core.String? error,
    $fixnum.Int64? startedAtMs,
    $fixnum.Int64? endedAtMs,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (sessionId != null) result.sessionId = sessionId;
    if (userId != null) result.userId = userId;
    if (reason != null) result.reason = reason;
    if (error != null) result.error = error;
    if (startedAtMs != null) result.startedAtMs = startedAtMs;
    if (endedAtMs != null) result.endedAtMs = endedAtMs;
    return result;
  }

  SessionEvent._();

  factory SessionEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SessionEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SessionEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<SessionEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: SessionEventKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'sessionId')
    ..aOS(3, _omitFieldNames ? '' : 'userId')
    ..aOS(4, _omitFieldNames ? '' : 'reason')
    ..aOS(5, _omitFieldNames ? '' : 'error')
    ..aInt64(6, _omitFieldNames ? '' : 'startedAtMs')
    ..aInt64(7, _omitFieldNames ? '' : 'endedAtMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SessionEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SessionEvent copyWith(void Function(SessionEvent) updates) =>
      super.copyWith((message) => updates(message as SessionEvent))
          as SessionEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SessionEvent create() => SessionEvent._();
  @$core.override
  SessionEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SessionEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SessionEvent>(create);
  static SessionEvent? _defaultInstance;

  @$pb.TagNumber(1)
  SessionEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(SessionEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get sessionId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sessionId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSessionId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSessionId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get userId => $_getSZ(2);
  @$pb.TagNumber(3)
  set userId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasUserId() => $_has(2);
  @$pb.TagNumber(3)
  void clearUserId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get reason => $_getSZ(3);
  @$pb.TagNumber(4)
  set reason($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasReason() => $_has(3);
  @$pb.TagNumber(4)
  void clearReason() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get error => $_getSZ(4);
  @$pb.TagNumber(5)
  set error($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasError() => $_has(4);
  @$pb.TagNumber(5)
  void clearError() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get startedAtMs => $_getI64(5);
  @$pb.TagNumber(6)
  set startedAtMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasStartedAtMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearStartedAtMs() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get endedAtMs => $_getI64(6);
  @$pb.TagNumber(7)
  set endedAtMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasEndedAtMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearEndedAtMs() => $_clearField(7);
}

/// ---------------------------------------------------------------------------
/// LLM generation events. Mirrors RN
///   events.ts:72-89 (SDKGenerationEvent: 12 variants).
/// Plus Kotlin LLMEvent (5 variants), Dart SDKGenerationEvent (4 factories).
/// ---------------------------------------------------------------------------
class GenerationEvent extends $pb.GeneratedMessage {
  factory GenerationEvent({
    GenerationEventKind? kind,
    $core.String? sessionId,
    $core.String? prompt,
    $core.String? token,
    $core.String? streamingText,
    $core.int? tokensCount,
    $core.String? response,
    $core.int? tokensUsed,
    $fixnum.Int64? latencyMs,
    $fixnum.Int64? firstTokenLatencyMs,
    $core.String? error,
    $core.String? modelId,
    $core.double? costAmount,
    $core.double? costSavedAmount,
    $core.String? routingTarget,
    $core.String? routingReason,
    $core.String? cancelReason,
    $core.String? toolCallId,
    $core.String? toolName,
    $core.String? toolPayloadJson,
    $core.String? structuredSchemaJson,
    $core.String? structuredOutputJson,
    $core.String? thinkingText,
    $core.int? inputTokens,
    $core.double? tokensPerSecond,
    $fixnum.Int64? timeToFirstTokenMs,
    $core.bool? isStreaming,
    $core.double? temperature,
    $core.int? maxTokens,
    $core.int? contextLength,
    $core.String? modelName,
    $core.double? durationMs,
    $core.int? framework,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (sessionId != null) result.sessionId = sessionId;
    if (prompt != null) result.prompt = prompt;
    if (token != null) result.token = token;
    if (streamingText != null) result.streamingText = streamingText;
    if (tokensCount != null) result.tokensCount = tokensCount;
    if (response != null) result.response = response;
    if (tokensUsed != null) result.tokensUsed = tokensUsed;
    if (latencyMs != null) result.latencyMs = latencyMs;
    if (firstTokenLatencyMs != null)
      result.firstTokenLatencyMs = firstTokenLatencyMs;
    if (error != null) result.error = error;
    if (modelId != null) result.modelId = modelId;
    if (costAmount != null) result.costAmount = costAmount;
    if (costSavedAmount != null) result.costSavedAmount = costSavedAmount;
    if (routingTarget != null) result.routingTarget = routingTarget;
    if (routingReason != null) result.routingReason = routingReason;
    if (cancelReason != null) result.cancelReason = cancelReason;
    if (toolCallId != null) result.toolCallId = toolCallId;
    if (toolName != null) result.toolName = toolName;
    if (toolPayloadJson != null) result.toolPayloadJson = toolPayloadJson;
    if (structuredSchemaJson != null)
      result.structuredSchemaJson = structuredSchemaJson;
    if (structuredOutputJson != null)
      result.structuredOutputJson = structuredOutputJson;
    if (thinkingText != null) result.thinkingText = thinkingText;
    if (inputTokens != null) result.inputTokens = inputTokens;
    if (tokensPerSecond != null) result.tokensPerSecond = tokensPerSecond;
    if (timeToFirstTokenMs != null)
      result.timeToFirstTokenMs = timeToFirstTokenMs;
    if (isStreaming != null) result.isStreaming = isStreaming;
    if (temperature != null) result.temperature = temperature;
    if (maxTokens != null) result.maxTokens = maxTokens;
    if (contextLength != null) result.contextLength = contextLength;
    if (modelName != null) result.modelName = modelName;
    if (durationMs != null) result.durationMs = durationMs;
    if (framework != null) result.framework = framework;
    return result;
  }

  GenerationEvent._();

  factory GenerationEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory GenerationEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'GenerationEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<GenerationEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: GenerationEventKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'sessionId')
    ..aOS(3, _omitFieldNames ? '' : 'prompt')
    ..aOS(4, _omitFieldNames ? '' : 'token')
    ..aOS(5, _omitFieldNames ? '' : 'streamingText')
    ..aI(6, _omitFieldNames ? '' : 'tokensCount')
    ..aOS(7, _omitFieldNames ? '' : 'response')
    ..aI(8, _omitFieldNames ? '' : 'tokensUsed')
    ..aInt64(9, _omitFieldNames ? '' : 'latencyMs')
    ..aInt64(10, _omitFieldNames ? '' : 'firstTokenLatencyMs')
    ..aOS(11, _omitFieldNames ? '' : 'error')
    ..aOS(12, _omitFieldNames ? '' : 'modelId')
    ..aD(13, _omitFieldNames ? '' : 'costAmount')
    ..aD(14, _omitFieldNames ? '' : 'costSavedAmount')
    ..aOS(15, _omitFieldNames ? '' : 'routingTarget')
    ..aOS(16, _omitFieldNames ? '' : 'routingReason')
    ..aOS(17, _omitFieldNames ? '' : 'cancelReason')
    ..aOS(18, _omitFieldNames ? '' : 'toolCallId')
    ..aOS(19, _omitFieldNames ? '' : 'toolName')
    ..aOS(20, _omitFieldNames ? '' : 'toolPayloadJson')
    ..aOS(21, _omitFieldNames ? '' : 'structuredSchemaJson')
    ..aOS(22, _omitFieldNames ? '' : 'structuredOutputJson')
    ..aOS(23, _omitFieldNames ? '' : 'thinkingText')
    ..aI(24, _omitFieldNames ? '' : 'inputTokens')
    ..aD(25, _omitFieldNames ? '' : 'tokensPerSecond')
    ..aInt64(26, _omitFieldNames ? '' : 'timeToFirstTokenMs')
    ..aOB(27, _omitFieldNames ? '' : 'isStreaming')
    ..aD(28, _omitFieldNames ? '' : 'temperature',
        fieldType: $pb.PbFieldType.OF)
    ..aI(29, _omitFieldNames ? '' : 'maxTokens')
    ..aI(30, _omitFieldNames ? '' : 'contextLength')
    ..aOS(31, _omitFieldNames ? '' : 'modelName')
    ..aD(32, _omitFieldNames ? '' : 'durationMs')
    ..aI(33, _omitFieldNames ? '' : 'framework')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GenerationEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  GenerationEvent copyWith(void Function(GenerationEvent) updates) =>
      super.copyWith((message) => updates(message as GenerationEvent))
          as GenerationEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static GenerationEvent create() => GenerationEvent._();
  @$core.override
  GenerationEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static GenerationEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<GenerationEvent>(create);
  static GenerationEvent? _defaultInstance;

  @$pb.TagNumber(1)
  GenerationEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(GenerationEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  /// Optional session id (RN voiceSession_*, generationStarted.sessionId).
  @$pb.TagNumber(2)
  $core.String get sessionId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sessionId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSessionId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSessionId() => $_clearField(2);

  /// For STARTED — the prompt text (RN events.ts:75).
  @$pb.TagNumber(3)
  $core.String get prompt => $_getSZ(2);
  @$pb.TagNumber(3)
  set prompt($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasPrompt() => $_has(2);
  @$pb.TagNumber(3)
  void clearPrompt() => $_clearField(3);

  /// For TOKEN_GENERATED / FIRST_TOKEN_GENERATED — single token text.
  @$pb.TagNumber(4)
  $core.String get token => $_getSZ(3);
  @$pb.TagNumber(4)
  set token($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasToken() => $_has(3);
  @$pb.TagNumber(4)
  void clearToken() => $_clearField(4);

  /// For STREAMING_UPDATE — the running response text and token count.
  @$pb.TagNumber(5)
  $core.String get streamingText => $_getSZ(4);
  @$pb.TagNumber(5)
  set streamingText($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasStreamingText() => $_has(4);
  @$pb.TagNumber(5)
  void clearStreamingText() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.int get tokensCount => $_getIZ(5);
  @$pb.TagNumber(6)
  set tokensCount($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTokensCount() => $_has(5);
  @$pb.TagNumber(6)
  void clearTokensCount() => $_clearField(6);

  /// For COMPLETED — full response, usage stats, latency.
  @$pb.TagNumber(7)
  $core.String get response => $_getSZ(6);
  @$pb.TagNumber(7)
  set response($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasResponse() => $_has(6);
  @$pb.TagNumber(7)
  void clearResponse() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.int get tokensUsed => $_getIZ(7);
  @$pb.TagNumber(8)
  set tokensUsed($core.int value) => $_setSignedInt32(7, value);
  @$pb.TagNumber(8)
  $core.bool hasTokensUsed() => $_has(7);
  @$pb.TagNumber(8)
  void clearTokensUsed() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get latencyMs => $_getI64(8);
  @$pb.TagNumber(9)
  set latencyMs($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasLatencyMs() => $_has(8);
  @$pb.TagNumber(9)
  void clearLatencyMs() => $_clearField(9);

  /// For FIRST_TOKEN_GENERATED — TTFT in ms (RN events.ts:76).
  @$pb.TagNumber(10)
  $fixnum.Int64 get firstTokenLatencyMs => $_getI64(9);
  @$pb.TagNumber(10)
  set firstTokenLatencyMs($fixnum.Int64 value) => $_setInt64(9, value);
  @$pb.TagNumber(10)
  $core.bool hasFirstTokenLatencyMs() => $_has(9);
  @$pb.TagNumber(10)
  void clearFirstTokenLatencyMs() => $_clearField(10);

  /// For FAILED.
  @$pb.TagNumber(11)
  $core.String get error => $_getSZ(10);
  @$pb.TagNumber(11)
  set error($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasError() => $_has(10);
  @$pb.TagNumber(11)
  void clearError() => $_clearField(11);

  /// For MODEL_LOADED / MODEL_UNLOADED — bound model.
  @$pb.TagNumber(12)
  $core.String get modelId => $_getSZ(11);
  @$pb.TagNumber(12)
  set modelId($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasModelId() => $_has(11);
  @$pb.TagNumber(12)
  void clearModelId() => $_clearField(12);

  /// For COST_CALCULATED — RN events.ts:88, Dart SDKGenerationCostCalculated.
  @$pb.TagNumber(13)
  $core.double get costAmount => $_getN(12);
  @$pb.TagNumber(13)
  set costAmount($core.double value) => $_setDouble(12, value);
  @$pb.TagNumber(13)
  $core.bool hasCostAmount() => $_has(12);
  @$pb.TagNumber(13)
  void clearCostAmount() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.double get costSavedAmount => $_getN(13);
  @$pb.TagNumber(14)
  set costSavedAmount($core.double value) => $_setDouble(13, value);
  @$pb.TagNumber(14)
  $core.bool hasCostSavedAmount() => $_has(13);
  @$pb.TagNumber(14)
  void clearCostSavedAmount() => $_clearField(14);

  /// For ROUTING_DECISION — RN events.ts:89.
  @$pb.TagNumber(15)
  $core.String get routingTarget => $_getSZ(14);
  @$pb.TagNumber(15)
  set routingTarget($core.String value) => $_setString(14, value);
  @$pb.TagNumber(15)
  $core.bool hasRoutingTarget() => $_has(14);
  @$pb.TagNumber(15)
  void clearRoutingTarget() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.String get routingReason => $_getSZ(15);
  @$pb.TagNumber(16)
  set routingReason($core.String value) => $_setString(15, value);
  @$pb.TagNumber(16)
  $core.bool hasRoutingReason() => $_has(15);
  @$pb.TagNumber(16)
  void clearRoutingReason() => $_clearField(16);

  /// For cancellation / tool / structured-output / thinking events.
  @$pb.TagNumber(17)
  $core.String get cancelReason => $_getSZ(16);
  @$pb.TagNumber(17)
  set cancelReason($core.String value) => $_setString(16, value);
  @$pb.TagNumber(17)
  $core.bool hasCancelReason() => $_has(16);
  @$pb.TagNumber(17)
  void clearCancelReason() => $_clearField(17);

  @$pb.TagNumber(18)
  $core.String get toolCallId => $_getSZ(17);
  @$pb.TagNumber(18)
  set toolCallId($core.String value) => $_setString(17, value);
  @$pb.TagNumber(18)
  $core.bool hasToolCallId() => $_has(17);
  @$pb.TagNumber(18)
  void clearToolCallId() => $_clearField(18);

  @$pb.TagNumber(19)
  $core.String get toolName => $_getSZ(18);
  @$pb.TagNumber(19)
  set toolName($core.String value) => $_setString(18, value);
  @$pb.TagNumber(19)
  $core.bool hasToolName() => $_has(18);
  @$pb.TagNumber(19)
  void clearToolName() => $_clearField(19);

  @$pb.TagNumber(20)
  $core.String get toolPayloadJson => $_getSZ(19);
  @$pb.TagNumber(20)
  set toolPayloadJson($core.String value) => $_setString(19, value);
  @$pb.TagNumber(20)
  $core.bool hasToolPayloadJson() => $_has(19);
  @$pb.TagNumber(20)
  void clearToolPayloadJson() => $_clearField(20);

  @$pb.TagNumber(21)
  $core.String get structuredSchemaJson => $_getSZ(20);
  @$pb.TagNumber(21)
  set structuredSchemaJson($core.String value) => $_setString(20, value);
  @$pb.TagNumber(21)
  $core.bool hasStructuredSchemaJson() => $_has(20);
  @$pb.TagNumber(21)
  void clearStructuredSchemaJson() => $_clearField(21);

  @$pb.TagNumber(22)
  $core.String get structuredOutputJson => $_getSZ(21);
  @$pb.TagNumber(22)
  set structuredOutputJson($core.String value) => $_setString(21, value);
  @$pb.TagNumber(22)
  $core.bool hasStructuredOutputJson() => $_has(21);
  @$pb.TagNumber(22)
  void clearStructuredOutputJson() => $_clearField(22);

  @$pb.TagNumber(23)
  $core.String get thinkingText => $_getSZ(22);
  @$pb.TagNumber(23)
  set thinkingText($core.String value) => $_setString(22, value);
  @$pb.TagNumber(23)
  $core.bool hasThinkingText() => $_has(22);
  @$pb.TagNumber(23)
  void clearThinkingText() => $_clearField(23);

  /// For COMPLETED — prompt-token count (mirrors RALLMGenerationResult.inputTokens).
  /// Enables totalTokens = input_tokens + tokens_used analytics
  /// from the event stream alone.
  @$pb.TagNumber(24)
  $core.int get inputTokens => $_getIZ(23);
  @$pb.TagNumber(24)
  set inputTokens($core.int value) => $_setSignedInt32(23, value);
  @$pb.TagNumber(24)
  $core.bool hasInputTokens() => $_has(23);
  @$pb.TagNumber(24)
  void clearInputTokens() => $_clearField(24);

  /// Telemetry metrics carried on the canonical event stream so the C++
  /// destination router can derive the full telemetry payload from the
  /// proto SDKEvent alone (no parallel struct path). `framework` is the
  /// InferenceFramework enum stored as int32 (matches FrameworkEvent.framework).
  @$pb.TagNumber(25)
  $core.double get tokensPerSecond => $_getN(24);
  @$pb.TagNumber(25)
  set tokensPerSecond($core.double value) => $_setDouble(24, value);
  @$pb.TagNumber(25)
  $core.bool hasTokensPerSecond() => $_has(24);
  @$pb.TagNumber(25)
  void clearTokensPerSecond() => $_clearField(25);

  @$pb.TagNumber(26)
  $fixnum.Int64 get timeToFirstTokenMs => $_getI64(25);
  @$pb.TagNumber(26)
  set timeToFirstTokenMs($fixnum.Int64 value) => $_setInt64(25, value);
  @$pb.TagNumber(26)
  $core.bool hasTimeToFirstTokenMs() => $_has(25);
  @$pb.TagNumber(26)
  void clearTimeToFirstTokenMs() => $_clearField(26);

  @$pb.TagNumber(27)
  $core.bool get isStreaming => $_getBF(26);
  @$pb.TagNumber(27)
  set isStreaming($core.bool value) => $_setBool(26, value);
  @$pb.TagNumber(27)
  $core.bool hasIsStreaming() => $_has(26);
  @$pb.TagNumber(27)
  void clearIsStreaming() => $_clearField(27);

  @$pb.TagNumber(28)
  $core.double get temperature => $_getN(27);
  @$pb.TagNumber(28)
  set temperature($core.double value) => $_setFloat(27, value);
  @$pb.TagNumber(28)
  $core.bool hasTemperature() => $_has(27);
  @$pb.TagNumber(28)
  void clearTemperature() => $_clearField(28);

  @$pb.TagNumber(29)
  $core.int get maxTokens => $_getIZ(28);
  @$pb.TagNumber(29)
  set maxTokens($core.int value) => $_setSignedInt32(28, value);
  @$pb.TagNumber(29)
  $core.bool hasMaxTokens() => $_has(28);
  @$pb.TagNumber(29)
  void clearMaxTokens() => $_clearField(29);

  @$pb.TagNumber(30)
  $core.int get contextLength => $_getIZ(29);
  @$pb.TagNumber(30)
  set contextLength($core.int value) => $_setSignedInt32(29, value);
  @$pb.TagNumber(30)
  $core.bool hasContextLength() => $_has(29);
  @$pb.TagNumber(30)
  void clearContextLength() => $_clearField(30);

  @$pb.TagNumber(31)
  $core.String get modelName => $_getSZ(30);
  @$pb.TagNumber(31)
  set modelName($core.String value) => $_setString(30, value);
  @$pb.TagNumber(31)
  $core.bool hasModelName() => $_has(30);
  @$pb.TagNumber(31)
  void clearModelName() => $_clearField(31);

  @$pb.TagNumber(32)
  $core.double get durationMs => $_getN(31);
  @$pb.TagNumber(32)
  set durationMs($core.double value) => $_setDouble(31, value);
  @$pb.TagNumber(32)
  $core.bool hasDurationMs() => $_has(31);
  @$pb.TagNumber(32)
  void clearDurationMs() => $_clearField(32);

  @$pb.TagNumber(33)
  $core.int get framework => $_getIZ(32);
  @$pb.TagNumber(33)
  set framework($core.int value) => $_setSignedInt32(32, value);
  @$pb.TagNumber(33)
  $core.bool hasFramework() => $_has(32);
  @$pb.TagNumber(33)
  void clearFramework() => $_clearField(33);
}

/// ---------------------------------------------------------------------------
/// Voice / audio higher-level events. Mirrors RN
///   events.ts:136-187 (SDKVoiceEvent: 41 variants).
/// Plus Dart SDKVoiceEvent (~15 concrete classes), Kotlin STTEvent + TTSEvent.
///
/// Renamed from `VoiceEvent` to `VoiceLifecycleEvent` to avoid colliding with
/// `runanywhere.v1.VoiceEvent` from voice_events.proto, which carries the
/// low-level streaming pipeline payloads (UserSaid / AssistantToken /
/// AudioFrame / VAD / Interrupted / StateChange / Error / Metrics). The
/// pipeline events are exposed via SDKEvent.voice_pipeline; this message
/// is exposed via SDKEvent.voice.
/// ---------------------------------------------------------------------------
class VoiceLifecycleEvent extends $pb.GeneratedMessage {
  factory VoiceLifecycleEvent({
    VoiceEventKind? kind,
    $core.String? sessionId,
    $core.String? text,
    $core.double? confidence,
    $core.String? responseText,
    $core.String? audioBase64,
    $fixnum.Int64? durationMs,
    $core.double? audioLevel,
    $core.String? transcription,
    $core.String? turnResponse,
    $core.String? turnAudioBase64,
    $core.String? error,
    $core.String? modelId,
    $core.String? modelName,
    $fixnum.Int64? audioLengthMs,
    $core.int? audioSizeBytes,
    $core.int? wordCount,
    $core.double? realTimeFactor,
    $core.String? language,
    $core.int? sampleRate,
    $core.bool? isStreaming,
    $core.int? framework,
    $core.int? characterCount,
    $fixnum.Int64? audioDurationMs,
    $core.int? audioSizeBytesTts,
    $fixnum.Int64? processingDurationMs,
    $core.double? charactersPerSecond,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (sessionId != null) result.sessionId = sessionId;
    if (text != null) result.text = text;
    if (confidence != null) result.confidence = confidence;
    if (responseText != null) result.responseText = responseText;
    if (audioBase64 != null) result.audioBase64 = audioBase64;
    if (durationMs != null) result.durationMs = durationMs;
    if (audioLevel != null) result.audioLevel = audioLevel;
    if (transcription != null) result.transcription = transcription;
    if (turnResponse != null) result.turnResponse = turnResponse;
    if (turnAudioBase64 != null) result.turnAudioBase64 = turnAudioBase64;
    if (error != null) result.error = error;
    if (modelId != null) result.modelId = modelId;
    if (modelName != null) result.modelName = modelName;
    if (audioLengthMs != null) result.audioLengthMs = audioLengthMs;
    if (audioSizeBytes != null) result.audioSizeBytes = audioSizeBytes;
    if (wordCount != null) result.wordCount = wordCount;
    if (realTimeFactor != null) result.realTimeFactor = realTimeFactor;
    if (language != null) result.language = language;
    if (sampleRate != null) result.sampleRate = sampleRate;
    if (isStreaming != null) result.isStreaming = isStreaming;
    if (framework != null) result.framework = framework;
    if (characterCount != null) result.characterCount = characterCount;
    if (audioDurationMs != null) result.audioDurationMs = audioDurationMs;
    if (audioSizeBytesTts != null) result.audioSizeBytesTts = audioSizeBytesTts;
    if (processingDurationMs != null)
      result.processingDurationMs = processingDurationMs;
    if (charactersPerSecond != null)
      result.charactersPerSecond = charactersPerSecond;
    return result;
  }

  VoiceLifecycleEvent._();

  factory VoiceLifecycleEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory VoiceLifecycleEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'VoiceLifecycleEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<VoiceEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: VoiceEventKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'sessionId')
    ..aOS(3, _omitFieldNames ? '' : 'text')
    ..aD(4, _omitFieldNames ? '' : 'confidence', fieldType: $pb.PbFieldType.OF)
    ..aOS(5, _omitFieldNames ? '' : 'responseText')
    ..aOS(6, _omitFieldNames ? '' : 'audioBase64')
    ..aInt64(7, _omitFieldNames ? '' : 'durationMs')
    ..aD(8, _omitFieldNames ? '' : 'audioLevel', fieldType: $pb.PbFieldType.OF)
    ..aOS(9, _omitFieldNames ? '' : 'transcription')
    ..aOS(10, _omitFieldNames ? '' : 'turnResponse')
    ..aOS(11, _omitFieldNames ? '' : 'turnAudioBase64')
    ..aOS(12, _omitFieldNames ? '' : 'error')
    ..aOS(13, _omitFieldNames ? '' : 'modelId')
    ..aOS(14, _omitFieldNames ? '' : 'modelName')
    ..aInt64(15, _omitFieldNames ? '' : 'audioLengthMs')
    ..aI(16, _omitFieldNames ? '' : 'audioSizeBytes')
    ..aI(17, _omitFieldNames ? '' : 'wordCount')
    ..aD(18, _omitFieldNames ? '' : 'realTimeFactor')
    ..aOS(19, _omitFieldNames ? '' : 'language')
    ..aI(20, _omitFieldNames ? '' : 'sampleRate')
    ..aOB(21, _omitFieldNames ? '' : 'isStreaming')
    ..aI(22, _omitFieldNames ? '' : 'framework')
    ..aI(23, _omitFieldNames ? '' : 'characterCount')
    ..aInt64(24, _omitFieldNames ? '' : 'audioDurationMs')
    ..aI(25, _omitFieldNames ? '' : 'audioSizeBytesTts')
    ..aInt64(26, _omitFieldNames ? '' : 'processingDurationMs')
    ..aD(27, _omitFieldNames ? '' : 'charactersPerSecond')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceLifecycleEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  VoiceLifecycleEvent copyWith(void Function(VoiceLifecycleEvent) updates) =>
      super.copyWith((message) => updates(message as VoiceLifecycleEvent))
          as VoiceLifecycleEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static VoiceLifecycleEvent create() => VoiceLifecycleEvent._();
  @$core.override
  VoiceLifecycleEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static VoiceLifecycleEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<VoiceLifecycleEvent>(create);
  static VoiceLifecycleEvent? _defaultInstance;

  @$pb.TagNumber(1)
  VoiceEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(VoiceEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  /// For listeningStarted / voiceSession_* — optional session id.
  @$pb.TagNumber(2)
  $core.String get sessionId => $_getSZ(1);
  @$pb.TagNumber(2)
  set sessionId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasSessionId() => $_has(1);
  @$pb.TagNumber(2)
  void clearSessionId() => $_clearField(2);

  /// For TRANSCRIPTION_PARTIAL / TRANSCRIPTION_FINAL / STT_PARTIAL_RESULT /
  /// STT_COMPLETED.
  @$pb.TagNumber(3)
  $core.String get text => $_getSZ(2);
  @$pb.TagNumber(3)
  set text($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasText() => $_has(2);
  @$pb.TagNumber(3)
  void clearText() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.double get confidence => $_getN(3);
  @$pb.TagNumber(4)
  set confidence($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasConfidence() => $_has(3);
  @$pb.TagNumber(4)
  void clearConfidence() => $_clearField(4);

  /// For RESPONSE_GENERATED.
  @$pb.TagNumber(5)
  $core.String get responseText => $_getSZ(4);
  @$pb.TagNumber(5)
  set responseText($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasResponseText() => $_has(4);
  @$pb.TagNumber(5)
  void clearResponseText() => $_clearField(5);

  /// For AUDIO_GENERATED — base64-encoded PCM (RN events.ts:145).
  @$pb.TagNumber(6)
  $core.String get audioBase64 => $_getSZ(5);
  @$pb.TagNumber(6)
  set audioBase64($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasAudioBase64() => $_has(5);
  @$pb.TagNumber(6)
  void clearAudioBase64() => $_clearField(6);

  /// For RECORDING_STOPPED / PLAYBACK_STARTED / PLAYBACK_COMPLETED —
  /// duration in milliseconds (RN events.ts:158, 160-161).
  @$pb.TagNumber(7)
  $fixnum.Int64 get durationMs => $_getI64(6);
  @$pb.TagNumber(7)
  set durationMs($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasDurationMs() => $_has(6);
  @$pb.TagNumber(7)
  void clearDurationMs() => $_clearField(7);

  /// For VOICE_SESSION_LISTENING — current audio level (RN events.ts:178).
  @$pb.TagNumber(8)
  $core.double get audioLevel => $_getN(7);
  @$pb.TagNumber(8)
  set audioLevel($core.double value) => $_setFloat(7, value);
  @$pb.TagNumber(8)
  $core.bool hasAudioLevel() => $_has(7);
  @$pb.TagNumber(8)
  void clearAudioLevel() => $_clearField(8);

  /// For VOICE_SESSION_TRANSCRIBED / VOICE_SESSION_RESPONDED /
  /// VOICE_SESSION_TURN_COMPLETED — RN events.ts:182-185.
  @$pb.TagNumber(9)
  $core.String get transcription => $_getSZ(8);
  @$pb.TagNumber(9)
  set transcription($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasTranscription() => $_has(8);
  @$pb.TagNumber(9)
  void clearTranscription() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get turnResponse => $_getSZ(9);
  @$pb.TagNumber(10)
  set turnResponse($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasTurnResponse() => $_has(9);
  @$pb.TagNumber(10)
  void clearTurnResponse() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.String get turnAudioBase64 => $_getSZ(10);
  @$pb.TagNumber(11)
  set turnAudioBase64($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasTurnAudioBase64() => $_has(10);
  @$pb.TagNumber(11)
  void clearTurnAudioBase64() => $_clearField(11);

  /// For *_ERROR / *_FAILED.
  @$pb.TagNumber(12)
  $core.String get error => $_getSZ(11);
  @$pb.TagNumber(12)
  set error($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasError() => $_has(11);
  @$pb.TagNumber(12)
  void clearError() => $_clearField(12);

  /// -----------------------------------------------------------------------
  /// Telemetry metrics (STT transcription + TTS synthesis + model load) so
  /// the C++ destination router derives the full telemetry payload from the
  /// proto SDKEvent alone. Populated per-component (component on the SDKEvent
  /// envelope selects which subset applies). `framework` is the
  /// InferenceFramework enum stored as int32.
  /// -----------------------------------------------------------------------
  @$pb.TagNumber(13)
  $core.String get modelId => $_getSZ(12);
  @$pb.TagNumber(13)
  set modelId($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasModelId() => $_has(12);
  @$pb.TagNumber(13)
  void clearModelId() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get modelName => $_getSZ(13);
  @$pb.TagNumber(14)
  set modelName($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasModelName() => $_has(13);
  @$pb.TagNumber(14)
  void clearModelName() => $_clearField(14);

  @$pb.TagNumber(15)
  $fixnum.Int64 get audioLengthMs => $_getI64(14);
  @$pb.TagNumber(15)
  set audioLengthMs($fixnum.Int64 value) => $_setInt64(14, value);
  @$pb.TagNumber(15)
  $core.bool hasAudioLengthMs() => $_has(14);
  @$pb.TagNumber(15)
  void clearAudioLengthMs() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.int get audioSizeBytes => $_getIZ(15);
  @$pb.TagNumber(16)
  set audioSizeBytes($core.int value) => $_setSignedInt32(15, value);
  @$pb.TagNumber(16)
  $core.bool hasAudioSizeBytes() => $_has(15);
  @$pb.TagNumber(16)
  void clearAudioSizeBytes() => $_clearField(16);

  @$pb.TagNumber(17)
  $core.int get wordCount => $_getIZ(16);
  @$pb.TagNumber(17)
  set wordCount($core.int value) => $_setSignedInt32(16, value);
  @$pb.TagNumber(17)
  $core.bool hasWordCount() => $_has(16);
  @$pb.TagNumber(17)
  void clearWordCount() => $_clearField(17);

  @$pb.TagNumber(18)
  $core.double get realTimeFactor => $_getN(17);
  @$pb.TagNumber(18)
  set realTimeFactor($core.double value) => $_setDouble(17, value);
  @$pb.TagNumber(18)
  $core.bool hasRealTimeFactor() => $_has(17);
  @$pb.TagNumber(18)
  void clearRealTimeFactor() => $_clearField(18);

  @$pb.TagNumber(19)
  $core.String get language => $_getSZ(18);
  @$pb.TagNumber(19)
  set language($core.String value) => $_setString(18, value);
  @$pb.TagNumber(19)
  $core.bool hasLanguage() => $_has(18);
  @$pb.TagNumber(19)
  void clearLanguage() => $_clearField(19);

  @$pb.TagNumber(20)
  $core.int get sampleRate => $_getIZ(19);
  @$pb.TagNumber(20)
  set sampleRate($core.int value) => $_setSignedInt32(19, value);
  @$pb.TagNumber(20)
  $core.bool hasSampleRate() => $_has(19);
  @$pb.TagNumber(20)
  void clearSampleRate() => $_clearField(20);

  @$pb.TagNumber(21)
  $core.bool get isStreaming => $_getBF(20);
  @$pb.TagNumber(21)
  set isStreaming($core.bool value) => $_setBool(20, value);
  @$pb.TagNumber(21)
  $core.bool hasIsStreaming() => $_has(20);
  @$pb.TagNumber(21)
  void clearIsStreaming() => $_clearField(21);

  @$pb.TagNumber(22)
  $core.int get framework => $_getIZ(21);
  @$pb.TagNumber(22)
  set framework($core.int value) => $_setSignedInt32(21, value);
  @$pb.TagNumber(22)
  $core.bool hasFramework() => $_has(21);
  @$pb.TagNumber(22)
  void clearFramework() => $_clearField(22);

  /// TTS synthesis metrics.
  @$pb.TagNumber(23)
  $core.int get characterCount => $_getIZ(22);
  @$pb.TagNumber(23)
  set characterCount($core.int value) => $_setSignedInt32(22, value);
  @$pb.TagNumber(23)
  $core.bool hasCharacterCount() => $_has(22);
  @$pb.TagNumber(23)
  void clearCharacterCount() => $_clearField(23);

  @$pb.TagNumber(24)
  $fixnum.Int64 get audioDurationMs => $_getI64(23);
  @$pb.TagNumber(24)
  set audioDurationMs($fixnum.Int64 value) => $_setInt64(23, value);
  @$pb.TagNumber(24)
  $core.bool hasAudioDurationMs() => $_has(23);
  @$pb.TagNumber(24)
  void clearAudioDurationMs() => $_clearField(24);

  @$pb.TagNumber(25)
  $core.int get audioSizeBytesTts => $_getIZ(24);
  @$pb.TagNumber(25)
  set audioSizeBytesTts($core.int value) => $_setSignedInt32(24, value);
  @$pb.TagNumber(25)
  $core.bool hasAudioSizeBytesTts() => $_has(24);
  @$pb.TagNumber(25)
  void clearAudioSizeBytesTts() => $_clearField(25);

  @$pb.TagNumber(26)
  $fixnum.Int64 get processingDurationMs => $_getI64(25);
  @$pb.TagNumber(26)
  set processingDurationMs($fixnum.Int64 value) => $_setInt64(25, value);
  @$pb.TagNumber(26)
  $core.bool hasProcessingDurationMs() => $_has(25);
  @$pb.TagNumber(26)
  void clearProcessingDurationMs() => $_clearField(26);

  @$pb.TagNumber(27)
  $core.double get charactersPerSecond => $_getN(26);
  @$pb.TagNumber(27)
  set charactersPerSecond($core.double value) => $_setDouble(26, value);
  @$pb.TagNumber(27)
  $core.bool hasCharactersPerSecond() => $_has(26);
  @$pb.TagNumber(27)
  void clearCharactersPerSecond() => $_clearField(27);
}

/// ===========================================================================
/// SECTION 6 — EMBEDDINGS / SECTION 7 — DIFFUSION / SECTION 8 — RAG /
/// SECTION 9 — LORA / SECTION 2b — VLM (capability operations)
/// ===========================================================================
/// Embeddings, Diffusion, RAG, LoRA, and VLM capability-operation lifecycle is
/// consolidated into a single `CapabilityOperationEvent` message discriminated
/// by `CapabilityOperationEventKind` (VLM_* / DIFFUSION_* / EMBEDDINGS_* /
/// RAG_* / LORA_*). One flat struct keeps these analytics-only operation events
/// uniform across the five capability components.
/// ---------------------------------------------------------------------------
class CapabilityOperationEvent extends $pb.GeneratedMessage {
  factory CapabilityOperationEvent({
    CapabilityOperationEventKind? kind,
    SDKComponent? component,
    $core.String? modelId,
    $core.String? operationId,
    $core.String? operation,
    $core.double? progress,
    $fixnum.Int64? inputCount,
    $fixnum.Int64? outputCount,
    $core.String? resultJson,
    $core.String? error,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (component != null) result.component = component;
    if (modelId != null) result.modelId = modelId;
    if (operationId != null) result.operationId = operationId;
    if (operation != null) result.operation = operation;
    if (progress != null) result.progress = progress;
    if (inputCount != null) result.inputCount = inputCount;
    if (outputCount != null) result.outputCount = outputCount;
    if (resultJson != null) result.resultJson = resultJson;
    if (error != null) result.error = error;
    return result;
  }

  CapabilityOperationEvent._();

  factory CapabilityOperationEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CapabilityOperationEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CapabilityOperationEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<CapabilityOperationEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: CapabilityOperationEventKind.values)
    ..aE<SDKComponent>(2, _omitFieldNames ? '' : 'component',
        enumValues: SDKComponent.values)
    ..aOS(3, _omitFieldNames ? '' : 'modelId')
    ..aOS(4, _omitFieldNames ? '' : 'operationId')
    ..aOS(5, _omitFieldNames ? '' : 'operation')
    ..aD(6, _omitFieldNames ? '' : 'progress', fieldType: $pb.PbFieldType.OF)
    ..aInt64(7, _omitFieldNames ? '' : 'inputCount')
    ..aInt64(8, _omitFieldNames ? '' : 'outputCount')
    ..aOS(9, _omitFieldNames ? '' : 'resultJson')
    ..aOS(10, _omitFieldNames ? '' : 'error')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CapabilityOperationEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CapabilityOperationEvent copyWith(
          void Function(CapabilityOperationEvent) updates) =>
      super.copyWith((message) => updates(message as CapabilityOperationEvent))
          as CapabilityOperationEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CapabilityOperationEvent create() => CapabilityOperationEvent._();
  @$core.override
  CapabilityOperationEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CapabilityOperationEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CapabilityOperationEvent>(create);
  static CapabilityOperationEvent? _defaultInstance;

  @$pb.TagNumber(1)
  CapabilityOperationEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(CapabilityOperationEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  SDKComponent get component => $_getN(1);
  @$pb.TagNumber(2)
  set component(SDKComponent value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasComponent() => $_has(1);
  @$pb.TagNumber(2)
  void clearComponent() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get modelId => $_getSZ(2);
  @$pb.TagNumber(3)
  set modelId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasModelId() => $_has(2);
  @$pb.TagNumber(3)
  void clearModelId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get operationId => $_getSZ(3);
  @$pb.TagNumber(4)
  set operationId($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasOperationId() => $_has(3);
  @$pb.TagNumber(4)
  void clearOperationId() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get operation => $_getSZ(4);
  @$pb.TagNumber(5)
  set operation($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasOperation() => $_has(4);
  @$pb.TagNumber(5)
  void clearOperation() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.double get progress => $_getN(5);
  @$pb.TagNumber(6)
  set progress($core.double value) => $_setFloat(5, value);
  @$pb.TagNumber(6)
  $core.bool hasProgress() => $_has(5);
  @$pb.TagNumber(6)
  void clearProgress() => $_clearField(6);

  @$pb.TagNumber(7)
  $fixnum.Int64 get inputCount => $_getI64(6);
  @$pb.TagNumber(7)
  set inputCount($fixnum.Int64 value) => $_setInt64(6, value);
  @$pb.TagNumber(7)
  $core.bool hasInputCount() => $_has(6);
  @$pb.TagNumber(7)
  void clearInputCount() => $_clearField(7);

  @$pb.TagNumber(8)
  $fixnum.Int64 get outputCount => $_getI64(7);
  @$pb.TagNumber(8)
  set outputCount($fixnum.Int64 value) => $_setInt64(7, value);
  @$pb.TagNumber(8)
  $core.bool hasOutputCount() => $_has(7);
  @$pb.TagNumber(8)
  void clearOutputCount() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get resultJson => $_getSZ(8);
  @$pb.TagNumber(9)
  set resultJson($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasResultJson() => $_has(8);
  @$pb.TagNumber(9)
  void clearResultJson() => $_clearField(9);

  @$pb.TagNumber(10)
  $core.String get error => $_getSZ(9);
  @$pb.TagNumber(10)
  set error($core.String value) => $_setString(9, value);
  @$pb.TagNumber(10)
  $core.bool hasError() => $_has(9);
  @$pb.TagNumber(10)
  void clearError() => $_clearField(10);
}

/// ---------------------------------------------------------------------------
/// Model lifecycle events: load / unload / download / list / catalog / delete /
/// custom-model / built-in-registration. Mirrors RN
///   events.ts:95-130 (SDKModelEvent: 24 variants).
/// Plus Kotlin ModelEvent (7 ModelEventType) and Dart SDKModelEvent (10
/// concrete classes).
/// ---------------------------------------------------------------------------
class ModelEvent extends $pb.GeneratedMessage {
  factory ModelEvent({
    ModelEventKind? kind,
    $core.String? modelId,
    $core.String? taskId,
    $core.double? progress,
    $fixnum.Int64? bytesDownloaded,
    $fixnum.Int64? totalBytes,
    $core.String? downloadState,
    $core.String? localPath,
    $core.String? error,
    $core.int? modelCount,
    $core.String? customModelName,
    $core.String? customModelUrl,
    $core.String? modelName,
    $fixnum.Int64? modelSizeBytes,
    $fixnum.Int64? durationMs,
    $core.int? framework,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (modelId != null) result.modelId = modelId;
    if (taskId != null) result.taskId = taskId;
    if (progress != null) result.progress = progress;
    if (bytesDownloaded != null) result.bytesDownloaded = bytesDownloaded;
    if (totalBytes != null) result.totalBytes = totalBytes;
    if (downloadState != null) result.downloadState = downloadState;
    if (localPath != null) result.localPath = localPath;
    if (error != null) result.error = error;
    if (modelCount != null) result.modelCount = modelCount;
    if (customModelName != null) result.customModelName = customModelName;
    if (customModelUrl != null) result.customModelUrl = customModelUrl;
    if (modelName != null) result.modelName = modelName;
    if (modelSizeBytes != null) result.modelSizeBytes = modelSizeBytes;
    if (durationMs != null) result.durationMs = durationMs;
    if (framework != null) result.framework = framework;
    return result;
  }

  ModelEvent._();

  factory ModelEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<ModelEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: ModelEventKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..aOS(3, _omitFieldNames ? '' : 'taskId')
    ..aD(4, _omitFieldNames ? '' : 'progress', fieldType: $pb.PbFieldType.OF)
    ..aInt64(5, _omitFieldNames ? '' : 'bytesDownloaded')
    ..aInt64(6, _omitFieldNames ? '' : 'totalBytes')
    ..aOS(7, _omitFieldNames ? '' : 'downloadState')
    ..aOS(8, _omitFieldNames ? '' : 'localPath')
    ..aOS(9, _omitFieldNames ? '' : 'error')
    ..aI(10, _omitFieldNames ? '' : 'modelCount')
    ..aOS(11, _omitFieldNames ? '' : 'customModelName')
    ..aOS(12, _omitFieldNames ? '' : 'customModelUrl')
    ..aOS(13, _omitFieldNames ? '' : 'modelName')
    ..aInt64(14, _omitFieldNames ? '' : 'modelSizeBytes')
    ..aInt64(15, _omitFieldNames ? '' : 'durationMs')
    ..aI(16, _omitFieldNames ? '' : 'framework')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelEvent copyWith(void Function(ModelEvent) updates) =>
      super.copyWith((message) => updates(message as ModelEvent)) as ModelEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelEvent create() => ModelEvent._();
  @$core.override
  ModelEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelEvent>(create);
  static ModelEvent? _defaultInstance;

  @$pb.TagNumber(1)
  ModelEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(ModelEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get taskId => $_getSZ(2);
  @$pb.TagNumber(3)
  set taskId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTaskId() => $_has(2);
  @$pb.TagNumber(3)
  void clearTaskId() => $_clearField(3);

  /// For LOAD_PROGRESS / DOWNLOAD_PROGRESS — 0.0..1.0.
  @$pb.TagNumber(4)
  $core.double get progress => $_getN(3);
  @$pb.TagNumber(4)
  set progress($core.double value) => $_setFloat(3, value);
  @$pb.TagNumber(4)
  $core.bool hasProgress() => $_has(3);
  @$pb.TagNumber(4)
  void clearProgress() => $_clearField(4);

  /// For DOWNLOAD_PROGRESS — bytes counters.
  @$pb.TagNumber(5)
  $fixnum.Int64 get bytesDownloaded => $_getI64(4);
  @$pb.TagNumber(5)
  set bytesDownloaded($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasBytesDownloaded() => $_has(4);
  @$pb.TagNumber(5)
  void clearBytesDownloaded() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get totalBytes => $_getI64(5);
  @$pb.TagNumber(6)
  set totalBytes($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTotalBytes() => $_has(5);
  @$pb.TagNumber(6)
  void clearTotalBytes() => $_clearField(6);

  /// For DOWNLOAD_PROGRESS — engine-level state string (RN events.ts:111).
  @$pb.TagNumber(7)
  $core.String get downloadState => $_getSZ(6);
  @$pb.TagNumber(7)
  set downloadState($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasDownloadState() => $_has(6);
  @$pb.TagNumber(7)
  void clearDownloadState() => $_clearField(7);

  /// For DOWNLOAD_COMPLETED — landed local path (RN events.ts:118).
  @$pb.TagNumber(8)
  $core.String get localPath => $_getSZ(7);
  @$pb.TagNumber(8)
  set localPath($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasLocalPath() => $_has(7);
  @$pb.TagNumber(8)
  void clearLocalPath() => $_clearField(8);

  /// For *_FAILED.
  @$pb.TagNumber(9)
  $core.String get error => $_getSZ(8);
  @$pb.TagNumber(9)
  set error($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasError() => $_has(8);
  @$pb.TagNumber(9)
  void clearError() => $_clearField(9);

  /// For LIST_COMPLETED / CATALOG_LOADED — count only; the full
  /// ModelInfo array travels via response RPCs, not via events.
  @$pb.TagNumber(10)
  $core.int get modelCount => $_getIZ(9);
  @$pb.TagNumber(10)
  set modelCount($core.int value) => $_setSignedInt32(9, value);
  @$pb.TagNumber(10)
  $core.bool hasModelCount() => $_has(9);
  @$pb.TagNumber(10)
  void clearModelCount() => $_clearField(10);

  /// For CUSTOM_MODEL_ADDED — RN events.ts:129.
  @$pb.TagNumber(11)
  $core.String get customModelName => $_getSZ(10);
  @$pb.TagNumber(11)
  set customModelName($core.String value) => $_setString(10, value);
  @$pb.TagNumber(11)
  $core.bool hasCustomModelName() => $_has(10);
  @$pb.TagNumber(11)
  void clearCustomModelName() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get customModelUrl => $_getSZ(11);
  @$pb.TagNumber(12)
  set customModelUrl($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasCustomModelUrl() => $_has(11);
  @$pb.TagNumber(12)
  void clearCustomModelUrl() => $_clearField(12);

  /// Model-load + download/extraction telemetry metrics so the C++
  /// destination router derives the telemetry payload from the proto
  /// SDKEvent alone. `framework` is the InferenceFramework enum stored as
  /// int32 (matches FrameworkEvent.framework).
  @$pb.TagNumber(13)
  $core.String get modelName => $_getSZ(12);
  @$pb.TagNumber(13)
  set modelName($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasModelName() => $_has(12);
  @$pb.TagNumber(13)
  void clearModelName() => $_clearField(13);

  @$pb.TagNumber(14)
  $fixnum.Int64 get modelSizeBytes => $_getI64(13);
  @$pb.TagNumber(14)
  set modelSizeBytes($fixnum.Int64 value) => $_setInt64(13, value);
  @$pb.TagNumber(14)
  $core.bool hasModelSizeBytes() => $_has(13);
  @$pb.TagNumber(14)
  void clearModelSizeBytes() => $_clearField(14);

  @$pb.TagNumber(15)
  $fixnum.Int64 get durationMs => $_getI64(14);
  @$pb.TagNumber(15)
  set durationMs($fixnum.Int64 value) => $_setInt64(14, value);
  @$pb.TagNumber(15)
  $core.bool hasDurationMs() => $_has(14);
  @$pb.TagNumber(15)
  void clearDurationMs() => $_clearField(15);

  @$pb.TagNumber(16)
  $core.int get framework => $_getIZ(15);
  @$pb.TagNumber(16)
  set framework($core.int value) => $_setSignedInt32(15, value);
  @$pb.TagNumber(16)
  $core.bool hasFramework() => $_has(15);
  @$pb.TagNumber(16)
  void clearFramework() => $_clearField(16);
}

enum ModelRegistryEvent_Result {
  refreshResult,
  listResult,
  getResult,
  importResult,
  discoveryResult,
  compatibilityResult,
  currentModelResult,
  notSet
}

class ModelRegistryEvent extends $pb.GeneratedMessage {
  factory ModelRegistryEvent({
    ModelRegistryEventKind? kind,
    $core.String? modelId,
    $core.String? assignmentId,
    SDKComponent? assignedComponent,
    $0.InferenceFramework? framework,
    $core.String? sourcePath,
    $core.String? error,
    $0.ModelRegistryRefreshResult? refreshResult,
    $0.ModelListResult? listResult,
    $0.ModelGetResult? getResult,
    $0.ModelImportResult? importResult,
    $0.ModelDiscoveryResult? discoveryResult,
    $0.ModelCompatibilityResult? compatibilityResult,
    $0.CurrentModelResult? currentModelResult,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (modelId != null) result.modelId = modelId;
    if (assignmentId != null) result.assignmentId = assignmentId;
    if (assignedComponent != null) result.assignedComponent = assignedComponent;
    if (framework != null) result.framework = framework;
    if (sourcePath != null) result.sourcePath = sourcePath;
    if (error != null) result.error = error;
    if (refreshResult != null) result.refreshResult = refreshResult;
    if (listResult != null) result.listResult = listResult;
    if (getResult != null) result.getResult = getResult;
    if (importResult != null) result.importResult = importResult;
    if (discoveryResult != null) result.discoveryResult = discoveryResult;
    if (compatibilityResult != null)
      result.compatibilityResult = compatibilityResult;
    if (currentModelResult != null)
      result.currentModelResult = currentModelResult;
    return result;
  }

  ModelRegistryEvent._();

  factory ModelRegistryEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory ModelRegistryEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, ModelRegistryEvent_Result>
      _ModelRegistryEvent_ResultByTag = {
    20: ModelRegistryEvent_Result.refreshResult,
    21: ModelRegistryEvent_Result.listResult,
    22: ModelRegistryEvent_Result.getResult,
    23: ModelRegistryEvent_Result.importResult,
    24: ModelRegistryEvent_Result.discoveryResult,
    25: ModelRegistryEvent_Result.compatibilityResult,
    26: ModelRegistryEvent_Result.currentModelResult,
    0: ModelRegistryEvent_Result.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'ModelRegistryEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..oo(0, [20, 21, 22, 23, 24, 25, 26])
    ..aE<ModelRegistryEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: ModelRegistryEventKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..aOS(3, _omitFieldNames ? '' : 'assignmentId')
    ..aE<SDKComponent>(4, _omitFieldNames ? '' : 'assignedComponent',
        enumValues: SDKComponent.values)
    ..aE<$0.InferenceFramework>(5, _omitFieldNames ? '' : 'framework',
        enumValues: $0.InferenceFramework.values)
    ..aOS(6, _omitFieldNames ? '' : 'sourcePath')
    ..aOS(7, _omitFieldNames ? '' : 'error')
    ..aOM<$0.ModelRegistryRefreshResult>(
        20, _omitFieldNames ? '' : 'refreshResult',
        subBuilder: $0.ModelRegistryRefreshResult.create)
    ..aOM<$0.ModelListResult>(21, _omitFieldNames ? '' : 'listResult',
        subBuilder: $0.ModelListResult.create)
    ..aOM<$0.ModelGetResult>(22, _omitFieldNames ? '' : 'getResult',
        subBuilder: $0.ModelGetResult.create)
    ..aOM<$0.ModelImportResult>(23, _omitFieldNames ? '' : 'importResult',
        subBuilder: $0.ModelImportResult.create)
    ..aOM<$0.ModelDiscoveryResult>(24, _omitFieldNames ? '' : 'discoveryResult',
        subBuilder: $0.ModelDiscoveryResult.create)
    ..aOM<$0.ModelCompatibilityResult>(
        25, _omitFieldNames ? '' : 'compatibilityResult',
        subBuilder: $0.ModelCompatibilityResult.create)
    ..aOM<$0.CurrentModelResult>(
        26, _omitFieldNames ? '' : 'currentModelResult',
        subBuilder: $0.CurrentModelResult.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelRegistryEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  ModelRegistryEvent copyWith(void Function(ModelRegistryEvent) updates) =>
      super.copyWith((message) => updates(message as ModelRegistryEvent))
          as ModelRegistryEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static ModelRegistryEvent create() => ModelRegistryEvent._();
  @$core.override
  ModelRegistryEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static ModelRegistryEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<ModelRegistryEvent>(create);
  static ModelRegistryEvent? _defaultInstance;

  @$pb.TagNumber(20)
  @$pb.TagNumber(21)
  @$pb.TagNumber(22)
  @$pb.TagNumber(23)
  @$pb.TagNumber(24)
  @$pb.TagNumber(25)
  @$pb.TagNumber(26)
  ModelRegistryEvent_Result whichResult() =>
      _ModelRegistryEvent_ResultByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(20)
  @$pb.TagNumber(21)
  @$pb.TagNumber(22)
  @$pb.TagNumber(23)
  @$pb.TagNumber(24)
  @$pb.TagNumber(25)
  @$pb.TagNumber(26)
  void clearResult() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  ModelRegistryEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(ModelRegistryEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get assignmentId => $_getSZ(2);
  @$pb.TagNumber(3)
  set assignmentId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAssignmentId() => $_has(2);
  @$pb.TagNumber(3)
  void clearAssignmentId() => $_clearField(3);

  @$pb.TagNumber(4)
  SDKComponent get assignedComponent => $_getN(3);
  @$pb.TagNumber(4)
  set assignedComponent(SDKComponent value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasAssignedComponent() => $_has(3);
  @$pb.TagNumber(4)
  void clearAssignedComponent() => $_clearField(4);

  @$pb.TagNumber(5)
  $0.InferenceFramework get framework => $_getN(4);
  @$pb.TagNumber(5)
  set framework($0.InferenceFramework value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasFramework() => $_has(4);
  @$pb.TagNumber(5)
  void clearFramework() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get sourcePath => $_getSZ(5);
  @$pb.TagNumber(6)
  set sourcePath($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasSourcePath() => $_has(5);
  @$pb.TagNumber(6)
  void clearSourcePath() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get error => $_getSZ(6);
  @$pb.TagNumber(7)
  set error($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasError() => $_has(6);
  @$pb.TagNumber(7)
  void clearError() => $_clearField(7);

  @$pb.TagNumber(20)
  $0.ModelRegistryRefreshResult get refreshResult => $_getN(7);
  @$pb.TagNumber(20)
  set refreshResult($0.ModelRegistryRefreshResult value) =>
      $_setField(20, value);
  @$pb.TagNumber(20)
  $core.bool hasRefreshResult() => $_has(7);
  @$pb.TagNumber(20)
  void clearRefreshResult() => $_clearField(20);
  @$pb.TagNumber(20)
  $0.ModelRegistryRefreshResult ensureRefreshResult() => $_ensure(7);

  @$pb.TagNumber(21)
  $0.ModelListResult get listResult => $_getN(8);
  @$pb.TagNumber(21)
  set listResult($0.ModelListResult value) => $_setField(21, value);
  @$pb.TagNumber(21)
  $core.bool hasListResult() => $_has(8);
  @$pb.TagNumber(21)
  void clearListResult() => $_clearField(21);
  @$pb.TagNumber(21)
  $0.ModelListResult ensureListResult() => $_ensure(8);

  @$pb.TagNumber(22)
  $0.ModelGetResult get getResult => $_getN(9);
  @$pb.TagNumber(22)
  set getResult($0.ModelGetResult value) => $_setField(22, value);
  @$pb.TagNumber(22)
  $core.bool hasGetResult() => $_has(9);
  @$pb.TagNumber(22)
  void clearGetResult() => $_clearField(22);
  @$pb.TagNumber(22)
  $0.ModelGetResult ensureGetResult() => $_ensure(9);

  @$pb.TagNumber(23)
  $0.ModelImportResult get importResult => $_getN(10);
  @$pb.TagNumber(23)
  set importResult($0.ModelImportResult value) => $_setField(23, value);
  @$pb.TagNumber(23)
  $core.bool hasImportResult() => $_has(10);
  @$pb.TagNumber(23)
  void clearImportResult() => $_clearField(23);
  @$pb.TagNumber(23)
  $0.ModelImportResult ensureImportResult() => $_ensure(10);

  @$pb.TagNumber(24)
  $0.ModelDiscoveryResult get discoveryResult => $_getN(11);
  @$pb.TagNumber(24)
  set discoveryResult($0.ModelDiscoveryResult value) => $_setField(24, value);
  @$pb.TagNumber(24)
  $core.bool hasDiscoveryResult() => $_has(11);
  @$pb.TagNumber(24)
  void clearDiscoveryResult() => $_clearField(24);
  @$pb.TagNumber(24)
  $0.ModelDiscoveryResult ensureDiscoveryResult() => $_ensure(11);

  @$pb.TagNumber(25)
  $0.ModelCompatibilityResult get compatibilityResult => $_getN(12);
  @$pb.TagNumber(25)
  set compatibilityResult($0.ModelCompatibilityResult value) =>
      $_setField(25, value);
  @$pb.TagNumber(25)
  $core.bool hasCompatibilityResult() => $_has(12);
  @$pb.TagNumber(25)
  void clearCompatibilityResult() => $_clearField(25);
  @$pb.TagNumber(25)
  $0.ModelCompatibilityResult ensureCompatibilityResult() => $_ensure(12);

  @$pb.TagNumber(26)
  $0.CurrentModelResult get currentModelResult => $_getN(13);
  @$pb.TagNumber(26)
  set currentModelResult($0.CurrentModelResult value) => $_setField(26, value);
  @$pb.TagNumber(26)
  $core.bool hasCurrentModelResult() => $_has(13);
  @$pb.TagNumber(26)
  void clearCurrentModelResult() => $_clearField(26);
  @$pb.TagNumber(26)
  $0.CurrentModelResult ensureCurrentModelResult() => $_ensure(13);
}

enum DownloadEvent_Payload {
  planResult,
  startResult,
  progress,
  cancelResult,
  resumeResult,
  notSet
}

class DownloadEvent extends $pb.GeneratedMessage {
  factory DownloadEvent({
    DownloadEventKind? kind,
    $core.String? modelId,
    $core.String? taskId,
    $core.String? error,
    $1.DownloadPlanResult? planResult,
    $1.DownloadStartResult? startResult,
    $1.DownloadProgress? progress,
    $1.DownloadCancelResult? cancelResult,
    $1.DownloadResumeResult? resumeResult,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (modelId != null) result.modelId = modelId;
    if (taskId != null) result.taskId = taskId;
    if (error != null) result.error = error;
    if (planResult != null) result.planResult = planResult;
    if (startResult != null) result.startResult = startResult;
    if (progress != null) result.progress = progress;
    if (cancelResult != null) result.cancelResult = cancelResult;
    if (resumeResult != null) result.resumeResult = resumeResult;
    return result;
  }

  DownloadEvent._();

  factory DownloadEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DownloadEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, DownloadEvent_Payload>
      _DownloadEvent_PayloadByTag = {
    20: DownloadEvent_Payload.planResult,
    21: DownloadEvent_Payload.startResult,
    22: DownloadEvent_Payload.progress,
    23: DownloadEvent_Payload.cancelResult,
    24: DownloadEvent_Payload.resumeResult,
    0: DownloadEvent_Payload.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DownloadEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..oo(0, [20, 21, 22, 23, 24])
    ..aE<DownloadEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: DownloadEventKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..aOS(3, _omitFieldNames ? '' : 'taskId')
    ..aOS(4, _omitFieldNames ? '' : 'error')
    ..aOM<$1.DownloadPlanResult>(20, _omitFieldNames ? '' : 'planResult',
        subBuilder: $1.DownloadPlanResult.create)
    ..aOM<$1.DownloadStartResult>(21, _omitFieldNames ? '' : 'startResult',
        subBuilder: $1.DownloadStartResult.create)
    ..aOM<$1.DownloadProgress>(22, _omitFieldNames ? '' : 'progress',
        subBuilder: $1.DownloadProgress.create)
    ..aOM<$1.DownloadCancelResult>(23, _omitFieldNames ? '' : 'cancelResult',
        subBuilder: $1.DownloadCancelResult.create)
    ..aOM<$1.DownloadResumeResult>(24, _omitFieldNames ? '' : 'resumeResult',
        subBuilder: $1.DownloadResumeResult.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DownloadEvent copyWith(void Function(DownloadEvent) updates) =>
      super.copyWith((message) => updates(message as DownloadEvent))
          as DownloadEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DownloadEvent create() => DownloadEvent._();
  @$core.override
  DownloadEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DownloadEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DownloadEvent>(create);
  static DownloadEvent? _defaultInstance;

  @$pb.TagNumber(20)
  @$pb.TagNumber(21)
  @$pb.TagNumber(22)
  @$pb.TagNumber(23)
  @$pb.TagNumber(24)
  DownloadEvent_Payload whichPayload() =>
      _DownloadEvent_PayloadByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(20)
  @$pb.TagNumber(21)
  @$pb.TagNumber(22)
  @$pb.TagNumber(23)
  @$pb.TagNumber(24)
  void clearPayload() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  DownloadEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(DownloadEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get taskId => $_getSZ(2);
  @$pb.TagNumber(3)
  set taskId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasTaskId() => $_has(2);
  @$pb.TagNumber(3)
  void clearTaskId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get error => $_getSZ(3);
  @$pb.TagNumber(4)
  set error($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasError() => $_has(3);
  @$pb.TagNumber(4)
  void clearError() => $_clearField(4);

  @$pb.TagNumber(20)
  $1.DownloadPlanResult get planResult => $_getN(4);
  @$pb.TagNumber(20)
  set planResult($1.DownloadPlanResult value) => $_setField(20, value);
  @$pb.TagNumber(20)
  $core.bool hasPlanResult() => $_has(4);
  @$pb.TagNumber(20)
  void clearPlanResult() => $_clearField(20);
  @$pb.TagNumber(20)
  $1.DownloadPlanResult ensurePlanResult() => $_ensure(4);

  @$pb.TagNumber(21)
  $1.DownloadStartResult get startResult => $_getN(5);
  @$pb.TagNumber(21)
  set startResult($1.DownloadStartResult value) => $_setField(21, value);
  @$pb.TagNumber(21)
  $core.bool hasStartResult() => $_has(5);
  @$pb.TagNumber(21)
  void clearStartResult() => $_clearField(21);
  @$pb.TagNumber(21)
  $1.DownloadStartResult ensureStartResult() => $_ensure(5);

  @$pb.TagNumber(22)
  $1.DownloadProgress get progress => $_getN(6);
  @$pb.TagNumber(22)
  set progress($1.DownloadProgress value) => $_setField(22, value);
  @$pb.TagNumber(22)
  $core.bool hasProgress() => $_has(6);
  @$pb.TagNumber(22)
  void clearProgress() => $_clearField(22);
  @$pb.TagNumber(22)
  $1.DownloadProgress ensureProgress() => $_ensure(6);

  @$pb.TagNumber(23)
  $1.DownloadCancelResult get cancelResult => $_getN(7);
  @$pb.TagNumber(23)
  set cancelResult($1.DownloadCancelResult value) => $_setField(23, value);
  @$pb.TagNumber(23)
  $core.bool hasCancelResult() => $_has(7);
  @$pb.TagNumber(23)
  void clearCancelResult() => $_clearField(23);
  @$pb.TagNumber(23)
  $1.DownloadCancelResult ensureCancelResult() => $_ensure(7);

  @$pb.TagNumber(24)
  $1.DownloadResumeResult get resumeResult => $_getN(8);
  @$pb.TagNumber(24)
  set resumeResult($1.DownloadResumeResult value) => $_setField(24, value);
  @$pb.TagNumber(24)
  $core.bool hasResumeResult() => $_has(8);
  @$pb.TagNumber(24)
  void clearResumeResult() => $_clearField(24);
  @$pb.TagNumber(24)
  $1.DownloadResumeResult ensureResumeResult() => $_ensure(8);
}

/// ---------------------------------------------------------------------------
/// Storage events. Mirrors RN
///   events.ts:213-226 (SDKStorageEvent: 13 variants).
/// Plus Dart SDKStorageEvent (cacheCleared, tempFilesCleaned).
/// ---------------------------------------------------------------------------
class StorageEvent extends $pb.GeneratedMessage {
  factory StorageEvent({
    StorageEventKind? kind,
    $core.String? modelId,
    $core.String? error,
    $fixnum.Int64? totalBytes,
    $fixnum.Int64? availableBytes,
    $fixnum.Int64? usedBytes,
    $core.int? storedModelCount,
    $core.String? cacheKey,
    $fixnum.Int64? evictedBytes,
    $fixnum.Int64? freedBytes,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (modelId != null) result.modelId = modelId;
    if (error != null) result.error = error;
    if (totalBytes != null) result.totalBytes = totalBytes;
    if (availableBytes != null) result.availableBytes = availableBytes;
    if (usedBytes != null) result.usedBytes = usedBytes;
    if (storedModelCount != null) result.storedModelCount = storedModelCount;
    if (cacheKey != null) result.cacheKey = cacheKey;
    if (evictedBytes != null) result.evictedBytes = evictedBytes;
    if (freedBytes != null) result.freedBytes = freedBytes;
    return result;
  }

  StorageEvent._();

  factory StorageEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StorageEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StorageEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<StorageEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: StorageEventKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..aOS(3, _omitFieldNames ? '' : 'error')
    ..aInt64(4, _omitFieldNames ? '' : 'totalBytes')
    ..aInt64(5, _omitFieldNames ? '' : 'availableBytes')
    ..aInt64(6, _omitFieldNames ? '' : 'usedBytes')
    ..aI(7, _omitFieldNames ? '' : 'storedModelCount')
    ..aOS(8, _omitFieldNames ? '' : 'cacheKey')
    ..aInt64(9, _omitFieldNames ? '' : 'evictedBytes')
    ..aInt64(10, _omitFieldNames ? '' : 'freedBytes')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageEvent copyWith(void Function(StorageEvent) updates) =>
      super.copyWith((message) => updates(message as StorageEvent))
          as StorageEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageEvent create() => StorageEvent._();
  @$core.override
  StorageEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StorageEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StorageEvent>(create);
  static StorageEvent? _defaultInstance;

  @$pb.TagNumber(1)
  StorageEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(StorageEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  /// For DELETE_MODEL_* events.
  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => $_clearField(2);

  /// For *_FAILED.
  @$pb.TagNumber(3)
  $core.String get error => $_getSZ(2);
  @$pb.TagNumber(3)
  set error($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(3)
  void clearError() => $_clearField(3);

  /// For INFO_RETRIEVED — total/available bytes (StorageInfo summary).
  @$pb.TagNumber(4)
  $fixnum.Int64 get totalBytes => $_getI64(3);
  @$pb.TagNumber(4)
  set totalBytes($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasTotalBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearTotalBytes() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get availableBytes => $_getI64(4);
  @$pb.TagNumber(5)
  set availableBytes($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasAvailableBytes() => $_has(4);
  @$pb.TagNumber(5)
  void clearAvailableBytes() => $_clearField(5);

  @$pb.TagNumber(6)
  $fixnum.Int64 get usedBytes => $_getI64(5);
  @$pb.TagNumber(6)
  set usedBytes($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasUsedBytes() => $_has(5);
  @$pb.TagNumber(6)
  void clearUsedBytes() => $_clearField(6);

  /// For MODELS_RETRIEVED.
  @$pb.TagNumber(7)
  $core.int get storedModelCount => $_getIZ(6);
  @$pb.TagNumber(7)
  set storedModelCount($core.int value) => $_setSignedInt32(6, value);
  @$pb.TagNumber(7)
  $core.bool hasStoredModelCount() => $_has(6);
  @$pb.TagNumber(7)
  void clearStoredModelCount() => $_clearField(7);

  /// For CACHE_HIT / CACHE_MISS / EVICTION (canonical superset additions
  /// not in RN's events.ts but called out in Step 3 spec).
  @$pb.TagNumber(8)
  $core.String get cacheKey => $_getSZ(7);
  @$pb.TagNumber(8)
  set cacheKey($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasCacheKey() => $_has(7);
  @$pb.TagNumber(8)
  void clearCacheKey() => $_clearField(8);

  @$pb.TagNumber(9)
  $fixnum.Int64 get evictedBytes => $_getI64(8);
  @$pb.TagNumber(9)
  set evictedBytes($fixnum.Int64 value) => $_setInt64(8, value);
  @$pb.TagNumber(9)
  $core.bool hasEvictedBytes() => $_has(8);
  @$pb.TagNumber(9)
  void clearEvictedBytes() => $_clearField(9);

  /// For CLEAR_CACHE_COMPLETED / CLEAN_TEMP_COMPLETED — bytes reclaimed.
  @$pb.TagNumber(10)
  $fixnum.Int64 get freedBytes => $_getI64(9);
  @$pb.TagNumber(10)
  set freedBytes($fixnum.Int64 value) => $_setInt64(9, value);
  @$pb.TagNumber(10)
  $core.bool hasFreedBytes() => $_has(9);
  @$pb.TagNumber(10)
  void clearFreedBytes() => $_clearField(10);
}

enum StorageLifecycleEvent_Result {
  infoResult,
  availabilityResult,
  deletePlan,
  deleteResult,
  notSet
}

class StorageLifecycleEvent extends $pb.GeneratedMessage {
  factory StorageLifecycleEvent({
    StorageLifecycleEventKind? kind,
    $core.String? modelId,
    $core.String? cacheKey,
    $fixnum.Int64? bytes,
    $core.String? error,
    $2.StorageInfoResult? infoResult,
    $2.StorageAvailabilityResult? availabilityResult,
    $2.StorageDeletePlan? deletePlan,
    $2.StorageDeleteResult? deleteResult,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (modelId != null) result.modelId = modelId;
    if (cacheKey != null) result.cacheKey = cacheKey;
    if (bytes != null) result.bytes = bytes;
    if (error != null) result.error = error;
    if (infoResult != null) result.infoResult = infoResult;
    if (availabilityResult != null)
      result.availabilityResult = availabilityResult;
    if (deletePlan != null) result.deletePlan = deletePlan;
    if (deleteResult != null) result.deleteResult = deleteResult;
    return result;
  }

  StorageLifecycleEvent._();

  factory StorageLifecycleEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory StorageLifecycleEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, StorageLifecycleEvent_Result>
      _StorageLifecycleEvent_ResultByTag = {
    20: StorageLifecycleEvent_Result.infoResult,
    21: StorageLifecycleEvent_Result.availabilityResult,
    22: StorageLifecycleEvent_Result.deletePlan,
    23: StorageLifecycleEvent_Result.deleteResult,
    0: StorageLifecycleEvent_Result.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'StorageLifecycleEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..oo(0, [20, 21, 22, 23])
    ..aE<StorageLifecycleEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: StorageLifecycleEventKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'modelId')
    ..aOS(3, _omitFieldNames ? '' : 'cacheKey')
    ..aInt64(4, _omitFieldNames ? '' : 'bytes')
    ..aOS(5, _omitFieldNames ? '' : 'error')
    ..aOM<$2.StorageInfoResult>(20, _omitFieldNames ? '' : 'infoResult',
        subBuilder: $2.StorageInfoResult.create)
    ..aOM<$2.StorageAvailabilityResult>(
        21, _omitFieldNames ? '' : 'availabilityResult',
        subBuilder: $2.StorageAvailabilityResult.create)
    ..aOM<$2.StorageDeletePlan>(22, _omitFieldNames ? '' : 'deletePlan',
        subBuilder: $2.StorageDeletePlan.create)
    ..aOM<$2.StorageDeleteResult>(23, _omitFieldNames ? '' : 'deleteResult',
        subBuilder: $2.StorageDeleteResult.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageLifecycleEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  StorageLifecycleEvent copyWith(
          void Function(StorageLifecycleEvent) updates) =>
      super.copyWith((message) => updates(message as StorageLifecycleEvent))
          as StorageLifecycleEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static StorageLifecycleEvent create() => StorageLifecycleEvent._();
  @$core.override
  StorageLifecycleEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static StorageLifecycleEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<StorageLifecycleEvent>(create);
  static StorageLifecycleEvent? _defaultInstance;

  @$pb.TagNumber(20)
  @$pb.TagNumber(21)
  @$pb.TagNumber(22)
  @$pb.TagNumber(23)
  StorageLifecycleEvent_Result whichResult() =>
      _StorageLifecycleEvent_ResultByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(20)
  @$pb.TagNumber(21)
  @$pb.TagNumber(22)
  @$pb.TagNumber(23)
  void clearResult() => $_clearField($_whichOneof(0));

  @$pb.TagNumber(1)
  StorageLifecycleEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(StorageLifecycleEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get modelId => $_getSZ(1);
  @$pb.TagNumber(2)
  set modelId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasModelId() => $_has(1);
  @$pb.TagNumber(2)
  void clearModelId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get cacheKey => $_getSZ(2);
  @$pb.TagNumber(3)
  set cacheKey($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasCacheKey() => $_has(2);
  @$pb.TagNumber(3)
  void clearCacheKey() => $_clearField(3);

  @$pb.TagNumber(4)
  $fixnum.Int64 get bytes => $_getI64(3);
  @$pb.TagNumber(4)
  set bytes($fixnum.Int64 value) => $_setInt64(3, value);
  @$pb.TagNumber(4)
  $core.bool hasBytes() => $_has(3);
  @$pb.TagNumber(4)
  void clearBytes() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get error => $_getSZ(4);
  @$pb.TagNumber(5)
  set error($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasError() => $_has(4);
  @$pb.TagNumber(5)
  void clearError() => $_clearField(5);

  @$pb.TagNumber(20)
  $2.StorageInfoResult get infoResult => $_getN(5);
  @$pb.TagNumber(20)
  set infoResult($2.StorageInfoResult value) => $_setField(20, value);
  @$pb.TagNumber(20)
  $core.bool hasInfoResult() => $_has(5);
  @$pb.TagNumber(20)
  void clearInfoResult() => $_clearField(20);
  @$pb.TagNumber(20)
  $2.StorageInfoResult ensureInfoResult() => $_ensure(5);

  @$pb.TagNumber(21)
  $2.StorageAvailabilityResult get availabilityResult => $_getN(6);
  @$pb.TagNumber(21)
  set availabilityResult($2.StorageAvailabilityResult value) =>
      $_setField(21, value);
  @$pb.TagNumber(21)
  $core.bool hasAvailabilityResult() => $_has(6);
  @$pb.TagNumber(21)
  void clearAvailabilityResult() => $_clearField(21);
  @$pb.TagNumber(21)
  $2.StorageAvailabilityResult ensureAvailabilityResult() => $_ensure(6);

  @$pb.TagNumber(22)
  $2.StorageDeletePlan get deletePlan => $_getN(7);
  @$pb.TagNumber(22)
  set deletePlan($2.StorageDeletePlan value) => $_setField(22, value);
  @$pb.TagNumber(22)
  $core.bool hasDeletePlan() => $_has(7);
  @$pb.TagNumber(22)
  void clearDeletePlan() => $_clearField(22);
  @$pb.TagNumber(22)
  $2.StorageDeletePlan ensureDeletePlan() => $_ensure(7);

  @$pb.TagNumber(23)
  $2.StorageDeleteResult get deleteResult => $_getN(8);
  @$pb.TagNumber(23)
  set deleteResult($2.StorageDeleteResult value) => $_setField(23, value);
  @$pb.TagNumber(23)
  $core.bool hasDeleteResult() => $_has(8);
  @$pb.TagNumber(23)
  void clearDeleteResult() => $_clearField(23);
  @$pb.TagNumber(23)
  $2.StorageDeleteResult ensureDeleteResult() => $_ensure(8);
}

class AuthEvent extends $pb.GeneratedMessage {
  factory AuthEvent({
    AuthEventKind? kind,
    $core.String? provider,
    $core.String? subjectId,
    $core.String? scope,
    $core.String? error,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (provider != null) result.provider = provider;
    if (subjectId != null) result.subjectId = subjectId;
    if (scope != null) result.scope = scope;
    if (error != null) result.error = error;
    return result;
  }

  AuthEvent._();

  factory AuthEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory AuthEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'AuthEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<AuthEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: AuthEventKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'provider')
    ..aOS(3, _omitFieldNames ? '' : 'subjectId')
    ..aOS(4, _omitFieldNames ? '' : 'scope')
    ..aOS(5, _omitFieldNames ? '' : 'error')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AuthEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  AuthEvent copyWith(void Function(AuthEvent) updates) =>
      super.copyWith((message) => updates(message as AuthEvent)) as AuthEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static AuthEvent create() => AuthEvent._();
  @$core.override
  AuthEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static AuthEvent getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<AuthEvent>(create);
  static AuthEvent? _defaultInstance;

  @$pb.TagNumber(1)
  AuthEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(AuthEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get provider => $_getSZ(1);
  @$pb.TagNumber(2)
  set provider($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasProvider() => $_has(1);
  @$pb.TagNumber(2)
  void clearProvider() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get subjectId => $_getSZ(2);
  @$pb.TagNumber(3)
  set subjectId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasSubjectId() => $_has(2);
  @$pb.TagNumber(3)
  void clearSubjectId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get scope => $_getSZ(3);
  @$pb.TagNumber(4)
  set scope($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasScope() => $_has(3);
  @$pb.TagNumber(4)
  void clearScope() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get error => $_getSZ(4);
  @$pb.TagNumber(5)
  set error($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasError() => $_has(4);
  @$pb.TagNumber(5)
  void clearError() => $_clearField(5);
}

/// ---------------------------------------------------------------------------
/// Device events: device-info collection / sync, plus battery / thermal /
/// connectivity changes (canonical superset; Kotlin's analytics layer
/// already emits these as raw `BaseSDKEvent`s with category=device).
/// Mirrors RN events.ts:257-264 (SDKDeviceEvent: 7 variants).
/// ---------------------------------------------------------------------------
class DeviceEvent extends $pb.GeneratedMessage {
  factory DeviceEvent({
    DeviceEventKind? kind,
    $core.String? deviceId,
    $core.String? osName,
    $core.String? osVersion,
    $core.String? model,
    $core.String? error,
    $core.String? property,
    $core.String? newValue,
    $core.String? oldValue,
    $core.double? batteryLevel,
    $core.bool? isCharging,
    $core.String? thermalState,
    $core.bool? isConnected,
    $core.String? connectionType,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (deviceId != null) result.deviceId = deviceId;
    if (osName != null) result.osName = osName;
    if (osVersion != null) result.osVersion = osVersion;
    if (model != null) result.model = model;
    if (error != null) result.error = error;
    if (property != null) result.property = property;
    if (newValue != null) result.newValue = newValue;
    if (oldValue != null) result.oldValue = oldValue;
    if (batteryLevel != null) result.batteryLevel = batteryLevel;
    if (isCharging != null) result.isCharging = isCharging;
    if (thermalState != null) result.thermalState = thermalState;
    if (isConnected != null) result.isConnected = isConnected;
    if (connectionType != null) result.connectionType = connectionType;
    return result;
  }

  DeviceEvent._();

  factory DeviceEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory DeviceEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'DeviceEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<DeviceEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: DeviceEventKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'deviceId')
    ..aOS(3, _omitFieldNames ? '' : 'osName')
    ..aOS(4, _omitFieldNames ? '' : 'osVersion')
    ..aOS(5, _omitFieldNames ? '' : 'model')
    ..aOS(6, _omitFieldNames ? '' : 'error')
    ..aOS(7, _omitFieldNames ? '' : 'property')
    ..aOS(8, _omitFieldNames ? '' : 'newValue')
    ..aOS(9, _omitFieldNames ? '' : 'oldValue')
    ..aD(10, _omitFieldNames ? '' : 'batteryLevel',
        fieldType: $pb.PbFieldType.OF)
    ..aOB(11, _omitFieldNames ? '' : 'isCharging')
    ..aOS(12, _omitFieldNames ? '' : 'thermalState')
    ..aOB(13, _omitFieldNames ? '' : 'isConnected')
    ..aOS(14, _omitFieldNames ? '' : 'connectionType')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  DeviceEvent copyWith(void Function(DeviceEvent) updates) =>
      super.copyWith((message) => updates(message as DeviceEvent))
          as DeviceEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static DeviceEvent create() => DeviceEvent._();
  @$core.override
  DeviceEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static DeviceEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<DeviceEvent>(create);
  static DeviceEvent? _defaultInstance;

  @$pb.TagNumber(1)
  DeviceEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(DeviceEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  /// For DEVICE_INFO_COLLECTED / REFRESHED — populated state-key/value
  /// pairs (avoid embedding full DeviceInfoData; that lives in its own
  /// proto). The summary fields below are the most-queried subset.
  @$pb.TagNumber(2)
  $core.String get deviceId => $_getSZ(1);
  @$pb.TagNumber(2)
  set deviceId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasDeviceId() => $_has(1);
  @$pb.TagNumber(2)
  void clearDeviceId() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get osName => $_getSZ(2);
  @$pb.TagNumber(3)
  set osName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasOsName() => $_has(2);
  @$pb.TagNumber(3)
  void clearOsName() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get osVersion => $_getSZ(3);
  @$pb.TagNumber(4)
  set osVersion($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasOsVersion() => $_has(3);
  @$pb.TagNumber(4)
  void clearOsVersion() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get model => $_getSZ(4);
  @$pb.TagNumber(5)
  set model($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasModel() => $_has(4);
  @$pb.TagNumber(5)
  void clearModel() => $_clearField(5);

  /// For *_FAILED.
  @$pb.TagNumber(6)
  $core.String get error => $_getSZ(5);
  @$pb.TagNumber(6)
  set error($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasError() => $_has(5);
  @$pb.TagNumber(6)
  void clearError() => $_clearField(6);

  /// For DEVICE_STATE_CHANGED — RN events.ts:264.
  @$pb.TagNumber(7)
  $core.String get property => $_getSZ(6);
  @$pb.TagNumber(7)
  set property($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasProperty() => $_has(6);
  @$pb.TagNumber(7)
  void clearProperty() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get newValue => $_getSZ(7);
  @$pb.TagNumber(8)
  set newValue($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasNewValue() => $_has(7);
  @$pb.TagNumber(8)
  void clearNewValue() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get oldValue => $_getSZ(8);
  @$pb.TagNumber(9)
  set oldValue($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasOldValue() => $_has(8);
  @$pb.TagNumber(9)
  void clearOldValue() => $_clearField(9);

  /// For BATTERY_CHANGED / THERMAL_CHANGED / CONNECTIVITY_CHANGED.
  @$pb.TagNumber(10)
  $core.double get batteryLevel => $_getN(9);
  @$pb.TagNumber(10)
  set batteryLevel($core.double value) => $_setFloat(9, value);
  @$pb.TagNumber(10)
  $core.bool hasBatteryLevel() => $_has(9);
  @$pb.TagNumber(10)
  void clearBatteryLevel() => $_clearField(10);

  @$pb.TagNumber(11)
  $core.bool get isCharging => $_getBF(10);
  @$pb.TagNumber(11)
  set isCharging($core.bool value) => $_setBool(10, value);
  @$pb.TagNumber(11)
  $core.bool hasIsCharging() => $_has(10);
  @$pb.TagNumber(11)
  void clearIsCharging() => $_clearField(11);

  @$pb.TagNumber(12)
  $core.String get thermalState => $_getSZ(11);
  @$pb.TagNumber(12)
  set thermalState($core.String value) => $_setString(11, value);
  @$pb.TagNumber(12)
  $core.bool hasThermalState() => $_has(11);
  @$pb.TagNumber(12)
  void clearThermalState() => $_clearField(12);

  @$pb.TagNumber(13)
  $core.bool get isConnected => $_getBF(12);
  @$pb.TagNumber(13)
  set isConnected($core.bool value) => $_setBool(12, value);
  @$pb.TagNumber(13)
  $core.bool hasIsConnected() => $_has(12);
  @$pb.TagNumber(13)
  void clearIsConnected() => $_clearField(13);

  @$pb.TagNumber(14)
  $core.String get connectionType => $_getSZ(13);
  @$pb.TagNumber(14)
  set connectionType($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasConnectionType() => $_has(13);
  @$pb.TagNumber(14)
  void clearConnectionType() => $_clearField(14);
}

/// ---------------------------------------------------------------------------
/// Network events. Mirrors RN
///   events.ts:203-207 (SDKNetworkEvent: 4 variants).
/// ---------------------------------------------------------------------------
class NetworkEvent extends $pb.GeneratedMessage {
  factory NetworkEvent({
    NetworkEventKind? kind,
    $core.String? url,
    $core.int? statusCode,
    $core.bool? isOnline,
    $core.String? error,
    $fixnum.Int64? latencyMs,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (url != null) result.url = url;
    if (statusCode != null) result.statusCode = statusCode;
    if (isOnline != null) result.isOnline = isOnline;
    if (error != null) result.error = error;
    if (latencyMs != null) result.latencyMs = latencyMs;
    return result;
  }

  NetworkEvent._();

  factory NetworkEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory NetworkEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'NetworkEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<NetworkEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: NetworkEventKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'url')
    ..aI(3, _omitFieldNames ? '' : 'statusCode')
    ..aOB(4, _omitFieldNames ? '' : 'isOnline')
    ..aOS(5, _omitFieldNames ? '' : 'error')
    ..aInt64(6, _omitFieldNames ? '' : 'latencyMs')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NetworkEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  NetworkEvent copyWith(void Function(NetworkEvent) updates) =>
      super.copyWith((message) => updates(message as NetworkEvent))
          as NetworkEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static NetworkEvent create() => NetworkEvent._();
  @$core.override
  NetworkEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static NetworkEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<NetworkEvent>(create);
  static NetworkEvent? _defaultInstance;

  @$pb.TagNumber(1)
  NetworkEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(NetworkEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get url => $_getSZ(1);
  @$pb.TagNumber(2)
  set url($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasUrl() => $_has(1);
  @$pb.TagNumber(2)
  void clearUrl() => $_clearField(2);

  /// For REQUEST_COMPLETED — HTTP status (RN events.ts:205).
  @$pb.TagNumber(3)
  $core.int get statusCode => $_getIZ(2);
  @$pb.TagNumber(3)
  set statusCode($core.int value) => $_setSignedInt32(2, value);
  @$pb.TagNumber(3)
  $core.bool hasStatusCode() => $_has(2);
  @$pb.TagNumber(3)
  void clearStatusCode() => $_clearField(3);

  /// For CONNECTIVITY_CHANGED — RN events.ts:207.
  @$pb.TagNumber(4)
  $core.bool get isOnline => $_getBF(3);
  @$pb.TagNumber(4)
  set isOnline($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasIsOnline() => $_has(3);
  @$pb.TagNumber(4)
  void clearIsOnline() => $_clearField(4);

  /// For REQUEST_FAILED / TIMEOUT.
  @$pb.TagNumber(5)
  $core.String get error => $_getSZ(4);
  @$pb.TagNumber(5)
  set error($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasError() => $_has(4);
  @$pb.TagNumber(5)
  void clearError() => $_clearField(5);

  /// For REQUEST_COMPLETED — response time in ms (canonical addition,
  /// implied by Kotlin/iOS request timing instrumentation).
  @$pb.TagNumber(6)
  $fixnum.Int64 get latencyMs => $_getI64(5);
  @$pb.TagNumber(6)
  set latencyMs($fixnum.Int64 value) => $_setInt64(5, value);
  @$pb.TagNumber(6)
  $core.bool hasLatencyMs() => $_has(5);
  @$pb.TagNumber(6)
  void clearLatencyMs() => $_clearField(6);
}

/// ---------------------------------------------------------------------------
/// Framework registry events. Mirrors RN
///   events.ts:232-251 (SDKFrameworkEvent: 11 variants).
/// ---------------------------------------------------------------------------
class FrameworkEvent extends $pb.GeneratedMessage {
  factory FrameworkEvent({
    FrameworkEventKind? kind,
    $core.int? framework,
    $core.String? adapterName,
    $core.int? adapterCount,
    $core.int? frameworkCount,
    $core.int? modelCount,
    $core.String? modality,
    $core.String? error,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (framework != null) result.framework = framework;
    if (adapterName != null) result.adapterName = adapterName;
    if (adapterCount != null) result.adapterCount = adapterCount;
    if (frameworkCount != null) result.frameworkCount = frameworkCount;
    if (modelCount != null) result.modelCount = modelCount;
    if (modality != null) result.modality = modality;
    if (error != null) result.error = error;
    return result;
  }

  FrameworkEvent._();

  factory FrameworkEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FrameworkEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FrameworkEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<FrameworkEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: FrameworkEventKind.values)
    ..aI(2, _omitFieldNames ? '' : 'framework')
    ..aOS(3, _omitFieldNames ? '' : 'adapterName')
    ..aI(4, _omitFieldNames ? '' : 'adapterCount')
    ..aI(5, _omitFieldNames ? '' : 'frameworkCount')
    ..aI(6, _omitFieldNames ? '' : 'modelCount')
    ..aOS(7, _omitFieldNames ? '' : 'modality')
    ..aOS(8, _omitFieldNames ? '' : 'error')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FrameworkEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FrameworkEvent copyWith(void Function(FrameworkEvent) updates) =>
      super.copyWith((message) => updates(message as FrameworkEvent))
          as FrameworkEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FrameworkEvent create() => FrameworkEvent._();
  @$core.override
  FrameworkEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FrameworkEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FrameworkEvent>(create);
  static FrameworkEvent? _defaultInstance;

  @$pb.TagNumber(1)
  FrameworkEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(FrameworkEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  /// For ADAPTER_REGISTERED / *_RETRIEVED — bound framework. Uses
  /// canonical InferenceFramework from model_types.proto, but stored as
  /// its enum int32 here to avoid cross-file message dependency just for
  /// a single field. Frontends decode via the shared codegen.
  @$pb.TagNumber(2)
  $core.int get framework => $_getIZ(1);
  @$pb.TagNumber(2)
  set framework($core.int value) => $_setSignedInt32(1, value);
  @$pb.TagNumber(2)
  $core.bool hasFramework() => $_has(1);
  @$pb.TagNumber(2)
  void clearFramework() => $_clearField(2);

  /// For ADAPTER_REGISTERED — adapter display name.
  @$pb.TagNumber(3)
  $core.String get adapterName => $_getSZ(2);
  @$pb.TagNumber(3)
  set adapterName($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasAdapterName() => $_has(2);
  @$pb.TagNumber(3)
  void clearAdapterName() => $_clearField(3);

  /// For ADAPTERS_RETRIEVED / *_RETRIEVED — counts.
  @$pb.TagNumber(4)
  $core.int get adapterCount => $_getIZ(3);
  @$pb.TagNumber(4)
  set adapterCount($core.int value) => $_setSignedInt32(3, value);
  @$pb.TagNumber(4)
  $core.bool hasAdapterCount() => $_has(3);
  @$pb.TagNumber(4)
  void clearAdapterCount() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.int get frameworkCount => $_getIZ(4);
  @$pb.TagNumber(5)
  set frameworkCount($core.int value) => $_setSignedInt32(4, value);
  @$pb.TagNumber(5)
  $core.bool hasFrameworkCount() => $_has(4);
  @$pb.TagNumber(5)
  void clearFrameworkCount() => $_clearField(5);

  /// For MODELS_FOR_FRAMEWORK_RETRIEVED — model count (full ModelInfo[]
  /// travels via RPCs, not events).
  @$pb.TagNumber(6)
  $core.int get modelCount => $_getIZ(5);
  @$pb.TagNumber(6)
  set modelCount($core.int value) => $_setSignedInt32(5, value);
  @$pb.TagNumber(6)
  $core.bool hasModelCount() => $_has(5);
  @$pb.TagNumber(6)
  void clearModelCount() => $_clearField(6);

  /// For *_FOR_MODALITY_* — modality identifier (string-keyed; canonical
  /// FrameworkModality enum exists in model_types but we keep this loose
  /// so plugins can register custom modalities).
  @$pb.TagNumber(7)
  $core.String get modality => $_getSZ(6);
  @$pb.TagNumber(7)
  set modality($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasModality() => $_has(6);
  @$pb.TagNumber(7)
  void clearModality() => $_clearField(7);

  /// For ERROR / UNREGISTERED failures (canonical superset additions).
  @$pb.TagNumber(8)
  $core.String get error => $_getSZ(7);
  @$pb.TagNumber(8)
  set error($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasError() => $_has(7);
  @$pb.TagNumber(8)
  void clearError() => $_clearField(8);
}

class HardwareRoutingEvent extends $pb.GeneratedMessage {
  factory HardwareRoutingEvent({
    HardwareRoutingEventKind? kind,
    SDKComponent? component,
    $0.InferenceFramework? framework,
    $core.String? capability,
    $core.String? route,
    $core.String? reason,
    $core.String? error,
    $3.HardwareProfileResult? hardwareProfile,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (component != null) result.component = component;
    if (framework != null) result.framework = framework;
    if (capability != null) result.capability = capability;
    if (route != null) result.route = route;
    if (reason != null) result.reason = reason;
    if (error != null) result.error = error;
    if (hardwareProfile != null) result.hardwareProfile = hardwareProfile;
    return result;
  }

  HardwareRoutingEvent._();

  factory HardwareRoutingEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory HardwareRoutingEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'HardwareRoutingEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<HardwareRoutingEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: HardwareRoutingEventKind.values)
    ..aE<SDKComponent>(2, _omitFieldNames ? '' : 'component',
        enumValues: SDKComponent.values)
    ..aE<$0.InferenceFramework>(3, _omitFieldNames ? '' : 'framework',
        enumValues: $0.InferenceFramework.values)
    ..aOS(4, _omitFieldNames ? '' : 'capability')
    ..aOS(5, _omitFieldNames ? '' : 'route')
    ..aOS(6, _omitFieldNames ? '' : 'reason')
    ..aOS(7, _omitFieldNames ? '' : 'error')
    ..aOM<$3.HardwareProfileResult>(
        20, _omitFieldNames ? '' : 'hardwareProfile',
        subBuilder: $3.HardwareProfileResult.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HardwareRoutingEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  HardwareRoutingEvent copyWith(void Function(HardwareRoutingEvent) updates) =>
      super.copyWith((message) => updates(message as HardwareRoutingEvent))
          as HardwareRoutingEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static HardwareRoutingEvent create() => HardwareRoutingEvent._();
  @$core.override
  HardwareRoutingEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static HardwareRoutingEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<HardwareRoutingEvent>(create);
  static HardwareRoutingEvent? _defaultInstance;

  @$pb.TagNumber(1)
  HardwareRoutingEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(HardwareRoutingEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  SDKComponent get component => $_getN(1);
  @$pb.TagNumber(2)
  set component(SDKComponent value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasComponent() => $_has(1);
  @$pb.TagNumber(2)
  void clearComponent() => $_clearField(2);

  @$pb.TagNumber(3)
  $0.InferenceFramework get framework => $_getN(2);
  @$pb.TagNumber(3)
  set framework($0.InferenceFramework value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasFramework() => $_has(2);
  @$pb.TagNumber(3)
  void clearFramework() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get capability => $_getSZ(3);
  @$pb.TagNumber(4)
  set capability($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasCapability() => $_has(3);
  @$pb.TagNumber(4)
  void clearCapability() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get route => $_getSZ(4);
  @$pb.TagNumber(5)
  set route($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasRoute() => $_has(4);
  @$pb.TagNumber(5)
  void clearRoute() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get reason => $_getSZ(5);
  @$pb.TagNumber(6)
  set reason($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasReason() => $_has(5);
  @$pb.TagNumber(6)
  void clearReason() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get error => $_getSZ(6);
  @$pb.TagNumber(7)
  set error($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasError() => $_has(6);
  @$pb.TagNumber(7)
  void clearError() => $_clearField(7);

  @$pb.TagNumber(20)
  $3.HardwareProfileResult get hardwareProfile => $_getN(7);
  @$pb.TagNumber(20)
  set hardwareProfile($3.HardwareProfileResult value) => $_setField(20, value);
  @$pb.TagNumber(20)
  $core.bool hasHardwareProfile() => $_has(7);
  @$pb.TagNumber(20)
  void clearHardwareProfile() => $_clearField(20);
  @$pb.TagNumber(20)
  $3.HardwareProfileResult ensureHardwareProfile() => $_ensure(7);
}

/// ---------------------------------------------------------------------------
/// Performance metrics events. Mirrors RN
///   events.ts:193-197 (SDKPerformanceEvent: 4 variants).
/// ---------------------------------------------------------------------------
class PerformanceEvent extends $pb.GeneratedMessage {
  factory PerformanceEvent({
    PerformanceEventKind? kind,
    $fixnum.Int64? memoryBytes,
    $core.String? thermalState,
    $core.String? operation,
    $fixnum.Int64? milliseconds,
    $core.double? tokensPerSecond,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (memoryBytes != null) result.memoryBytes = memoryBytes;
    if (thermalState != null) result.thermalState = thermalState;
    if (operation != null) result.operation = operation;
    if (milliseconds != null) result.milliseconds = milliseconds;
    if (tokensPerSecond != null) result.tokensPerSecond = tokensPerSecond;
    return result;
  }

  PerformanceEvent._();

  factory PerformanceEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory PerformanceEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'PerformanceEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<PerformanceEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: PerformanceEventKind.values)
    ..aInt64(2, _omitFieldNames ? '' : 'memoryBytes')
    ..aOS(3, _omitFieldNames ? '' : 'thermalState')
    ..aOS(4, _omitFieldNames ? '' : 'operation')
    ..aInt64(5, _omitFieldNames ? '' : 'milliseconds')
    ..aD(6, _omitFieldNames ? '' : 'tokensPerSecond')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PerformanceEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  PerformanceEvent copyWith(void Function(PerformanceEvent) updates) =>
      super.copyWith((message) => updates(message as PerformanceEvent))
          as PerformanceEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static PerformanceEvent create() => PerformanceEvent._();
  @$core.override
  PerformanceEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static PerformanceEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<PerformanceEvent>(create);
  static PerformanceEvent? _defaultInstance;

  @$pb.TagNumber(1)
  PerformanceEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(PerformanceEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  /// For MEMORY_WARNING — usage in bytes (RN typed as number).
  @$pb.TagNumber(2)
  $fixnum.Int64 get memoryBytes => $_getI64(1);
  @$pb.TagNumber(2)
  set memoryBytes($fixnum.Int64 value) => $_setInt64(1, value);
  @$pb.TagNumber(2)
  $core.bool hasMemoryBytes() => $_has(1);
  @$pb.TagNumber(2)
  void clearMemoryBytes() => $_clearField(2);

  /// For THERMAL_STATE_CHANGED — engine-defined state string
  /// (e.g. "nominal", "fair", "serious", "critical"; Apple-specific
  /// names preserved as strings to avoid platform-coupled enums).
  @$pb.TagNumber(3)
  $core.String get thermalState => $_getSZ(2);
  @$pb.TagNumber(3)
  set thermalState($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasThermalState() => $_has(2);
  @$pb.TagNumber(3)
  void clearThermalState() => $_clearField(3);

  /// For LATENCY_MEASURED.
  @$pb.TagNumber(4)
  $core.String get operation => $_getSZ(3);
  @$pb.TagNumber(4)
  set operation($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasOperation() => $_has(3);
  @$pb.TagNumber(4)
  void clearOperation() => $_clearField(4);

  @$pb.TagNumber(5)
  $fixnum.Int64 get milliseconds => $_getI64(4);
  @$pb.TagNumber(5)
  set milliseconds($fixnum.Int64 value) => $_setInt64(4, value);
  @$pb.TagNumber(5)
  $core.bool hasMilliseconds() => $_has(4);
  @$pb.TagNumber(5)
  void clearMilliseconds() => $_clearField(5);

  /// For THROUGHPUT_MEASURED — RN events.ts:197.
  @$pb.TagNumber(6)
  $core.double get tokensPerSecond => $_getN(5);
  @$pb.TagNumber(6)
  set tokensPerSecond($core.double value) => $_setDouble(5, value);
  @$pb.TagNumber(6)
  $core.bool hasTokensPerSecond() => $_has(5);
  @$pb.TagNumber(6)
  void clearTokensPerSecond() => $_clearField(6);
}

class TelemetryEvent extends $pb.GeneratedMessage {
  factory TelemetryEvent({
    TelemetryEventKind? kind,
    $core.String? name,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? attributes,
    $core.double? value,
    $core.String? unit,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (name != null) result.name = name;
    if (attributes != null) result.attributes.addEntries(attributes);
    if (value != null) result.value = value;
    if (unit != null) result.unit = unit;
    return result;
  }

  TelemetryEvent._();

  factory TelemetryEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory TelemetryEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'TelemetryEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<TelemetryEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: TelemetryEventKind.values)
    ..aOS(2, _omitFieldNames ? '' : 'name')
    ..m<$core.String, $core.String>(3, _omitFieldNames ? '' : 'attributes',
        entryClassName: 'TelemetryEvent.AttributesEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..aD(4, _omitFieldNames ? '' : 'value')
    ..aOS(5, _omitFieldNames ? '' : 'unit')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TelemetryEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  TelemetryEvent copyWith(void Function(TelemetryEvent) updates) =>
      super.copyWith((message) => updates(message as TelemetryEvent))
          as TelemetryEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static TelemetryEvent create() => TelemetryEvent._();
  @$core.override
  TelemetryEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static TelemetryEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<TelemetryEvent>(create);
  static TelemetryEvent? _defaultInstance;

  @$pb.TagNumber(1)
  TelemetryEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(TelemetryEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get name => $_getSZ(1);
  @$pb.TagNumber(2)
  set name($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasName() => $_has(1);
  @$pb.TagNumber(2)
  void clearName() => $_clearField(2);

  @$pb.TagNumber(3)
  $pb.PbMap<$core.String, $core.String> get attributes => $_getMap(2);

  @$pb.TagNumber(4)
  $core.double get value => $_getN(3);
  @$pb.TagNumber(4)
  set value($core.double value) => $_setDouble(3, value);
  @$pb.TagNumber(4)
  $core.bool hasValue() => $_has(3);
  @$pb.TagNumber(4)
  void clearValue() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get unit => $_getSZ(4);
  @$pb.TagNumber(5)
  set unit($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasUnit() => $_has(4);
  @$pb.TagNumber(5)
  void clearUnit() => $_clearField(5);
}

class CancellationEvent extends $pb.GeneratedMessage {
  factory CancellationEvent({
    CancellationEventKind? kind,
    SDKComponent? component,
    $core.String? operationId,
    $core.String? reason,
    $core.bool? userInitiated,
  }) {
    final result = create();
    if (kind != null) result.kind = kind;
    if (component != null) result.component = component;
    if (operationId != null) result.operationId = operationId;
    if (reason != null) result.reason = reason;
    if (userInitiated != null) result.userInitiated = userInitiated;
    return result;
  }

  CancellationEvent._();

  factory CancellationEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory CancellationEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'CancellationEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<CancellationEventKind>(1, _omitFieldNames ? '' : 'kind',
        enumValues: CancellationEventKind.values)
    ..aE<SDKComponent>(2, _omitFieldNames ? '' : 'component',
        enumValues: SDKComponent.values)
    ..aOS(3, _omitFieldNames ? '' : 'operationId')
    ..aOS(4, _omitFieldNames ? '' : 'reason')
    ..aOB(5, _omitFieldNames ? '' : 'userInitiated')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CancellationEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  CancellationEvent copyWith(void Function(CancellationEvent) updates) =>
      super.copyWith((message) => updates(message as CancellationEvent))
          as CancellationEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static CancellationEvent create() => CancellationEvent._();
  @$core.override
  CancellationEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static CancellationEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<CancellationEvent>(create);
  static CancellationEvent? _defaultInstance;

  @$pb.TagNumber(1)
  CancellationEventKind get kind => $_getN(0);
  @$pb.TagNumber(1)
  set kind(CancellationEventKind value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasKind() => $_has(0);
  @$pb.TagNumber(1)
  void clearKind() => $_clearField(1);

  @$pb.TagNumber(2)
  SDKComponent get component => $_getN(1);
  @$pb.TagNumber(2)
  set component(SDKComponent value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasComponent() => $_has(1);
  @$pb.TagNumber(2)
  void clearComponent() => $_clearField(2);

  @$pb.TagNumber(3)
  $core.String get operationId => $_getSZ(2);
  @$pb.TagNumber(3)
  set operationId($core.String value) => $_setString(2, value);
  @$pb.TagNumber(3)
  $core.bool hasOperationId() => $_has(2);
  @$pb.TagNumber(3)
  void clearOperationId() => $_clearField(3);

  @$pb.TagNumber(4)
  $core.String get reason => $_getSZ(3);
  @$pb.TagNumber(4)
  set reason($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasReason() => $_has(3);
  @$pb.TagNumber(4)
  void clearReason() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.bool get userInitiated => $_getBF(4);
  @$pb.TagNumber(5)
  set userInitiated($core.bool value) => $_setBool(4, value);
  @$pb.TagNumber(5)
  $core.bool hasUserInitiated() => $_has(4);
  @$pb.TagNumber(5)
  void clearUserInitiated() => $_clearField(5);
}

class FailureEvent extends $pb.GeneratedMessage {
  factory FailureEvent({
    SDKComponent? component,
    $core.String? operation,
    $4.SDKError? error,
    $core.bool? recoverable,
  }) {
    final result = create();
    if (component != null) result.component = component;
    if (operation != null) result.operation = operation;
    if (error != null) result.error = error;
    if (recoverable != null) result.recoverable = recoverable;
    return result;
  }

  FailureEvent._();

  factory FailureEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory FailureEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'FailureEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aE<SDKComponent>(1, _omitFieldNames ? '' : 'component',
        enumValues: SDKComponent.values)
    ..aOS(2, _omitFieldNames ? '' : 'operation')
    ..aOM<$4.SDKError>(3, _omitFieldNames ? '' : 'error',
        subBuilder: $4.SDKError.create)
    ..aOB(4, _omitFieldNames ? '' : 'recoverable')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FailureEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  FailureEvent copyWith(void Function(FailureEvent) updates) =>
      super.copyWith((message) => updates(message as FailureEvent))
          as FailureEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static FailureEvent create() => FailureEvent._();
  @$core.override
  FailureEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static FailureEvent getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<FailureEvent>(create);
  static FailureEvent? _defaultInstance;

  @$pb.TagNumber(1)
  SDKComponent get component => $_getN(0);
  @$pb.TagNumber(1)
  set component(SDKComponent value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasComponent() => $_has(0);
  @$pb.TagNumber(1)
  void clearComponent() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get operation => $_getSZ(1);
  @$pb.TagNumber(2)
  set operation($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasOperation() => $_has(1);
  @$pb.TagNumber(2)
  void clearOperation() => $_clearField(2);

  @$pb.TagNumber(3)
  $4.SDKError get error => $_getN(2);
  @$pb.TagNumber(3)
  set error($4.SDKError value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasError() => $_has(2);
  @$pb.TagNumber(3)
  void clearError() => $_clearField(3);
  @$pb.TagNumber(3)
  $4.SDKError ensureError() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.bool get recoverable => $_getBF(3);
  @$pb.TagNumber(4)
  set recoverable($core.bool value) => $_setBool(3, value);
  @$pb.TagNumber(4)
  $core.bool hasRecoverable() => $_has(3);
  @$pb.TagNumber(4)
  void clearRecoverable() => $_clearField(4);
}

enum SDKEvent_Event {
  initialization,
  configuration,
  generation,
  model,
  performance,
  network,
  storage,
  framework,
  device,
  componentInit,
  voice,
  voicePipeline,
  componentLifecycle,
  session,
  auth,
  modelRegistry,
  download,
  storageLifecycle,
  hardwareRouting,
  capability,
  telemetry,
  cancellation,
  failure,
  notSet
}

/// ---------------------------------------------------------------------------
/// Top-level event envelope. Every event published by every SDK is wrapped in
/// exactly one `SDKEvent` — analytics consumers, app developers, and
/// pipelines all decode the same bytes.
///
/// `voice_pipeline` carries the streaming voice pipeline events from
/// `voice_events.proto` (UserSaid / AssistantToken / AudioFrame / VAD /
/// Interrupted / StateChange / Error / Metrics). Higher-level voice
/// lifecycle events live in this file's `voice` field.
/// ---------------------------------------------------------------------------
class SDKEvent extends $pb.GeneratedMessage {
  factory SDKEvent({
    $fixnum.Int64? timestampMs,
    $4.ErrorSeverity? severity,
    InitializationEvent? initialization,
    ConfigurationEvent? configuration,
    GenerationEvent? generation,
    ModelEvent? model,
    PerformanceEvent? performance,
    NetworkEvent? network,
    StorageEvent? storage,
    FrameworkEvent? framework,
    DeviceEvent? device,
    ComponentInitializationEvent? componentInit,
    $core.String? id,
    $core.String? sessionId,
    EventDestination? destination,
    $core.Iterable<$core.MapEntry<$core.String, $core.String>>? properties,
    VoiceLifecycleEvent? voice,
    $5.VoiceEvent? voicePipeline,
    ComponentLifecycleEvent? componentLifecycle,
    $6.EventCategory? category,
    SDKComponent? component,
    $4.SDKError? error,
    SessionEvent? session,
    AuthEvent? auth,
    ModelRegistryEvent? modelRegistry,
    DownloadEvent? download,
    StorageLifecycleEvent? storageLifecycle,
    HardwareRoutingEvent? hardwareRouting,
    CapabilityOperationEvent? capability,
    TelemetryEvent? telemetry,
    CancellationEvent? cancellation,
    FailureEvent? failure,
    $core.String? operationId,
    $core.String? correlationId,
    $core.String? source,
    $core.String? traceId,
  }) {
    final result = create();
    if (timestampMs != null) result.timestampMs = timestampMs;
    if (severity != null) result.severity = severity;
    if (initialization != null) result.initialization = initialization;
    if (configuration != null) result.configuration = configuration;
    if (generation != null) result.generation = generation;
    if (model != null) result.model = model;
    if (performance != null) result.performance = performance;
    if (network != null) result.network = network;
    if (storage != null) result.storage = storage;
    if (framework != null) result.framework = framework;
    if (device != null) result.device = device;
    if (componentInit != null) result.componentInit = componentInit;
    if (id != null) result.id = id;
    if (sessionId != null) result.sessionId = sessionId;
    if (destination != null) result.destination = destination;
    if (properties != null) result.properties.addEntries(properties);
    if (voice != null) result.voice = voice;
    if (voicePipeline != null) result.voicePipeline = voicePipeline;
    if (componentLifecycle != null)
      result.componentLifecycle = componentLifecycle;
    if (category != null) result.category = category;
    if (component != null) result.component = component;
    if (error != null) result.error = error;
    if (session != null) result.session = session;
    if (auth != null) result.auth = auth;
    if (modelRegistry != null) result.modelRegistry = modelRegistry;
    if (download != null) result.download = download;
    if (storageLifecycle != null) result.storageLifecycle = storageLifecycle;
    if (hardwareRouting != null) result.hardwareRouting = hardwareRouting;
    if (capability != null) result.capability = capability;
    if (telemetry != null) result.telemetry = telemetry;
    if (cancellation != null) result.cancellation = cancellation;
    if (failure != null) result.failure = failure;
    if (operationId != null) result.operationId = operationId;
    if (correlationId != null) result.correlationId = correlationId;
    if (source != null) result.source = source;
    if (traceId != null) result.traceId = traceId;
    return result;
  }

  SDKEvent._();

  factory SDKEvent.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SDKEvent.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static const $core.Map<$core.int, SDKEvent_Event> _SDKEvent_EventByTag = {
    3: SDKEvent_Event.initialization,
    4: SDKEvent_Event.configuration,
    5: SDKEvent_Event.generation,
    6: SDKEvent_Event.model,
    7: SDKEvent_Event.performance,
    8: SDKEvent_Event.network,
    9: SDKEvent_Event.storage,
    10: SDKEvent_Event.framework,
    11: SDKEvent_Event.device,
    12: SDKEvent_Event.componentInit,
    17: SDKEvent_Event.voice,
    18: SDKEvent_Event.voicePipeline,
    19: SDKEvent_Event.componentLifecycle,
    23: SDKEvent_Event.session,
    24: SDKEvent_Event.auth,
    25: SDKEvent_Event.modelRegistry,
    26: SDKEvent_Event.download,
    27: SDKEvent_Event.storageLifecycle,
    28: SDKEvent_Event.hardwareRouting,
    29: SDKEvent_Event.capability,
    30: SDKEvent_Event.telemetry,
    31: SDKEvent_Event.cancellation,
    32: SDKEvent_Event.failure,
    0: SDKEvent_Event.notSet
  };
  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SDKEvent',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..oo(0, [
      3,
      4,
      5,
      6,
      7,
      8,
      9,
      10,
      11,
      12,
      17,
      18,
      19,
      23,
      24,
      25,
      26,
      27,
      28,
      29,
      30,
      31,
      32
    ])
    ..aInt64(1, _omitFieldNames ? '' : 'timestampMs')
    ..aE<$4.ErrorSeverity>(2, _omitFieldNames ? '' : 'severity',
        enumValues: $4.ErrorSeverity.values)
    ..aOM<InitializationEvent>(3, _omitFieldNames ? '' : 'initialization',
        subBuilder: InitializationEvent.create)
    ..aOM<ConfigurationEvent>(4, _omitFieldNames ? '' : 'configuration',
        subBuilder: ConfigurationEvent.create)
    ..aOM<GenerationEvent>(5, _omitFieldNames ? '' : 'generation',
        subBuilder: GenerationEvent.create)
    ..aOM<ModelEvent>(6, _omitFieldNames ? '' : 'model',
        subBuilder: ModelEvent.create)
    ..aOM<PerformanceEvent>(7, _omitFieldNames ? '' : 'performance',
        subBuilder: PerformanceEvent.create)
    ..aOM<NetworkEvent>(8, _omitFieldNames ? '' : 'network',
        subBuilder: NetworkEvent.create)
    ..aOM<StorageEvent>(9, _omitFieldNames ? '' : 'storage',
        subBuilder: StorageEvent.create)
    ..aOM<FrameworkEvent>(10, _omitFieldNames ? '' : 'framework',
        subBuilder: FrameworkEvent.create)
    ..aOM<DeviceEvent>(11, _omitFieldNames ? '' : 'device',
        subBuilder: DeviceEvent.create)
    ..aOM<ComponentInitializationEvent>(
        12, _omitFieldNames ? '' : 'componentInit',
        subBuilder: ComponentInitializationEvent.create)
    ..aOS(13, _omitFieldNames ? '' : 'id')
    ..aOS(14, _omitFieldNames ? '' : 'sessionId')
    ..aE<EventDestination>(15, _omitFieldNames ? '' : 'destination',
        enumValues: EventDestination.values)
    ..m<$core.String, $core.String>(16, _omitFieldNames ? '' : 'properties',
        entryClassName: 'SDKEvent.PropertiesEntry',
        keyFieldType: $pb.PbFieldType.OS,
        valueFieldType: $pb.PbFieldType.OS,
        packageName: const $pb.PackageName('runanywhere.v1'))
    ..aOM<VoiceLifecycleEvent>(17, _omitFieldNames ? '' : 'voice',
        subBuilder: VoiceLifecycleEvent.create)
    ..aOM<$5.VoiceEvent>(18, _omitFieldNames ? '' : 'voicePipeline',
        subBuilder: $5.VoiceEvent.create)
    ..aOM<ComponentLifecycleEvent>(
        19, _omitFieldNames ? '' : 'componentLifecycle',
        subBuilder: ComponentLifecycleEvent.create)
    ..aE<$6.EventCategory>(20, _omitFieldNames ? '' : 'category',
        enumValues: $6.EventCategory.values)
    ..aE<SDKComponent>(21, _omitFieldNames ? '' : 'component',
        enumValues: SDKComponent.values)
    ..aOM<$4.SDKError>(22, _omitFieldNames ? '' : 'error',
        subBuilder: $4.SDKError.create)
    ..aOM<SessionEvent>(23, _omitFieldNames ? '' : 'session',
        subBuilder: SessionEvent.create)
    ..aOM<AuthEvent>(24, _omitFieldNames ? '' : 'auth',
        subBuilder: AuthEvent.create)
    ..aOM<ModelRegistryEvent>(25, _omitFieldNames ? '' : 'modelRegistry',
        subBuilder: ModelRegistryEvent.create)
    ..aOM<DownloadEvent>(26, _omitFieldNames ? '' : 'download',
        subBuilder: DownloadEvent.create)
    ..aOM<StorageLifecycleEvent>(27, _omitFieldNames ? '' : 'storageLifecycle',
        subBuilder: StorageLifecycleEvent.create)
    ..aOM<HardwareRoutingEvent>(28, _omitFieldNames ? '' : 'hardwareRouting',
        subBuilder: HardwareRoutingEvent.create)
    ..aOM<CapabilityOperationEvent>(29, _omitFieldNames ? '' : 'capability',
        subBuilder: CapabilityOperationEvent.create)
    ..aOM<TelemetryEvent>(30, _omitFieldNames ? '' : 'telemetry',
        subBuilder: TelemetryEvent.create)
    ..aOM<CancellationEvent>(31, _omitFieldNames ? '' : 'cancellation',
        subBuilder: CancellationEvent.create)
    ..aOM<FailureEvent>(32, _omitFieldNames ? '' : 'failure',
        subBuilder: FailureEvent.create)
    ..aOS(33, _omitFieldNames ? '' : 'operationId')
    ..aOS(34, _omitFieldNames ? '' : 'correlationId')
    ..aOS(35, _omitFieldNames ? '' : 'source')
    ..aOS(36, _omitFieldNames ? '' : 'traceId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SDKEvent clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SDKEvent copyWith(void Function(SDKEvent) updates) =>
      super.copyWith((message) => updates(message as SDKEvent)) as SDKEvent;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SDKEvent create() => SDKEvent._();
  @$core.override
  SDKEvent createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SDKEvent getDefault() =>
      _defaultInstance ??= $pb.GeneratedMessage.$_defaultFor<SDKEvent>(create);
  static SDKEvent? _defaultInstance;

  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(9)
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  @$pb.TagNumber(19)
  @$pb.TagNumber(23)
  @$pb.TagNumber(24)
  @$pb.TagNumber(25)
  @$pb.TagNumber(26)
  @$pb.TagNumber(27)
  @$pb.TagNumber(28)
  @$pb.TagNumber(29)
  @$pb.TagNumber(30)
  @$pb.TagNumber(31)
  @$pb.TagNumber(32)
  SDKEvent_Event whichEvent() => _SDKEvent_EventByTag[$_whichOneof(0)]!;
  @$pb.TagNumber(3)
  @$pb.TagNumber(4)
  @$pb.TagNumber(5)
  @$pb.TagNumber(6)
  @$pb.TagNumber(7)
  @$pb.TagNumber(8)
  @$pb.TagNumber(9)
  @$pb.TagNumber(10)
  @$pb.TagNumber(11)
  @$pb.TagNumber(12)
  @$pb.TagNumber(17)
  @$pb.TagNumber(18)
  @$pb.TagNumber(19)
  @$pb.TagNumber(23)
  @$pb.TagNumber(24)
  @$pb.TagNumber(25)
  @$pb.TagNumber(26)
  @$pb.TagNumber(27)
  @$pb.TagNumber(28)
  @$pb.TagNumber(29)
  @$pb.TagNumber(30)
  @$pb.TagNumber(31)
  @$pb.TagNumber(32)
  void clearEvent() => $_clearField($_whichOneof(0));

  /// Wall-clock time of event creation, milliseconds since Unix epoch.
  @$pb.TagNumber(1)
  $fixnum.Int64 get timestampMs => $_getI64(0);
  @$pb.TagNumber(1)
  set timestampMs($fixnum.Int64 value) => $_setInt64(0, value);
  @$pb.TagNumber(1)
  $core.bool hasTimestampMs() => $_has(0);
  @$pb.TagNumber(1)
  void clearTimestampMs() => $_clearField(1);

  @$pb.TagNumber(2)
  $4.ErrorSeverity get severity => $_getN(1);
  @$pb.TagNumber(2)
  set severity($4.ErrorSeverity value) => $_setField(2, value);
  @$pb.TagNumber(2)
  $core.bool hasSeverity() => $_has(1);
  @$pb.TagNumber(2)
  void clearSeverity() => $_clearField(2);

  @$pb.TagNumber(3)
  InitializationEvent get initialization => $_getN(2);
  @$pb.TagNumber(3)
  set initialization(InitializationEvent value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasInitialization() => $_has(2);
  @$pb.TagNumber(3)
  void clearInitialization() => $_clearField(3);
  @$pb.TagNumber(3)
  InitializationEvent ensureInitialization() => $_ensure(2);

  @$pb.TagNumber(4)
  ConfigurationEvent get configuration => $_getN(3);
  @$pb.TagNumber(4)
  set configuration(ConfigurationEvent value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasConfiguration() => $_has(3);
  @$pb.TagNumber(4)
  void clearConfiguration() => $_clearField(4);
  @$pb.TagNumber(4)
  ConfigurationEvent ensureConfiguration() => $_ensure(3);

  @$pb.TagNumber(5)
  GenerationEvent get generation => $_getN(4);
  @$pb.TagNumber(5)
  set generation(GenerationEvent value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasGeneration() => $_has(4);
  @$pb.TagNumber(5)
  void clearGeneration() => $_clearField(5);
  @$pb.TagNumber(5)
  GenerationEvent ensureGeneration() => $_ensure(4);

  @$pb.TagNumber(6)
  ModelEvent get model => $_getN(5);
  @$pb.TagNumber(6)
  set model(ModelEvent value) => $_setField(6, value);
  @$pb.TagNumber(6)
  $core.bool hasModel() => $_has(5);
  @$pb.TagNumber(6)
  void clearModel() => $_clearField(6);
  @$pb.TagNumber(6)
  ModelEvent ensureModel() => $_ensure(5);

  @$pb.TagNumber(7)
  PerformanceEvent get performance => $_getN(6);
  @$pb.TagNumber(7)
  set performance(PerformanceEvent value) => $_setField(7, value);
  @$pb.TagNumber(7)
  $core.bool hasPerformance() => $_has(6);
  @$pb.TagNumber(7)
  void clearPerformance() => $_clearField(7);
  @$pb.TagNumber(7)
  PerformanceEvent ensurePerformance() => $_ensure(6);

  @$pb.TagNumber(8)
  NetworkEvent get network => $_getN(7);
  @$pb.TagNumber(8)
  set network(NetworkEvent value) => $_setField(8, value);
  @$pb.TagNumber(8)
  $core.bool hasNetwork() => $_has(7);
  @$pb.TagNumber(8)
  void clearNetwork() => $_clearField(8);
  @$pb.TagNumber(8)
  NetworkEvent ensureNetwork() => $_ensure(7);

  @$pb.TagNumber(9)
  StorageEvent get storage => $_getN(8);
  @$pb.TagNumber(9)
  set storage(StorageEvent value) => $_setField(9, value);
  @$pb.TagNumber(9)
  $core.bool hasStorage() => $_has(8);
  @$pb.TagNumber(9)
  void clearStorage() => $_clearField(9);
  @$pb.TagNumber(9)
  StorageEvent ensureStorage() => $_ensure(8);

  @$pb.TagNumber(10)
  FrameworkEvent get framework => $_getN(9);
  @$pb.TagNumber(10)
  set framework(FrameworkEvent value) => $_setField(10, value);
  @$pb.TagNumber(10)
  $core.bool hasFramework() => $_has(9);
  @$pb.TagNumber(10)
  void clearFramework() => $_clearField(10);
  @$pb.TagNumber(10)
  FrameworkEvent ensureFramework() => $_ensure(9);

  @$pb.TagNumber(11)
  DeviceEvent get device => $_getN(10);
  @$pb.TagNumber(11)
  set device(DeviceEvent value) => $_setField(11, value);
  @$pb.TagNumber(11)
  $core.bool hasDevice() => $_has(10);
  @$pb.TagNumber(11)
  void clearDevice() => $_clearField(11);
  @$pb.TagNumber(11)
  DeviceEvent ensureDevice() => $_ensure(10);

  @$pb.TagNumber(12)
  ComponentInitializationEvent get componentInit => $_getN(11);
  @$pb.TagNumber(12)
  set componentInit(ComponentInitializationEvent value) =>
      $_setField(12, value);
  @$pb.TagNumber(12)
  $core.bool hasComponentInit() => $_has(11);
  @$pb.TagNumber(12)
  void clearComponentInit() => $_clearField(12);
  @$pb.TagNumber(12)
  ComponentInitializationEvent ensureComponentInit() => $_ensure(11);

  /// Event identifier (UUID). Required by Swift SDKEvent.id /
  /// Kotlin SDKEvent.id / Dart SDKEvent.id for de-duplication.
  @$pb.TagNumber(13)
  $core.String get id => $_getSZ(12);
  @$pb.TagNumber(13)
  set id($core.String value) => $_setString(12, value);
  @$pb.TagNumber(13)
  $core.bool hasId() => $_has(12);
  @$pb.TagNumber(13)
  void clearId() => $_clearField(13);

  /// Optional session id for grouping related events
  /// (Swift sessionId / Kotlin sessionId / Dart sessionId).
  @$pb.TagNumber(14)
  $core.String get sessionId => $_getSZ(13);
  @$pb.TagNumber(14)
  set sessionId($core.String value) => $_setString(13, value);
  @$pb.TagNumber(14)
  $core.bool hasSessionId() => $_has(13);
  @$pb.TagNumber(14)
  void clearSessionId() => $_clearField(14);

  /// Event routing destination (Swift EventDestination, Kotlin
  /// EventDestination, Dart EventDestination).
  @$pb.TagNumber(15)
  EventDestination get destination => $_getN(14);
  @$pb.TagNumber(15)
  set destination(EventDestination value) => $_setField(15, value);
  @$pb.TagNumber(15)
  $core.bool hasDestination() => $_has(14);
  @$pb.TagNumber(15)
  void clearDestination() => $_clearField(15);

  /// Free-form metadata for properties not modeled above
  /// (mirrors `properties: Map<String, String>` from each SDK).
  @$pb.TagNumber(16)
  $pb.PbMap<$core.String, $core.String> get properties => $_getMap(15);

  @$pb.TagNumber(17)
  VoiceLifecycleEvent get voice => $_getN(16);
  @$pb.TagNumber(17)
  set voice(VoiceLifecycleEvent value) => $_setField(17, value);
  @$pb.TagNumber(17)
  $core.bool hasVoice() => $_has(16);
  @$pb.TagNumber(17)
  void clearVoice() => $_clearField(17);
  @$pb.TagNumber(17)
  VoiceLifecycleEvent ensureVoice() => $_ensure(16);

  @$pb.TagNumber(18)
  $5.VoiceEvent get voicePipeline => $_getN(17);
  @$pb.TagNumber(18)
  set voicePipeline($5.VoiceEvent value) => $_setField(18, value);
  @$pb.TagNumber(18)
  $core.bool hasVoicePipeline() => $_has(17);
  @$pb.TagNumber(18)
  void clearVoicePipeline() => $_clearField(18);
  @$pb.TagNumber(18)
  $5.VoiceEvent ensureVoicePipeline() => $_ensure(17);

  @$pb.TagNumber(19)
  ComponentLifecycleEvent get componentLifecycle => $_getN(18);
  @$pb.TagNumber(19)
  set componentLifecycle(ComponentLifecycleEvent value) =>
      $_setField(19, value);
  @$pb.TagNumber(19)
  $core.bool hasComponentLifecycle() => $_has(18);
  @$pb.TagNumber(19)
  void clearComponentLifecycle() => $_clearField(19);
  @$pb.TagNumber(19)
  ComponentLifecycleEvent ensureComponentLifecycle() => $_ensure(18);

  @$pb.TagNumber(20)
  $6.EventCategory get category => $_getN(19);
  @$pb.TagNumber(20)
  set category($6.EventCategory value) => $_setField(20, value);
  @$pb.TagNumber(20)
  $core.bool hasCategory() => $_has(19);
  @$pb.TagNumber(20)
  void clearCategory() => $_clearField(20);

  @$pb.TagNumber(21)
  SDKComponent get component => $_getN(20);
  @$pb.TagNumber(21)
  set component(SDKComponent value) => $_setField(21, value);
  @$pb.TagNumber(21)
  $core.bool hasComponent() => $_has(20);
  @$pb.TagNumber(21)
  void clearComponent() => $_clearField(21);

  /// Typed failure details for any failed event. When the event itself is
  /// only an error notification, use the failure oneof arm below.
  @$pb.TagNumber(22)
  $4.SDKError get error => $_getN(21);
  @$pb.TagNumber(22)
  set error($4.SDKError value) => $_setField(22, value);
  @$pb.TagNumber(22)
  $core.bool hasError() => $_has(21);
  @$pb.TagNumber(22)
  void clearError() => $_clearField(22);
  @$pb.TagNumber(22)
  $4.SDKError ensureError() => $_ensure(21);

  @$pb.TagNumber(23)
  SessionEvent get session => $_getN(22);
  @$pb.TagNumber(23)
  set session(SessionEvent value) => $_setField(23, value);
  @$pb.TagNumber(23)
  $core.bool hasSession() => $_has(22);
  @$pb.TagNumber(23)
  void clearSession() => $_clearField(23);
  @$pb.TagNumber(23)
  SessionEvent ensureSession() => $_ensure(22);

  @$pb.TagNumber(24)
  AuthEvent get auth => $_getN(23);
  @$pb.TagNumber(24)
  set auth(AuthEvent value) => $_setField(24, value);
  @$pb.TagNumber(24)
  $core.bool hasAuth() => $_has(23);
  @$pb.TagNumber(24)
  void clearAuth() => $_clearField(24);
  @$pb.TagNumber(24)
  AuthEvent ensureAuth() => $_ensure(23);

  @$pb.TagNumber(25)
  ModelRegistryEvent get modelRegistry => $_getN(24);
  @$pb.TagNumber(25)
  set modelRegistry(ModelRegistryEvent value) => $_setField(25, value);
  @$pb.TagNumber(25)
  $core.bool hasModelRegistry() => $_has(24);
  @$pb.TagNumber(25)
  void clearModelRegistry() => $_clearField(25);
  @$pb.TagNumber(25)
  ModelRegistryEvent ensureModelRegistry() => $_ensure(24);

  @$pb.TagNumber(26)
  DownloadEvent get download => $_getN(25);
  @$pb.TagNumber(26)
  set download(DownloadEvent value) => $_setField(26, value);
  @$pb.TagNumber(26)
  $core.bool hasDownload() => $_has(25);
  @$pb.TagNumber(26)
  void clearDownload() => $_clearField(26);
  @$pb.TagNumber(26)
  DownloadEvent ensureDownload() => $_ensure(25);

  @$pb.TagNumber(27)
  StorageLifecycleEvent get storageLifecycle => $_getN(26);
  @$pb.TagNumber(27)
  set storageLifecycle(StorageLifecycleEvent value) => $_setField(27, value);
  @$pb.TagNumber(27)
  $core.bool hasStorageLifecycle() => $_has(26);
  @$pb.TagNumber(27)
  void clearStorageLifecycle() => $_clearField(27);
  @$pb.TagNumber(27)
  StorageLifecycleEvent ensureStorageLifecycle() => $_ensure(26);

  @$pb.TagNumber(28)
  HardwareRoutingEvent get hardwareRouting => $_getN(27);
  @$pb.TagNumber(28)
  set hardwareRouting(HardwareRoutingEvent value) => $_setField(28, value);
  @$pb.TagNumber(28)
  $core.bool hasHardwareRouting() => $_has(27);
  @$pb.TagNumber(28)
  void clearHardwareRouting() => $_clearField(28);
  @$pb.TagNumber(28)
  HardwareRoutingEvent ensureHardwareRouting() => $_ensure(27);

  @$pb.TagNumber(29)
  CapabilityOperationEvent get capability => $_getN(28);
  @$pb.TagNumber(29)
  set capability(CapabilityOperationEvent value) => $_setField(29, value);
  @$pb.TagNumber(29)
  $core.bool hasCapability() => $_has(28);
  @$pb.TagNumber(29)
  void clearCapability() => $_clearField(29);
  @$pb.TagNumber(29)
  CapabilityOperationEvent ensureCapability() => $_ensure(28);

  @$pb.TagNumber(30)
  TelemetryEvent get telemetry => $_getN(29);
  @$pb.TagNumber(30)
  set telemetry(TelemetryEvent value) => $_setField(30, value);
  @$pb.TagNumber(30)
  $core.bool hasTelemetry() => $_has(29);
  @$pb.TagNumber(30)
  void clearTelemetry() => $_clearField(30);
  @$pb.TagNumber(30)
  TelemetryEvent ensureTelemetry() => $_ensure(29);

  @$pb.TagNumber(31)
  CancellationEvent get cancellation => $_getN(30);
  @$pb.TagNumber(31)
  set cancellation(CancellationEvent value) => $_setField(31, value);
  @$pb.TagNumber(31)
  $core.bool hasCancellation() => $_has(30);
  @$pb.TagNumber(31)
  void clearCancellation() => $_clearField(31);
  @$pb.TagNumber(31)
  CancellationEvent ensureCancellation() => $_ensure(30);

  @$pb.TagNumber(32)
  FailureEvent get failure => $_getN(31);
  @$pb.TagNumber(32)
  set failure(FailureEvent value) => $_setField(32, value);
  @$pb.TagNumber(32)
  $core.bool hasFailure() => $_has(31);
  @$pb.TagNumber(32)
  void clearFailure() => $_clearField(32);
  @$pb.TagNumber(32)
  FailureEvent ensureFailure() => $_ensure(31);

  /// Logical operation identifier for this event, e.g. "download.start",
  /// "model.load", or "llm.generate". This is separate from the event UUID
  /// so retry/cancel/progress/failure events can share one operation id.
  @$pb.TagNumber(33)
  $core.String get operationId => $_getSZ(32);
  @$pb.TagNumber(33)
  set operationId($core.String value) => $_setString(32, value);
  @$pb.TagNumber(33)
  $core.bool hasOperationId() => $_has(32);
  @$pb.TagNumber(33)
  void clearOperationId() => $_clearField(33);

  /// Cross-service correlation key supplied by the SDK/app or generated by
  /// the portable layer. Native/Web adapters may propagate it through HTTP
  /// headers or OS task metadata, but C++ owns the canonical event field.
  @$pb.TagNumber(34)
  $core.String get correlationId => $_getSZ(33);
  @$pb.TagNumber(34)
  set correlationId($core.String value) => $_setString(33, value);
  @$pb.TagNumber(34)
  $core.bool hasCorrelationId() => $_has(33);
  @$pb.TagNumber(34)
  void clearCorrelationId() => $_clearField(34);

  /// Source that emitted the event: "cpp", "swift", "kotlin", "flutter",
  /// "react_native", "web", or a backend/plugin key. This disambiguates
  /// platform adapter facts from portable orchestration events.
  @$pb.TagNumber(35)
  $core.String get source => $_getSZ(34);
  @$pb.TagNumber(35)
  set source($core.String value) => $_setString(34, value);
  @$pb.TagNumber(35)
  $core.bool hasSource() => $_has(34);
  @$pb.TagNumber(35)
  void clearSource() => $_clearField(35);

  /// Optional tracing identifier for diagnostics. Empty when tracing is not
  /// enabled; do not use it as a business key.
  @$pb.TagNumber(36)
  $core.String get traceId => $_getSZ(35);
  @$pb.TagNumber(36)
  set traceId($core.String value) => $_setString(35, value);
  @$pb.TagNumber(36)
  $core.bool hasTraceId() => $_has(35);
  @$pb.TagNumber(36)
  void clearTraceId() => $_clearField(36);
}

/// Subscription-side filter for the canonical SDKEvent stream. Empty fields are
/// wildcards; implementations match populated fields against the envelope fields
/// above without interpreting payload-specific data.
class SDKEventFilter extends $pb.GeneratedMessage {
  factory SDKEventFilter({
    $core.Iterable<$6.EventCategory>? categories,
    $core.Iterable<SDKComponent>? components,
    $core.Iterable<EventDestination>? destinations,
    $4.ErrorSeverity? minimumSeverity,
    $core.String? sessionId,
    $core.String? operationId,
    $core.String? correlationId,
    $core.String? source,
    $core.String? traceId,
  }) {
    final result = create();
    if (categories != null) result.categories.addAll(categories);
    if (components != null) result.components.addAll(components);
    if (destinations != null) result.destinations.addAll(destinations);
    if (minimumSeverity != null) result.minimumSeverity = minimumSeverity;
    if (sessionId != null) result.sessionId = sessionId;
    if (operationId != null) result.operationId = operationId;
    if (correlationId != null) result.correlationId = correlationId;
    if (source != null) result.source = source;
    if (traceId != null) result.traceId = traceId;
    return result;
  }

  SDKEventFilter._();

  factory SDKEventFilter.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SDKEventFilter.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SDKEventFilter',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..pc<$6.EventCategory>(
        1, _omitFieldNames ? '' : 'categories', $pb.PbFieldType.KE,
        valueOf: $6.EventCategory.valueOf,
        enumValues: $6.EventCategory.values,
        defaultEnumValue: $6.EventCategory.EVENT_CATEGORY_UNSPECIFIED)
    ..pc<SDKComponent>(
        2, _omitFieldNames ? '' : 'components', $pb.PbFieldType.KE,
        valueOf: SDKComponent.valueOf,
        enumValues: SDKComponent.values,
        defaultEnumValue: SDKComponent.SDK_COMPONENT_UNSPECIFIED)
    ..pc<EventDestination>(
        3, _omitFieldNames ? '' : 'destinations', $pb.PbFieldType.KE,
        valueOf: EventDestination.valueOf,
        enumValues: EventDestination.values,
        defaultEnumValue: EventDestination.EVENT_DESTINATION_UNSPECIFIED)
    ..aE<$4.ErrorSeverity>(4, _omitFieldNames ? '' : 'minimumSeverity',
        enumValues: $4.ErrorSeverity.values)
    ..aOS(5, _omitFieldNames ? '' : 'sessionId')
    ..aOS(6, _omitFieldNames ? '' : 'operationId')
    ..aOS(7, _omitFieldNames ? '' : 'correlationId')
    ..aOS(8, _omitFieldNames ? '' : 'source')
    ..aOS(9, _omitFieldNames ? '' : 'traceId')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SDKEventFilter clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SDKEventFilter copyWith(void Function(SDKEventFilter) updates) =>
      super.copyWith((message) => updates(message as SDKEventFilter))
          as SDKEventFilter;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SDKEventFilter create() => SDKEventFilter._();
  @$core.override
  SDKEventFilter createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SDKEventFilter getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SDKEventFilter>(create);
  static SDKEventFilter? _defaultInstance;

  @$pb.TagNumber(1)
  $pb.PbList<$6.EventCategory> get categories => $_getList(0);

  @$pb.TagNumber(2)
  $pb.PbList<SDKComponent> get components => $_getList(1);

  @$pb.TagNumber(3)
  $pb.PbList<EventDestination> get destinations => $_getList(2);

  @$pb.TagNumber(4)
  $4.ErrorSeverity get minimumSeverity => $_getN(3);
  @$pb.TagNumber(4)
  set minimumSeverity($4.ErrorSeverity value) => $_setField(4, value);
  @$pb.TagNumber(4)
  $core.bool hasMinimumSeverity() => $_has(3);
  @$pb.TagNumber(4)
  void clearMinimumSeverity() => $_clearField(4);

  @$pb.TagNumber(5)
  $core.String get sessionId => $_getSZ(4);
  @$pb.TagNumber(5)
  set sessionId($core.String value) => $_setString(4, value);
  @$pb.TagNumber(5)
  $core.bool hasSessionId() => $_has(4);
  @$pb.TagNumber(5)
  void clearSessionId() => $_clearField(5);

  @$pb.TagNumber(6)
  $core.String get operationId => $_getSZ(5);
  @$pb.TagNumber(6)
  set operationId($core.String value) => $_setString(5, value);
  @$pb.TagNumber(6)
  $core.bool hasOperationId() => $_has(5);
  @$pb.TagNumber(6)
  void clearOperationId() => $_clearField(6);

  @$pb.TagNumber(7)
  $core.String get correlationId => $_getSZ(6);
  @$pb.TagNumber(7)
  set correlationId($core.String value) => $_setString(6, value);
  @$pb.TagNumber(7)
  $core.bool hasCorrelationId() => $_has(6);
  @$pb.TagNumber(7)
  void clearCorrelationId() => $_clearField(7);

  @$pb.TagNumber(8)
  $core.String get source => $_getSZ(7);
  @$pb.TagNumber(8)
  set source($core.String value) => $_setString(7, value);
  @$pb.TagNumber(8)
  $core.bool hasSource() => $_has(7);
  @$pb.TagNumber(8)
  void clearSource() => $_clearField(8);

  @$pb.TagNumber(9)
  $core.String get traceId => $_getSZ(8);
  @$pb.TagNumber(9)
  set traceId($core.String value) => $_setString(8, value);
  @$pb.TagNumber(9)
  $core.bool hasTraceId() => $_has(8);
  @$pb.TagNumber(9)
  void clearTraceId() => $_clearField(9);
}

class SDKEventPublishRequest extends $pb.GeneratedMessage {
  factory SDKEventPublishRequest({
    SDKEvent? event,
    $core.bool? normalizeEnvelope,
  }) {
    final result = create();
    if (event != null) result.event = event;
    if (normalizeEnvelope != null) result.normalizeEnvelope = normalizeEnvelope;
    return result;
  }

  SDKEventPublishRequest._();

  factory SDKEventPublishRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SDKEventPublishRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SDKEventPublishRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOM<SDKEvent>(1, _omitFieldNames ? '' : 'event',
        subBuilder: SDKEvent.create)
    ..aOB(2, _omitFieldNames ? '' : 'normalizeEnvelope')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SDKEventPublishRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SDKEventPublishRequest copyWith(
          void Function(SDKEventPublishRequest) updates) =>
      super.copyWith((message) => updates(message as SDKEventPublishRequest))
          as SDKEventPublishRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SDKEventPublishRequest create() => SDKEventPublishRequest._();
  @$core.override
  SDKEventPublishRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SDKEventPublishRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SDKEventPublishRequest>(create);
  static SDKEventPublishRequest? _defaultInstance;

  @$pb.TagNumber(1)
  SDKEvent get event => $_getN(0);
  @$pb.TagNumber(1)
  set event(SDKEvent value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasEvent() => $_has(0);
  @$pb.TagNumber(1)
  void clearEvent() => $_clearField(1);
  @$pb.TagNumber(1)
  SDKEvent ensureEvent() => $_ensure(0);

  /// When true, the portable event layer fills missing envelope metadata such
  /// as id, timestamp, destination, category/component defaults, source, and
  /// correlation fields before routing the event.
  @$pb.TagNumber(2)
  $core.bool get normalizeEnvelope => $_getBF(1);
  @$pb.TagNumber(2)
  set normalizeEnvelope($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasNormalizeEnvelope() => $_has(1);
  @$pb.TagNumber(2)
  void clearNormalizeEnvelope() => $_clearField(2);
}

class SDKEventPublishResult extends $pb.GeneratedMessage {
  factory SDKEventPublishResult({
    $core.bool? accepted,
    $core.String? eventId,
    SDKEvent? normalizedEvent,
    $core.String? errorMessage,
    $4.SDKError? error,
  }) {
    final result = create();
    if (accepted != null) result.accepted = accepted;
    if (eventId != null) result.eventId = eventId;
    if (normalizedEvent != null) result.normalizedEvent = normalizedEvent;
    if (errorMessage != null) result.errorMessage = errorMessage;
    if (error != null) result.error = error;
    return result;
  }

  SDKEventPublishResult._();

  factory SDKEventPublishResult.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SDKEventPublishResult.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SDKEventPublishResult',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOB(1, _omitFieldNames ? '' : 'accepted')
    ..aOS(2, _omitFieldNames ? '' : 'eventId')
    ..aOM<SDKEvent>(3, _omitFieldNames ? '' : 'normalizedEvent',
        subBuilder: SDKEvent.create)
    ..aOS(4, _omitFieldNames ? '' : 'errorMessage')
    ..aOM<$4.SDKError>(5, _omitFieldNames ? '' : 'error',
        subBuilder: $4.SDKError.create)
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SDKEventPublishResult clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SDKEventPublishResult copyWith(
          void Function(SDKEventPublishResult) updates) =>
      super.copyWith((message) => updates(message as SDKEventPublishResult))
          as SDKEventPublishResult;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SDKEventPublishResult create() => SDKEventPublishResult._();
  @$core.override
  SDKEventPublishResult createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SDKEventPublishResult getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SDKEventPublishResult>(create);
  static SDKEventPublishResult? _defaultInstance;

  @$pb.TagNumber(1)
  $core.bool get accepted => $_getBF(0);
  @$pb.TagNumber(1)
  set accepted($core.bool value) => $_setBool(0, value);
  @$pb.TagNumber(1)
  $core.bool hasAccepted() => $_has(0);
  @$pb.TagNumber(1)
  void clearAccepted() => $_clearField(1);

  @$pb.TagNumber(2)
  $core.String get eventId => $_getSZ(1);
  @$pb.TagNumber(2)
  set eventId($core.String value) => $_setString(1, value);
  @$pb.TagNumber(2)
  $core.bool hasEventId() => $_has(1);
  @$pb.TagNumber(2)
  void clearEventId() => $_clearField(2);

  /// The event as accepted by the portable layer after optional envelope
  /// normalization. This is the same typed payload that serialized-proto
  /// bridges publish to subscribers.
  @$pb.TagNumber(3)
  SDKEvent get normalizedEvent => $_getN(2);
  @$pb.TagNumber(3)
  set normalizedEvent(SDKEvent value) => $_setField(3, value);
  @$pb.TagNumber(3)
  $core.bool hasNormalizedEvent() => $_has(2);
  @$pb.TagNumber(3)
  void clearNormalizedEvent() => $_clearField(3);
  @$pb.TagNumber(3)
  SDKEvent ensureNormalizedEvent() => $_ensure(2);

  @$pb.TagNumber(4)
  $core.String get errorMessage => $_getSZ(3);
  @$pb.TagNumber(4)
  set errorMessage($core.String value) => $_setString(3, value);
  @$pb.TagNumber(4)
  $core.bool hasErrorMessage() => $_has(3);
  @$pb.TagNumber(4)
  void clearErrorMessage() => $_clearField(4);

  @$pb.TagNumber(5)
  $4.SDKError get error => $_getN(4);
  @$pb.TagNumber(5)
  set error($4.SDKError value) => $_setField(5, value);
  @$pb.TagNumber(5)
  $core.bool hasError() => $_has(4);
  @$pb.TagNumber(5)
  void clearError() => $_clearField(5);
  @$pb.TagNumber(5)
  $4.SDKError ensureError() => $_ensure(4);
}

class SDKEventSubscribeRequest extends $pb.GeneratedMessage {
  factory SDKEventSubscribeRequest({
    SDKEventFilter? filter,
    $core.bool? replayQueuedEvents,
  }) {
    final result = create();
    if (filter != null) result.filter = filter;
    if (replayQueuedEvents != null)
      result.replayQueuedEvents = replayQueuedEvents;
    return result;
  }

  SDKEventSubscribeRequest._();

  factory SDKEventSubscribeRequest.fromBuffer($core.List<$core.int> data,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromBuffer(data, registry);
  factory SDKEventSubscribeRequest.fromJson($core.String json,
          [$pb.ExtensionRegistry registry = $pb.ExtensionRegistry.EMPTY]) =>
      create()..mergeFromJson(json, registry);

  static final $pb.BuilderInfo _i = $pb.BuilderInfo(
      _omitMessageNames ? '' : 'SDKEventSubscribeRequest',
      package: const $pb.PackageName(_omitMessageNames ? '' : 'runanywhere.v1'),
      createEmptyInstance: create)
    ..aOM<SDKEventFilter>(1, _omitFieldNames ? '' : 'filter',
        subBuilder: SDKEventFilter.create)
    ..aOB(2, _omitFieldNames ? '' : 'replayQueuedEvents')
    ..hasRequiredFields = false;

  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SDKEventSubscribeRequest clone() => deepCopy();
  @$core.Deprecated('See https://github.com/google/protobuf.dart/issues/998.')
  SDKEventSubscribeRequest copyWith(
          void Function(SDKEventSubscribeRequest) updates) =>
      super.copyWith((message) => updates(message as SDKEventSubscribeRequest))
          as SDKEventSubscribeRequest;

  @$core.override
  $pb.BuilderInfo get info_ => _i;

  @$core.pragma('dart2js:noInline')
  static SDKEventSubscribeRequest create() => SDKEventSubscribeRequest._();
  @$core.override
  SDKEventSubscribeRequest createEmptyInstance() => create();
  @$core.pragma('dart2js:noInline')
  static SDKEventSubscribeRequest getDefault() => _defaultInstance ??=
      $pb.GeneratedMessage.$_defaultFor<SDKEventSubscribeRequest>(create);
  static SDKEventSubscribeRequest? _defaultInstance;

  @$pb.TagNumber(1)
  SDKEventFilter get filter => $_getN(0);
  @$pb.TagNumber(1)
  set filter(SDKEventFilter value) => $_setField(1, value);
  @$pb.TagNumber(1)
  $core.bool hasFilter() => $_has(0);
  @$pb.TagNumber(1)
  void clearFilter() => $_clearField(1);
  @$pb.TagNumber(1)
  SDKEventFilter ensureFilter() => $_ensure(0);

  /// Replays queued events before following live events when the backing
  /// bridge has a poll queue. Implementations without retention may ignore it
  /// and continue with live events only.
  @$pb.TagNumber(2)
  $core.bool get replayQueuedEvents => $_getBF(1);
  @$pb.TagNumber(2)
  set replayQueuedEvents($core.bool value) => $_setBool(1, value);
  @$pb.TagNumber(2)
  $core.bool hasReplayQueuedEvents() => $_has(1);
  @$pb.TagNumber(2)
  void clearReplayQueuedEvents() => $_clearField(2);
}

/// Logical SDK event service contract. C++ owns event envelope normalization,
/// routing/subscription matching, correlation/operation/source/trace metadata,
/// and the serialized-proto bridge. Platform adapters own OS notification APIs,
/// lifecycle callbacks, permission prompts, and host event-loop integration.
class SDKEventsApi {
  final $pb.RpcClient _client;

  SDKEventsApi(this._client);

  $async.Future<SDKEventPublishResult> publish(
          $pb.ClientContext? ctx, SDKEventPublishRequest request) =>
      _client.invoke<SDKEventPublishResult>(
          ctx, 'SDKEvents', 'Publish', request, SDKEventPublishResult());
  $async.Future<SDKEvent> subscribe(
          $pb.ClientContext? ctx, SDKEventSubscribeRequest request) =>
      _client.invoke<SDKEvent>(
          ctx, 'SDKEvents', 'Subscribe', request, SDKEvent());
}

const $core.bool _omitFieldNames =
    $core.bool.fromEnvironment('protobuf.omit_field_names');
const $core.bool _omitMessageNames =
    $core.bool.fromEnvironment('protobuf.omit_message_names');
