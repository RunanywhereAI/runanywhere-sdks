//
//  Generated code. Do not modify.
//  source: sdk_events.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:core' as $core;

import 'package:protobuf/protobuf.dart' as $pb;

/// ---------------------------------------------------------------------------
/// Component identifier — every consumer / framework that the SDK orchestrates.
/// Sources pre-IDL:
///   RN     enums.ts:168 (SDKComponent)             — 7 cases
///   Swift  ComponentTypes.swift:SDKComponent       — 7 cases
///   Kotlin ComponentTypes.kt:SDKComponent          — 7 cases
///   Dart   sdk_component.dart                      — 7 cases
/// Canonical superset adds: VLM, DIFFUSION, RAG, WAKEWORD (referenced by
/// RN's ComponentInitializationEvent.components: SDKComponent[] but not yet
/// in any SDK's enum).
/// ---------------------------------------------------------------------------
class SDKComponent extends $pb.ProtobufEnum {
  static const SDKComponent SDK_COMPONENT_UNSPECIFIED = SDKComponent._(0, _omitEnumNames ? '' : 'SDK_COMPONENT_UNSPECIFIED');
  static const SDKComponent SDK_COMPONENT_STT = SDKComponent._(1, _omitEnumNames ? '' : 'SDK_COMPONENT_STT');
  static const SDKComponent SDK_COMPONENT_TTS = SDKComponent._(2, _omitEnumNames ? '' : 'SDK_COMPONENT_TTS');
  static const SDKComponent SDK_COMPONENT_VAD = SDKComponent._(3, _omitEnumNames ? '' : 'SDK_COMPONENT_VAD');
  static const SDKComponent SDK_COMPONENT_LLM = SDKComponent._(4, _omitEnumNames ? '' : 'SDK_COMPONENT_LLM');
  static const SDKComponent SDK_COMPONENT_VLM = SDKComponent._(5, _omitEnumNames ? '' : 'SDK_COMPONENT_VLM');
  static const SDKComponent SDK_COMPONENT_DIFFUSION = SDKComponent._(6, _omitEnumNames ? '' : 'SDK_COMPONENT_DIFFUSION');
  static const SDKComponent SDK_COMPONENT_RAG = SDKComponent._(7, _omitEnumNames ? '' : 'SDK_COMPONENT_RAG');
  static const SDKComponent SDK_COMPONENT_EMBEDDINGS = SDKComponent._(8, _omitEnumNames ? '' : 'SDK_COMPONENT_EMBEDDINGS');
  static const SDKComponent SDK_COMPONENT_VOICE_AGENT = SDKComponent._(9, _omitEnumNames ? '' : 'SDK_COMPONENT_VOICE_AGENT');
  static const SDKComponent SDK_COMPONENT_WAKEWORD = SDKComponent._(10, _omitEnumNames ? '' : 'SDK_COMPONENT_WAKEWORD');
  static const SDKComponent SDK_COMPONENT_SPEAKER_DIARIZATION = SDKComponent._(11, _omitEnumNames ? '' : 'SDK_COMPONENT_SPEAKER_DIARIZATION');

  static const $core.List<SDKComponent> values = <SDKComponent> [
    SDK_COMPONENT_UNSPECIFIED,
    SDK_COMPONENT_STT,
    SDK_COMPONENT_TTS,
    SDK_COMPONENT_VAD,
    SDK_COMPONENT_LLM,
    SDK_COMPONENT_VLM,
    SDK_COMPONENT_DIFFUSION,
    SDK_COMPONENT_RAG,
    SDK_COMPONENT_EMBEDDINGS,
    SDK_COMPONENT_VOICE_AGENT,
    SDK_COMPONENT_WAKEWORD,
    SDK_COMPONENT_SPEAKER_DIARIZATION,
  ];

  static final $core.Map<$core.int, SDKComponent> _byValue = $pb.ProtobufEnum.initByValue(values);
  static SDKComponent? valueOf($core.int value) => _byValue[value];

  const SDKComponent._($core.int v, $core.String n) : super(v, n);
}

/// ---------------------------------------------------------------------------
/// Event severity. New unification — pre-IDL each SDK either implied severity
/// from event type ("failed" → ERROR) or had no notion. Canonicalizing now
/// enables analytics to filter without parsing event names.
/// ---------------------------------------------------------------------------
class EventSeverity extends $pb.ProtobufEnum {
  static const EventSeverity EVENT_SEVERITY_DEBUG = EventSeverity._(0, _omitEnumNames ? '' : 'EVENT_SEVERITY_DEBUG');
  static const EventSeverity EVENT_SEVERITY_INFO = EventSeverity._(1, _omitEnumNames ? '' : 'EVENT_SEVERITY_INFO');
  static const EventSeverity EVENT_SEVERITY_WARNING = EventSeverity._(2, _omitEnumNames ? '' : 'EVENT_SEVERITY_WARNING');
  static const EventSeverity EVENT_SEVERITY_ERROR = EventSeverity._(3, _omitEnumNames ? '' : 'EVENT_SEVERITY_ERROR');
  static const EventSeverity EVENT_SEVERITY_CRITICAL = EventSeverity._(4, _omitEnumNames ? '' : 'EVENT_SEVERITY_CRITICAL');

  static const $core.List<EventSeverity> values = <EventSeverity> [
    EVENT_SEVERITY_DEBUG,
    EVENT_SEVERITY_INFO,
    EVENT_SEVERITY_WARNING,
    EVENT_SEVERITY_ERROR,
    EVENT_SEVERITY_CRITICAL,
  ];

  static final $core.Map<$core.int, EventSeverity> _byValue = $pb.ProtobufEnum.initByValue(values);
  static EventSeverity? valueOf($core.int value) => _byValue[value];

  const EventSeverity._($core.int v, $core.String n) : super(v, n);
}

/// ---------------------------------------------------------------------------
/// Where an event should be routed. Mirrors Swift `EventDestination` /
/// Kotlin `EventDestination` / Dart `EventDestination`.
/// Sources pre-IDL:
///   Swift  SDKEvent.swift:15-22       — publicOnly / analyticsOnly / all
///   Kotlin SDKEvent.kt:24-33          — PUBLIC_ONLY / ANALYTICS_ONLY / ALL
///   Dart   sdk_event.dart:20-29       — all / publicOnly / analyticsOnly
/// ---------------------------------------------------------------------------
class EventDestination extends $pb.ProtobufEnum {
  static const EventDestination EVENT_DESTINATION_UNSPECIFIED = EventDestination._(0, _omitEnumNames ? '' : 'EVENT_DESTINATION_UNSPECIFIED');
  static const EventDestination EVENT_DESTINATION_ALL = EventDestination._(1, _omitEnumNames ? '' : 'EVENT_DESTINATION_ALL');
  static const EventDestination EVENT_DESTINATION_PUBLIC_ONLY = EventDestination._(2, _omitEnumNames ? '' : 'EVENT_DESTINATION_PUBLIC_ONLY');
  static const EventDestination EVENT_DESTINATION_ANALYTICS_ONLY = EventDestination._(3, _omitEnumNames ? '' : 'EVENT_DESTINATION_ANALYTICS_ONLY');

  static const $core.List<EventDestination> values = <EventDestination> [
    EVENT_DESTINATION_UNSPECIFIED,
    EVENT_DESTINATION_ALL,
    EVENT_DESTINATION_PUBLIC_ONLY,
    EVENT_DESTINATION_ANALYTICS_ONLY,
  ];

  static final $core.Map<$core.int, EventDestination> _byValue = $pb.ProtobufEnum.initByValue(values);
  static EventDestination? valueOf($core.int value) => _byValue[value];

  const EventDestination._($core.int v, $core.String n) : super(v, n);
}

/// Canonical event category carried by every SDKEvent envelope. The oneof arm
/// identifies the concrete payload shape; this field preserves the stable bus /
/// analytics route used by Swift, Kotlin, Dart/Flutter, React Native, Web, and
/// C++ commons.
class EventCategory extends $pb.ProtobufEnum {
  static const EventCategory EVENT_CATEGORY_UNSPECIFIED = EventCategory._(0, _omitEnumNames ? '' : 'EVENT_CATEGORY_UNSPECIFIED');
  static const EventCategory EVENT_CATEGORY_SDK = EventCategory._(1, _omitEnumNames ? '' : 'EVENT_CATEGORY_SDK');
  static const EventCategory EVENT_CATEGORY_INITIALIZATION = EventCategory._(2, _omitEnumNames ? '' : 'EVENT_CATEGORY_INITIALIZATION');
  static const EventCategory EVENT_CATEGORY_SHUTDOWN = EventCategory._(3, _omitEnumNames ? '' : 'EVENT_CATEGORY_SHUTDOWN');
  static const EventCategory EVENT_CATEGORY_SESSION = EventCategory._(4, _omitEnumNames ? '' : 'EVENT_CATEGORY_SESSION');
  static const EventCategory EVENT_CATEGORY_AUTH = EventCategory._(5, _omitEnumNames ? '' : 'EVENT_CATEGORY_AUTH');
  static const EventCategory EVENT_CATEGORY_DEVICE = EventCategory._(6, _omitEnumNames ? '' : 'EVENT_CATEGORY_DEVICE');
  static const EventCategory EVENT_CATEGORY_REGISTRY = EventCategory._(7, _omitEnumNames ? '' : 'EVENT_CATEGORY_REGISTRY');
  static const EventCategory EVENT_CATEGORY_ASSIGNMENT = EventCategory._(8, _omitEnumNames ? '' : 'EVENT_CATEGORY_ASSIGNMENT');
  static const EventCategory EVENT_CATEGORY_IMPORT = EventCategory._(9, _omitEnumNames ? '' : 'EVENT_CATEGORY_IMPORT');
  static const EventCategory EVENT_CATEGORY_DISCOVERY = EventCategory._(10, _omitEnumNames ? '' : 'EVENT_CATEGORY_DISCOVERY');
  static const EventCategory EVENT_CATEGORY_DOWNLOAD = EventCategory._(11, _omitEnumNames ? '' : 'EVENT_CATEGORY_DOWNLOAD');
  static const EventCategory EVENT_CATEGORY_STORAGE = EventCategory._(12, _omitEnumNames ? '' : 'EVENT_CATEGORY_STORAGE');
  static const EventCategory EVENT_CATEGORY_HARDWARE = EventCategory._(13, _omitEnumNames ? '' : 'EVENT_CATEGORY_HARDWARE');
  static const EventCategory EVENT_CATEGORY_ROUTING = EventCategory._(14, _omitEnumNames ? '' : 'EVENT_CATEGORY_ROUTING');
  static const EventCategory EVENT_CATEGORY_FRAMEWORK = EventCategory._(15, _omitEnumNames ? '' : 'EVENT_CATEGORY_FRAMEWORK');
  static const EventCategory EVENT_CATEGORY_MODEL = EventCategory._(16, _omitEnumNames ? '' : 'EVENT_CATEGORY_MODEL');
  static const EventCategory EVENT_CATEGORY_COMPONENT = EventCategory._(17, _omitEnumNames ? '' : 'EVENT_CATEGORY_COMPONENT');
  static const EventCategory EVENT_CATEGORY_LLM = EventCategory._(18, _omitEnumNames ? '' : 'EVENT_CATEGORY_LLM');
  static const EventCategory EVENT_CATEGORY_STT = EventCategory._(19, _omitEnumNames ? '' : 'EVENT_CATEGORY_STT');
  static const EventCategory EVENT_CATEGORY_ASR = EventCategory._(20, _omitEnumNames ? '' : 'EVENT_CATEGORY_ASR');
  static const EventCategory EVENT_CATEGORY_TTS = EventCategory._(21, _omitEnumNames ? '' : 'EVENT_CATEGORY_TTS');
  static const EventCategory EVENT_CATEGORY_VAD = EventCategory._(22, _omitEnumNames ? '' : 'EVENT_CATEGORY_VAD');
  static const EventCategory EVENT_CATEGORY_STD = EventCategory._(23, _omitEnumNames ? '' : 'EVENT_CATEGORY_STD');
  static const EventCategory EVENT_CATEGORY_VOICE_AGENT = EventCategory._(24, _omitEnumNames ? '' : 'EVENT_CATEGORY_VOICE_AGENT');
  static const EventCategory EVENT_CATEGORY_VLM = EventCategory._(25, _omitEnumNames ? '' : 'EVENT_CATEGORY_VLM');
  static const EventCategory EVENT_CATEGORY_DIFFUSION = EventCategory._(26, _omitEnumNames ? '' : 'EVENT_CATEGORY_DIFFUSION');
  static const EventCategory EVENT_CATEGORY_EMBEDDINGS = EventCategory._(27, _omitEnumNames ? '' : 'EVENT_CATEGORY_EMBEDDINGS');
  static const EventCategory EVENT_CATEGORY_RAG = EventCategory._(28, _omitEnumNames ? '' : 'EVENT_CATEGORY_RAG');
  static const EventCategory EVENT_CATEGORY_LORA = EventCategory._(29, _omitEnumNames ? '' : 'EVENT_CATEGORY_LORA');
  static const EventCategory EVENT_CATEGORY_TELEMETRY = EventCategory._(30, _omitEnumNames ? '' : 'EVENT_CATEGORY_TELEMETRY');
  static const EventCategory EVENT_CATEGORY_PERFORMANCE = EventCategory._(31, _omitEnumNames ? '' : 'EVENT_CATEGORY_PERFORMANCE');
  static const EventCategory EVENT_CATEGORY_CANCELLATION = EventCategory._(32, _omitEnumNames ? '' : 'EVENT_CATEGORY_CANCELLATION');
  static const EventCategory EVENT_CATEGORY_FAILURE = EventCategory._(33, _omitEnumNames ? '' : 'EVENT_CATEGORY_FAILURE');
  static const EventCategory EVENT_CATEGORY_NETWORK = EventCategory._(34, _omitEnumNames ? '' : 'EVENT_CATEGORY_NETWORK');
  static const EventCategory EVENT_CATEGORY_ERROR = EventCategory._(35, _omitEnumNames ? '' : 'EVENT_CATEGORY_ERROR');

