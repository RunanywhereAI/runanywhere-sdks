// This is a generated file - do not edit.
//
// Generated from component_types.proto.

// @dart = 3.3

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names
// ignore_for_file: curly_braces_in_flow_control_structures
// ignore_for_file: deprecated_member_use_from_same_package, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_relative_imports

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// Component runtime lifecycle state for model-backed SDK components. Platform
/// adapters own native component handles; this enum carries the C++ lifecycle
/// state every SDK can expose uniformly. Previously lived in sdk_events.proto
/// (also used by voice_events.proto's VoiceAgentComponentStates after the
/// former hand-rolled `ComponentLoadState` was consolidated into this single
/// richer taxonomy).
class ComponentLifecycleState extends $pb.ProtobufEnum {
  static const ComponentLifecycleState COMPONENT_LIFECYCLE_STATE_UNSPECIFIED =
      ComponentLifecycleState._(
          0, _omitEnumNames ? '' : 'COMPONENT_LIFECYCLE_STATE_UNSPECIFIED');
  static const ComponentLifecycleState COMPONENT_LIFECYCLE_STATE_NOT_LOADED =
      ComponentLifecycleState._(
          1, _omitEnumNames ? '' : 'COMPONENT_LIFECYCLE_STATE_NOT_LOADED');
  static const ComponentLifecycleState COMPONENT_LIFECYCLE_STATE_LOADING =
      ComponentLifecycleState._(
          2, _omitEnumNames ? '' : 'COMPONENT_LIFECYCLE_STATE_LOADING');
  static const ComponentLifecycleState COMPONENT_LIFECYCLE_STATE_READY =
      ComponentLifecycleState._(
          3, _omitEnumNames ? '' : 'COMPONENT_LIFECYCLE_STATE_READY');
  static const ComponentLifecycleState COMPONENT_LIFECYCLE_STATE_UNLOADING =
      ComponentLifecycleState._(
          4, _omitEnumNames ? '' : 'COMPONENT_LIFECYCLE_STATE_UNLOADING');
  static const ComponentLifecycleState COMPONENT_LIFECYCLE_STATE_ERROR =
      ComponentLifecycleState._(
          5, _omitEnumNames ? '' : 'COMPONENT_LIFECYCLE_STATE_ERROR');
  static const ComponentLifecycleState COMPONENT_LIFECYCLE_STATE_SHUTDOWN =
      ComponentLifecycleState._(
          6, _omitEnumNames ? '' : 'COMPONENT_LIFECYCLE_STATE_SHUTDOWN');
  static const ComponentLifecycleState COMPONENT_LIFECYCLE_STATE_DOWNLOADING =
      ComponentLifecycleState._(
          7, _omitEnumNames ? '' : 'COMPONENT_LIFECYCLE_STATE_DOWNLOADING');
  static const ComponentLifecycleState COMPONENT_LIFECYCLE_STATE_DELETING =
      ComponentLifecycleState._(
          8, _omitEnumNames ? '' : 'COMPONENT_LIFECYCLE_STATE_DELETING');
  static const ComponentLifecycleState COMPONENT_LIFECYCLE_STATE_PAUSED =
      ComponentLifecycleState._(
          9, _omitEnumNames ? '' : 'COMPONENT_LIFECYCLE_STATE_PAUSED');
  static const ComponentLifecycleState COMPONENT_LIFECYCLE_STATE_UPDATING =
      ComponentLifecycleState._(
          10, _omitEnumNames ? '' : 'COMPONENT_LIFECYCLE_STATE_UPDATING');

  static const $core.List<ComponentLifecycleState> values =
      <ComponentLifecycleState>[
    COMPONENT_LIFECYCLE_STATE_UNSPECIFIED,
    COMPONENT_LIFECYCLE_STATE_NOT_LOADED,
    COMPONENT_LIFECYCLE_STATE_LOADING,
    COMPONENT_LIFECYCLE_STATE_READY,
    COMPONENT_LIFECYCLE_STATE_UNLOADING,
    COMPONENT_LIFECYCLE_STATE_ERROR,
    COMPONENT_LIFECYCLE_STATE_SHUTDOWN,
    COMPONENT_LIFECYCLE_STATE_DOWNLOADING,
    COMPONENT_LIFECYCLE_STATE_DELETING,
    COMPONENT_LIFECYCLE_STATE_PAUSED,
    COMPONENT_LIFECYCLE_STATE_UPDATING,
  ];

  static final $core.List<ComponentLifecycleState?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 10);
  static ComponentLifecycleState? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const ComponentLifecycleState._(super.value, super.name);
}

