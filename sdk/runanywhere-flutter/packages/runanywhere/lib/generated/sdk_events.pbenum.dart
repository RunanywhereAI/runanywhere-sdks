///
//  Generated code. Do not modify.
//  source: sdk_events.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

// ignore_for_file: UNDEFINED_SHOWN_NAME
import 'dart:core' as $core;
import 'package:protobuf/protobuf.dart' as $pb;

class SDKComponent extends $pb.ProtobufEnum {
  static const SDKComponent SDK_COMPONENT_UNSPECIFIED = SDKComponent._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SDK_COMPONENT_UNSPECIFIED');
  static const SDKComponent SDK_COMPONENT_STT = SDKComponent._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SDK_COMPONENT_STT');
  static const SDKComponent SDK_COMPONENT_TTS = SDKComponent._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SDK_COMPONENT_TTS');
  static const SDKComponent SDK_COMPONENT_VAD = SDKComponent._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SDK_COMPONENT_VAD');
  static const SDKComponent SDK_COMPONENT_LLM = SDKComponent._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SDK_COMPONENT_LLM');
  static const SDKComponent SDK_COMPONENT_VLM = SDKComponent._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SDK_COMPONENT_VLM');
  static const SDKComponent SDK_COMPONENT_DIFFUSION = SDKComponent._(6, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SDK_COMPONENT_DIFFUSION');
  static const SDKComponent SDK_COMPONENT_RAG = SDKComponent._(7, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SDK_COMPONENT_RAG');
  static const SDKComponent SDK_COMPONENT_EMBEDDINGS = SDKComponent._(8, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SDK_COMPONENT_EMBEDDINGS');
  static const SDKComponent SDK_COMPONENT_VOICE_AGENT = SDKComponent._(9, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SDK_COMPONENT_VOICE_AGENT');
  static const SDKComponent SDK_COMPONENT_WAKEWORD = SDKComponent._(10, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SDK_COMPONENT_WAKEWORD');
  static const SDKComponent SDK_COMPONENT_SPEAKER_DIARIZATION = SDKComponent._(11, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'SDK_COMPONENT_SPEAKER_DIARIZATION');

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

class EventSeverity extends $pb.ProtobufEnum {
  static const EventSeverity EVENT_SEVERITY_DEBUG = EventSeverity._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'EVENT_SEVERITY_DEBUG');
  static const EventSeverity EVENT_SEVERITY_INFO = EventSeverity._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'EVENT_SEVERITY_INFO');
  static const EventSeverity EVENT_SEVERITY_WARNING = EventSeverity._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'EVENT_SEVERITY_WARNING');
  static const EventSeverity EVENT_SEVERITY_ERROR = EventSeverity._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'EVENT_SEVERITY_ERROR');
  static const EventSeverity EVENT_SEVERITY_CRITICAL = EventSeverity._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'EVENT_SEVERITY_CRITICAL');

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

class EventDestination extends $pb.ProtobufEnum {
  static const EventDestination EVENT_DESTINATION_UNSPECIFIED = EventDestination._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'EVENT_DESTINATION_UNSPECIFIED');
  static const EventDestination EVENT_DESTINATION_ALL = EventDestination._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'EVENT_DESTINATION_ALL');
  static const EventDestination EVENT_DESTINATION_PUBLIC_ONLY = EventDestination._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'EVENT_DESTINATION_PUBLIC_ONLY');
  static const EventDestination EVENT_DESTINATION_ANALYTICS_ONLY = EventDestination._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'EVENT_DESTINATION_ANALYTICS_ONLY');

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