  static const $core.List<EventCategory> values = <EventCategory> [
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
  ];

  static final $core.Map<$core.int, EventCategory> _byValue = $pb.ProtobufEnum.initByValue(values);
  static EventCategory? valueOf($core.int value) => _byValue[value];

  const EventCategory._($core.int v, $core.String n) : super(v, n);
}

/// Component runtime lifecycle state for model-backed SDK components. This is
/// distinct from voice_events.proto's ComponentLoadState, which is scoped to
/// the voice-agent sub-pipeline. Platform adapters own native component handles;
/// this enum carries the C++ lifecycle state every SDK can expose uniformly.
class ComponentLifecycleState extends $pb.ProtobufEnum {
  static const ComponentLifecycleState COMPONENT_LIFECYCLE_STATE_UNSPECIFIED = ComponentLifecycleState._(0, _omitEnumNames ? '' : 'COMPONENT_LIFECYCLE_STATE_UNSPECIFIED');
  static const ComponentLifecycleState COMPONENT_LIFECYCLE_STATE_NOT_LOADED = ComponentLifecycleState._(1, _omitEnumNames ? '' : 'COMPONENT_LIFECYCLE_STATE_NOT_LOADED');
  static const ComponentLifecycleState COMPONENT_LIFECYCLE_STATE_LOADING = ComponentLifecycleState._(2, _omitEnumNames ? '' : 'COMPONENT_LIFECYCLE_STATE_LOADING');
  static const ComponentLifecycleState COMPONENT_LIFECYCLE_STATE_READY = ComponentLifecycleState._(3, _omitEnumNames ? '' : 'COMPONENT_LIFECYCLE_STATE_READY');
  static const ComponentLifecycleState COMPONENT_LIFECYCLE_STATE_UNLOADING = ComponentLifecycleState._(4, _omitEnumNames ? '' : 'COMPONENT_LIFECYCLE_STATE_UNLOADING');
  static const ComponentLifecycleState COMPONENT_LIFECYCLE_STATE_ERROR = ComponentLifecycleState._(5, _omitEnumNames ? '' : 'COMPONENT_LIFECYCLE_STATE_ERROR');
  static const ComponentLifecycleState COMPONENT_LIFECYCLE_STATE_SHUTDOWN = ComponentLifecycleState._(6, _omitEnumNames ? '' : 'COMPONENT_LIFECYCLE_STATE_SHUTDOWN');

  static const $core.List<ComponentLifecycleState> values = <ComponentLifecycleState> [
    COMPONENT_LIFECYCLE_STATE_UNSPECIFIED,
    COMPONENT_LIFECYCLE_STATE_NOT_LOADED,
    COMPONENT_LIFECYCLE_STATE_LOADING,
    COMPONENT_LIFECYCLE_STATE_READY,
    COMPONENT_LIFECYCLE_STATE_UNLOADING,
    COMPONENT_LIFECYCLE_STATE_ERROR,
    COMPONENT_LIFECYCLE_STATE_SHUTDOWN,
  ];

  static final $core.Map<$core.int, ComponentLifecycleState> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ComponentLifecycleState? valueOf($core.int value) => _byValue[value];

  const ComponentLifecycleState._($core.int v, $core.String n) : super(v, n);
}

class InitializationStage extends $pb.ProtobufEnum {
  static const InitializationStage INITIALIZATION_STAGE_UNSPECIFIED = InitializationStage._(0, _omitEnumNames ? '' : 'INITIALIZATION_STAGE_UNSPECIFIED');
  static const InitializationStage INITIALIZATION_STAGE_STARTED = InitializationStage._(1, _omitEnumNames ? '' : 'INITIALIZATION_STAGE_STARTED');
  static const InitializationStage INITIALIZATION_STAGE_CONFIGURATION_LOADED = InitializationStage._(2, _omitEnumNames ? '' : 'INITIALIZATION_STAGE_CONFIGURATION_LOADED');
  static const InitializationStage INITIALIZATION_STAGE_SERVICES_BOOTSTRAPPED = InitializationStage._(3, _omitEnumNames ? '' : 'INITIALIZATION_STAGE_SERVICES_BOOTSTRAPPED');
  static const InitializationStage INITIALIZATION_STAGE_COMPLETED = InitializationStage._(4, _omitEnumNames ? '' : 'INITIALIZATION_STAGE_COMPLETED');
  static const InitializationStage INITIALIZATION_STAGE_FAILED = InitializationStage._(5, _omitEnumNames ? '' : 'INITIALIZATION_STAGE_FAILED');
  static const InitializationStage INITIALIZATION_STAGE_SHUTDOWN = InitializationStage._(6, _omitEnumNames ? '' : 'INITIALIZATION_STAGE_SHUTDOWN');

  static const $core.List<InitializationStage> values = <InitializationStage> [
    INITIALIZATION_STAGE_UNSPECIFIED,
    INITIALIZATION_STAGE_STARTED,
    INITIALIZATION_STAGE_CONFIGURATION_LOADED,
    INITIALIZATION_STAGE_SERVICES_BOOTSTRAPPED,
    INITIALIZATION_STAGE_COMPLETED,
    INITIALIZATION_STAGE_FAILED,
    INITIALIZATION_STAGE_SHUTDOWN,
  ];

  static final $core.Map<$core.int, InitializationStage> _byValue = $pb.ProtobufEnum.initByValue(values);
  static InitializationStage? valueOf($core.int value) => _byValue[value];

  const InitializationStage._($core.int v, $core.String n) : super(v, n);
}