/// Canonical event category carried by every SDKEvent envelope. Lives here
/// (instead of sdk_events.proto) so voice_events.proto and voice_agent_service
/// .proto can reference it without importing sdk_events.proto (which itself
/// imports voice_events.proto — cycle resolution).
class EventCategory extends $pb.ProtobufEnum {
  static const EventCategory EVENT_CATEGORY_UNSPECIFIED =
      EventCategory._(0, _omitEnumNames ? '' : 'EVENT_CATEGORY_UNSPECIFIED');
  static const EventCategory EVENT_CATEGORY_SDK =
      EventCategory._(1, _omitEnumNames ? '' : 'EVENT_CATEGORY_SDK');
  static const EventCategory EVENT_CATEGORY_INITIALIZATION =
      EventCategory._(2, _omitEnumNames ? '' : 'EVENT_CATEGORY_INITIALIZATION');
  static const EventCategory EVENT_CATEGORY_SHUTDOWN =
      EventCategory._(3, _omitEnumNames ? '' : 'EVENT_CATEGORY_SHUTDOWN');
  static const EventCategory EVENT_CATEGORY_SESSION =
      EventCategory._(4, _omitEnumNames ? '' : 'EVENT_CATEGORY_SESSION');
  static const EventCategory EVENT_CATEGORY_AUTH =
      EventCategory._(5, _omitEnumNames ? '' : 'EVENT_CATEGORY_AUTH');
  static const EventCategory EVENT_CATEGORY_DEVICE =
      EventCategory._(6, _omitEnumNames ? '' : 'EVENT_CATEGORY_DEVICE');
  static const EventCategory EVENT_CATEGORY_REGISTRY =
      EventCategory._(7, _omitEnumNames ? '' : 'EVENT_CATEGORY_REGISTRY');
  static const EventCategory EVENT_CATEGORY_ASSIGNMENT =
      EventCategory._(8, _omitEnumNames ? '' : 'EVENT_CATEGORY_ASSIGNMENT');
  static const EventCategory EVENT_CATEGORY_IMPORT =
      EventCategory._(9, _omitEnumNames ? '' : 'EVENT_CATEGORY_IMPORT');
  static const EventCategory EVENT_CATEGORY_DISCOVERY =
      EventCategory._(10, _omitEnumNames ? '' : 'EVENT_CATEGORY_DISCOVERY');
  static const EventCategory EVENT_CATEGORY_DOWNLOAD =
      EventCategory._(11, _omitEnumNames ? '' : 'EVENT_CATEGORY_DOWNLOAD');
  static const EventCategory EVENT_CATEGORY_STORAGE =
      EventCategory._(12, _omitEnumNames ? '' : 'EVENT_CATEGORY_STORAGE');
  static const EventCategory EVENT_CATEGORY_HARDWARE =
      EventCategory._(13, _omitEnumNames ? '' : 'EVENT_CATEGORY_HARDWARE');
  static const EventCategory EVENT_CATEGORY_ROUTING =
      EventCategory._(14, _omitEnumNames ? '' : 'EVENT_CATEGORY_ROUTING');
  static const EventCategory EVENT_CATEGORY_FRAMEWORK =
      EventCategory._(15, _omitEnumNames ? '' : 'EVENT_CATEGORY_FRAMEWORK');
  static const EventCategory EVENT_CATEGORY_MODEL =
      EventCategory._(16, _omitEnumNames ? '' : 'EVENT_CATEGORY_MODEL');
  static const EventCategory EVENT_CATEGORY_COMPONENT =
      EventCategory._(17, _omitEnumNames ? '' : 'EVENT_CATEGORY_COMPONENT');
  static const EventCategory EVENT_CATEGORY_LLM =
      EventCategory._(18, _omitEnumNames ? '' : 'EVENT_CATEGORY_LLM');
  static const EventCategory EVENT_CATEGORY_STT =
      EventCategory._(19, _omitEnumNames ? '' : 'EVENT_CATEGORY_STT');
  static const EventCategory EVENT_CATEGORY_ASR =
      EventCategory._(20, _omitEnumNames ? '' : 'EVENT_CATEGORY_ASR');
  static const EventCategory EVENT_CATEGORY_TTS =
      EventCategory._(21, _omitEnumNames ? '' : 'EVENT_CATEGORY_TTS');
  static const EventCategory EVENT_CATEGORY_VAD =
      EventCategory._(22, _omitEnumNames ? '' : 'EVENT_CATEGORY_VAD');
  static const EventCategory EVENT_CATEGORY_STD =
      EventCategory._(23, _omitEnumNames ? '' : 'EVENT_CATEGORY_STD');
  static const EventCategory EVENT_CATEGORY_VOICE_AGENT =
      EventCategory._(24, _omitEnumNames ? '' : 'EVENT_CATEGORY_VOICE_AGENT');
  static const EventCategory EVENT_CATEGORY_VLM =
      EventCategory._(25, _omitEnumNames ? '' : 'EVENT_CATEGORY_VLM');
  static const EventCategory EVENT_CATEGORY_DIFFUSION =
      EventCategory._(26, _omitEnumNames ? '' : 'EVENT_CATEGORY_DIFFUSION');
  static const EventCategory EVENT_CATEGORY_EMBEDDINGS =
      EventCategory._(27, _omitEnumNames ? '' : 'EVENT_CATEGORY_EMBEDDINGS');
  static const EventCategory EVENT_CATEGORY_RAG =
      EventCategory._(28, _omitEnumNames ? '' : 'EVENT_CATEGORY_RAG');
  static const EventCategory EVENT_CATEGORY_LORA =
      EventCategory._(29, _omitEnumNames ? '' : 'EVENT_CATEGORY_LORA');
  static const EventCategory EVENT_CATEGORY_TELEMETRY =
      EventCategory._(30, _omitEnumNames ? '' : 'EVENT_CATEGORY_TELEMETRY');
  static const EventCategory EVENT_CATEGORY_PERFORMANCE =
      EventCategory._(31, _omitEnumNames ? '' : 'EVENT_CATEGORY_PERFORMANCE');
  static const EventCategory EVENT_CATEGORY_CANCELLATION =
      EventCategory._(32, _omitEnumNames ? '' : 'EVENT_CATEGORY_CANCELLATION');
  static const EventCategory EVENT_CATEGORY_FAILURE =
      EventCategory._(33, _omitEnumNames ? '' : 'EVENT_CATEGORY_FAILURE');
  static const EventCategory EVENT_CATEGORY_NETWORK =
      EventCategory._(34, _omitEnumNames ? '' : 'EVENT_CATEGORY_NETWORK');
  static const EventCategory EVENT_CATEGORY_ERROR =
      EventCategory._(35, _omitEnumNames ? '' : 'EVENT_CATEGORY_ERROR');