class InitializationStage extends $pb.ProtobufEnum {
  static const InitializationStage INITIALIZATION_STAGE_UNSPECIFIED = InitializationStage._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INITIALIZATION_STAGE_UNSPECIFIED');
  static const InitializationStage INITIALIZATION_STAGE_STARTED = InitializationStage._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INITIALIZATION_STAGE_STARTED');
  static const InitializationStage INITIALIZATION_STAGE_CONFIGURATION_LOADED = InitializationStage._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INITIALIZATION_STAGE_CONFIGURATION_LOADED');
  static const InitializationStage INITIALIZATION_STAGE_SERVICES_BOOTSTRAPPED = InitializationStage._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INITIALIZATION_STAGE_SERVICES_BOOTSTRAPPED');
  static const InitializationStage INITIALIZATION_STAGE_COMPLETED = InitializationStage._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INITIALIZATION_STAGE_COMPLETED');
  static const InitializationStage INITIALIZATION_STAGE_FAILED = InitializationStage._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INITIALIZATION_STAGE_FAILED');
  static const InitializationStage INITIALIZATION_STAGE_SHUTDOWN = InitializationStage._(6, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'INITIALIZATION_STAGE_SHUTDOWN');

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
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_UNSPECIFIED = ConfigurationEventKind._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'CONFIGURATION_EVENT_KIND_UNSPECIFIED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_FETCH_STARTED = ConfigurationEventKind._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'CONFIGURATION_EVENT_KIND_FETCH_STARTED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_FETCH_COMPLETED = ConfigurationEventKind._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'CONFIGURATION_EVENT_KIND_FETCH_COMPLETED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_FETCH_FAILED = ConfigurationEventKind._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'CONFIGURATION_EVENT_KIND_FETCH_FAILED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_LOADED = ConfigurationEventKind._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'CONFIGURATION_EVENT_KIND_LOADED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_UPDATED = ConfigurationEventKind._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'CONFIGURATION_EVENT_KIND_UPDATED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_SYNC_STARTED = ConfigurationEventKind._(6, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'CONFIGURATION_EVENT_KIND_SYNC_STARTED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_SYNC_COMPLETED = ConfigurationEventKind._(7, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'CONFIGURATION_EVENT_KIND_SYNC_COMPLETED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_SYNC_FAILED = ConfigurationEventKind._(8, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'CONFIGURATION_EVENT_KIND_SYNC_FAILED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_SYNC_REQUESTED = ConfigurationEventKind._(9, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'CONFIGURATION_EVENT_KIND_SYNC_REQUESTED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_SETTINGS_REQUESTED = ConfigurationEventKind._(10, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'CONFIGURATION_EVENT_KIND_SETTINGS_REQUESTED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_SETTINGS_RETRIEVED = ConfigurationEventKind._(11, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'CONFIGURATION_EVENT_KIND_SETTINGS_RETRIEVED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_ROUTING_POLICY_REQUESTED = ConfigurationEventKind._(12, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'CONFIGURATION_EVENT_KIND_ROUTING_POLICY_REQUESTED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_ROUTING_POLICY_RETRIEVED = ConfigurationEventKind._(13, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'CONFIGURATION_EVENT_KIND_ROUTING_POLICY_RETRIEVED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_PRIVACY_MODE_REQUESTED = ConfigurationEventKind._(14, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'CONFIGURATION_EVENT_KIND_PRIVACY_MODE_REQUESTED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_PRIVACY_MODE_RETRIEVED = ConfigurationEventKind._(15, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'CONFIGURATION_EVENT_KIND_PRIVACY_MODE_RETRIEVED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_ANALYTICS_STATUS_REQUESTED = ConfigurationEventKind._(16, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'CONFIGURATION_EVENT_KIND_ANALYTICS_STATUS_REQUESTED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_ANALYTICS_STATUS_RETRIEVED = ConfigurationEventKind._(17, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'CONFIGURATION_EVENT_KIND_ANALYTICS_STATUS_RETRIEVED');
  static const ConfigurationEventKind CONFIGURATION_EVENT_KIND_CHANGED = ConfigurationEventKind._(18, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'CONFIGURATION_EVENT_KIND_CHANGED');

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
  static const GenerationEventKind GENERATION_EVENT_KIND_UNSPECIFIED = GenerationEventKind._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'GENERATION_EVENT_KIND_UNSPECIFIED');
  static const GenerationEventKind GENERATION_EVENT_KIND_SESSION_STARTED = GenerationEventKind._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'GENERATION_EVENT_KIND_SESSION_STARTED');
  static const GenerationEventKind GENERATION_EVENT_KIND_SESSION_ENDED = GenerationEventKind._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'GENERATION_EVENT_KIND_SESSION_ENDED');
  static const GenerationEventKind GENERATION_EVENT_KIND_STARTED = GenerationEventKind._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'GENERATION_EVENT_KIND_STARTED');
  static const GenerationEventKind GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED = GenerationEventKind._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED');
  static const GenerationEventKind GENERATION_EVENT_KIND_TOKEN_GENERATED = GenerationEventKind._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'GENERATION_EVENT_KIND_TOKEN_GENERATED');
  static const GenerationEventKind GENERATION_EVENT_KIND_STREAMING_UPDATE = GenerationEventKind._(6, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'GENERATION_EVENT_KIND_STREAMING_UPDATE');
  static const GenerationEventKind GENERATION_EVENT_KIND_COMPLETED = GenerationEventKind._(7, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'GENERATION_EVENT_KIND_COMPLETED');
  static const GenerationEventKind GENERATION_EVENT_KIND_FAILED = GenerationEventKind._(8, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'GENERATION_EVENT_KIND_FAILED');
  static const GenerationEventKind GENERATION_EVENT_KIND_MODEL_LOADED = GenerationEventKind._(9, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'GENERATION_EVENT_KIND_MODEL_LOADED');
  static const GenerationEventKind GENERATION_EVENT_KIND_MODEL_UNLOADED = GenerationEventKind._(10, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'GENERATION_EVENT_KIND_MODEL_UNLOADED');
  static const GenerationEventKind GENERATION_EVENT_KIND_COST_CALCULATED = GenerationEventKind._(11, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'GENERATION_EVENT_KIND_COST_CALCULATED');
  static const GenerationEventKind GENERATION_EVENT_KIND_ROUTING_DECISION = GenerationEventKind._(12, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'GENERATION_EVENT_KIND_ROUTING_DECISION');
  static const GenerationEventKind GENERATION_EVENT_KIND_STREAM_COMPLETED = GenerationEventKind._(13, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'GENERATION_EVENT_KIND_STREAM_COMPLETED');

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
  ];