class ConfigurationEventKind extends $pb.ProtobufEnum {
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_UNSPECIFIED = ConfigurationEventKind._(0, _omitEnumNames ? '' : 'CONFIGURATION_EVENT_KIND_UNSPECIFIED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_FETCH_STARTED = ConfigurationEventKind._(1, _omitEnumNames ? '' : 'CONFIGURATION_EVENT_KIND_FETCH_STARTED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_FETCH_COMPLETED = ConfigurationEventKind._(2, _omitEnumNames ? '' : 'CONFIGURATION_EVENT_KIND_FETCH_COMPLETED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_FETCH_FAILED = ConfigurationEventKind._(3, _omitEnumNames ? '' : 'CONFIGURATION_EVENT_KIND_FETCH_FAILED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_LOADED = ConfigurationEventKind._(4, _omitEnumNames ? '' : 'CONFIGURATION_EVENT_KIND_LOADED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_UPDATED = ConfigurationEventKind._(5, _omitEnumNames ? '' : 'CONFIGURATION_EVENT_KIND_UPDATED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_SYNC_STARTED = ConfigurationEventKind._(6, _omitEnumNames ? '' : 'CONFIGURATION_EVENT_KIND_SYNC_STARTED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_SYNC_COMPLETED = ConfigurationEventKind._(7, _omitEnumNames ? '' : 'CONFIGURATION_EVENT_KIND_SYNC_COMPLETED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_SYNC_FAILED = ConfigurationEventKind._(8, _omitEnumNames ? '' : 'CONFIGURATION_EVENT_KIND_SYNC_FAILED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_SYNC_REQUESTED = ConfigurationEventKind._(9, _omitEnumNames ? '' : 'CONFIGURATION_EVENT_KIND_SYNC_REQUESTED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_SETTINGS_REQUESTED = ConfigurationEventKind._(10, _omitEnumNames ? '' : 'CONFIGURATION_EVENT_KIND_SETTINGS_REQUESTED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_SETTINGS_RETRIEVED = ConfigurationEventKind._(11, _omitEnumNames ? '' : 'CONFIGURATION_EVENT_KIND_SETTINGS_RETRIEVED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_ROUTING_POLICY_REQUESTED = ConfigurationEventKind._(12, _omitEnumNames ? '' : 'CONFIGURATION_EVENT_KIND_ROUTING_POLICY_REQUESTED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_ROUTING_POLICY_RETRIEVED = ConfigurationEventKind._(13, _omitEnumNames ? '' : 'CONFIGURATION_EVENT_KIND_ROUTING_POLICY_RETRIEVED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_PRIVACY_MODE_REQUESTED = ConfigurationEventKind._(14, _omitEnumNames ? '' : 'CONFIGURATION_EVENT_KIND_PRIVACY_MODE_REQUESTED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_PRIVACY_MODE_RETRIEVED = ConfigurationEventKind._(15, _omitEnumNames ? '' : 'CONFIGURATION_EVENT_KIND_PRIVACY_MODE_RETRIEVED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_ANALYTICS_STATUS_REQUESTED = ConfigurationEventKind._(16, _omitEnumNames ? '' : 'CONFIGURATION_EVENT_KIND_ANALYTICS_STATUS_REQUESTED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_ANALYTICS_STATUS_RETRIEVED = ConfigurationEventKind._(17, _omitEnumNames ? '' : 'CONFIGURATION_EVENT_KIND_ANALYTICS_STATUS_RETRIEVED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_CHANGED = ConfigurationEventKind._(18, _omitEnumNames ? '' : 'CONFIGURATION_EVENT_KIND_CHANGED');

  static const $core.List<ConfigurationEventKind> values = <ConfigurationEventKind> [
    CONFIGURATION_EVENT_KIND_UNSPECIFIED,
    CONFIGURATION_EVENT_KIND_FETCH_STARTED,
    CONFIGURATION_EVENT_KIND_FETCH_COMPLETED,
    CONFIGURATION_EVENT_KIND_FETCH_FAILED,
    CONFIGURATION_EVENT_KIND_LOADED,
    CONFIGURATION_EVENT_KIND_UPDATED,
    CONFIGURATION_EVENT_KIND_SYNC_STARTED,
    CONFIGURATION_EVENT_KIND_SYNC_COMPLETED,
    CONFIGURATION_EVENT_KIND_SYNC_FAILED,
    CONFIGURATION_EVENT_KIND_SYNC_REQUESTED,
    CONFIGURATION_EVENT_KIND_SETTINGS_REQUESTED,
    CONFIGURATION_EVENT_KIND_SETTINGS_RETRIEVED,
    CONFIGURATION_EVENT_KIND_ROUTING_POLICY_REQUESTED,
    CONFIGURATION_EVENT_KIND_ROUTING_POLICY_RETRIEVED,
    CONFIGURATION_EVENT_KIND_PRIVACY_MODE_REQUESTED,
    CONFIGURATION_EVENT_KIND_PRIVACY_MODE_RETRIEVED,
    CONFIGURATION_EVENT_KIND_ANALYTICS_STATUS_REQUESTED,
    CONFIGURATION_EVENT_KIND_ANALYTICS_STATUS_RETRIEVED,
    CONFIGURATION_EVENT_KIND_CHANGED,
  ];

  static final $core.Map<$core.int, ConfigurationEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ConfigurationEventKind? valueOf($core.int value) => _byValue[value];

  const ConfigurationEventKind._($core.int v, $core.String n) : super(v, n);
}

class GenerationEventKind extends $pb.ProtobufEnum {
  static const GenerationEventKind GENERATION_EVENT_KIND_UNSPECIFIED = GenerationEventKind._(0, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_UNSPECIFIED');
  static const GenerationEventKind GENERATION_EVENT_KIND_SESSION_STARTED = GenerationEventKind._(1, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_SESSION_STARTED');
  static const GenerationEventKind GENERATION_EVENT_KIND_SESSION_ENDED = GenerationEventKind._(2, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_SESSION_ENDED');
  static const GenerationEventKind GENERATION_EVENT_KIND_STARTED = GenerationEventKind._(3, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_STARTED');
  static const GenerationEventKind GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED = GenerationEventKind._(4, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED');
  static const GenerationEventKind GENERATION_EVENT_KIND_TOKEN_GENERATED = GenerationEventKind._(5, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_TOKEN_GENERATED');
  static const GenerationEventKind GENERATION_EVENT_KIND_STREAMING_UPDATE = GenerationEventKind._(6, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_STREAMING_UPDATE');
  static const GenerationEventKind GENERATION_EVENT_KIND_COMPLETED = GenerationEventKind._(7, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_COMPLETED');
  static const GenerationEventKind GENERATION_EVENT_KIND_FAILED = GenerationEventKind._(8, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_FAILED');
  static const GenerationEventKind GENERATION_EVENT_KIND_MODEL_LOADED = GenerationEventKind._(9, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_MODEL_LOADED');
  static const GenerationEventKind GENERATION_EVENT_KIND_MODEL_UNLOADED = GenerationEventKind._(10, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_MODEL_UNLOADED');
  static const GenerationEventKind GENERATION_EVENT_KIND_COST_CALCULATED = GenerationEventKind._(11, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_COST_CALCULATED');
  static const GenerationEventKind GENERATION_EVENT_KIND_ROUTING_DECISION = GenerationEventKind._(12, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_ROUTING_DECISION');
  static const GenerationEventKind GENERATION_EVENT_KIND_STREAM_COMPLETED = GenerationEventKind._(13, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_STREAM_COMPLETED');
  static const GenerationEventKind GENERATION_EVENT_KIND_CANCEL_REQUESTED = GenerationEventKind._(14, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_CANCEL_REQUESTED');
  static const GenerationEventKind GENERATION_EVENT_KIND_CANCELLED = GenerationEventKind._(15, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_CANCELLED');
  static const GenerationEventKind GENERATION_EVENT_KIND_TOOL_CALL_STARTED = GenerationEventKind._(16, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_TOOL_CALL_STARTED');
  static const GenerationEventKind GENERATION_EVENT_KIND_TOOL_CALL_COMPLETED = GenerationEventKind._(17, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_TOOL_CALL_COMPLETED');
  static const GenerationEventKind GENERATION_EVENT_KIND_TOOL_CALL_FAILED = GenerationEventKind._(18, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_TOOL_CALL_FAILED');
  static const GenerationEventKind GENERATION_EVENT_KIND_STRUCTURED_OUTPUT_STARTED = GenerationEventKind._(19, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_STRUCTURED_OUTPUT_STARTED');
  static const GenerationEventKind GENERATION_EVENT_KIND_STRUCTURED_OUTPUT_COMPLETED = GenerationEventKind._(20, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_STRUCTURED_OUTPUT_COMPLETED');
  static const GenerationEventKind GENERATION_EVENT_KIND_STRUCTURED_OUTPUT_FAILED = GenerationEventKind._(21, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_STRUCTURED_OUTPUT_FAILED');
  static const GenerationEventKind GENERATION_EVENT_KIND_THINKING_STARTED = GenerationEventKind._(22, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_THINKING_STARTED');
  static const GenerationEventKind GENERATION_EVENT_KIND_THINKING_DELTA = GenerationEventKind._(23, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_THINKING_DELTA');
  static const GenerationEventKind GENERATION_EVENT_KIND_THINKING_COMPLETED = GenerationEventKind._(24, _omitEnumNames ? '' : 'GENERATION_EVENT_KIND_THINKING_COMPLETED');

  static const $core.List<GenerationEventKind> values = <GenerationEventKind> [
    GENERATION_EVENT_KIND_UNSPECIFIED,
    GENERATION_EVENT_KIND_SESSION_STARTED,
    GENERATION_EVENT_KIND_SESSION_ENDED,
    GENERATION_EVENT_KIND_STARTED,
    GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED,
    GENERATION_EVENT_KIND_TOKEN_GENERATED,
    GENERATION_EVENT_KIND_STREAMING_UPDATE,
    GENERATION_EVENT_KIND_COMPLETED,
    GENERATION_EVENT_KIND_FAILED,
    GENERATION_EVENT_KIND_MODEL_LOADED,
    GENERATION_EVENT_KIND_MODEL_UNLOADED,
    GENERATION_EVENT_KIND_COST_CALCULATED,
    GENERATION_EVENT_KIND_ROUTING_DECISION,
    GENERATION_EVENT_KIND_STREAM_COMPLETED,
    GENERATION_EVENT_KIND_CANCEL_REQUESTED,
    GENERATION_EVENT_KIND_CANCELLED,
    GENERATION_EVENT_KIND_TOOL_CALL_STARTED,
    GENERATION_EVENT_KIND_TOOL_CALL_COMPLETED,
    GENERATION_EVENT_KIND_TOOL_CALL_FAILED,
    GENERATION_EVENT_KIND_STRUCTURED_OUTPUT_STARTED,
    GENERATION_EVENT_KIND_STRUCTURED_OUTPUT_COMPLETED,
    GENERATION_EVENT_KIND_STRUCTURED_OUTPUT_FAILED,
    GENERATION_EVENT_KIND_THINKING_STARTED,
    GENERATION_EVENT_KIND_THINKING_DELTA,
    GENERATION_EVENT_KIND_THINKING_COMPLETED,
  ];

  static final $core.Map<$core.int, GenerationEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static GenerationEventKind? valueOf($core.int value) => _byValue[value];

  const GenerationEventKind._($core.int v, $core.String n) : super(v, n);
}

class ModelEventKind extends $pb.ProtobufEnum {
  static const ModelEventKind MODEL_EVENT_KIND_UNSPECIFIED = ModelEventKind._(0, _omitEnumNames ? '' : 'MODEL_EVENT_KIND_UNSPECIFIED');
  static const ModelEventKind MODEL_EVENT_KIND_LOAD_STARTED = ModelEventKind._(1, _omitEnumNames ? '' : 'MODEL_EVENT_KIND_LOAD_STARTED');
  static const ModelEventKind MODEL_EVENT_KIND_LOAD_PROGRESS = ModelEventKind._(2, _omitEnumNames ? '' : 'MODEL_EVENT_KIND_LOAD_PROGRESS');
  static const ModelEventKind MODEL_EVENT_KIND_LOAD_COMPLETED = ModelEventKind._(3, _omitEnumNames ? '' : 'MODEL_EVENT_KIND_LOAD_COMPLETED');
  static const ModelEventKind MODEL_EVENT_KIND_LOAD_FAILED = ModelEventKind._(4, _omitEnumNames ? '' : 'MODEL_EVENT_KIND_LOAD_FAILED');
  static const ModelEventKind MODEL_EVENT_KIND_UNLOAD_STARTED = ModelEventKind._(5, _omitEnumNames ? '' : 'MODEL_EVENT_KIND_UNLOAD_STARTED');
  static const ModelEventKind MODEL_EVENT_KIND_UNLOAD_COMPLETED = ModelEventKind._(6, _omitEnumNames ? '' : 'MODEL_EVENT_KIND_UNLOAD_COMPLETED');
  static const ModelEventKind MODEL_EVENT_KIND_UNLOAD_FAILED = ModelEventKind._(7, _omitEnumNames ? '' : 'MODEL_EVENT_KIND_UNLOAD_FAILED');
  static const ModelEventKind MODEL_EVENT_KIND_DOWNLOAD_STARTED = ModelEventKind._(8, _omitEnumNames ? '' : 'MODEL_EVENT_KIND_DOWNLOAD_STARTED');
  static const ModelEventKind MODEL_EVENT_KIND_DOWNLOAD_PROGRESS = ModelEventKind._(9, _omitEnumNames ? '' : 'MODEL_EVENT_KIND_DOWNLOAD_PROGRESS');
  static const ModelEventKind MODEL_EVENT_KIND_DOWNLOAD_COMPLETED = ModelEventKind._(10, _omitEnumNames ? '' : 'MODEL_EVENT_KIND_DOWNLOAD_COMPLETED');
  static const ModelEventKind MODEL_EVENT_KIND_DOWNLOAD_FAILED = ModelEventKind._(11, _omitEnumNames ? '' : 'MODEL_EVENT_KIND_DOWNLOAD_FAILED');
  static const ModelEventKind MODEL_EVENT_KIND_DOWNLOAD_CANCELLED = ModelEventKind._(12, _omitEnumNames ? '' : 'MODEL_EVENT_KIND_DOWNLOAD_CANCELLED');
  static const ModelEventKind MODEL_EVENT_KIND_LIST_REQUESTED = ModelEventKind._(13, _omitEnumNames ? '' : 'MODEL_EVENT_KIND_LIST_REQUESTED');
  static const ModelEventKind MODEL_EVENT_KIND_LIST_COMPLETED = ModelEventKind._(14, _omitEnumNames ? '' : 'MODEL_EVENT_KIND_LIST_COMPLETED');
  static const ModelEventKind MODEL_EVENT_KIND_LIST_FAILED = ModelEventKind._(15, _omitEnumNames ? '' : 'MODEL_EVENT_KIND_LIST_FAILED');
  static const ModelEventKind MODEL_EVENT_KIND_CATALOG_LOADED = ModelEventKind._(16, _omitEnumNames ? '' : 'MODEL_EVENT_KIND_CATALOG_LOADED');
  static const ModelEventKind MODEL_EVENT_KIND_DELETE_STARTED = ModelEventKind._(17, _omitEnumNames ? '' : 'MODEL_EVENT_KIND_DELETE_STARTED');
  static const ModelEventKind MODEL_EVENT_KIND_DELETE_COMPLETED = ModelEventKind._(18, _omitEnumNames ? '' : 'MODEL_EVENT_KIND_DELETE_COMPLETED');
  static const ModelEventKind MODEL_EVENT_KIND_DELETE_FAILED = ModelEventKind._(19, _omitEnumNames ? '' : 'MODEL_EVENT_KIND_DELETE_FAILED');
  static const ModelEventKind MODEL_EVENT_KIND_CUSTOM_MODEL_ADDED = ModelEventKind._(20, _omitEnumNames ? '' : 'MODEL_EVENT_KIND_CUSTOM_MODEL_ADDED');
  static const ModelEventKind MODEL_EVENT_KIND_BUILT_IN_REGISTERED = ModelEventKind._(21, _omitEnumNames ? '' : 'MODEL_EVENT_KIND_BUILT_IN_REGISTERED');

  static const $core.List<ModelEventKind> values = <ModelEventKind> [
    MODEL_EVENT_KIND_UNSPECIFIED,
    MODEL_EVENT_KIND_LOAD_STARTED,
    MODEL_EVENT_KIND_LOAD_PROGRESS,
    MODEL_EVENT_KIND_LOAD_COMPLETED,
    MODEL_EVENT_KIND_LOAD_FAILED,
    MODEL_EVENT_KIND_UNLOAD_STARTED,
    MODEL_EVENT_KIND_UNLOAD_COMPLETED,
    MODEL_EVENT_KIND_UNLOAD_FAILED,
    MODEL_EVENT_KIND_DOWNLOAD_STARTED,
    MODEL_EVENT_KIND_DOWNLOAD_PROGRESS,
    MODEL_EVENT_KIND_DOWNLOAD_COMPLETED,
    MODEL_EVENT_KIND_DOWNLOAD_FAILED,
    MODEL_EVENT_KIND_DOWNLOAD_CANCELLED,
    MODEL_EVENT_KIND_LIST_REQUESTED,
    MODEL_EVENT_KIND_LIST_COMPLETED,
    MODEL_EVENT_KIND_LIST_FAILED,
    MODEL_EVENT_KIND_CATALOG_LOADED,
    MODEL_EVENT_KIND_DELETE_STARTED,
    MODEL_EVENT_KIND_DELETE_COMPLETED,
    MODEL_EVENT_KIND_DELETE_FAILED,
    MODEL_EVENT_KIND_CUSTOM_MODEL_ADDED,
    MODEL_EVENT_KIND_BUILT_IN_REGISTERED,
  ];

  static final $core.Map<$core.int, ModelEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ModelEventKind? valueOf($core.int value) => _byValue[value];

  const ModelEventKind._($core.int v, $core.String n) : super(v, n);
}

class VoiceEventKind extends $pb.ProtobufEnum {
  static const VoiceEventKind VOICE_EVENT_KIND_UNSPECIFIED = VoiceEventKind._(0, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_UNSPECIFIED');
  static const VoiceEventKind VOICE_EVENT_KIND_LISTENING_STARTED = VoiceEventKind._(1, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_LISTENING_STARTED');
  static const VoiceEventKind VOICE_EVENT_KIND_LISTENING_ENDED = VoiceEventKind._(2, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_LISTENING_ENDED');
  static const VoiceEventKind VOICE_EVENT_KIND_SPEECH_DETECTED = VoiceEventKind._(3, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_SPEECH_DETECTED');
  static const VoiceEventKind VOICE_EVENT_KIND_TRANSCRIPTION_STARTED = VoiceEventKind._(4, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_TRANSCRIPTION_STARTED');
  static const VoiceEventKind VOICE_EVENT_KIND_TRANSCRIPTION_PARTIAL = VoiceEventKind._(5, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_TRANSCRIPTION_PARTIAL');
  static const VoiceEventKind VOICE_EVENT_KIND_TRANSCRIPTION_FINAL = VoiceEventKind._(6, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_TRANSCRIPTION_FINAL');
  static const VoiceEventKind VOICE_EVENT_KIND_RESPONSE_GENERATED = VoiceEventKind._(7, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_RESPONSE_GENERATED');
  static const VoiceEventKind VOICE_EVENT_KIND_SYNTHESIS_STARTED = VoiceEventKind._(8, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_SYNTHESIS_STARTED');
  static const VoiceEventKind VOICE_EVENT_KIND_AUDIO_GENERATED = VoiceEventKind._(9, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_AUDIO_GENERATED');
  static const VoiceEventKind VOICE_EVENT_KIND_SYNTHESIS_COMPLETED = VoiceEventKind._(10, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_SYNTHESIS_COMPLETED');
  static const VoiceEventKind VOICE_EVENT_KIND_SYNTHESIS_FAILED = VoiceEventKind._(11, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_SYNTHESIS_FAILED');
  static const VoiceEventKind VOICE_EVENT_KIND_PIPELINE_STARTED = VoiceEventKind._(12, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_PIPELINE_STARTED');
  static const VoiceEventKind VOICE_EVENT_KIND_PIPELINE_COMPLETED = VoiceEventKind._(13, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_PIPELINE_COMPLETED');
  static const VoiceEventKind VOICE_EVENT_KIND_PIPELINE_ERROR = VoiceEventKind._(14, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_PIPELINE_ERROR');
  static const VoiceEventKind VOICE_EVENT_KIND_VAD_STARTED = VoiceEventKind._(15, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_VAD_STARTED');
  static const VoiceEventKind VOICE_EVENT_KIND_VAD_DETECTED = VoiceEventKind._(16, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_VAD_DETECTED');
  static const VoiceEventKind VOICE_EVENT_KIND_VAD_ENDED = VoiceEventKind._(17, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_VAD_ENDED');
  static const VoiceEventKind VOICE_EVENT_KIND_VAD_INITIALIZED = VoiceEventKind._(18, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_VAD_INITIALIZED');
  static const VoiceEventKind VOICE_EVENT_KIND_VAD_STOPPED = VoiceEventKind._(19, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_VAD_STOPPED');
  static const VoiceEventKind VOICE_EVENT_KIND_VAD_CLEANED_UP = VoiceEventKind._(20, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_VAD_CLEANED_UP');
  static const VoiceEventKind VOICE_EVENT_KIND_SPEECH_STARTED = VoiceEventKind._(21, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_SPEECH_STARTED');
  static const VoiceEventKind VOICE_EVENT_KIND_SPEECH_ENDED = VoiceEventKind._(22, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_SPEECH_ENDED');
  static const VoiceEventKind VOICE_EVENT_KIND_STT_PROCESSING = VoiceEventKind._(23, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_STT_PROCESSING');
  static const VoiceEventKind VOICE_EVENT_KIND_STT_PARTIAL_RESULT = VoiceEventKind._(24, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_STT_PARTIAL_RESULT');
  static const VoiceEventKind VOICE_EVENT_KIND_STT_COMPLETED = VoiceEventKind._(25, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_STT_COMPLETED');
  static const VoiceEventKind VOICE_EVENT_KIND_STT_FAILED = VoiceEventKind._(26, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_STT_FAILED');
  static const VoiceEventKind VOICE_EVENT_KIND_LLM_PROCESSING = VoiceEventKind._(27, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_LLM_PROCESSING');
  static const VoiceEventKind VOICE_EVENT_KIND_TTS_PROCESSING = VoiceEventKind._(28, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_TTS_PROCESSING');
  static const VoiceEventKind VOICE_EVENT_KIND_RECORDING_STARTED = VoiceEventKind._(29, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_RECORDING_STARTED');
  static const VoiceEventKind VOICE_EVENT_KIND_RECORDING_STOPPED = VoiceEventKind._(30, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_RECORDING_STOPPED');
  static const VoiceEventKind VOICE_EVENT_KIND_PLAYBACK_STARTED = VoiceEventKind._(31, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_PLAYBACK_STARTED');
  static const VoiceEventKind VOICE_EVENT_KIND_PLAYBACK_COMPLETED = VoiceEventKind._(32, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_PLAYBACK_COMPLETED');
  static const VoiceEventKind VOICE_EVENT_KIND_PLAYBACK_STOPPED = VoiceEventKind._(33, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_PLAYBACK_STOPPED');
  static const VoiceEventKind VOICE_EVENT_KIND_PLAYBACK_PAUSED = VoiceEventKind._(34, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_PLAYBACK_PAUSED');
  static const VoiceEventKind VOICE_EVENT_KIND_PLAYBACK_RESUMED = VoiceEventKind._(35, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_PLAYBACK_RESUMED');
  static const VoiceEventKind VOICE_EVENT_KIND_PLAYBACK_FAILED = VoiceEventKind._(36, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_PLAYBACK_FAILED');
  static const VoiceEventKind VOICE_EVENT_KIND_VOICE_SESSION_STARTED = VoiceEventKind._(37, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_VOICE_SESSION_STARTED');
  static const VoiceEventKind VOICE_EVENT_KIND_VOICE_SESSION_LISTENING = VoiceEventKind._(38, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_VOICE_SESSION_LISTENING');
  static const VoiceEventKind VOICE_EVENT_KIND_VOICE_SESSION_SPEECH_STARTED = VoiceEventKind._(39, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_VOICE_SESSION_SPEECH_STARTED');
  static const VoiceEventKind VOICE_EVENT_KIND_VOICE_SESSION_SPEECH_ENDED = VoiceEventKind._(40, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_VOICE_SESSION_SPEECH_ENDED');
  static const VoiceEventKind VOICE_EVENT_KIND_VOICE_SESSION_PROCESSING = VoiceEventKind._(41, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_VOICE_SESSION_PROCESSING');
  static const VoiceEventKind VOICE_EVENT_KIND_VOICE_SESSION_TRANSCRIBED = VoiceEventKind._(42, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_VOICE_SESSION_TRANSCRIBED');
  static const VoiceEventKind VOICE_EVENT_KIND_VOICE_SESSION_RESPONDED = VoiceEventKind._(43, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_VOICE_SESSION_RESPONDED');
  static const VoiceEventKind VOICE_EVENT_KIND_VOICE_SESSION_SPEAKING = VoiceEventKind._(44, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_VOICE_SESSION_SPEAKING');
  static const VoiceEventKind VOICE_EVENT_KIND_VOICE_SESSION_TURN_COMPLETED = VoiceEventKind._(45, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_VOICE_SESSION_TURN_COMPLETED');
  static const VoiceEventKind VOICE_EVENT_KIND_VOICE_SESSION_STOPPED = VoiceEventKind._(46, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_VOICE_SESSION_STOPPED');
  static const VoiceEventKind VOICE_EVENT_KIND_VOICE_SESSION_ERROR = VoiceEventKind._(47, _omitEnumNames ? '' : 'VOICE_EVENT_KIND_VOICE_SESSION_ERROR');

  static const $core.List<VoiceEventKind> values = <VoiceEventKind> [
    VOICE_EVENT_KIND_UNSPECIFIED,
    VOICE_EVENT_KIND_LISTENING_STARTED,
    VOICE_EVENT_KIND_LISTENING_ENDED,
    VOICE_EVENT_KIND_SPEECH_DETECTED,
    VOICE_EVENT_KIND_TRANSCRIPTION_STARTED,
    VOICE_EVENT_KIND_TRANSCRIPTION_PARTIAL,
    VOICE_EVENT_KIND_TRANSCRIPTION_FINAL,
    VOICE_EVENT_KIND_RESPONSE_GENERATED,
    VOICE_EVENT_KIND_SYNTHESIS_STARTED,
    VOICE_EVENT_KIND_AUDIO_GENERATED,
    VOICE_EVENT_KIND_SYNTHESIS_COMPLETED,
    VOICE_EVENT_KIND_SYNTHESIS_FAILED,
    VOICE_EVENT_KIND_PIPELINE_STARTED,
    VOICE_EVENT_KIND_PIPELINE_COMPLETED,
    VOICE_EVENT_KIND_PIPELINE_ERROR,
    VOICE_EVENT_KIND_VAD_STARTED,
    VOICE_EVENT_KIND_VAD_DETECTED,
    VOICE_EVENT_KIND_VAD_ENDED,
    VOICE_EVENT_KIND_VAD_INITIALIZED,
    VOICE_EVENT_KIND_VAD_STOPPED,
    VOICE_EVENT_KIND_VAD_CLEANED_UP,
    VOICE_EVENT_KIND_SPEECH_STARTED,
    VOICE_EVENT_KIND_SPEECH_ENDED,
    VOICE_EVENT_KIND_STT_PROCESSING,
    VOICE_EVENT_KIND_STT_PARTIAL_RESULT,
    VOICE_EVENT_KIND_STT_COMPLETED,
    VOICE_EVENT_KIND_STT_FAILED,
    VOICE_EVENT_KIND_LLM_PROCESSING,
    VOICE_EVENT_KIND_TTS_PROCESSING,
    VOICE_EVENT_KIND_RECORDING_STARTED,
    VOICE_EVENT_KIND_RECORDING_STOPPED,
    VOICE_EVENT_KIND_PLAYBACK_STARTED,
    VOICE_EVENT_KIND_PLAYBACK_COMPLETED,
    VOICE_EVENT_KIND_PLAYBACK_STOPPED,
    VOICE_EVENT_KIND_PLAYBACK_PAUSED,
    VOICE_EVENT_KIND_PLAYBACK_RESUMED,
    VOICE_EVENT_KIND_PLAYBACK_FAILED,
    VOICE_EVENT_KIND_VOICE_SESSION_STARTED,
    VOICE_EVENT_KIND_VOICE_SESSION_LISTENING,
    VOICE_EVENT_KIND_VOICE_SESSION_SPEECH_STARTED,
    VOICE_EVENT_KIND_VOICE_SESSION_SPEECH_ENDED,
    VOICE_EVENT_KIND_VOICE_SESSION_PROCESSING,
    VOICE_EVENT_KIND_VOICE_SESSION_TRANSCRIBED,
    VOICE_EVENT_KIND_VOICE_SESSION_RESPONDED,
    VOICE_EVENT_KIND_VOICE_SESSION_SPEAKING,
    VOICE_EVENT_KIND_VOICE_SESSION_TURN_COMPLETED,
    VOICE_EVENT_KIND_VOICE_SESSION_STOPPED,
    VOICE_EVENT_KIND_VOICE_SESSION_ERROR,
  ];

  static final $core.Map<$core.int, VoiceEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static VoiceEventKind? valueOf($core.int value) => _byValue[value];

  const VoiceEventKind._($core.int v, $core.String n) : super(v, n);
}

class PerformanceEventKind extends $pb.ProtobufEnum {
  static const PerformanceEventKind PERFORMANCE_EVENT_KIND_UNSPECIFIED = PerformanceEventKind._(0, _omitEnumNames ? '' : 'PERFORMANCE_EVENT_KIND_UNSPECIFIED');
  static const PerformanceEventKind PERFORMANCE_EVENT_KIND_MEMORY_WARNING = PerformanceEventKind._(1, _omitEnumNames ? '' : 'PERFORMANCE_EVENT_KIND_MEMORY_WARNING');
  static const PerformanceEventKind PERFORMANCE_EVENT_KIND_THERMAL_STATE_CHANGED = PerformanceEventKind._(2, _omitEnumNames ? '' : 'PERFORMANCE_EVENT_KIND_THERMAL_STATE_CHANGED');
  static const PerformanceEventKind PERFORMANCE_EVENT_KIND_LATENCY_MEASURED = PerformanceEventKind._(3, _omitEnumNames ? '' : 'PERFORMANCE_EVENT_KIND_LATENCY_MEASURED');
  static const PerformanceEventKind PERFORMANCE_EVENT_KIND_THROUGHPUT_MEASURED = PerformanceEventKind._(4, _omitEnumNames ? '' : 'PERFORMANCE_EVENT_KIND_THROUGHPUT_MEASURED');

  static const $core.List<PerformanceEventKind> values = <PerformanceEventKind> [
    PERFORMANCE_EVENT_KIND_UNSPECIFIED,
    PERFORMANCE_EVENT_KIND_MEMORY_WARNING,
    PERFORMANCE_EVENT_KIND_THERMAL_STATE_CHANGED,
    PERFORMANCE_EVENT_KIND_LATENCY_MEASURED,
    PERFORMANCE_EVENT_KIND_THROUGHPUT_MEASURED,
  ];

  static final $core.Map<$core.int, PerformanceEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static PerformanceEventKind? valueOf($core.int value) => _byValue[value];

  const PerformanceEventKind._($core.int v, $core.String n) : super(v, n);
}

class NetworkEventKind extends $pb.ProtobufEnum {
  static const NetworkEventKind NETWORK_EVENT_KIND_UNSPECIFIED = NetworkEventKind._(0, _omitEnumNames ? '' : 'NETWORK_EVENT_KIND_UNSPECIFIED');
  static const NetworkEventKind NETWORK_EVENT_KIND_REQUEST_STARTED = NetworkEventKind._(1, _omitEnumNames ? '' : 'NETWORK_EVENT_KIND_REQUEST_STARTED');
  static const NetworkEventKind NETWORK_EVENT_KIND_REQUEST_COMPLETED = NetworkEventKind._(2, _omitEnumNames ? '' : 'NETWORK_EVENT_KIND_REQUEST_COMPLETED');
  static const NetworkEventKind NETWORK_EVENT_KIND_REQUEST_FAILED = NetworkEventKind._(3, _omitEnumNames ? '' : 'NETWORK_EVENT_KIND_REQUEST_FAILED');
  static const NetworkEventKind NETWORK_EVENT_KIND_REQUEST_TIMEOUT = NetworkEventKind._(4, _omitEnumNames ? '' : 'NETWORK_EVENT_KIND_REQUEST_TIMEOUT');
  static const NetworkEventKind NETWORK_EVENT_KIND_CONNECTIVITY_CHANGED = NetworkEventKind._(5, _omitEnumNames ? '' : 'NETWORK_EVENT_KIND_CONNECTIVITY_CHANGED');

  static const $core.List<NetworkEventKind> values = <NetworkEventKind> [
    NETWORK_EVENT_KIND_UNSPECIFIED,
    NETWORK_EVENT_KIND_REQUEST_STARTED,
    NETWORK_EVENT_KIND_REQUEST_COMPLETED,
    NETWORK_EVENT_KIND_REQUEST_FAILED,
    NETWORK_EVENT_KIND_REQUEST_TIMEOUT,
    NETWORK_EVENT_KIND_CONNECTIVITY_CHANGED,
  ];

  static final $core.Map<$core.int, NetworkEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static NetworkEventKind? valueOf($core.int value) => _byValue[value];

  const NetworkEventKind._($core.int v, $core.String n) : super(v, n);
}

class StorageEventKind extends $pb.ProtobufEnum {
  static const StorageEventKind STORAGE_EVENT_KIND_UNSPECIFIED = StorageEventKind._(0, _omitEnumNames ? '' : 'STORAGE_EVENT_KIND_UNSPECIFIED');
  static const StorageEventKind STORAGE_EVENT_KIND_INFO_REQUESTED = StorageEventKind._(1, _omitEnumNames ? '' : 'STORAGE_EVENT_KIND_INFO_REQUESTED');
  static const StorageEventKind STORAGE_EVENT_KIND_INFO_RETRIEVED = StorageEventKind._(2, _omitEnumNames ? '' : 'STORAGE_EVENT_KIND_INFO_RETRIEVED');
  static const StorageEventKind STORAGE_EVENT_KIND_MODELS_REQUESTED = StorageEventKind._(3, _omitEnumNames ? '' : 'STORAGE_EVENT_KIND_MODELS_REQUESTED');
  static const StorageEventKind STORAGE_EVENT_KIND_MODELS_RETRIEVED = StorageEventKind._(4, _omitEnumNames ? '' : 'STORAGE_EVENT_KIND_MODELS_RETRIEVED');
  static const StorageEventKind STORAGE_EVENT_KIND_CLEAR_CACHE_STARTED = StorageEventKind._(5, _omitEnumNames ? '' : 'STORAGE_EVENT_KIND_CLEAR_CACHE_STARTED');
  static const StorageEventKind STORAGE_EVENT_KIND_CLEAR_CACHE_COMPLETED = StorageEventKind._(6, _omitEnumNames ? '' : 'STORAGE_EVENT_KIND_CLEAR_CACHE_COMPLETED');
  static const StorageEventKind STORAGE_EVENT_KIND_CLEAR_CACHE_FAILED = StorageEventKind._(7, _omitEnumNames ? '' : 'STORAGE_EVENT_KIND_CLEAR_CACHE_FAILED');
  static const StorageEventKind STORAGE_EVENT_KIND_CLEAN_TEMP_STARTED = StorageEventKind._(8, _omitEnumNames ? '' : 'STORAGE_EVENT_KIND_CLEAN_TEMP_STARTED');
  static const StorageEventKind STORAGE_EVENT_KIND_CLEAN_TEMP_COMPLETED = StorageEventKind._(9, _omitEnumNames ? '' : 'STORAGE_EVENT_KIND_CLEAN_TEMP_COMPLETED');
  static const StorageEventKind STORAGE_EVENT_KIND_CLEAN_TEMP_FAILED = StorageEventKind._(10, _omitEnumNames ? '' : 'STORAGE_EVENT_KIND_CLEAN_TEMP_FAILED');
  static const StorageEventKind STORAGE_EVENT_KIND_DELETE_MODEL_STARTED = StorageEventKind._(11, _omitEnumNames ? '' : 'STORAGE_EVENT_KIND_DELETE_MODEL_STARTED');
  static const StorageEventKind STORAGE_EVENT_KIND_DELETE_MODEL_COMPLETED = StorageEventKind._(12, _omitEnumNames ? '' : 'STORAGE_EVENT_KIND_DELETE_MODEL_COMPLETED');
  static const StorageEventKind STORAGE_EVENT_KIND_DELETE_MODEL_FAILED = StorageEventKind._(13, _omitEnumNames ? '' : 'STORAGE_EVENT_KIND_DELETE_MODEL_FAILED');
  static const StorageEventKind STORAGE_EVENT_KIND_CACHE_HIT = StorageEventKind._(14, _omitEnumNames ? '' : 'STORAGE_EVENT_KIND_CACHE_HIT');
  static const StorageEventKind STORAGE_EVENT_KIND_CACHE_MISS = StorageEventKind._(15, _omitEnumNames ? '' : 'STORAGE_EVENT_KIND_CACHE_MISS');
  static const StorageEventKind STORAGE_EVENT_KIND_EVICTION = StorageEventKind._(16, _omitEnumNames ? '' : 'STORAGE_EVENT_KIND_EVICTION');
  static const StorageEventKind STORAGE_EVENT_KIND_DISK_FULL = StorageEventKind._(17, _omitEnumNames ? '' : 'STORAGE_EVENT_KIND_DISK_FULL');

  static const $core.List<StorageEventKind> values = <StorageEventKind> [
    STORAGE_EVENT_KIND_UNSPECIFIED,
    STORAGE_EVENT_KIND_INFO_REQUESTED,
    STORAGE_EVENT_KIND_INFO_RETRIEVED,
    STORAGE_EVENT_KIND_MODELS_REQUESTED,
    STORAGE_EVENT_KIND_MODELS_RETRIEVED,
    STORAGE_EVENT_KIND_CLEAR_CACHE_STARTED,
    STORAGE_EVENT_KIND_CLEAR_CACHE_COMPLETED,
    STORAGE_EVENT_KIND_CLEAR_CACHE_FAILED,
    STORAGE_EVENT_KIND_CLEAN_TEMP_STARTED,
    STORAGE_EVENT_KIND_CLEAN_TEMP_COMPLETED,
    STORAGE_EVENT_KIND_CLEAN_TEMP_FAILED,
    STORAGE_EVENT_KIND_DELETE_MODEL_STARTED,
    STORAGE_EVENT_KIND_DELETE_MODEL_COMPLETED,
    STORAGE_EVENT_KIND_DELETE_MODEL_FAILED,
    STORAGE_EVENT_KIND_CACHE_HIT,
    STORAGE_EVENT_KIND_CACHE_MISS,
    STORAGE_EVENT_KIND_EVICTION,
    STORAGE_EVENT_KIND_DISK_FULL,
  ];

  static final $core.Map<$core.int, StorageEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static StorageEventKind? valueOf($core.int value) => _byValue[value];

  const StorageEventKind._($core.int v, $core.String n) : super(v, n);
}

class FrameworkEventKind extends $pb.ProtobufEnum {
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_UNSPECIFIED = FrameworkEventKind._(0, _omitEnumNames ? '' : 'FRAMEWORK_EVENT_KIND_UNSPECIFIED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_ADAPTER_REGISTERED = FrameworkEventKind._(1, _omitEnumNames ? '' : 'FRAMEWORK_EVENT_KIND_ADAPTER_REGISTERED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_ADAPTER_UNREGISTERED = FrameworkEventKind._(2, _omitEnumNames ? '' : 'FRAMEWORK_EVENT_KIND_ADAPTER_UNREGISTERED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_ADAPTERS_REQUESTED = FrameworkEventKind._(3, _omitEnumNames ? '' : 'FRAMEWORK_EVENT_KIND_ADAPTERS_REQUESTED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_ADAPTERS_RETRIEVED = FrameworkEventKind._(4, _omitEnumNames ? '' : 'FRAMEWORK_EVENT_KIND_ADAPTERS_RETRIEVED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_FRAMEWORKS_REQUESTED = FrameworkEventKind._(5, _omitEnumNames ? '' : 'FRAMEWORK_EVENT_KIND_FRAMEWORKS_REQUESTED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_FRAMEWORKS_RETRIEVED = FrameworkEventKind._(6, _omitEnumNames ? '' : 'FRAMEWORK_EVENT_KIND_FRAMEWORKS_RETRIEVED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_AVAILABILITY_REQUESTED = FrameworkEventKind._(7, _omitEnumNames ? '' : 'FRAMEWORK_EVENT_KIND_AVAILABILITY_REQUESTED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_AVAILABILITY_RETRIEVED = FrameworkEventKind._(8, _omitEnumNames ? '' : 'FRAMEWORK_EVENT_KIND_AVAILABILITY_RETRIEVED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_MODELS_FOR_FRAMEWORK_REQUESTED = FrameworkEventKind._(9, _omitEnumNames ? '' : 'FRAMEWORK_EVENT_KIND_MODELS_FOR_FRAMEWORK_REQUESTED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_MODELS_FOR_FRAMEWORK_RETRIEVED = FrameworkEventKind._(10, _omitEnumNames ? '' : 'FRAMEWORK_EVENT_KIND_MODELS_FOR_FRAMEWORK_RETRIEVED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_FRAMEWORKS_FOR_MODALITY_REQUESTED = FrameworkEventKind._(11, _omitEnumNames ? '' : 'FRAMEWORK_EVENT_KIND_FRAMEWORKS_FOR_MODALITY_REQUESTED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_FRAMEWORKS_FOR_MODALITY_RETRIEVED = FrameworkEventKind._(12, _omitEnumNames ? '' : 'FRAMEWORK_EVENT_KIND_FRAMEWORKS_FOR_MODALITY_RETRIEVED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_ERROR = FrameworkEventKind._(13, _omitEnumNames ? '' : 'FRAMEWORK_EVENT_KIND_ERROR');

  static const $core.List<FrameworkEventKind> values = <FrameworkEventKind> [
    FRAMEWORK_EVENT_KIND_UNSPECIFIED,
    FRAMEWORK_EVENT_KIND_ADAPTER_REGISTERED,
    FRAMEWORK_EVENT_KIND_ADAPTER_UNREGISTERED,
    FRAMEWORK_EVENT_KIND_ADAPTERS_REQUESTED,
    FRAMEWORK_EVENT_KIND_ADAPTERS_RETRIEVED,
    FRAMEWORK_EVENT_KIND_FRAMEWORKS_REQUESTED,
    FRAMEWORK_EVENT_KIND_FRAMEWORKS_RETRIEVED,
    FRAMEWORK_EVENT_KIND_AVAILABILITY_REQUESTED,
    FRAMEWORK_EVENT_KIND_AVAILABILITY_RETRIEVED,
    FRAMEWORK_EVENT_KIND_MODELS_FOR_FRAMEWORK_REQUESTED,
    FRAMEWORK_EVENT_KIND_MODELS_FOR_FRAMEWORK_RETRIEVED,
    FRAMEWORK_EVENT_KIND_FRAMEWORKS_FOR_MODALITY_REQUESTED,
    FRAMEWORK_EVENT_KIND_FRAMEWORKS_FOR_MODALITY_RETRIEVED,
    FRAMEWORK_EVENT_KIND_ERROR,
  ];

  static final $core.Map<$core.int, FrameworkEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static FrameworkEventKind? valueOf($core.int value) => _byValue[value];

  const FrameworkEventKind._($core.int v, $core.String n) : super(v, n);
}

class DeviceEventKind extends $pb.ProtobufEnum {
  static const DeviceEventKind DEVICE_EVENT_KIND_UNSPECIFIED = DeviceEventKind._(0, _omitEnumNames ? '' : 'DEVICE_EVENT_KIND_UNSPECIFIED');
  static const DeviceEventKind DEVICE_EVENT_KIND_DEVICE_INFO_COLLECTED = DeviceEventKind._(1, _omitEnumNames ? '' : 'DEVICE_EVENT_KIND_DEVICE_INFO_COLLECTED');
  static const DeviceEventKind DEVICE_EVENT_KIND_DEVICE_INFO_COLLECTION_FAILED = DeviceEventKind._(2, _omitEnumNames ? '' : 'DEVICE_EVENT_KIND_DEVICE_INFO_COLLECTION_FAILED');
  static const DeviceEventKind DEVICE_EVENT_KIND_DEVICE_INFO_REFRESHED = DeviceEventKind._(3, _omitEnumNames ? '' : 'DEVICE_EVENT_KIND_DEVICE_INFO_REFRESHED');
  static const DeviceEventKind DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_STARTED = DeviceEventKind._(4, _omitEnumNames ? '' : 'DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_STARTED');
  static const DeviceEventKind DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_COMPLETED = DeviceEventKind._(5, _omitEnumNames ? '' : 'DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_COMPLETED');
  static const DeviceEventKind DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_FAILED = DeviceEventKind._(6, _omitEnumNames ? '' : 'DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_FAILED');
  static const DeviceEventKind DEVICE_EVENT_KIND_DEVICE_STATE_CHANGED = DeviceEventKind._(7, _omitEnumNames ? '' : 'DEVICE_EVENT_KIND_DEVICE_STATE_CHANGED');
  static const DeviceEventKind DEVICE_EVENT_KIND_BATTERY_CHANGED = DeviceEventKind._(8, _omitEnumNames ? '' : 'DEVICE_EVENT_KIND_BATTERY_CHANGED');
  static const DeviceEventKind DEVICE_EVENT_KIND_THERMAL_CHANGED = DeviceEventKind._(9, _omitEnumNames ? '' : 'DEVICE_EVENT_KIND_THERMAL_CHANGED');
  static const DeviceEventKind DEVICE_EVENT_KIND_CONNECTIVITY_CHANGED = DeviceEventKind._(10, _omitEnumNames ? '' : 'DEVICE_EVENT_KIND_CONNECTIVITY_CHANGED');
  static const DeviceEventKind DEVICE_EVENT_KIND_DEVICE_REGISTERED = DeviceEventKind._(11, _omitEnumNames ? '' : 'DEVICE_EVENT_KIND_DEVICE_REGISTERED');
  static const DeviceEventKind DEVICE_EVENT_KIND_DEVICE_REGISTRATION_FAILED = DeviceEventKind._(12, _omitEnumNames ? '' : 'DEVICE_EVENT_KIND_DEVICE_REGISTRATION_FAILED');

  static const $core.List<DeviceEventKind> values = <DeviceEventKind> [
    DEVICE_EVENT_KIND_UNSPECIFIED,
    DEVICE_EVENT_KIND_DEVICE_INFO_COLLECTED,
    DEVICE_EVENT_KIND_DEVICE_INFO_COLLECTION_FAILED,
    DEVICE_EVENT_KIND_DEVICE_INFO_REFRESHED,
    DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_STARTED,
    DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_COMPLETED,
    DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_FAILED,
    DEVICE_EVENT_KIND_DEVICE_STATE_CHANGED,
    DEVICE_EVENT_KIND_BATTERY_CHANGED,
    DEVICE_EVENT_KIND_THERMAL_CHANGED,
    DEVICE_EVENT_KIND_CONNECTIVITY_CHANGED,
    DEVICE_EVENT_KIND_DEVICE_REGISTERED,
    DEVICE_EVENT_KIND_DEVICE_REGISTRATION_FAILED,
  ];

  static final $core.Map<$core.int, DeviceEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static DeviceEventKind? valueOf($core.int value) => _byValue[value];

  const DeviceEventKind._($core.int v, $core.String n) : super(v, n);
}

class ComponentInitializationEventKind extends $pb.ProtobufEnum {
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_UNSPECIFIED = ComponentInitializationEventKind._(0, _omitEnumNames ? '' : 'COMPONENT_INIT_EVENT_KIND_UNSPECIFIED');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_INITIALIZATION_STARTED = ComponentInitializationEventKind._(1, _omitEnumNames ? '' : 'COMPONENT_INIT_EVENT_KIND_INITIALIZATION_STARTED');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_INITIALIZATION_COMPLETED = ComponentInitializationEventKind._(2, _omitEnumNames ? '' : 'COMPONENT_INIT_EVENT_KIND_INITIALIZATION_COMPLETED');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_COMPONENT_STATE_CHANGED = ComponentInitializationEventKind._(3, _omitEnumNames ? '' : 'COMPONENT_INIT_EVENT_KIND_COMPONENT_STATE_CHANGED');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_COMPONENT_CHECKING = ComponentInitializationEventKind._(4, _omitEnumNames ? '' : 'COMPONENT_INIT_EVENT_KIND_COMPONENT_CHECKING');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_REQUIRED = ComponentInitializationEventKind._(5, _omitEnumNames ? '' : 'COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_REQUIRED');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_STARTED = ComponentInitializationEventKind._(6, _omitEnumNames ? '' : 'COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_STARTED');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_PROGRESS = ComponentInitializationEventKind._(7, _omitEnumNames ? '' : 'COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_PROGRESS');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_COMPLETED = ComponentInitializationEventKind._(8, _omitEnumNames ? '' : 'COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_COMPLETED');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_COMPONENT_INITIALIZING = ComponentInitializationEventKind._(9, _omitEnumNames ? '' : 'COMPONENT_INIT_EVENT_KIND_COMPONENT_INITIALIZING');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_COMPONENT_READY = ComponentInitializationEventKind._(10, _omitEnumNames ? '' : 'COMPONENT_INIT_EVENT_KIND_COMPONENT_READY');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_COMPONENT_FAILED = ComponentInitializationEventKind._(11, _omitEnumNames ? '' : 'COMPONENT_INIT_EVENT_KIND_COMPONENT_FAILED');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_PARALLEL_INIT_STARTED = ComponentInitializationEventKind._(12, _omitEnumNames ? '' : 'COMPONENT_INIT_EVENT_KIND_PARALLEL_INIT_STARTED');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_SEQUENTIAL_INIT_STARTED = ComponentInitializationEventKind._(13, _omitEnumNames ? '' : 'COMPONENT_INIT_EVENT_KIND_SEQUENTIAL_INIT_STARTED');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_ALL_COMPONENTS_READY = ComponentInitializationEventKind._(14, _omitEnumNames ? '' : 'COMPONENT_INIT_EVENT_KIND_ALL_COMPONENTS_READY');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_SOME_COMPONENTS_READY = ComponentInitializationEventKind._(15, _omitEnumNames ? '' : 'COMPONENT_INIT_EVENT_KIND_SOME_COMPONENTS_READY');

  static const $core.List<ComponentInitializationEventKind> values = <ComponentInitializationEventKind> [
    COMPONENT_INIT_EVENT_KIND_UNSPECIFIED,
    COMPONENT_INIT_EVENT_KIND_INITIALIZATION_STARTED,
    COMPONENT_INIT_EVENT_KIND_INITIALIZATION_COMPLETED,
    COMPONENT_INIT_EVENT_KIND_COMPONENT_STATE_CHANGED,
    COMPONENT_INIT_EVENT_KIND_COMPONENT_CHECKING,
    COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_REQUIRED,
    COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_STARTED,
    COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_PROGRESS,
    COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_COMPLETED,
    COMPONENT_INIT_EVENT_KIND_COMPONENT_INITIALIZING,
    COMPONENT_INIT_EVENT_KIND_COMPONENT_READY,
    COMPONENT_INIT_EVENT_KIND_COMPONENT_FAILED,
    COMPONENT_INIT_EVENT_KIND_PARALLEL_INIT_STARTED,
    COMPONENT_INIT_EVENT_KIND_SEQUENTIAL_INIT_STARTED,
    COMPONENT_INIT_EVENT_KIND_ALL_COMPONENTS_READY,
    COMPONENT_INIT_EVENT_KIND_SOME_COMPONENTS_READY,
  ];

  static final $core.Map<$core.int, ComponentInitializationEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ComponentInitializationEventKind? valueOf($core.int value) => _byValue[value];

  const ComponentInitializationEventKind._($core.int v, $core.String n) : super(v, n);
}

class SessionEventKind extends $pb.ProtobufEnum {
  static const SessionEventKind SESSION_EVENT_KIND_UNSPECIFIED = SessionEventKind._(0, _omitEnumNames ? '' : 'SESSION_EVENT_KIND_UNSPECIFIED');
  static const SessionEventKind SESSION_EVENT_KIND_CREATED = SessionEventKind._(1, _omitEnumNames ? '' : 'SESSION_EVENT_KIND_CREATED');
  static const SessionEventKind SESSION_EVENT_KIND_STARTED = SessionEventKind._(2, _omitEnumNames ? '' : 'SESSION_EVENT_KIND_STARTED');
  static const SessionEventKind SESSION_EVENT_KIND_RESUMED = SessionEventKind._(3, _omitEnumNames ? '' : 'SESSION_EVENT_KIND_RESUMED');
  static const SessionEventKind SESSION_EVENT_KIND_PAUSED = SessionEventKind._(4, _omitEnumNames ? '' : 'SESSION_EVENT_KIND_PAUSED');
  static const SessionEventKind SESSION_EVENT_KIND_ENDED = SessionEventKind._(5, _omitEnumNames ? '' : 'SESSION_EVENT_KIND_ENDED');
  static const SessionEventKind SESSION_EVENT_KIND_EXPIRED = SessionEventKind._(6, _omitEnumNames ? '' : 'SESSION_EVENT_KIND_EXPIRED');
  static const SessionEventKind SESSION_EVENT_KIND_FAILED = SessionEventKind._(7, _omitEnumNames ? '' : 'SESSION_EVENT_KIND_FAILED');

  static const $core.List<SessionEventKind> values = <SessionEventKind> [
    SESSION_EVENT_KIND_UNSPECIFIED,
    SESSION_EVENT_KIND_CREATED,
    SESSION_EVENT_KIND_STARTED,
    SESSION_EVENT_KIND_RESUMED,
    SESSION_EVENT_KIND_PAUSED,
    SESSION_EVENT_KIND_ENDED,
    SESSION_EVENT_KIND_EXPIRED,
    SESSION_EVENT_KIND_FAILED,
  ];

  static final $core.Map<$core.int, SessionEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static SessionEventKind? valueOf($core.int value) => _byValue[value];

  const SessionEventKind._($core.int v, $core.String n) : super(v, n);
}

class AuthEventKind extends $pb.ProtobufEnum {
  static const AuthEventKind AUTH_EVENT_KIND_UNSPECIFIED = AuthEventKind._(0, _omitEnumNames ? '' : 'AUTH_EVENT_KIND_UNSPECIFIED');
  static const AuthEventKind AUTH_EVENT_KIND_REQUESTED = AuthEventKind._(1, _omitEnumNames ? '' : 'AUTH_EVENT_KIND_REQUESTED');
  static const AuthEventKind AUTH_EVENT_KIND_SUCCEEDED = AuthEventKind._(2, _omitEnumNames ? '' : 'AUTH_EVENT_KIND_SUCCEEDED');
  static const AuthEventKind AUTH_EVENT_KIND_FAILED = AuthEventKind._(3, _omitEnumNames ? '' : 'AUTH_EVENT_KIND_FAILED');
  static const AuthEventKind AUTH_EVENT_KIND_TOKEN_REFRESHED = AuthEventKind._(4, _omitEnumNames ? '' : 'AUTH_EVENT_KIND_TOKEN_REFRESHED');
  static const AuthEventKind AUTH_EVENT_KIND_TOKEN_EXPIRED = AuthEventKind._(5, _omitEnumNames ? '' : 'AUTH_EVENT_KIND_TOKEN_EXPIRED');
  static const AuthEventKind AUTH_EVENT_KIND_DEVICE_REGISTERED = AuthEventKind._(6, _omitEnumNames ? '' : 'AUTH_EVENT_KIND_DEVICE_REGISTERED');
  static const AuthEventKind AUTH_EVENT_KIND_DEVICE_REGISTRATION_FAILED = AuthEventKind._(7, _omitEnumNames ? '' : 'AUTH_EVENT_KIND_DEVICE_REGISTRATION_FAILED');

  static const $core.List<AuthEventKind> values = <AuthEventKind> [
    AUTH_EVENT_KIND_UNSPECIFIED,
    AUTH_EVENT_KIND_REQUESTED,
    AUTH_EVENT_KIND_SUCCEEDED,
    AUTH_EVENT_KIND_FAILED,
    AUTH_EVENT_KIND_TOKEN_REFRESHED,
    AUTH_EVENT_KIND_TOKEN_EXPIRED,
    AUTH_EVENT_KIND_DEVICE_REGISTERED,
    AUTH_EVENT_KIND_DEVICE_REGISTRATION_FAILED,
  ];

  static final $core.Map<$core.int, AuthEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static AuthEventKind? valueOf($core.int value) => _byValue[value];

  const AuthEventKind._($core.int v, $core.String n) : super(v, n);
}

class ModelRegistryEventKind extends $pb.ProtobufEnum {
  static const ModelRegistryEventKind MODEL_REGISTRY_EVENT_KIND_UNSPECIFIED = ModelRegistryEventKind._(0, _omitEnumNames ? '' : 'MODEL_REGISTRY_EVENT_KIND_UNSPECIFIED');
  static const ModelRegistryEventKind MODEL_REGISTRY_EVENT_KIND_REFRESH_STARTED = ModelRegistryEventKind._(1, _omitEnumNames ? '' : 'MODEL_REGISTRY_EVENT_KIND_REFRESH_STARTED');
  static const ModelRegistryEventKind MODEL_REGISTRY_EVENT_KIND_REFRESH_COMPLETED = ModelRegistryEventKind._(2, _omitEnumNames ? '' : 'MODEL_REGISTRY_EVENT_KIND_REFRESH_COMPLETED');
  static const ModelRegistryEventKind MODEL_REGISTRY_EVENT_KIND_REFRESH_FAILED = ModelRegistryEventKind._(3, _omitEnumNames ? '' : 'MODEL_REGISTRY_EVENT_KIND_REFRESH_FAILED');
  static const ModelRegistryEventKind MODEL_REGISTRY_EVENT_KIND_ASSIGNMENT_STARTED = ModelRegistryEventKind._(4, _omitEnumNames ? '' : 'MODEL_REGISTRY_EVENT_KIND_ASSIGNMENT_STARTED');
  static const ModelRegistryEventKind MODEL_REGISTRY_EVENT_KIND_ASSIGNMENT_COMPLETED = ModelRegistryEventKind._(5, _omitEnumNames ? '' : 'MODEL_REGISTRY_EVENT_KIND_ASSIGNMENT_COMPLETED');
  static const ModelRegistryEventKind MODEL_REGISTRY_EVENT_KIND_ASSIGNMENT_FAILED = ModelRegistryEventKind._(6, _omitEnumNames ? '' : 'MODEL_REGISTRY_EVENT_KIND_ASSIGNMENT_FAILED');
  static const ModelRegistryEventKind MODEL_REGISTRY_EVENT_KIND_IMPORT_STARTED = ModelRegistryEventKind._(7, _omitEnumNames ? '' : 'MODEL_REGISTRY_EVENT_KIND_IMPORT_STARTED');
  static const ModelRegistryEventKind MODEL_REGISTRY_EVENT_KIND_IMPORT_COMPLETED = ModelRegistryEventKind._(8, _omitEnumNames ? '' : 'MODEL_REGISTRY_EVENT_KIND_IMPORT_COMPLETED');
  static const ModelRegistryEventKind MODEL_REGISTRY_EVENT_KIND_IMPORT_FAILED = ModelRegistryEventKind._(9, _omitEnumNames ? '' : 'MODEL_REGISTRY_EVENT_KIND_IMPORT_FAILED');
  static const ModelRegistryEventKind MODEL_REGISTRY_EVENT_KIND_DISCOVERY_STARTED = ModelRegistryEventKind._(10, _omitEnumNames ? '' : 'MODEL_REGISTRY_EVENT_KIND_DISCOVERY_STARTED');
  static const ModelRegistryEventKind MODEL_REGISTRY_EVENT_KIND_DISCOVERY_COMPLETED = ModelRegistryEventKind._(11, _omitEnumNames ? '' : 'MODEL_REGISTRY_EVENT_KIND_DISCOVERY_COMPLETED');
  static const ModelRegistryEventKind MODEL_REGISTRY_EVENT_KIND_DISCOVERY_FAILED = ModelRegistryEventKind._(12, _omitEnumNames ? '' : 'MODEL_REGISTRY_EVENT_KIND_DISCOVERY_FAILED');
  static const ModelRegistryEventKind MODEL_REGISTRY_EVENT_KIND_CURRENT_MODEL_CHANGED = ModelRegistryEventKind._(13, _omitEnumNames ? '' : 'MODEL_REGISTRY_EVENT_KIND_CURRENT_MODEL_CHANGED');

  static const $core.List<ModelRegistryEventKind> values = <ModelRegistryEventKind> [
    MODEL_REGISTRY_EVENT_KIND_UNSPECIFIED,
    MODEL_REGISTRY_EVENT_KIND_REFRESH_STARTED,
    MODEL_REGISTRY_EVENT_KIND_REFRESH_COMPLETED,
    MODEL_REGISTRY_EVENT_KIND_REFRESH_FAILED,
    MODEL_REGISTRY_EVENT_KIND_ASSIGNMENT_STARTED,
    MODEL_REGISTRY_EVENT_KIND_ASSIGNMENT_COMPLETED,
    MODEL_REGISTRY_EVENT_KIND_ASSIGNMENT_FAILED,
    MODEL_REGISTRY_EVENT_KIND_IMPORT_STARTED,
    MODEL_REGISTRY_EVENT_KIND_IMPORT_COMPLETED,
    MODEL_REGISTRY_EVENT_KIND_IMPORT_FAILED,
    MODEL_REGISTRY_EVENT_KIND_DISCOVERY_STARTED,
    MODEL_REGISTRY_EVENT_KIND_DISCOVERY_COMPLETED,
    MODEL_REGISTRY_EVENT_KIND_DISCOVERY_FAILED,
    MODEL_REGISTRY_EVENT_KIND_CURRENT_MODEL_CHANGED,
  ];

  static final $core.Map<$core.int, ModelRegistryEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static ModelRegistryEventKind? valueOf($core.int value) => _byValue[value];

  const ModelRegistryEventKind._($core.int v, $core.String n) : super(v, n);
}

class DownloadEventKind extends $pb.ProtobufEnum {
  static const DownloadEventKind DOWNLOAD_EVENT_KIND_UNSPECIFIED = DownloadEventKind._(0, _omitEnumNames ? '' : 'DOWNLOAD_EVENT_KIND_UNSPECIFIED');
  static const DownloadEventKind DOWNLOAD_EVENT_KIND_PLAN_STARTED = DownloadEventKind._(1, _omitEnumNames ? '' : 'DOWNLOAD_EVENT_KIND_PLAN_STARTED');
  static const DownloadEventKind DOWNLOAD_EVENT_KIND_PLAN_COMPLETED = DownloadEventKind._(2, _omitEnumNames ? '' : 'DOWNLOAD_EVENT_KIND_PLAN_COMPLETED');
  static const DownloadEventKind DOWNLOAD_EVENT_KIND_PLAN_FAILED = DownloadEventKind._(3, _omitEnumNames ? '' : 'DOWNLOAD_EVENT_KIND_PLAN_FAILED');
  static const DownloadEventKind DOWNLOAD_EVENT_KIND_STARTED = DownloadEventKind._(4, _omitEnumNames ? '' : 'DOWNLOAD_EVENT_KIND_STARTED');
  static const DownloadEventKind DOWNLOAD_EVENT_KIND_PROGRESS = DownloadEventKind._(5, _omitEnumNames ? '' : 'DOWNLOAD_EVENT_KIND_PROGRESS');
  static const DownloadEventKind DOWNLOAD_EVENT_KIND_CANCEL_REQUESTED = DownloadEventKind._(6, _omitEnumNames ? '' : 'DOWNLOAD_EVENT_KIND_CANCEL_REQUESTED');
  static const DownloadEventKind DOWNLOAD_EVENT_KIND_CANCELLED = DownloadEventKind._(7, _omitEnumNames ? '' : 'DOWNLOAD_EVENT_KIND_CANCELLED');
  static const DownloadEventKind DOWNLOAD_EVENT_KIND_RESUME_REQUESTED = DownloadEventKind._(8, _omitEnumNames ? '' : 'DOWNLOAD_EVENT_KIND_RESUME_REQUESTED');
  static const DownloadEventKind DOWNLOAD_EVENT_KIND_RESUMED = DownloadEventKind._(9, _omitEnumNames ? '' : 'DOWNLOAD_EVENT_KIND_RESUMED');
  static const DownloadEventKind DOWNLOAD_EVENT_KIND_COMPLETED = DownloadEventKind._(10, _omitEnumNames ? '' : 'DOWNLOAD_EVENT_KIND_COMPLETED');
  static const DownloadEventKind DOWNLOAD_EVENT_KIND_FAILED = DownloadEventKind._(11, _omitEnumNames ? '' : 'DOWNLOAD_EVENT_KIND_FAILED');

  static const $core.List<DownloadEventKind> values = <DownloadEventKind> [
    DOWNLOAD_EVENT_KIND_UNSPECIFIED,
    DOWNLOAD_EVENT_KIND_PLAN_STARTED,
    DOWNLOAD_EVENT_KIND_PLAN_COMPLETED,
    DOWNLOAD_EVENT_KIND_PLAN_FAILED,
    DOWNLOAD_EVENT_KIND_STARTED,
    DOWNLOAD_EVENT_KIND_PROGRESS,
    DOWNLOAD_EVENT_KIND_CANCEL_REQUESTED,
    DOWNLOAD_EVENT_KIND_CANCELLED,
    DOWNLOAD_EVENT_KIND_RESUME_REQUESTED,
    DOWNLOAD_EVENT_KIND_RESUMED,
    DOWNLOAD_EVENT_KIND_COMPLETED,
    DOWNLOAD_EVENT_KIND_FAILED,
  ];

  static final $core.Map<$core.int, DownloadEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static DownloadEventKind? valueOf($core.int value) => _byValue[value];

  const DownloadEventKind._($core.int v, $core.String n) : super(v, n);
}

class StorageLifecycleEventKind extends $pb.ProtobufEnum {
  static const StorageLifecycleEventKind STORAGE_LIFECYCLE_EVENT_KIND_UNSPECIFIED = StorageLifecycleEventKind._(0, _omitEnumNames ? '' : 'STORAGE_LIFECYCLE_EVENT_KIND_UNSPECIFIED');
  static const StorageLifecycleEventKind STORAGE_LIFECYCLE_EVENT_KIND_INFO_STARTED = StorageLifecycleEventKind._(1, _omitEnumNames ? '' : 'STORAGE_LIFECYCLE_EVENT_KIND_INFO_STARTED');
  static const StorageLifecycleEventKind STORAGE_LIFECYCLE_EVENT_KIND_INFO_COMPLETED = StorageLifecycleEventKind._(2, _omitEnumNames ? '' : 'STORAGE_LIFECYCLE_EVENT_KIND_INFO_COMPLETED');
  static const StorageLifecycleEventKind STORAGE_LIFECYCLE_EVENT_KIND_AVAILABILITY_CHECKED = StorageLifecycleEventKind._(3, _omitEnumNames ? '' : 'STORAGE_LIFECYCLE_EVENT_KIND_AVAILABILITY_CHECKED');
  static const StorageLifecycleEventKind STORAGE_LIFECYCLE_EVENT_KIND_DELETE_PLAN_CREATED = StorageLifecycleEventKind._(4, _omitEnumNames ? '' : 'STORAGE_LIFECYCLE_EVENT_KIND_DELETE_PLAN_CREATED');
  static const StorageLifecycleEventKind STORAGE_LIFECYCLE_EVENT_KIND_DELETE_STARTED = StorageLifecycleEventKind._(5, _omitEnumNames ? '' : 'STORAGE_LIFECYCLE_EVENT_KIND_DELETE_STARTED');
  static const StorageLifecycleEventKind STORAGE_LIFECYCLE_EVENT_KIND_DELETE_COMPLETED = StorageLifecycleEventKind._(6, _omitEnumNames ? '' : 'STORAGE_LIFECYCLE_EVENT_KIND_DELETE_COMPLETED');
  static const StorageLifecycleEventKind STORAGE_LIFECYCLE_EVENT_KIND_DELETE_FAILED = StorageLifecycleEventKind._(7, _omitEnumNames ? '' : 'STORAGE_LIFECYCLE_EVENT_KIND_DELETE_FAILED');
  static const StorageLifecycleEventKind STORAGE_LIFECYCLE_EVENT_KIND_CACHE_CLEANUP_STARTED = StorageLifecycleEventKind._(8, _omitEnumNames ? '' : 'STORAGE_LIFECYCLE_EVENT_KIND_CACHE_CLEANUP_STARTED');
  static const StorageLifecycleEventKind STORAGE_LIFECYCLE_EVENT_KIND_CACHE_CLEANUP_COMPLETED = StorageLifecycleEventKind._(9, _omitEnumNames ? '' : 'STORAGE_LIFECYCLE_EVENT_KIND_CACHE_CLEANUP_COMPLETED');
  static const StorageLifecycleEventKind STORAGE_LIFECYCLE_EVENT_KIND_CACHE_CLEANUP_FAILED = StorageLifecycleEventKind._(10, _omitEnumNames ? '' : 'STORAGE_LIFECYCLE_EVENT_KIND_CACHE_CLEANUP_FAILED');

  static const $core.List<StorageLifecycleEventKind> values = <StorageLifecycleEventKind> [
    STORAGE_LIFECYCLE_EVENT_KIND_UNSPECIFIED,
    STORAGE_LIFECYCLE_EVENT_KIND_INFO_STARTED,
    STORAGE_LIFECYCLE_EVENT_KIND_INFO_COMPLETED,
    STORAGE_LIFECYCLE_EVENT_KIND_AVAILABILITY_CHECKED,
    STORAGE_LIFECYCLE_EVENT_KIND_DELETE_PLAN_CREATED,
    STORAGE_LIFECYCLE_EVENT_KIND_DELETE_STARTED,
    STORAGE_LIFECYCLE_EVENT_KIND_DELETE_COMPLETED,
    STORAGE_LIFECYCLE_EVENT_KIND_DELETE_FAILED,
    STORAGE_LIFECYCLE_EVENT_KIND_CACHE_CLEANUP_STARTED,
    STORAGE_LIFECYCLE_EVENT_KIND_CACHE_CLEANUP_COMPLETED,
    STORAGE_LIFECYCLE_EVENT_KIND_CACHE_CLEANUP_FAILED,
  ];

  static final $core.Map<$core.int, StorageLifecycleEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static StorageLifecycleEventKind? valueOf($core.int value) => _byValue[value];

  const StorageLifecycleEventKind._($core.int v, $core.String n) : super(v, n);
}

class HardwareRoutingEventKind extends $pb.ProtobufEnum {
  static const HardwareRoutingEventKind HARDWARE_ROUTING_EVENT_KIND_UNSPECIFIED = HardwareRoutingEventKind._(0, _omitEnumNames ? '' : 'HARDWARE_ROUTING_EVENT_KIND_UNSPECIFIED');
  static const HardwareRoutingEventKind HARDWARE_ROUTING_EVENT_KIND_PROFILE_STARTED = HardwareRoutingEventKind._(1, _omitEnumNames ? '' : 'HARDWARE_ROUTING_EVENT_KIND_PROFILE_STARTED');
  static const HardwareRoutingEventKind HARDWARE_ROUTING_EVENT_KIND_PROFILE_COMPLETED = HardwareRoutingEventKind._(2, _omitEnumNames ? '' : 'HARDWARE_ROUTING_EVENT_KIND_PROFILE_COMPLETED');
  static const HardwareRoutingEventKind HARDWARE_ROUTING_EVENT_KIND_PROFILE_FAILED = HardwareRoutingEventKind._(3, _omitEnumNames ? '' : 'HARDWARE_ROUTING_EVENT_KIND_PROFILE_FAILED');
  static const HardwareRoutingEventKind HARDWARE_ROUTING_EVENT_KIND_ROUTE_SELECTED = HardwareRoutingEventKind._(4, _omitEnumNames ? '' : 'HARDWARE_ROUTING_EVENT_KIND_ROUTE_SELECTED');
  static const HardwareRoutingEventKind HARDWARE_ROUTING_EVENT_KIND_ROUTE_CHANGED = HardwareRoutingEventKind._(5, _omitEnumNames ? '' : 'HARDWARE_ROUTING_EVENT_KIND_ROUTE_CHANGED');
  static const HardwareRoutingEventKind HARDWARE_ROUTING_EVENT_KIND_FRAMEWORK_CAPABILITY_DETECTED = HardwareRoutingEventKind._(6, _omitEnumNames ? '' : 'HARDWARE_ROUTING_EVENT_KIND_FRAMEWORK_CAPABILITY_DETECTED');
  static const HardwareRoutingEventKind HARDWARE_ROUTING_EVENT_KIND_FRAMEWORK_CAPABILITY_MISSING = HardwareRoutingEventKind._(7, _omitEnumNames ? '' : 'HARDWARE_ROUTING_EVENT_KIND_FRAMEWORK_CAPABILITY_MISSING');

  static const $core.List<HardwareRoutingEventKind> values = <HardwareRoutingEventKind> [
    HARDWARE_ROUTING_EVENT_KIND_UNSPECIFIED,
    HARDWARE_ROUTING_EVENT_KIND_PROFILE_STARTED,
    HARDWARE_ROUTING_EVENT_KIND_PROFILE_COMPLETED,
    HARDWARE_ROUTING_EVENT_KIND_PROFILE_FAILED,
    HARDWARE_ROUTING_EVENT_KIND_ROUTE_SELECTED,
    HARDWARE_ROUTING_EVENT_KIND_ROUTE_CHANGED,
    HARDWARE_ROUTING_EVENT_KIND_FRAMEWORK_CAPABILITY_DETECTED,
    HARDWARE_ROUTING_EVENT_KIND_FRAMEWORK_CAPABILITY_MISSING,
  ];

  static final $core.Map<$core.int, HardwareRoutingEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static HardwareRoutingEventKind? valueOf($core.int value) => _byValue[value];

  const HardwareRoutingEventKind._($core.int v, $core.String n) : super(v, n);
}

class CapabilityOperationEventKind extends $pb.ProtobufEnum {
  static const CapabilityOperationEventKind CAPABILITY_OPERATION_EVENT_KIND_UNSPECIFIED = CapabilityOperationEventKind._(0, _omitEnumNames ? '' : 'CAPABILITY_OPERATION_EVENT_KIND_UNSPECIFIED');
  static const CapabilityOperationEventKind CAPABILITY_OPERATION_EVENT_KIND_VLM_STARTED = CapabilityOperationEventKind._(1, _omitEnumNames ? '' : 'CAPABILITY_OPERATION_EVENT_KIND_VLM_STARTED');
  static const CapabilityOperationEventKind CAPABILITY_OPERATION_EVENT_KIND_VLM_COMPLETED = CapabilityOperationEventKind._(2, _omitEnumNames ? '' : 'CAPABILITY_OPERATION_EVENT_KIND_VLM_COMPLETED');
  static const CapabilityOperationEventKind CAPABILITY_OPERATION_EVENT_KIND_VLM_FAILED = CapabilityOperationEventKind._(3, _omitEnumNames ? '' : 'CAPABILITY_OPERATION_EVENT_KIND_VLM_FAILED');
  static const CapabilityOperationEventKind CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_STARTED = CapabilityOperationEventKind._(4, _omitEnumNames ? '' : 'CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_STARTED');
  static const CapabilityOperationEventKind CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_PROGRESS = CapabilityOperationEventKind._(5, _omitEnumNames ? '' : 'CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_PROGRESS');
  static const CapabilityOperationEventKind CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_COMPLETED = CapabilityOperationEventKind._(6, _omitEnumNames ? '' : 'CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_COMPLETED');
  static const CapabilityOperationEventKind CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_FAILED = CapabilityOperationEventKind._(7, _omitEnumNames ? '' : 'CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_FAILED');
  static const CapabilityOperationEventKind CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_STARTED = CapabilityOperationEventKind._(8, _omitEnumNames ? '' : 'CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_STARTED');
  static const CapabilityOperationEventKind CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_COMPLETED = CapabilityOperationEventKind._(9, _omitEnumNames ? '' : 'CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_COMPLETED');
  static const CapabilityOperationEventKind CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_FAILED = CapabilityOperationEventKind._(10, _omitEnumNames ? '' : 'CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_FAILED');
  static const CapabilityOperationEventKind CAPABILITY_OPERATION_EVENT_KIND_RAG_INGESTION_STARTED = CapabilityOperationEventKind._(11, _omitEnumNames ? '' : 'CAPABILITY_OPERATION_EVENT_KIND_RAG_INGESTION_STARTED');
  static const CapabilityOperationEventKind CAPABILITY_OPERATION_EVENT_KIND_RAG_INGESTION_COMPLETED = CapabilityOperationEventKind._(12, _omitEnumNames ? '' : 'CAPABILITY_OPERATION_EVENT_KIND_RAG_INGESTION_COMPLETED');
  static const CapabilityOperationEventKind CAPABILITY_OPERATION_EVENT_KIND_RAG_QUERY_STARTED = CapabilityOperationEventKind._(13, _omitEnumNames ? '' : 'CAPABILITY_OPERATION_EVENT_KIND_RAG_QUERY_STARTED');
  static const CapabilityOperationEventKind CAPABILITY_OPERATION_EVENT_KIND_RAG_QUERY_COMPLETED = CapabilityOperationEventKind._(14, _omitEnumNames ? '' : 'CAPABILITY_OPERATION_EVENT_KIND_RAG_QUERY_COMPLETED');
  static const CapabilityOperationEventKind CAPABILITY_OPERATION_EVENT_KIND_RAG_FAILED = CapabilityOperationEventKind._(15, _omitEnumNames ? '' : 'CAPABILITY_OPERATION_EVENT_KIND_RAG_FAILED');
  static const CapabilityOperationEventKind CAPABILITY_OPERATION_EVENT_KIND_LORA_ATTACHED = CapabilityOperationEventKind._(16, _omitEnumNames ? '' : 'CAPABILITY_OPERATION_EVENT_KIND_LORA_ATTACHED');
  static const CapabilityOperationEventKind CAPABILITY_OPERATION_EVENT_KIND_LORA_DETACHED = CapabilityOperationEventKind._(17, _omitEnumNames ? '' : 'CAPABILITY_OPERATION_EVENT_KIND_LORA_DETACHED');
  static const CapabilityOperationEventKind CAPABILITY_OPERATION_EVENT_KIND_LORA_FAILED = CapabilityOperationEventKind._(18, _omitEnumNames ? '' : 'CAPABILITY_OPERATION_EVENT_KIND_LORA_FAILED');

  static const $core.List<CapabilityOperationEventKind> values = <CapabilityOperationEventKind> [
    CAPABILITY_OPERATION_EVENT_KIND_UNSPECIFIED,
    CAPABILITY_OPERATION_EVENT_KIND_VLM_STARTED,
    CAPABILITY_OPERATION_EVENT_KIND_VLM_COMPLETED,
    CAPABILITY_OPERATION_EVENT_KIND_VLM_FAILED,
    CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_STARTED,
    CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_PROGRESS,
    CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_COMPLETED,
    CAPABILITY_OPERATION_EVENT_KIND_DIFFUSION_FAILED,
    CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_STARTED,
    CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_COMPLETED,
    CAPABILITY_OPERATION_EVENT_KIND_EMBEDDINGS_FAILED,
    CAPABILITY_OPERATION_EVENT_KIND_RAG_INGESTION_STARTED,
    CAPABILITY_OPERATION_EVENT_KIND_RAG_INGESTION_COMPLETED,
    CAPABILITY_OPERATION_EVENT_KIND_RAG_QUERY_STARTED,
    CAPABILITY_OPERATION_EVENT_KIND_RAG_QUERY_COMPLETED,
    CAPABILITY_OPERATION_EVENT_KIND_RAG_FAILED,
    CAPABILITY_OPERATION_EVENT_KIND_LORA_ATTACHED,
    CAPABILITY_OPERATION_EVENT_KIND_LORA_DETACHED,
    CAPABILITY_OPERATION_EVENT_KIND_LORA_FAILED,
  ];

  static final $core.Map<$core.int, CapabilityOperationEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static CapabilityOperationEventKind? valueOf($core.int value) => _byValue[value];

  const CapabilityOperationEventKind._($core.int v, $core.String n) : super(v, n);
}

class TelemetryEventKind extends $pb.ProtobufEnum {
  static const TelemetryEventKind TELEMETRY_EVENT_KIND_UNSPECIFIED = TelemetryEventKind._(0, _omitEnumNames ? '' : 'TELEMETRY_EVENT_KIND_UNSPECIFIED');
  static const TelemetryEventKind TELEMETRY_EVENT_KIND_COUNTER = TelemetryEventKind._(1, _omitEnumNames ? '' : 'TELEMETRY_EVENT_KIND_COUNTER');
  static const TelemetryEventKind TELEMETRY_EVENT_KIND_GAUGE = TelemetryEventKind._(2, _omitEnumNames ? '' : 'TELEMETRY_EVENT_KIND_GAUGE');
  static const TelemetryEventKind TELEMETRY_EVENT_KIND_HISTOGRAM = TelemetryEventKind._(3, _omitEnumNames ? '' : 'TELEMETRY_EVENT_KIND_HISTOGRAM');
  static const TelemetryEventKind TELEMETRY_EVENT_KIND_TRACE = TelemetryEventKind._(4, _omitEnumNames ? '' : 'TELEMETRY_EVENT_KIND_TRACE');

  static const $core.List<TelemetryEventKind> values = <TelemetryEventKind> [
    TELEMETRY_EVENT_KIND_UNSPECIFIED,
    TELEMETRY_EVENT_KIND_COUNTER,
    TELEMETRY_EVENT_KIND_GAUGE,
    TELEMETRY_EVENT_KIND_HISTOGRAM,
    TELEMETRY_EVENT_KIND_TRACE,
  ];

  static final $core.Map<$core.int, TelemetryEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static TelemetryEventKind? valueOf($core.int value) => _byValue[value];

  const TelemetryEventKind._($core.int v, $core.String n) : super(v, n);
}

class CancellationEventKind extends $pb.ProtobufEnum {
  static const CancellationEventKind CANCELLATION_EVENT_KIND_UNSPECIFIED = CancellationEventKind._(0, _omitEnumNames ? '' : 'CANCELLATION_EVENT_KIND_UNSPECIFIED');
  static const CancellationEventKind CANCELLATION_EVENT_KIND_REQUESTED = CancellationEventKind._(1, _omitEnumNames ? '' : 'CANCELLATION_EVENT_KIND_REQUESTED');
  static const CancellationEventKind CANCELLATION_EVENT_KIND_ACKNOWLEDGED = CancellationEventKind._(2, _omitEnumNames ? '' : 'CANCELLATION_EVENT_KIND_ACKNOWLEDGED');
  static const CancellationEventKind CANCELLATION_EVENT_KIND_COMPLETED = CancellationEventKind._(3, _omitEnumNames ? '' : 'CANCELLATION_EVENT_KIND_COMPLETED');
  static const CancellationEventKind CANCELLATION_EVENT_KIND_FAILED = CancellationEventKind._(4, _omitEnumNames ? '' : 'CANCELLATION_EVENT_KIND_FAILED');

  static const $core.List<CancellationEventKind> values = <CancellationEventKind> [
    CANCELLATION_EVENT_KIND_UNSPECIFIED,
    CANCELLATION_EVENT_KIND_REQUESTED,
    CANCELLATION_EVENT_KIND_ACKNOWLEDGED,
    CANCELLATION_EVENT_KIND_COMPLETED,
    CANCELLATION_EVENT_KIND_FAILED,
  ];

  static final $core.Map<$core.int, CancellationEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static CancellationEventKind? valueOf($core.int value) => _byValue[value];

  const CancellationEventKind._($core.int v, $core.String n) : super(v, n);
}


const _omitEnumNames = $core.bool.fromEnvironment('protobuf.omit_enum_names');