  /// Absorbed from former VoiceEventCategory (voice_events.proto).
  /// AUDIO and METRICS had no EventCategory counterpart; WAKEWORD was
  /// previously only on the voice-pipeline side.
  static const EventCategory EVENT_CATEGORY_AUDIO =
      EventCategory._(36, _omitEnumNames ? '' : 'EVENT_CATEGORY_AUDIO');
  static const EventCategory EVENT_CATEGORY_METRICS =
      EventCategory._(37, _omitEnumNames ? '' : 'EVENT_CATEGORY_METRICS');
  static const EventCategory EVENT_CATEGORY_WAKEWORD =
      EventCategory._(38, _omitEnumNames ? '' : 'EVENT_CATEGORY_WAKEWORD');

  static const $core.List<EventCategory> values = <EventCategory>[
    EVENT_CATEGORY_UNSPECIFIED,
    EVENT_CATEGORY_SDK,
    EVENT_CATEGORY_INITIALIZATION,
    EVENT_CATEGORY_SHUTDOWN,
    EVENT_CATEGORY_SESSION,
    EVENT_CATEGORY_AUTH,
    EVENT_CATEGORY_DEVICE,
    EVENT_CATEGORY_REGISTRY,
    EVENT_CATEGORY_ASSIGNMENT,
    EVENT_CATEGORY_IMPORT,
    EVENT_CATEGORY_DISCOVERY,
    EVENT_CATEGORY_DOWNLOAD,
    EVENT_CATEGORY_STORAGE,
    EVENT_CATEGORY_HARDWARE,
    EVENT_CATEGORY_ROUTING,
    EVENT_CATEGORY_FRAMEWORK,
    EVENT_CATEGORY_MODEL,
    EVENT_CATEGORY_COMPONENT,
    EVENT_CATEGORY_LLM,
    EVENT_CATEGORY_STT,
    EVENT_CATEGORY_ASR,
    EVENT_CATEGORY_TTS,
    EVENT_CATEGORY_VAD,
    EVENT_CATEGORY_STD,
    EVENT_CATEGORY_VOICE_AGENT,
    EVENT_CATEGORY_VLM,
    EVENT_CATEGORY_DIFFUSION,
    EVENT_CATEGORY_EMBEDDINGS,
    EVENT_CATEGORY_RAG,
    EVENT_CATEGORY_LORA,
    EVENT_CATEGORY_TELEMETRY,
    EVENT_CATEGORY_PERFORMANCE,
    EVENT_CATEGORY_CANCELLATION,
    EVENT_CATEGORY_FAILURE,
    EVENT_CATEGORY_NETWORK,
    EVENT_CATEGORY_ERROR,
    EVENT_CATEGORY_AUDIO,
    EVENT_CATEGORY_METRICS,
    EVENT_CATEGORY_WAKEWORD,
  ];

  static final $core.List<EventCategory?> _byValue =
      $pb.ProtobufEnum.$_initByValueList(values, 38);
  static EventCategory? valueOf($core.int value) =>
      value < 0 || value >= _byValue.length ? null : _byValue[value];

  const EventCategory._(super.value, super.name);
}

const $core.bool _omitEnumNames =
    $core.bool.fromEnvironment('protobuf.omit_enum_names');