  static final $core.Map<$core.int, GenerationEventKind> _byValue = $pb.ProtobufEnum.initByValue(values);
  static GenerationEventKind? valueOf($core.int value) => _byValue[value];

  const GenerationEventKind._($core.int v, $core.String n) : super(v, n);
}

class ModelEventKind extends $pb.ProtobufEnum {
  static const ModelEventKind MODEL_EVENT_KIND_UNSPECIFIED = ModelEventKind._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_EVENT_KIND_UNSPECIFIED');
  static const ModelEventKind MODEL_EVENT_KIND_LOAD_STARTED = ModelEventKind._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_EVENT_KIND_LOAD_STARTED');
  static const ModelEventKind MODEL_EVENT_KIND_LOAD_PROGRESS = ModelEventKind._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_EVENT_KIND_LOAD_PROGRESS');
  static const ModelEventKind MODEL_EVENT_KIND_LOAD_COMPLETED = ModelEventKind._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_EVENT_KIND_LOAD_COMPLETED');
  static const ModelEventKind MODEL_EVENT_KIND_LOAD_FAILED = ModelEventKind._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_EVENT_KIND_LOAD_FAILED');
  static const ModelEventKind MODEL_EVENT_KIND_UNLOAD_STARTED = ModelEventKind._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_EVENT_KIND_UNLOAD_STARTED');
  static const ModelEventKind MODEL_EVENT_KIND_UNLOAD_COMPLETED = ModelEventKind._(6, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_EVENT_KIND_UNLOAD_COMPLETED');
  static const ModelEventKind MODEL_EVENT_KIND_UNLOAD_FAILED = ModelEventKind._(7, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_EVENT_KIND_UNLOAD_FAILED');
  static const ModelEventKind MODEL_EVENT_KIND_DOWNLOAD_STARTED = ModelEventKind._(8, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_EVENT_KIND_DOWNLOAD_STARTED');
  static const ModelEventKind MODEL_EVENT_KIND_DOWNLOAD_PROGRESS = ModelEventKind._(9, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_EVENT_KIND_DOWNLOAD_PROGRESS');
  static const ModelEventKind MODEL_EVENT_KIND_DOWNLOAD_COMPLETED = ModelEventKind._(10, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_EVENT_KIND_DOWNLOAD_COMPLETED');
  static const ModelEventKind MODEL_EVENT_KIND_DOWNLOAD_FAILED = ModelEventKind._(11, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_EVENT_KIND_DOWNLOAD_FAILED');
  static const ModelEventKind MODEL_EVENT_KIND_DOWNLOAD_CANCELLED = ModelEventKind._(12, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_EVENT_KIND_DOWNLOAD_CANCELLED');
  static const ModelEventKind MODEL_EVENT_KIND_LIST_REQUESTED = ModelEventKind._(13, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_EVENT_KIND_LIST_REQUESTED');
  static const ModelEventKind MODEL_EVENT_KIND_LIST_COMPLETED = ModelEventKind._(14, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_EVENT_KIND_LIST_COMPLETED');
  static const ModelEventKind MODEL_EVENT_KIND_LIST_FAILED = ModelEventKind._(15, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_EVENT_KIND_LIST_FAILED');
  static const ModelEventKind MODEL_EVENT_KIND_CATALOG_LOADED = ModelEventKind._(16, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_EVENT_KIND_CATALOG_LOADED');
  static const ModelEventKind MODEL_EVENT_KIND_DELETE_STARTED = ModelEventKind._(17, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_EVENT_KIND_DELETE_STARTED');
  static const ModelEventKind MODEL_EVENT_KIND_DELETE_COMPLETED = ModelEventKind._(18, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_EVENT_KIND_DELETE_COMPLETED');
  static const ModelEventKind MODEL_EVENT_KIND_DELETE_FAILED = ModelEventKind._(19, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_EVENT_KIND_DELETE_FAILED');
  static const ModelEventKind MODEL_EVENT_KIND_CUSTOM_MODEL_ADDED = ModelEventKind._(20, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_EVENT_KIND_CUSTOM_MODEL_ADDED');
  static const ModelEventKind MODEL_EVENT_KIND_BUILT_IN_REGISTERED = ModelEventKind._(21, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'MODEL_EVENT_KIND_BUILT_IN_REGISTERED');

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
  static const VoiceEventKind VOICE_EVENT_KIND_UNSPECIFIED = VoiceEventKind._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_UNSPECIFIED');
  static const VoiceEventKind VOICE_EVENT_KIND_LISTENING_STARTED = VoiceEventKind._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_LISTENING_STARTED');
  static const VoiceEventKind VOICE_EVENT_KIND_LISTENING_ENDED = VoiceEventKind._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_LISTENING_ENDED');
  static const VoiceEventKind VOICE_EVENT_KIND_SPEECH_DETECTED = VoiceEventKind._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_SPEECH_DETECTED');
  static const VoiceEventKind VOICE_EVENT_KIND_TRANSCRIPTION_STARTED = VoiceEventKind._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_TRANSCRIPTION_STARTED');
  static const VoiceEventKind VOICE_EVENT_KIND_TRANSCRIPTION_PARTIAL = VoiceEventKind._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_TRANSCRIPTION_PARTIAL');
  static const VoiceEventKind VOICE_EVENT_KIND_TRANSCRIPTION_FINAL = VoiceEventKind._(6, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_TRANSCRIPTION_FINAL');
  static const VoiceEventKind VOICE_EVENT_KIND_RESPONSE_GENERATED = VoiceEventKind._(7, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_RESPONSE_GENERATED');
  static const VoiceEventKind VOICE_EVENT_KIND_SYNTHESIS_STARTED = VoiceEventKind._(8, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_SYNTHESIS_STARTED');
  static const VoiceEventKind VOICE_EVENT_KIND_AUDIO_GENERATED = VoiceEventKind._(9, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_AUDIO_GENERATED');
  static const VoiceEventKind VOICE_EVENT_KIND_SYNTHESIS_COMPLETED = VoiceEventKind._(10, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_SYNTHESIS_COMPLETED');
  static const VoiceEventKind VOICE_EVENT_KIND_SYNTHESIS_FAILED = VoiceEventKind._(11, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_SYNTHESIS_FAILED');
  static const VoiceEventKind VOICE_EVENT_KIND_PIPELINE_STARTED = VoiceEventKind._(12, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_PIPELINE_STARTED');
  static const VoiceEventKind VOICE_EVENT_KIND_PIPELINE_COMPLETED = VoiceEventKind._(13, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_PIPELINE_COMPLETED');
  static const VoiceEventKind VOICE_EVENT_KIND_PIPELINE_ERROR = VoiceEventKind._(14, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_PIPELINE_ERROR');
  static const VoiceEventKind VOICE_EVENT_KIND_VAD_STARTED = VoiceEventKind._(15, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_VAD_STARTED');
  static const VoiceEventKind VOICE_EVENT_KIND_VAD_DETECTED = VoiceEventKind._(16, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_VAD_DETECTED');
  static const VoiceEventKind VOICE_EVENT_KIND_VAD_ENDED = VoiceEventKind._(17, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_VAD_ENDED');
  static const VoiceEventKind VOICE_EVENT_KIND_VAD_INITIALIZED = VoiceEventKind._(18, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_VAD_INITIALIZED');
  static const VoiceEventKind VOICE_EVENT_KIND_VAD_STOPPED = VoiceEventKind._(19, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_VAD_STOPPED');
  static const VoiceEventKind VOICE_EVENT_KIND_VAD_CLEANED_UP = VoiceEventKind._(20, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_VAD_CLEANED_UP');
  static const VoiceEventKind VOICE_EVENT_KIND_SPEECH_STARTED = VoiceEventKind._(21, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_SPEECH_STARTED');
  static const VoiceEventKind VOICE_EVENT_KIND_SPEECH_ENDED = VoiceEventKind._(22, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_SPEECH_ENDED');
  static const VoiceEventKind VOICE_EVENT_KIND_STT_PROCESSING = VoiceEventKind._(23, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_STT_PROCESSING');
  static const VoiceEventKind VOICE_EVENT_KIND_STT_PARTIAL_RESULT = VoiceEventKind._(24, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_STT_PARTIAL_RESULT');
  static const VoiceEventKind VOICE_EVENT_KIND_STT_COMPLETED = VoiceEventKind._(25, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_STT_COMPLETED');
  static const VoiceEventKind VOICE_EVENT_KIND_STT_FAILED = VoiceEventKind._(26, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_STT_FAILED');
  static const VoiceEventKind VOICE_EVENT_KIND_LLM_PROCESSING = VoiceEventKind._(27, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_LLM_PROCESSING');
  static const VoiceEventKind VOICE_EVENT_KIND_TTS_PROCESSING = VoiceEventKind._(28, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_TTS_PROCESSING');
  static const VoiceEventKind VOICE_EVENT_KIND_RECORDING_STARTED = VoiceEventKind._(29, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_RECORDING_STARTED');
  static const VoiceEventKind VOICE_EVENT_KIND_RECORDING_STOPPED = VoiceEventKind._(30, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_RECORDING_STOPPED');
  static const VoiceEventKind VOICE_EVENT_KIND_PLAYBACK_STARTED = VoiceEventKind._(31, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_PLAYBACK_STARTED');
  static const VoiceEventKind VOICE_EVENT_KIND_PLAYBACK_COMPLETED = VoiceEventKind._(32, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_PLAYBACK_COMPLETED');
  static const VoiceEventKind VOICE_EVENT_KIND_PLAYBACK_STOPPED = VoiceEventKind._(33, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_PLAYBACK_STOPPED');
  static const VoiceEventKind VOICE_EVENT_KIND_PLAYBACK_PAUSED = VoiceEventKind._(34, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_PLAYBACK_PAUSED');
  static const VoiceEventKind VOICE_EVENT_KIND_PLAYBACK_RESUMED = VoiceEventKind._(35, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_PLAYBACK_RESUMED');
  static const VoiceEventKind VOICE_EVENT_KIND_PLAYBACK_FAILED = VoiceEventKind._(36, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_PLAYBACK_FAILED');
  static const VoiceEventKind VOICE_EVENT_KIND_VOICE_SESSION_STARTED = VoiceEventKind._(37, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_VOICE_SESSION_STARTED');
  static const VoiceEventKind VOICE_EVENT_KIND_VOICE_SESSION_LISTENING = VoiceEventKind._(38, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_VOICE_SESSION_LISTENING');
  static const VoiceEventKind VOICE_EVENT_KIND_VOICE_SESSION_SPEECH_STARTED = VoiceEventKind._(39, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_VOICE_SESSION_SPEECH_STARTED');
  static const VoiceEventKind VOICE_EVENT_KIND_VOICE_SESSION_SPEECH_ENDED = VoiceEventKind._(40, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_VOICE_SESSION_SPEECH_ENDED');
  static const VoiceEventKind VOICE_EVENT_KIND_VOICE_SESSION_PROCESSING = VoiceEventKind._(41, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_VOICE_SESSION_PROCESSING');
  static const VoiceEventKind VOICE_EVENT_KIND_VOICE_SESSION_TRANSCRIBED = VoiceEventKind._(42, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_VOICE_SESSION_TRANSCRIBED');
  static const VoiceEventKind VOICE_EVENT_KIND_VOICE_SESSION_RESPONDED = VoiceEventKind._(43, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_VOICE_SESSION_RESPONDED');
  static const VoiceEventKind VOICE_EVENT_KIND_VOICE_SESSION_SPEAKING = VoiceEventKind._(44, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_VOICE_SESSION_SPEAKING');
  static const VoiceEventKind VOICE_EVENT_KIND_VOICE_SESSION_TURN_COMPLETED = VoiceEventKind._(45, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_VOICE_SESSION_TURN_COMPLETED');
  static const VoiceEventKind VOICE_EVENT_KIND_VOICE_SESSION_STOPPED = VoiceEventKind._(46, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_VOICE_SESSION_STOPPED');
  static const VoiceEventKind VOICE_EVENT_KIND_VOICE_SESSION_ERROR = VoiceEventKind._(47, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'VOICE_EVENT_KIND_VOICE_SESSION_ERROR');

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
  static const PerformanceEventKind PERFORMANCE_EVENT_KIND_UNSPECIFIED = PerformanceEventKind._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'PERFORMANCE_EVENT_KIND_UNSPECIFIED');
  static const PerformanceEventKind PERFORMANCE_EVENT_KIND_MEMORY_WARNING = PerformanceEventKind._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'PERFORMANCE_EVENT_KIND_MEMORY_WARNING');
  static const PerformanceEventKind PERFORMANCE_EVENT_KIND_THERMAL_STATE_CHANGED = PerformanceEventKind._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'PERFORMANCE_EVENT_KIND_THERMAL_STATE_CHANGED');
  static const PerformanceEventKind PERFORMANCE_EVENT_KIND_LATENCY_MEASURED = PerformanceEventKind._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'PERFORMANCE_EVENT_KIND_LATENCY_MEASURED');
  static const PerformanceEventKind PERFORMANCE_EVENT_KIND_THROUGHPUT_MEASURED = PerformanceEventKind._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'PERFORMANCE_EVENT_KIND_THROUGHPUT_MEASURED');

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
  static const NetworkEventKind NETWORK_EVENT_KIND_UNSPECIFIED = NetworkEventKind._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'NETWORK_EVENT_KIND_UNSPECIFIED');
  static const NetworkEventKind NETWORK_EVENT_KIND_REQUEST_STARTED = NetworkEventKind._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'NETWORK_EVENT_KIND_REQUEST_STARTED');
  static const NetworkEventKind NETWORK_EVENT_KIND_REQUEST_COMPLETED = NetworkEventKind._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'NETWORK_EVENT_KIND_REQUEST_COMPLETED');
  static const NetworkEventKind NETWORK_EVENT_KIND_REQUEST_FAILED = NetworkEventKind._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'NETWORK_EVENT_KIND_REQUEST_FAILED');
  static const NetworkEventKind NETWORK_EVENT_KIND_REQUEST_TIMEOUT = NetworkEventKind._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'NETWORK_EVENT_KIND_REQUEST_TIMEOUT');
  static const NetworkEventKind NETWORK_EVENT_KIND_CONNECTIVITY_CHANGED = NetworkEventKind._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'NETWORK_EVENT_KIND_CONNECTIVITY_CHANGED');

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
  static const StorageEventKind STORAGE_EVENT_KIND_UNSPECIFIED = StorageEventKind._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STORAGE_EVENT_KIND_UNSPECIFIED');
  static const StorageEventKind STORAGE_EVENT_KIND_INFO_REQUESTED = StorageEventKind._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STORAGE_EVENT_KIND_INFO_REQUESTED');
  static const StorageEventKind STORAGE_EVENT_KIND_INFO_RETRIEVED = StorageEventKind._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STORAGE_EVENT_KIND_INFO_RETRIEVED');
  static const StorageEventKind STORAGE_EVENT_KIND_MODELS_REQUESTED = StorageEventKind._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STORAGE_EVENT_KIND_MODELS_REQUESTED');
  static const StorageEventKind STORAGE_EVENT_KIND_MODELS_RETRIEVED = StorageEventKind._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STORAGE_EVENT_KIND_MODELS_RETRIEVED');
  static const StorageEventKind STORAGE_EVENT_KIND_CLEAR_CACHE_STARTED = StorageEventKind._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STORAGE_EVENT_KIND_CLEAR_CACHE_STARTED');
  static const StorageEventKind STORAGE_EVENT_KIND_CLEAR_CACHE_COMPLETED = StorageEventKind._(6, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STORAGE_EVENT_KIND_CLEAR_CACHE_COMPLETED');
  static const StorageEventKind STORAGE_EVENT_KIND_CLEAR_CACHE_FAILED = StorageEventKind._(7, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STORAGE_EVENT_KIND_CLEAR_CACHE_FAILED');
  static const StorageEventKind STORAGE_EVENT_KIND_CLEAN_TEMP_STARTED = StorageEventKind._(8, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STORAGE_EVENT_KIND_CLEAN_TEMP_STARTED');
  static const StorageEventKind STORAGE_EVENT_KIND_CLEAN_TEMP_COMPLETED = StorageEventKind._(9, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STORAGE_EVENT_KIND_CLEAN_TEMP_COMPLETED');
  static const StorageEventKind STORAGE_EVENT_KIND_CLEAN_TEMP_FAILED = StorageEventKind._(10, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STORAGE_EVENT_KIND_CLEAN_TEMP_FAILED');
  static const StorageEventKind STORAGE_EVENT_KIND_DELETE_MODEL_STARTED = StorageEventKind._(11, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STORAGE_EVENT_KIND_DELETE_MODEL_STARTED');
  static const StorageEventKind STORAGE_EVENT_KIND_DELETE_MODEL_COMPLETED = StorageEventKind._(12, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STORAGE_EVENT_KIND_DELETE_MODEL_COMPLETED');
  static const StorageEventKind STORAGE_EVENT_KIND_DELETE_MODEL_FAILED = StorageEventKind._(13, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STORAGE_EVENT_KIND_DELETE_MODEL_FAILED');
  static const StorageEventKind STORAGE_EVENT_KIND_CACHE_HIT = StorageEventKind._(14, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STORAGE_EVENT_KIND_CACHE_HIT');
  static const StorageEventKind STORAGE_EVENT_KIND_CACHE_MISS = StorageEventKind._(15, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STORAGE_EVENT_KIND_CACHE_MISS');
  static const StorageEventKind STORAGE_EVENT_KIND_EVICTION = StorageEventKind._(16, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STORAGE_EVENT_KIND_EVICTION');
  static const StorageEventKind STORAGE_EVENT_KIND_DISK_FULL = StorageEventKind._(17, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'STORAGE_EVENT_KIND_DISK_FULL');

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
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_UNSPECIFIED = FrameworkEventKind._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'FRAMEWORK_EVENT_KIND_UNSPECIFIED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_ADAPTER_REGISTERED = FrameworkEventKind._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'FRAMEWORK_EVENT_KIND_ADAPTER_REGISTERED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_ADAPTER_UNREGISTERED = FrameworkEventKind._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'FRAMEWORK_EVENT_KIND_ADAPTER_UNREGISTERED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_ADAPTERS_REQUESTED = FrameworkEventKind._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'FRAMEWORK_EVENT_KIND_ADAPTERS_REQUESTED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_ADAPTERS_RETRIEVED = FrameworkEventKind._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'FRAMEWORK_EVENT_KIND_ADAPTERS_RETRIEVED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_FRAMEWORKS_REQUESTED = FrameworkEventKind._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'FRAMEWORK_EVENT_KIND_FRAMEWORKS_REQUESTED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_FRAMEWORKS_RETRIEVED = FrameworkEventKind._(6, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'FRAMEWORK_EVENT_KIND_FRAMEWORKS_RETRIEVED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_AVAILABILITY_REQUESTED = FrameworkEventKind._(7, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'FRAMEWORK_EVENT_KIND_AVAILABILITY_REQUESTED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_AVAILABILITY_RETRIEVED = FrameworkEventKind._(8, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'FRAMEWORK_EVENT_KIND_AVAILABILITY_RETRIEVED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_MODELS_FOR_FRAMEWORK_REQUESTED = FrameworkEventKind._(9, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'FRAMEWORK_EVENT_KIND_MODELS_FOR_FRAMEWORK_REQUESTED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_MODELS_FOR_FRAMEWORK_RETRIEVED = FrameworkEventKind._(10, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'FRAMEWORK_EVENT_KIND_MODELS_FOR_FRAMEWORK_RETRIEVED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_FRAMEWORKS_FOR_MODALITY_REQUESTED = FrameworkEventKind._(11, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'FRAMEWORK_EVENT_KIND_FRAMEWORKS_FOR_MODALITY_REQUESTED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_FRAMEWORKS_FOR_MODALITY_RETRIEVED = FrameworkEventKind._(12, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'FRAMEWORK_EVENT_KIND_FRAMEWORKS_FOR_MODALITY_RETRIEVED');
  static const FrameworkEventKind FRAMEWORK_EVENT_KIND_ERROR = FrameworkEventKind._(13, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'FRAMEWORK_EVENT_KIND_ERROR');

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
  static const DeviceEventKind DEVICE_EVENT_KIND_UNSPECIFIED = DeviceEventKind._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DEVICE_EVENT_KIND_UNSPECIFIED');
  static const DeviceEventKind DEVICE_EVENT_KIND_DEVICE_INFO_COLLECTED = DeviceEventKind._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DEVICE_EVENT_KIND_DEVICE_INFO_COLLECTED');
  static const DeviceEventKind DEVICE_EVENT_KIND_DEVICE_INFO_COLLECTION_FAILED = DeviceEventKind._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DEVICE_EVENT_KIND_DEVICE_INFO_COLLECTION_FAILED');
  static const DeviceEventKind DEVICE_EVENT_KIND_DEVICE_INFO_REFRESHED = DeviceEventKind._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DEVICE_EVENT_KIND_DEVICE_INFO_REFRESHED');
  static const DeviceEventKind DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_STARTED = DeviceEventKind._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_STARTED');
  static const DeviceEventKind DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_COMPLETED = DeviceEventKind._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_COMPLETED');
  static const DeviceEventKind DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_FAILED = DeviceEventKind._(6, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_FAILED');
  static const DeviceEventKind DEVICE_EVENT_KIND_DEVICE_STATE_CHANGED = DeviceEventKind._(7, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DEVICE_EVENT_KIND_DEVICE_STATE_CHANGED');
  static const DeviceEventKind DEVICE_EVENT_KIND_BATTERY_CHANGED = DeviceEventKind._(8, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DEVICE_EVENT_KIND_BATTERY_CHANGED');
  static const DeviceEventKind DEVICE_EVENT_KIND_THERMAL_CHANGED = DeviceEventKind._(9, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DEVICE_EVENT_KIND_THERMAL_CHANGED');
  static const DeviceEventKind DEVICE_EVENT_KIND_CONNECTIVITY_CHANGED = DeviceEventKind._(10, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DEVICE_EVENT_KIND_CONNECTIVITY_CHANGED');
  static const DeviceEventKind DEVICE_EVENT_KIND_DEVICE_REGISTERED = DeviceEventKind._(11, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DEVICE_EVENT_KIND_DEVICE_REGISTERED');
  static const DeviceEventKind DEVICE_EVENT_KIND_DEVICE_REGISTRATION_FAILED = DeviceEventKind._(12, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'DEVICE_EVENT_KIND_DEVICE_REGISTRATION_FAILED');

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
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_UNSPECIFIED = ComponentInitializationEventKind._(0, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'COMPONENT_INIT_EVENT_KIND_UNSPECIFIED');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_INITIALIZATION_STARTED = ComponentInitializationEventKind._(1, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'COMPONENT_INIT_EVENT_KIND_INITIALIZATION_STARTED');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_INITIALIZATION_COMPLETED = ComponentInitializationEventKind._(2, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'COMPONENT_INIT_EVENT_KIND_INITIALIZATION_COMPLETED');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_COMPONENT_STATE_CHANGED = ComponentInitializationEventKind._(3, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'COMPONENT_INIT_EVENT_KIND_COMPONENT_STATE_CHANGED');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_COMPONENT_CHECKING = ComponentInitializationEventKind._(4, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'COMPONENT_INIT_EVENT_KIND_COMPONENT_CHECKING');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_REQUIRED = ComponentInitializationEventKind._(5, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_REQUIRED');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_STARTED = ComponentInitializationEventKind._(6, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_STARTED');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_PROGRESS = ComponentInitializationEventKind._(7, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_PROGRESS');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_COMPLETED = ComponentInitializationEventKind._(8, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_COMPLETED');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_COMPONENT_INITIALIZING = ComponentInitializationEventKind._(9, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'COMPONENT_INIT_EVENT_KIND_COMPONENT_INITIALIZING');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_COMPONENT_READY = ComponentInitializationEventKind._(10, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'COMPONENT_INIT_EVENT_KIND_COMPONENT_READY');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_COMPONENT_FAILED = ComponentInitializationEventKind._(11, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'COMPONENT_INIT_EVENT_KIND_COMPONENT_FAILED');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_PARALLEL_INIT_STARTED = ComponentInitializationEventKind._(12, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'COMPONENT_INIT_EVENT_KIND_PARALLEL_INIT_STARTED');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_SEQUENTIAL_INIT_STARTED = ComponentInitializationEventKind._(13, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'COMPONENT_INIT_EVENT_KIND_SEQUENTIAL_INIT_STARTED');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_ALL_COMPONENTS_READY = ComponentInitializationEventKind._(14, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'COMPONENT_INIT_EVENT_KIND_ALL_COMPONENTS_READY');
  static const ComponentInitializationEventKind COMPONENT_INIT_EVENT_KIND_SOME_COMPONENTS_READY = ComponentInitializationEventKind._(15, const $core.bool.fromEnvironment('protobuf.omit_enum_names') ? '' : 'COMPONENT_INIT_EVENT_KIND_SOME_COMPONENTS_READY');

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

