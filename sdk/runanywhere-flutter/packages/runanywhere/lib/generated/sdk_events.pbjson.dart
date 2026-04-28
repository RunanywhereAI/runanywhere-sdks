///
//  Generated code. Do not modify.
//  source: sdk_events.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use sDKComponentDescriptor instead')
const SDKComponent$json = const {
  '1': 'SDKComponent',
  '2': const [
    const {'1': 'SDK_COMPONENT_UNSPECIFIED', '2': 0},
    const {'1': 'SDK_COMPONENT_STT', '2': 1},
    const {'1': 'SDK_COMPONENT_TTS', '2': 2},
    const {'1': 'SDK_COMPONENT_VAD', '2': 3},
    const {'1': 'SDK_COMPONENT_LLM', '2': 4},
    const {'1': 'SDK_COMPONENT_VLM', '2': 5},
    const {'1': 'SDK_COMPONENT_DIFFUSION', '2': 6},
    const {'1': 'SDK_COMPONENT_RAG', '2': 7},
    const {'1': 'SDK_COMPONENT_EMBEDDINGS', '2': 8},
    const {'1': 'SDK_COMPONENT_VOICE_AGENT', '2': 9},
    const {'1': 'SDK_COMPONENT_WAKEWORD', '2': 10},
    const {'1': 'SDK_COMPONENT_SPEAKER_DIARIZATION', '2': 11},
  ],
};

/// Descriptor for `SDKComponent`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List sDKComponentDescriptor = $convert.base64Decode('CgxTREtDb21wb25lbnQSHQoZU0RLX0NPTVBPTkVOVF9VTlNQRUNJRklFRBAAEhUKEVNES19DT01QT05FTlRfU1RUEAESFQoRU0RLX0NPTVBPTkVOVF9UVFMQAhIVChFTREtfQ09NUE9ORU5UX1ZBRBADEhUKEVNES19DT01QT05FTlRfTExNEAQSFQoRU0RLX0NPTVBPTkVOVF9WTE0QBRIbChdTREtfQ09NUE9ORU5UX0RJRkZVU0lPThAGEhUKEVNES19DT01QT05FTlRfUkFHEAcSHAoYU0RLX0NPTVBPTkVOVF9FTUJFRERJTkdTEAgSHQoZU0RLX0NPTVBPTkVOVF9WT0lDRV9BR0VOVBAJEhoKFlNES19DT01QT05FTlRfV0FLRVdPUkQQChIlCiFTREtfQ09NUE9ORU5UX1NQRUFLRVJfRElBUklaQVRJT04QCw==');
@$core.Deprecated('Use eventSeverityDescriptor instead')
const EventSeverity$json = const {
  '1': 'EventSeverity',
  '2': const [
    const {'1': 'EVENT_SEVERITY_DEBUG', '2': 0},
    const {'1': 'EVENT_SEVERITY_INFO', '2': 1},
    const {'1': 'EVENT_SEVERITY_WARNING', '2': 2},
    const {'1': 'EVENT_SEVERITY_ERROR', '2': 3},
    const {'1': 'EVENT_SEVERITY_CRITICAL', '2': 4},
  ],
};

/// Descriptor for `EventSeverity`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List eventSeverityDescriptor = $convert.base64Decode('Cg1FdmVudFNldmVyaXR5EhgKFEVWRU5UX1NFVkVSSVRZX0RFQlVHEAASFwoTRVZFTlRfU0VWRVJJVFlfSU5GTxABEhoKFkVWRU5UX1NFVkVSSVRZX1dBUk5JTkcQAhIYChRFVkVOVF9TRVZFUklUWV9FUlJPUhADEhsKF0VWRU5UX1NFVkVSSVRZX0NSSVRJQ0FMEAQ=');
@$core.Deprecated('Use eventDestinationDescriptor instead')
const EventDestination$json = const {
  '1': 'EventDestination',
  '2': const [
    const {'1': 'EVENT_DESTINATION_UNSPECIFIED', '2': 0},
    const {'1': 'EVENT_DESTINATION_ALL', '2': 1},
    const {'1': 'EVENT_DESTINATION_PUBLIC_ONLY', '2': 2},
    const {'1': 'EVENT_DESTINATION_ANALYTICS_ONLY', '2': 3},
  ],
};

/// Descriptor for `EventDestination`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List eventDestinationDescriptor = $convert.base64Decode('ChBFdmVudERlc3RpbmF0aW9uEiEKHUVWRU5UX0RFU1RJTkFUSU9OX1VOU1BFQ0lGSUVEEAASGQoVRVZFTlRfREVTVElOQVRJT05fQUxMEAESIQodRVZFTlRfREVTVElOQVRJT05fUFVCTElDX09OTFkQAhIkCiBFVkVOVF9ERVNUSU5BVElPTl9BTkFMWVRJQ1NfT05MWRAD');
@$core.Deprecated('Use initializationStageDescriptor instead')
const InitializationStage$json = const {
  '1': 'InitializationStage',
  '2': const [
    const {'1': 'INITIALIZATION_STAGE_UNSPECIFIED', '2': 0},
    const {'1': 'INITIALIZATION_STAGE_STARTED', '2': 1},
    const {'1': 'INITIALIZATION_STAGE_CONFIGURATION_LOADED', '2': 2},
    const {'1': 'INITIALIZATION_STAGE_SERVICES_BOOTSTRAPPED', '2': 3},
    const {'1': 'INITIALIZATION_STAGE_COMPLETED', '2': 4},
    const {'1': 'INITIALIZATION_STAGE_FAILED', '2': 5},
    const {'1': 'INITIALIZATION_STAGE_SHUTDOWN', '2': 6},
  ],
};

/// Descriptor for `InitializationStage`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List initializationStageDescriptor = $convert.base64Decode('ChNJbml0aWFsaXphdGlvblN0YWdlEiQKIElOSVRJQUxJWkFUSU9OX1NUQUdFX1VOU1BFQ0lGSUVEEAASIAocSU5JVElBTElaQVRJT05fU1RBR0VfU1RBUlRFRBABEi0KKUlOSVRJQUxJWkFUSU9OX1NUQUdFX0NPTkZJR1VSQVRJT05fTE9BREVEEAISLgoqSU5JVElBTElaQVRJT05fU1RBR0VfU0VSVklDRVNfQk9PVFNUUkFQUEVEEAMSIgoeSU5JVElBTElaQVRJT05fU1RBR0VfQ09NUExFVEVEEAQSHwobSU5JVElBTElaQVRJT05fU1RBR0VfRkFJTEVEEAUSIQodSU5JVElBTElaQVRJT05fU1RBR0VfU0hVVERPV04QBg==');
@$core.Deprecated('Use configurationEventKindDescriptor instead')
const ConfigurationEventKind$json = const {
  '1': 'ConfigurationEventKind',
  '2': const [
    const {'1': 'CONFIGURATION_EVENT_KIND_UNSPECIFIED', '2': 0},
    const {'1': 'CONFIGURATION_EVENT_KIND_FETCH_STARTED', '2': 1},
    const {'1': 'CONFIGURATION_EVENT_KIND_FETCH_COMPLETED', '2': 2},
    const {'1': 'CONFIGURATION_EVENT_KIND_FETCH_FAILED', '2': 3},
    const {'1': 'CONFIGURATION_EVENT_KIND_LOADED', '2': 4},
    const {'1': 'CONFIGURATION_EVENT_KIND_UPDATED', '2': 5},
    const {'1': 'CONFIGURATION_EVENT_KIND_SYNC_STARTED', '2': 6},
    const {'1': 'CONFIGURATION_EVENT_KIND_SYNC_COMPLETED', '2': 7},
    const {'1': 'CONFIGURATION_EVENT_KIND_SYNC_FAILED', '2': 8},
    const {'1': 'CONFIGURATION_EVENT_KIND_SYNC_REQUESTED', '2': 9},
    const {'1': 'CONFIGURATION_EVENT_KIND_SETTINGS_REQUESTED', '2': 10},
    const {'1': 'CONFIGURATION_EVENT_KIND_SETTINGS_RETRIEVED', '2': 11},
    const {'1': 'CONFIGURATION_EVENT_KIND_ROUTING_POLICY_REQUESTED', '2': 12},
    const {'1': 'CONFIGURATION_EVENT_KIND_ROUTING_POLICY_RETRIEVED', '2': 13},
    const {'1': 'CONFIGURATION_EVENT_KIND_PRIVACY_MODE_REQUESTED', '2': 14},
    const {'1': 'CONFIGURATION_EVENT_KIND_PRIVACY_MODE_RETRIEVED', '2': 15},
    const {'1': 'CONFIGURATION_EVENT_KIND_ANALYTICS_STATUS_REQUESTED', '2': 16},
    const {'1': 'CONFIGURATION_EVENT_KIND_ANALYTICS_STATUS_RETRIEVED', '2': 17},
    const {'1': 'CONFIGURATION_EVENT_KIND_CHANGED', '2': 18},
  ],
};

/// Descriptor for `ConfigurationEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List configurationEventKindDescriptor = $convert.base64Decode('ChZDb25maWd1cmF0aW9uRXZlbnRLaW5kEigKJENPTkZJR1VSQVRJT05fRVZFTlRfS0lORF9VTlNQRUNJRklFRBAAEioKJkNPTkZJR1VSQVRJT05fRVZFTlRfS0lORF9GRVRDSF9TVEFSVEVEEAESLAooQ09ORklHVVJBVElPTl9FVkVOVF9LSU5EX0ZFVENIX0NPTVBMRVRFRBACEikKJUNPTkZJR1VSQVRJT05fRVZFTlRfS0lORF9GRVRDSF9GQUlMRUQQAxIjCh9DT05GSUdVUkFUSU9OX0VWRU5UX0tJTkRfTE9BREVEEAQSJAogQ09ORklHVVJBVElPTl9FVkVOVF9LSU5EX1VQREFURUQQBRIpCiVDT05GSUdVUkFUSU9OX0VWRU5UX0tJTkRfU1lOQ19TVEFSVEVEEAYSKwonQ09ORklHVVJBVElPTl9FVkVOVF9LSU5EX1NZTkNfQ09NUExFVEVEEAcSKAokQ09ORklHVVJBVElPTl9FVkVOVF9LSU5EX1NZTkNfRkFJTEVEEAgSKwonQ09ORklHVVJBVElPTl9FVkVOVF9LSU5EX1NZTkNfUkVRVUVTVEVEEAkSLworQ09ORklHVVJBVElPTl9FVkVOVF9LSU5EX1NFVFRJTkdTX1JFUVVFU1RFRBAKEi8KK0NPTkZJR1VSQVRJT05fRVZFTlRfS0lORF9TRVRUSU5HU19SRVRSSUVWRUQQCxI1CjFDT05GSUdVUkFUSU9OX0VWRU5UX0tJTkRfUk9VVElOR19QT0xJQ1lfUkVRVUVTVEVEEAwSNQoxQ09ORklHVVJBVElPTl9FVkVOVF9LSU5EX1JPVVRJTkdfUE9MSUNZX1JFVFJJRVZFRBANEjMKL0NPTkZJR1VSQVRJT05fRVZFTlRfS0lORF9QUklWQUNZX01PREVfUkVRVUVTVEVEEA4SMwovQ09ORklHVVJBVElPTl9FVkVOVF9LSU5EX1BSSVZBQ1lfTU9ERV9SRVRSSUVWRUQQDxI3CjNDT05GSUdVUkFUSU9OX0VWRU5UX0tJTkRfQU5BTFlUSUNTX1NUQVRVU19SRVFVRVNURUQQEBI3CjNDT05GSUdVUkFUSU9OX0VWRU5UX0tJTkRfQU5BTFlUSUNTX1NUQVRVU19SRVRSSUVWRUQQERIkCiBDT05GSUdVUkFUSU9OX0VWRU5UX0tJTkRfQ0hBTkdFRBAS');
@$core.Deprecated('Use generationEventKindDescriptor instead')
const GenerationEventKind$json = const {
  '1': 'GenerationEventKind',
  '2': const [
    const {'1': 'GENERATION_EVENT_KIND_UNSPECIFIED', '2': 0},
    const {'1': 'GENERATION_EVENT_KIND_SESSION_STARTED', '2': 1},
    const {'1': 'GENERATION_EVENT_KIND_SESSION_ENDED', '2': 2},
    const {'1': 'GENERATION_EVENT_KIND_STARTED', '2': 3},
    const {'1': 'GENERATION_EVENT_KIND_FIRST_TOKEN_GENERATED', '2': 4},
    const {'1': 'GENERATION_EVENT_KIND_TOKEN_GENERATED', '2': 5},
    const {'1': 'GENERATION_EVENT_KIND_STREAMING_UPDATE', '2': 6},
    const {'1': 'GENERATION_EVENT_KIND_COMPLETED', '2': 7},
    const {'1': 'GENERATION_EVENT_KIND_FAILED', '2': 8},
    const {'1': 'GENERATION_EVENT_KIND_MODEL_LOADED', '2': 9},
    const {'1': 'GENERATION_EVENT_KIND_MODEL_UNLOADED', '2': 10},
    const {'1': 'GENERATION_EVENT_KIND_COST_CALCULATED', '2': 11},
    const {'1': 'GENERATION_EVENT_KIND_ROUTING_DECISION', '2': 12},
    const {'1': 'GENERATION_EVENT_KIND_STREAM_COMPLETED', '2': 13},
  ],
};

/// Descriptor for `GenerationEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List generationEventKindDescriptor = $convert.base64Decode('ChNHZW5lcmF0aW9uRXZlbnRLaW5kEiUKIUdFTkVSQVRJT05fRVZFTlRfS0lORF9VTlNQRUNJRklFRBAAEikKJUdFTkVSQVRJT05fRVZFTlRfS0lORF9TRVNTSU9OX1NUQVJURUQQARInCiNHRU5FUkFUSU9OX0VWRU5UX0tJTkRfU0VTU0lPTl9FTkRFRBACEiEKHUdFTkVSQVRJT05fRVZFTlRfS0lORF9TVEFSVEVEEAMSLworR0VORVJBVElPTl9FVkVOVF9LSU5EX0ZJUlNUX1RPS0VOX0dFTkVSQVRFRBAEEikKJUdFTkVSQVRJT05fRVZFTlRfS0lORF9UT0tFTl9HRU5FUkFURUQQBRIqCiZHRU5FUkFUSU9OX0VWRU5UX0tJTkRfU1RSRUFNSU5HX1VQREFURRAGEiMKH0dFTkVSQVRJT05fRVZFTlRfS0lORF9DT01QTEVURUQQBxIgChxHRU5FUkFUSU9OX0VWRU5UX0tJTkRfRkFJTEVEEAgSJgoiR0VORVJBVElPTl9FVkVOVF9LSU5EX01PREVMX0xPQURFRBAJEigKJEdFTkVSQVRJT05fRVZFTlRfS0lORF9NT0RFTF9VTkxPQURFRBAKEikKJUdFTkVSQVRJT05fRVZFTlRfS0lORF9DT1NUX0NBTENVTEFURUQQCxIqCiZHRU5FUkFUSU9OX0VWRU5UX0tJTkRfUk9VVElOR19ERUNJU0lPThAMEioKJkdFTkVSQVRJT05fRVZFTlRfS0lORF9TVFJFQU1fQ09NUExFVEVEEA0=');
@$core.Deprecated('Use modelEventKindDescriptor instead')
const ModelEventKind$json = const {
  '1': 'ModelEventKind',
  '2': const [
    const {'1': 'MODEL_EVENT_KIND_UNSPECIFIED', '2': 0},
    const {'1': 'MODEL_EVENT_KIND_LOAD_STARTED', '2': 1},
    const {'1': 'MODEL_EVENT_KIND_LOAD_PROGRESS', '2': 2},
    const {'1': 'MODEL_EVENT_KIND_LOAD_COMPLETED', '2': 3},
    const {'1': 'MODEL_EVENT_KIND_LOAD_FAILED', '2': 4},
    const {'1': 'MODEL_EVENT_KIND_UNLOAD_STARTED', '2': 5},
    const {'1': 'MODEL_EVENT_KIND_UNLOAD_COMPLETED', '2': 6},
    const {'1': 'MODEL_EVENT_KIND_UNLOAD_FAILED', '2': 7},
    const {'1': 'MODEL_EVENT_KIND_DOWNLOAD_STARTED', '2': 8},
    const {'1': 'MODEL_EVENT_KIND_DOWNLOAD_PROGRESS', '2': 9},
    const {'1': 'MODEL_EVENT_KIND_DOWNLOAD_COMPLETED', '2': 10},
    const {'1': 'MODEL_EVENT_KIND_DOWNLOAD_FAILED', '2': 11},
    const {'1': 'MODEL_EVENT_KIND_DOWNLOAD_CANCELLED', '2': 12},
    const {'1': 'MODEL_EVENT_KIND_LIST_REQUESTED', '2': 13},
    const {'1': 'MODEL_EVENT_KIND_LIST_COMPLETED', '2': 14},
    const {'1': 'MODEL_EVENT_KIND_LIST_FAILED', '2': 15},
    const {'1': 'MODEL_EVENT_KIND_CATALOG_LOADED', '2': 16},
    const {'1': 'MODEL_EVENT_KIND_DELETE_STARTED', '2': 17},
    const {'1': 'MODEL_EVENT_KIND_DELETE_COMPLETED', '2': 18},
    const {'1': 'MODEL_EVENT_KIND_DELETE_FAILED', '2': 19},
    const {'1': 'MODEL_EVENT_KIND_CUSTOM_MODEL_ADDED', '2': 20},
    const {'1': 'MODEL_EVENT_KIND_BUILT_IN_REGISTERED', '2': 21},
  ],
};

/// Descriptor for `ModelEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List modelEventKindDescriptor = $convert.base64Decode('Cg5Nb2RlbEV2ZW50S2luZBIgChxNT0RFTF9FVkVOVF9LSU5EX1VOU1BFQ0lGSUVEEAASIQodTU9ERUxfRVZFTlRfS0lORF9MT0FEX1NUQVJURUQQARIiCh5NT0RFTF9FVkVOVF9LSU5EX0xPQURfUFJPR1JFU1MQAhIjCh9NT0RFTF9FVkVOVF9LSU5EX0xPQURfQ09NUExFVEVEEAMSIAocTU9ERUxfRVZFTlRfS0lORF9MT0FEX0ZBSUxFRBAEEiMKH01PREVMX0VWRU5UX0tJTkRfVU5MT0FEX1NUQVJURUQQBRIlCiFNT0RFTF9FVkVOVF9LSU5EX1VOTE9BRF9DT01QTEVURUQQBhIiCh5NT0RFTF9FVkVOVF9LSU5EX1VOTE9BRF9GQUlMRUQQBxIlCiFNT0RFTF9FVkVOVF9LSU5EX0RPV05MT0FEX1NUQVJURUQQCBImCiJNT0RFTF9FVkVOVF9LSU5EX0RPV05MT0FEX1BST0dSRVNTEAkSJwojTU9ERUxfRVZFTlRfS0lORF9ET1dOTE9BRF9DT01QTEVURUQQChIkCiBNT0RFTF9FVkVOVF9LSU5EX0RPV05MT0FEX0ZBSUxFRBALEicKI01PREVMX0VWRU5UX0tJTkRfRE9XTkxPQURfQ0FOQ0VMTEVEEAwSIwofTU9ERUxfRVZFTlRfS0lORF9MSVNUX1JFUVVFU1RFRBANEiMKH01PREVMX0VWRU5UX0tJTkRfTElTVF9DT01QTEVURUQQDhIgChxNT0RFTF9FVkVOVF9LSU5EX0xJU1RfRkFJTEVEEA8SIwofTU9ERUxfRVZFTlRfS0lORF9DQVRBTE9HX0xPQURFRBAQEiMKH01PREVMX0VWRU5UX0tJTkRfREVMRVRFX1NUQVJURUQQERIlCiFNT0RFTF9FVkVOVF9LSU5EX0RFTEVURV9DT01QTEVURUQQEhIiCh5NT0RFTF9FVkVOVF9LSU5EX0RFTEVURV9GQUlMRUQQExInCiNNT0RFTF9FVkVOVF9LSU5EX0NVU1RPTV9NT0RFTF9BRERFRBAUEigKJE1PREVMX0VWRU5UX0tJTkRfQlVJTFRfSU5fUkVHSVNURVJFRBAV');
@$core.Deprecated('Use voiceEventKindDescriptor instead')
const VoiceEventKind$json = const {
  '1': 'VoiceEventKind',
  '2': const [
    const {'1': 'VOICE_EVENT_KIND_UNSPECIFIED', '2': 0},
    const {'1': 'VOICE_EVENT_KIND_LISTENING_STARTED', '2': 1},
    const {'1': 'VOICE_EVENT_KIND_LISTENING_ENDED', '2': 2},
    const {'1': 'VOICE_EVENT_KIND_SPEECH_DETECTED', '2': 3},
    const {'1': 'VOICE_EVENT_KIND_TRANSCRIPTION_STARTED', '2': 4},
    const {'1': 'VOICE_EVENT_KIND_TRANSCRIPTION_PARTIAL', '2': 5},
    const {'1': 'VOICE_EVENT_KIND_TRANSCRIPTION_FINAL', '2': 6},
    const {'1': 'VOICE_EVENT_KIND_RESPONSE_GENERATED', '2': 7},
    const {'1': 'VOICE_EVENT_KIND_SYNTHESIS_STARTED', '2': 8},
    const {'1': 'VOICE_EVENT_KIND_AUDIO_GENERATED', '2': 9},
    const {'1': 'VOICE_EVENT_KIND_SYNTHESIS_COMPLETED', '2': 10},
    const {'1': 'VOICE_EVENT_KIND_SYNTHESIS_FAILED', '2': 11},
    const {'1': 'VOICE_EVENT_KIND_PIPELINE_STARTED', '2': 12},
    const {'1': 'VOICE_EVENT_KIND_PIPELINE_COMPLETED', '2': 13},
    const {'1': 'VOICE_EVENT_KIND_PIPELINE_ERROR', '2': 14},
    const {'1': 'VOICE_EVENT_KIND_VAD_STARTED', '2': 15},
    const {'1': 'VOICE_EVENT_KIND_VAD_DETECTED', '2': 16},
    const {'1': 'VOICE_EVENT_KIND_VAD_ENDED', '2': 17},
    const {'1': 'VOICE_EVENT_KIND_VAD_INITIALIZED', '2': 18},
    const {'1': 'VOICE_EVENT_KIND_VAD_STOPPED', '2': 19},
    const {'1': 'VOICE_EVENT_KIND_VAD_CLEANED_UP', '2': 20},
    const {'1': 'VOICE_EVENT_KIND_SPEECH_STARTED', '2': 21},
    const {'1': 'VOICE_EVENT_KIND_SPEECH_ENDED', '2': 22},
    const {'1': 'VOICE_EVENT_KIND_STT_PROCESSING', '2': 23},
    const {'1': 'VOICE_EVENT_KIND_STT_PARTIAL_RESULT', '2': 24},
    const {'1': 'VOICE_EVENT_KIND_STT_COMPLETED', '2': 25},
    const {'1': 'VOICE_EVENT_KIND_STT_FAILED', '2': 26},
    const {'1': 'VOICE_EVENT_KIND_LLM_PROCESSING', '2': 27},
    const {'1': 'VOICE_EVENT_KIND_TTS_PROCESSING', '2': 28},
    const {'1': 'VOICE_EVENT_KIND_RECORDING_STARTED', '2': 29},
    const {'1': 'VOICE_EVENT_KIND_RECORDING_STOPPED', '2': 30},
    const {'1': 'VOICE_EVENT_KIND_PLAYBACK_STARTED', '2': 31},
    const {'1': 'VOICE_EVENT_KIND_PLAYBACK_COMPLETED', '2': 32},
    const {'1': 'VOICE_EVENT_KIND_PLAYBACK_STOPPED', '2': 33},
    const {'1': 'VOICE_EVENT_KIND_PLAYBACK_PAUSED', '2': 34},
    const {'1': 'VOICE_EVENT_KIND_PLAYBACK_RESUMED', '2': 35},
    const {'1': 'VOICE_EVENT_KIND_PLAYBACK_FAILED', '2': 36},
    const {'1': 'VOICE_EVENT_KIND_VOICE_SESSION_STARTED', '2': 37},
    const {'1': 'VOICE_EVENT_KIND_VOICE_SESSION_LISTENING', '2': 38},
    const {'1': 'VOICE_EVENT_KIND_VOICE_SESSION_SPEECH_STARTED', '2': 39},
    const {'1': 'VOICE_EVENT_KIND_VOICE_SESSION_SPEECH_ENDED', '2': 40},
    const {'1': 'VOICE_EVENT_KIND_VOICE_SESSION_PROCESSING', '2': 41},
    const {'1': 'VOICE_EVENT_KIND_VOICE_SESSION_TRANSCRIBED', '2': 42},
    const {'1': 'VOICE_EVENT_KIND_VOICE_SESSION_RESPONDED', '2': 43},
    const {'1': 'VOICE_EVENT_KIND_VOICE_SESSION_SPEAKING', '2': 44},
    const {'1': 'VOICE_EVENT_KIND_VOICE_SESSION_TURN_COMPLETED', '2': 45},
    const {'1': 'VOICE_EVENT_KIND_VOICE_SESSION_STOPPED', '2': 46},
    const {'1': 'VOICE_EVENT_KIND_VOICE_SESSION_ERROR', '2': 47},
  ],
};

/// Descriptor for `VoiceEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List voiceEventKindDescriptor = $convert.base64Decode('Cg5Wb2ljZUV2ZW50S2luZBIgChxWT0lDRV9FVkVOVF9LSU5EX1VOU1BFQ0lGSUVEEAASJgoiVk9JQ0VfRVZFTlRfS0lORF9MSVNURU5JTkdfU1RBUlRFRBABEiQKIFZPSUNFX0VWRU5UX0tJTkRfTElTVEVOSU5HX0VOREVEEAISJAogVk9JQ0VfRVZFTlRfS0lORF9TUEVFQ0hfREVURUNURUQQAxIqCiZWT0lDRV9FVkVOVF9LSU5EX1RSQU5TQ1JJUFRJT05fU1RBUlRFRBAEEioKJlZPSUNFX0VWRU5UX0tJTkRfVFJBTlNDUklQVElPTl9QQVJUSUFMEAUSKAokVk9JQ0VfRVZFTlRfS0lORF9UUkFOU0NSSVBUSU9OX0ZJTkFMEAYSJwojVk9JQ0VfRVZFTlRfS0lORF9SRVNQT05TRV9HRU5FUkFURUQQBxImCiJWT0lDRV9FVkVOVF9LSU5EX1NZTlRIRVNJU19TVEFSVEVEEAgSJAogVk9JQ0VfRVZFTlRfS0lORF9BVURJT19HRU5FUkFURUQQCRIoCiRWT0lDRV9FVkVOVF9LSU5EX1NZTlRIRVNJU19DT01QTEVURUQQChIlCiFWT0lDRV9FVkVOVF9LSU5EX1NZTlRIRVNJU19GQUlMRUQQCxIlCiFWT0lDRV9FVkVOVF9LSU5EX1BJUEVMSU5FX1NUQVJURUQQDBInCiNWT0lDRV9FVkVOVF9LSU5EX1BJUEVMSU5FX0NPTVBMRVRFRBANEiMKH1ZPSUNFX0VWRU5UX0tJTkRfUElQRUxJTkVfRVJST1IQDhIgChxWT0lDRV9FVkVOVF9LSU5EX1ZBRF9TVEFSVEVEEA8SIQodVk9JQ0VfRVZFTlRfS0lORF9WQURfREVURUNURUQQEBIeChpWT0lDRV9FVkVOVF9LSU5EX1ZBRF9FTkRFRBAREiQKIFZPSUNFX0VWRU5UX0tJTkRfVkFEX0lOSVRJQUxJWkVEEBISIAocVk9JQ0VfRVZFTlRfS0lORF9WQURfU1RPUFBFRBATEiMKH1ZPSUNFX0VWRU5UX0tJTkRfVkFEX0NMRUFORURfVVAQFBIjCh9WT0lDRV9FVkVOVF9LSU5EX1NQRUVDSF9TVEFSVEVEEBUSIQodVk9JQ0VfRVZFTlRfS0lORF9TUEVFQ0hfRU5ERUQQFhIjCh9WT0lDRV9FVkVOVF9LSU5EX1NUVF9QUk9DRVNTSU5HEBcSJwojVk9JQ0VfRVZFTlRfS0lORF9TVFRfUEFSVElBTF9SRVNVTFQQGBIiCh5WT0lDRV9FVkVOVF9LSU5EX1NUVF9DT01QTEVURUQQGRIfChtWT0lDRV9FVkVOVF9LSU5EX1NUVF9GQUlMRUQQGhIjCh9WT0lDRV9FVkVOVF9LSU5EX0xMTV9QUk9DRVNTSU5HEBsSIwofVk9JQ0VfRVZFTlRfS0lORF9UVFNfUFJPQ0VTU0lORxAcEiYKIlZPSUNFX0VWRU5UX0tJTkRfUkVDT1JESU5HX1NUQVJURUQQHRImCiJWT0lDRV9FVkVOVF9LSU5EX1JFQ09SRElOR19TVE9QUEVEEB4SJQohVk9JQ0VfRVZFTlRfS0lORF9QTEFZQkFDS19TVEFSVEVEEB8SJwojVk9JQ0VfRVZFTlRfS0lORF9QTEFZQkFDS19DT01QTEVURUQQIBIlCiFWT0lDRV9FVkVOVF9LSU5EX1BMQVlCQUNLX1NUT1BQRUQQIRIkCiBWT0lDRV9FVkVOVF9LSU5EX1BMQVlCQUNLX1BBVVNFRBAiEiUKIVZPSUNFX0VWRU5UX0tJTkRfUExBWUJBQ0tfUkVTVU1FRBAjEiQKIFZPSUNFX0VWRU5UX0tJTkRfUExBWUJBQ0tfRkFJTEVEECQSKgomVk9JQ0VfRVZFTlRfS0lORF9WT0lDRV9TRVNTSU9OX1NUQVJURUQQJRIsCihWT0lDRV9FVkVOVF9LSU5EX1ZPSUNFX1NFU1NJT05fTElTVEVOSU5HECYSMQotVk9JQ0VfRVZFTlRfS0lORF9WT0lDRV9TRVNTSU9OX1NQRUVDSF9TVEFSVEVEECcSLworVk9JQ0VfRVZFTlRfS0lORF9WT0lDRV9TRVNTSU9OX1NQRUVDSF9FTkRFRBAoEi0KKVZPSUNFX0VWRU5UX0tJTkRfVk9JQ0VfU0VTU0lPTl9QUk9DRVNTSU5HECkSLgoqVk9JQ0VfRVZFTlRfS0lORF9WT0lDRV9TRVNTSU9OX1RSQU5TQ1JJQkVEECoSLAooVk9JQ0VfRVZFTlRfS0lORF9WT0lDRV9TRVNTSU9OX1JFU1BPTkRFRBArEisKJ1ZPSUNFX0VWRU5UX0tJTkRfVk9JQ0VfU0VTU0lPTl9TUEVBS0lORxAsEjEKLVZPSUNFX0VWRU5UX0tJTkRfVk9JQ0VfU0VTU0lPTl9UVVJOX0NPTVBMRVRFRBAtEioKJlZPSUNFX0VWRU5UX0tJTkRfVk9JQ0VfU0VTU0lPTl9TVE9QUEVEEC4SKAokVk9JQ0VfRVZFTlRfS0lORF9WT0lDRV9TRVNTSU9OX0VSUk9SEC8=');
@$core.Deprecated('Use performanceEventKindDescriptor instead')
const PerformanceEventKind$json = const {
  '1': 'PerformanceEventKind',
  '2': const [
    const {'1': 'PERFORMANCE_EVENT_KIND_UNSPECIFIED', '2': 0},
    const {'1': 'PERFORMANCE_EVENT_KIND_MEMORY_WARNING', '2': 1},
    const {'1': 'PERFORMANCE_EVENT_KIND_THERMAL_STATE_CHANGED', '2': 2},
    const {'1': 'PERFORMANCE_EVENT_KIND_LATENCY_MEASURED', '2': 3},
    const {'1': 'PERFORMANCE_EVENT_KIND_THROUGHPUT_MEASURED', '2': 4},
  ],
};

/// Descriptor for `PerformanceEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List performanceEventKindDescriptor = $convert.base64Decode('ChRQZXJmb3JtYW5jZUV2ZW50S2luZBImCiJQRVJGT1JNQU5DRV9FVkVOVF9LSU5EX1VOU1BFQ0lGSUVEEAASKQolUEVSRk9STUFOQ0VfRVZFTlRfS0lORF9NRU1PUllfV0FSTklORxABEjAKLFBFUkZPUk1BTkNFX0VWRU5UX0tJTkRfVEhFUk1BTF9TVEFURV9DSEFOR0VEEAISKwonUEVSRk9STUFOQ0VfRVZFTlRfS0lORF9MQVRFTkNZX01FQVNVUkVEEAMSLgoqUEVSRk9STUFOQ0VfRVZFTlRfS0lORF9USFJPVUdIUFVUX01FQVNVUkVEEAQ=');
@$core.Deprecated('Use networkEventKindDescriptor instead')
const NetworkEventKind$json = const {
  '1': 'NetworkEventKind',
  '2': const [
    const {'1': 'NETWORK_EVENT_KIND_UNSPECIFIED', '2': 0},
    const {'1': 'NETWORK_EVENT_KIND_REQUEST_STARTED', '2': 1},
    const {'1': 'NETWORK_EVENT_KIND_REQUEST_COMPLETED', '2': 2},
    const {'1': 'NETWORK_EVENT_KIND_REQUEST_FAILED', '2': 3},
    const {'1': 'NETWORK_EVENT_KIND_REQUEST_TIMEOUT', '2': 4},
    const {'1': 'NETWORK_EVENT_KIND_CONNECTIVITY_CHANGED', '2': 5},
  ],
};

/// Descriptor for `NetworkEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List networkEventKindDescriptor = $convert.base64Decode('ChBOZXR3b3JrRXZlbnRLaW5kEiIKHk5FVFdPUktfRVZFTlRfS0lORF9VTlNQRUNJRklFRBAAEiYKIk5FVFdPUktfRVZFTlRfS0lORF9SRVFVRVNUX1NUQVJURUQQARIoCiRORVRXT1JLX0VWRU5UX0tJTkRfUkVRVUVTVF9DT01QTEVURUQQAhIlCiFORVRXT1JLX0VWRU5UX0tJTkRfUkVRVUVTVF9GQUlMRUQQAxImCiJORVRXT1JLX0VWRU5UX0tJTkRfUkVRVUVTVF9USU1FT1VUEAQSKwonTkVUV09SS19FVkVOVF9LSU5EX0NPTk5FQ1RJVklUWV9DSEFOR0VEEAU=');
@$core.Deprecated('Use storageEventKindDescriptor instead')
const StorageEventKind$json = const {
  '1': 'StorageEventKind',
  '2': const [
    const {'1': 'STORAGE_EVENT_KIND_UNSPECIFIED', '2': 0},
    const {'1': 'STORAGE_EVENT_KIND_INFO_REQUESTED', '2': 1},
    const {'1': 'STORAGE_EVENT_KIND_INFO_RETRIEVED', '2': 2},
    const {'1': 'STORAGE_EVENT_KIND_MODELS_REQUESTED', '2': 3},
    const {'1': 'STORAGE_EVENT_KIND_MODELS_RETRIEVED', '2': 4},
    const {'1': 'STORAGE_EVENT_KIND_CLEAR_CACHE_STARTED', '2': 5},
    const {'1': 'STORAGE_EVENT_KIND_CLEAR_CACHE_COMPLETED', '2': 6},
    const {'1': 'STORAGE_EVENT_KIND_CLEAR_CACHE_FAILED', '2': 7},
    const {'1': 'STORAGE_EVENT_KIND_CLEAN_TEMP_STARTED', '2': 8},
    const {'1': 'STORAGE_EVENT_KIND_CLEAN_TEMP_COMPLETED', '2': 9},
    const {'1': 'STORAGE_EVENT_KIND_CLEAN_TEMP_FAILED', '2': 10},
    const {'1': 'STORAGE_EVENT_KIND_DELETE_MODEL_STARTED', '2': 11},
    const {'1': 'STORAGE_EVENT_KIND_DELETE_MODEL_COMPLETED', '2': 12},
    const {'1': 'STORAGE_EVENT_KIND_DELETE_MODEL_FAILED', '2': 13},
    const {'1': 'STORAGE_EVENT_KIND_CACHE_HIT', '2': 14},
    const {'1': 'STORAGE_EVENT_KIND_CACHE_MISS', '2': 15},
    const {'1': 'STORAGE_EVENT_KIND_EVICTION', '2': 16},
    const {'1': 'STORAGE_EVENT_KIND_DISK_FULL', '2': 17},
  ],
};

/// Descriptor for `StorageEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List storageEventKindDescriptor = $convert.base64Decode('ChBTdG9yYWdlRXZlbnRLaW5kEiIKHlNUT1JBR0VfRVZFTlRfS0lORF9VTlNQRUNJRklFRBAAEiUKIVNUT1JBR0VfRVZFTlRfS0lORF9JTkZPX1JFUVVFU1RFRBABEiUKIVNUT1JBR0VfRVZFTlRfS0lORF9JTkZPX1JFVFJJRVZFRBACEicKI1NUT1JBR0VfRVZFTlRfS0lORF9NT0RFTFNfUkVRVUVTVEVEEAMSJwojU1RPUkFHRV9FVkVOVF9LSU5EX01PREVMU19SRVRSSUVWRUQQBBIqCiZTVE9SQUdFX0VWRU5UX0tJTkRfQ0xFQVJfQ0FDSEVfU1RBUlRFRBAFEiwKKFNUT1JBR0VfRVZFTlRfS0lORF9DTEVBUl9DQUNIRV9DT01QTEVURUQQBhIpCiVTVE9SQUdFX0VWRU5UX0tJTkRfQ0xFQVJfQ0FDSEVfRkFJTEVEEAcSKQolU1RPUkFHRV9FVkVOVF9LSU5EX0NMRUFOX1RFTVBfU1RBUlRFRBAIEisKJ1NUT1JBR0VfRVZFTlRfS0lORF9DTEVBTl9URU1QX0NPTVBMRVRFRBAJEigKJFNUT1JBR0VfRVZFTlRfS0lORF9DTEVBTl9URU1QX0ZBSUxFRBAKEisKJ1NUT1JBR0VfRVZFTlRfS0lORF9ERUxFVEVfTU9ERUxfU1RBUlRFRBALEi0KKVNUT1JBR0VfRVZFTlRfS0lORF9ERUxFVEVfTU9ERUxfQ09NUExFVEVEEAwSKgomU1RPUkFHRV9FVkVOVF9LSU5EX0RFTEVURV9NT0RFTF9GQUlMRUQQDRIgChxTVE9SQUdFX0VWRU5UX0tJTkRfQ0FDSEVfSElUEA4SIQodU1RPUkFHRV9FVkVOVF9LSU5EX0NBQ0hFX01JU1MQDxIfChtTVE9SQUdFX0VWRU5UX0tJTkRfRVZJQ1RJT04QEBIgChxTVE9SQUdFX0VWRU5UX0tJTkRfRElTS19GVUxMEBE=');
@$core.Deprecated('Use frameworkEventKindDescriptor instead')
const FrameworkEventKind$json = const {
  '1': 'FrameworkEventKind',
  '2': const [
    const {'1': 'FRAMEWORK_EVENT_KIND_UNSPECIFIED', '2': 0},
    const {'1': 'FRAMEWORK_EVENT_KIND_ADAPTER_REGISTERED', '2': 1},
    const {'1': 'FRAMEWORK_EVENT_KIND_ADAPTER_UNREGISTERED', '2': 2},
    const {'1': 'FRAMEWORK_EVENT_KIND_ADAPTERS_REQUESTED', '2': 3},
    const {'1': 'FRAMEWORK_EVENT_KIND_ADAPTERS_RETRIEVED', '2': 4},
    const {'1': 'FRAMEWORK_EVENT_KIND_FRAMEWORKS_REQUESTED', '2': 5},
    const {'1': 'FRAMEWORK_EVENT_KIND_FRAMEWORKS_RETRIEVED', '2': 6},
    const {'1': 'FRAMEWORK_EVENT_KIND_AVAILABILITY_REQUESTED', '2': 7},
    const {'1': 'FRAMEWORK_EVENT_KIND_AVAILABILITY_RETRIEVED', '2': 8},
    const {'1': 'FRAMEWORK_EVENT_KIND_MODELS_FOR_FRAMEWORK_REQUESTED', '2': 9},
    const {'1': 'FRAMEWORK_EVENT_KIND_MODELS_FOR_FRAMEWORK_RETRIEVED', '2': 10},
    const {'1': 'FRAMEWORK_EVENT_KIND_FRAMEWORKS_FOR_MODALITY_REQUESTED', '2': 11},
    const {'1': 'FRAMEWORK_EVENT_KIND_FRAMEWORKS_FOR_MODALITY_RETRIEVED', '2': 12},
    const {'1': 'FRAMEWORK_EVENT_KIND_ERROR', '2': 13},
  ],
};

/// Descriptor for `FrameworkEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List frameworkEventKindDescriptor = $convert.base64Decode('ChJGcmFtZXdvcmtFdmVudEtpbmQSJAogRlJBTUVXT1JLX0VWRU5UX0tJTkRfVU5TUEVDSUZJRUQQABIrCidGUkFNRVdPUktfRVZFTlRfS0lORF9BREFQVEVSX1JFR0lTVEVSRUQQARItCilGUkFNRVdPUktfRVZFTlRfS0lORF9BREFQVEVSX1VOUkVHSVNURVJFRBACEisKJ0ZSQU1FV09SS19FVkVOVF9LSU5EX0FEQVBURVJTX1JFUVVFU1RFRBADEisKJ0ZSQU1FV09SS19FVkVOVF9LSU5EX0FEQVBURVJTX1JFVFJJRVZFRBAEEi0KKUZSQU1FV09SS19FVkVOVF9LSU5EX0ZSQU1FV09SS1NfUkVRVUVTVEVEEAUSLQopRlJBTUVXT1JLX0VWRU5UX0tJTkRfRlJBTUVXT1JLU19SRVRSSUVWRUQQBhIvCitGUkFNRVdPUktfRVZFTlRfS0lORF9BVkFJTEFCSUxJVFlfUkVRVUVTVEVEEAcSLworRlJBTUVXT1JLX0VWRU5UX0tJTkRfQVZBSUxBQklMSVRZX1JFVFJJRVZFRBAIEjcKM0ZSQU1FV09SS19FVkVOVF9LSU5EX01PREVMU19GT1JfRlJBTUVXT1JLX1JFUVVFU1RFRBAJEjcKM0ZSQU1FV09SS19FVkVOVF9LSU5EX01PREVMU19GT1JfRlJBTUVXT1JLX1JFVFJJRVZFRBAKEjoKNkZSQU1FV09SS19FVkVOVF9LSU5EX0ZSQU1FV09SS1NfRk9SX01PREFMSVRZX1JFUVVFU1RFRBALEjoKNkZSQU1FV09SS19FVkVOVF9LSU5EX0ZSQU1FV09SS1NfRk9SX01PREFMSVRZX1JFVFJJRVZFRBAMEh4KGkZSQU1FV09SS19FVkVOVF9LSU5EX0VSUk9SEA0=');
@$core.Deprecated('Use deviceEventKindDescriptor instead')
const DeviceEventKind$json = const {
  '1': 'DeviceEventKind',
  '2': const [
    const {'1': 'DEVICE_EVENT_KIND_UNSPECIFIED', '2': 0},
    const {'1': 'DEVICE_EVENT_KIND_DEVICE_INFO_COLLECTED', '2': 1},
    const {'1': 'DEVICE_EVENT_KIND_DEVICE_INFO_COLLECTION_FAILED', '2': 2},
    const {'1': 'DEVICE_EVENT_KIND_DEVICE_INFO_REFRESHED', '2': 3},
    const {'1': 'DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_STARTED', '2': 4},
    const {'1': 'DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_COMPLETED', '2': 5},
    const {'1': 'DEVICE_EVENT_KIND_DEVICE_INFO_SYNC_FAILED', '2': 6},
    const {'1': 'DEVICE_EVENT_KIND_DEVICE_STATE_CHANGED', '2': 7},
    const {'1': 'DEVICE_EVENT_KIND_BATTERY_CHANGED', '2': 8},
    const {'1': 'DEVICE_EVENT_KIND_THERMAL_CHANGED', '2': 9},
    const {'1': 'DEVICE_EVENT_KIND_CONNECTIVITY_CHANGED', '2': 10},
    const {'1': 'DEVICE_EVENT_KIND_DEVICE_REGISTERED', '2': 11},
    const {'1': 'DEVICE_EVENT_KIND_DEVICE_REGISTRATION_FAILED', '2': 12},
  ],
};

/// Descriptor for `DeviceEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List deviceEventKindDescriptor = $convert.base64Decode('Cg9EZXZpY2VFdmVudEtpbmQSIQodREVWSUNFX0VWRU5UX0tJTkRfVU5TUEVDSUZJRUQQABIrCidERVZJQ0VfRVZFTlRfS0lORF9ERVZJQ0VfSU5GT19DT0xMRUNURUQQARIzCi9ERVZJQ0VfRVZFTlRfS0lORF9ERVZJQ0VfSU5GT19DT0xMRUNUSU9OX0ZBSUxFRBACEisKJ0RFVklDRV9FVkVOVF9LSU5EX0RFVklDRV9JTkZPX1JFRlJFU0hFRBADEi4KKkRFVklDRV9FVkVOVF9LSU5EX0RFVklDRV9JTkZPX1NZTkNfU1RBUlRFRBAEEjAKLERFVklDRV9FVkVOVF9LSU5EX0RFVklDRV9JTkZPX1NZTkNfQ09NUExFVEVEEAUSLQopREVWSUNFX0VWRU5UX0tJTkRfREVWSUNFX0lORk9fU1lOQ19GQUlMRUQQBhIqCiZERVZJQ0VfRVZFTlRfS0lORF9ERVZJQ0VfU1RBVEVfQ0hBTkdFRBAHEiUKIURFVklDRV9FVkVOVF9LSU5EX0JBVFRFUllfQ0hBTkdFRBAIEiUKIURFVklDRV9FVkVOVF9LSU5EX1RIRVJNQUxfQ0hBTkdFRBAJEioKJkRFVklDRV9FVkVOVF9LSU5EX0NPTk5FQ1RJVklUWV9DSEFOR0VEEAoSJwojREVWSUNFX0VWRU5UX0tJTkRfREVWSUNFX1JFR0lTVEVSRUQQCxIwCixERVZJQ0VfRVZFTlRfS0lORF9ERVZJQ0VfUkVHSVNUUkFUSU9OX0ZBSUxFRBAM');
@$core.Deprecated('Use componentInitializationEventKindDescriptor instead')
const ComponentInitializationEventKind$json = const {
  '1': 'ComponentInitializationEventKind',
  '2': const [
    const {'1': 'COMPONENT_INIT_EVENT_KIND_UNSPECIFIED', '2': 0},
    const {'1': 'COMPONENT_INIT_EVENT_KIND_INITIALIZATION_STARTED', '2': 1},
    const {'1': 'COMPONENT_INIT_EVENT_KIND_INITIALIZATION_COMPLETED', '2': 2},
    const {'1': 'COMPONENT_INIT_EVENT_KIND_COMPONENT_STATE_CHANGED', '2': 3},
    const {'1': 'COMPONENT_INIT_EVENT_KIND_COMPONENT_CHECKING', '2': 4},
    const {'1': 'COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_REQUIRED', '2': 5},
    const {'1': 'COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_STARTED', '2': 6},
    const {'1': 'COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_PROGRESS', '2': 7},
    const {'1': 'COMPONENT_INIT_EVENT_KIND_COMPONENT_DOWNLOAD_COMPLETED', '2': 8},
    const {'1': 'COMPONENT_INIT_EVENT_KIND_COMPONENT_INITIALIZING', '2': 9},
    const {'1': 'COMPONENT_INIT_EVENT_KIND_COMPONENT_READY', '2': 10},
    const {'1': 'COMPONENT_INIT_EVENT_KIND_COMPONENT_FAILED', '2': 11},
    const {'1': 'COMPONENT_INIT_EVENT_KIND_PARALLEL_INIT_STARTED', '2': 12},
    const {'1': 'COMPONENT_INIT_EVENT_KIND_SEQUENTIAL_INIT_STARTED', '2': 13},
    const {'1': 'COMPONENT_INIT_EVENT_KIND_ALL_COMPONENTS_READY', '2': 14},
    const {'1': 'COMPONENT_INIT_EVENT_KIND_SOME_COMPONENTS_READY', '2': 15},
  ],
};

/// Descriptor for `ComponentInitializationEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List componentInitializationEventKindDescriptor = $convert.base64Decode('CiBDb21wb25lbnRJbml0aWFsaXphdGlvbkV2ZW50S2luZBIpCiVDT01QT05FTlRfSU5JVF9FVkVOVF9LSU5EX1VOU1BFQ0lGSUVEEAASNAowQ09NUE9ORU5UX0lOSVRfRVZFTlRfS0lORF9JTklUSUFMSVpBVElPTl9TVEFSVEVEEAESNgoyQ09NUE9ORU5UX0lOSVRfRVZFTlRfS0lORF9JTklUSUFMSVpBVElPTl9DT01QTEVURUQQAhI1CjFDT01QT05FTlRfSU5JVF9FVkVOVF9LSU5EX0NPTVBPTkVOVF9TVEFURV9DSEFOR0VEEAMSMAosQ09NUE9ORU5UX0lOSVRfRVZFTlRfS0lORF9DT01QT05FTlRfQ0hFQ0tJTkcQBBI5CjVDT01QT05FTlRfSU5JVF9FVkVOVF9LSU5EX0NPTVBPTkVOVF9ET1dOTE9BRF9SRVFVSVJFRBAFEjgKNENPTVBPTkVOVF9JTklUX0VWRU5UX0tJTkRfQ09NUE9ORU5UX0RPV05MT0FEX1NUQVJURUQQBhI5CjVDT01QT05FTlRfSU5JVF9FVkVOVF9LSU5EX0NPTVBPTkVOVF9ET1dOTE9BRF9QUk9HUkVTUxAHEjoKNkNPTVBPTkVOVF9JTklUX0VWRU5UX0tJTkRfQ09NUE9ORU5UX0RPV05MT0FEX0NPTVBMRVRFRBAIEjQKMENPTVBPTkVOVF9JTklUX0VWRU5UX0tJTkRfQ09NUE9ORU5UX0lOSVRJQUxJWklORxAJEi0KKUNPTVBPTkVOVF9JTklUX0VWRU5UX0tJTkRfQ09NUE9ORU5UX1JFQURZEAoSLgoqQ09NUE9ORU5UX0lOSVRfRVZFTlRfS0lORF9DT01QT05FTlRfRkFJTEVEEAsSMwovQ09NUE9ORU5UX0lOSVRfRVZFTlRfS0lORF9QQVJBTExFTF9JTklUX1NUQVJURUQQDBI1CjFDT01QT05FTlRfSU5JVF9FVkVOVF9LSU5EX1NFUVVFTlRJQUxfSU5JVF9TVEFSVEVEEA0SMgouQ09NUE9ORU5UX0lOSVRfRVZFTlRfS0lORF9BTExfQ09NUE9ORU5UU19SRUFEWRAOEjMKL0NPTVBPTkVOVF9JTklUX0VWRU5UX0tJTkRfU09NRV9DT01QT05FTlRTX1JFQURZEA8=');
@$core.Deprecated('Use initializationEventDescriptor instead')
const InitializationEvent$json = const {
  '1': 'InitializationEvent',
  '2': const [
    const {'1': 'stage', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.InitializationStage', '10': 'stage'},
    const {'1': 'source', '3': 2, '4': 1, '5': 9, '10': 'source'},
    const {'1': 'error', '3': 3, '4': 1, '5': 9, '10': 'error'},
    const {'1': 'version', '3': 4, '4': 1, '5': 9, '10': 'version'},
  ],
};

/// Descriptor for `InitializationEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List initializationEventDescriptor = $convert.base64Decode('ChNJbml0aWFsaXphdGlvbkV2ZW50EjkKBXN0YWdlGAEgASgOMiMucnVuYW55d2hlcmUudjEuSW5pdGlhbGl6YXRpb25TdGFnZVIFc3RhZ2USFgoGc291cmNlGAIgASgJUgZzb3VyY2USFAoFZXJyb3IYAyABKAlSBWVycm9yEhgKB3ZlcnNpb24YBCABKAlSB3ZlcnNpb24=');
@$core.Deprecated('Use configurationEventDescriptor instead')
const ConfigurationEvent$json = const {
  '1': 'ConfigurationEvent',
  '2': const [
    const {'1': 'kind', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.ConfigurationEventKind', '10': 'kind'},
    const {'1': 'source', '3': 2, '4': 1, '5': 9, '10': 'source'},
    const {'1': 'error', '3': 3, '4': 1, '5': 9, '10': 'error'},
    const {'1': 'changed_keys', '3': 4, '4': 3, '5': 9, '10': 'changedKeys'},
    const {'1': 'settings_json', '3': 5, '4': 1, '5': 9, '10': 'settingsJson'},
    const {'1': 'routing_policy', '3': 6, '4': 1, '5': 9, '10': 'routingPolicy'},
    const {'1': 'privacy_mode', '3': 7, '4': 1, '5': 9, '10': 'privacyMode'},
    const {'1': 'analytics_enabled', '3': 8, '4': 1, '5': 8, '10': 'analyticsEnabled'},
    const {'1': 'old_value_json', '3': 9, '4': 1, '5': 9, '10': 'oldValueJson'},
    const {'1': 'new_value_json', '3': 10, '4': 1, '5': 9, '10': 'newValueJson'},
  ],
};

/// Descriptor for `ConfigurationEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List configurationEventDescriptor = $convert.base64Decode('ChJDb25maWd1cmF0aW9uRXZlbnQSOgoEa2luZBgBIAEoDjImLnJ1bmFueXdoZXJlLnYxLkNvbmZpZ3VyYXRpb25FdmVudEtpbmRSBGtpbmQSFgoGc291cmNlGAIgASgJUgZzb3VyY2USFAoFZXJyb3IYAyABKAlSBWVycm9yEiEKDGNoYW5nZWRfa2V5cxgEIAMoCVILY2hhbmdlZEtleXMSIwoNc2V0dGluZ3NfanNvbhgFIAEoCVIMc2V0dGluZ3NKc29uEiUKDnJvdXRpbmdfcG9saWN5GAYgASgJUg1yb3V0aW5nUG9saWN5EiEKDHByaXZhY3lfbW9kZRgHIAEoCVILcHJpdmFjeU1vZGUSKwoRYW5hbHl0aWNzX2VuYWJsZWQYCCABKAhSEGFuYWx5dGljc0VuYWJsZWQSJAoOb2xkX3ZhbHVlX2pzb24YCSABKAlSDG9sZFZhbHVlSnNvbhIkCg5uZXdfdmFsdWVfanNvbhgKIAEoCVIMbmV3VmFsdWVKc29u');
@$core.Deprecated('Use generationEventDescriptor instead')
const GenerationEvent$json = const {
  '1': 'GenerationEvent',
  '2': const [
    const {'1': 'kind', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.GenerationEventKind', '10': 'kind'},
    const {'1': 'session_id', '3': 2, '4': 1, '5': 9, '10': 'sessionId'},
    const {'1': 'prompt', '3': 3, '4': 1, '5': 9, '10': 'prompt'},
    const {'1': 'token', '3': 4, '4': 1, '5': 9, '10': 'token'},
    const {'1': 'streaming_text', '3': 5, '4': 1, '5': 9, '10': 'streamingText'},
    const {'1': 'tokens_count', '3': 6, '4': 1, '5': 5, '10': 'tokensCount'},
    const {'1': 'response', '3': 7, '4': 1, '5': 9, '10': 'response'},
    const {'1': 'tokens_used', '3': 8, '4': 1, '5': 5, '10': 'tokensUsed'},
    const {'1': 'latency_ms', '3': 9, '4': 1, '5': 3, '10': 'latencyMs'},
    const {'1': 'first_token_latency_ms', '3': 10, '4': 1, '5': 3, '10': 'firstTokenLatencyMs'},
    const {'1': 'error', '3': 11, '4': 1, '5': 9, '10': 'error'},
    const {'1': 'model_id', '3': 12, '4': 1, '5': 9, '10': 'modelId'},
    const {'1': 'cost_amount', '3': 13, '4': 1, '5': 1, '10': 'costAmount'},
    const {'1': 'cost_saved_amount', '3': 14, '4': 1, '5': 1, '10': 'costSavedAmount'},
    const {'1': 'routing_target', '3': 15, '4': 1, '5': 9, '10': 'routingTarget'},
    const {'1': 'routing_reason', '3': 16, '4': 1, '5': 9, '10': 'routingReason'},
  ],
};

/// Descriptor for `GenerationEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List generationEventDescriptor = $convert.base64Decode('Cg9HZW5lcmF0aW9uRXZlbnQSNwoEa2luZBgBIAEoDjIjLnJ1bmFueXdoZXJlLnYxLkdlbmVyYXRpb25FdmVudEtpbmRSBGtpbmQSHQoKc2Vzc2lvbl9pZBgCIAEoCVIJc2Vzc2lvbklkEhYKBnByb21wdBgDIAEoCVIGcHJvbXB0EhQKBXRva2VuGAQgASgJUgV0b2tlbhIlCg5zdHJlYW1pbmdfdGV4dBgFIAEoCVINc3RyZWFtaW5nVGV4dBIhCgx0b2tlbnNfY291bnQYBiABKAVSC3Rva2Vuc0NvdW50EhoKCHJlc3BvbnNlGAcgASgJUghyZXNwb25zZRIfCgt0b2tlbnNfdXNlZBgIIAEoBVIKdG9rZW5zVXNlZBIdCgpsYXRlbmN5X21zGAkgASgDUglsYXRlbmN5TXMSMwoWZmlyc3RfdG9rZW5fbGF0ZW5jeV9tcxgKIAEoA1ITZmlyc3RUb2tlbkxhdGVuY3lNcxIUCgVlcnJvchgLIAEoCVIFZXJyb3ISGQoIbW9kZWxfaWQYDCABKAlSB21vZGVsSWQSHwoLY29zdF9hbW91bnQYDSABKAFSCmNvc3RBbW91bnQSKgoRY29zdF9zYXZlZF9hbW91bnQYDiABKAFSD2Nvc3RTYXZlZEFtb3VudBIlCg5yb3V0aW5nX3RhcmdldBgPIAEoCVINcm91dGluZ1RhcmdldBIlCg5yb3V0aW5nX3JlYXNvbhgQIAEoCVINcm91dGluZ1JlYXNvbg==');
@$core.Deprecated('Use modelEventDescriptor instead')
const ModelEvent$json = const {
  '1': 'ModelEvent',
  '2': const [
    const {'1': 'kind', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.ModelEventKind', '10': 'kind'},
    const {'1': 'model_id', '3': 2, '4': 1, '5': 9, '10': 'modelId'},
    const {'1': 'task_id', '3': 3, '4': 1, '5': 9, '10': 'taskId'},
    const {'1': 'progress', '3': 4, '4': 1, '5': 2, '10': 'progress'},
    const {'1': 'bytes_downloaded', '3': 5, '4': 1, '5': 3, '10': 'bytesDownloaded'},
    const {'1': 'total_bytes', '3': 6, '4': 1, '5': 3, '10': 'totalBytes'},
    const {'1': 'download_state', '3': 7, '4': 1, '5': 9, '10': 'downloadState'},
    const {'1': 'local_path', '3': 8, '4': 1, '5': 9, '10': 'localPath'},
    const {'1': 'error', '3': 9, '4': 1, '5': 9, '10': 'error'},
    const {'1': 'model_count', '3': 10, '4': 1, '5': 5, '10': 'modelCount'},
    const {'1': 'custom_model_name', '3': 11, '4': 1, '5': 9, '10': 'customModelName'},
    const {'1': 'custom_model_url', '3': 12, '4': 1, '5': 9, '10': 'customModelUrl'},
  ],
};

/// Descriptor for `ModelEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List modelEventDescriptor = $convert.base64Decode('CgpNb2RlbEV2ZW50EjIKBGtpbmQYASABKA4yHi5ydW5hbnl3aGVyZS52MS5Nb2RlbEV2ZW50S2luZFIEa2luZBIZCghtb2RlbF9pZBgCIAEoCVIHbW9kZWxJZBIXCgd0YXNrX2lkGAMgASgJUgZ0YXNrSWQSGgoIcHJvZ3Jlc3MYBCABKAJSCHByb2dyZXNzEikKEGJ5dGVzX2Rvd25sb2FkZWQYBSABKANSD2J5dGVzRG93bmxvYWRlZBIfCgt0b3RhbF9ieXRlcxgGIAEoA1IKdG90YWxCeXRlcxIlCg5kb3dubG9hZF9zdGF0ZRgHIAEoCVINZG93bmxvYWRTdGF0ZRIdCgpsb2NhbF9wYXRoGAggASgJUglsb2NhbFBhdGgSFAoFZXJyb3IYCSABKAlSBWVycm9yEh8KC21vZGVsX2NvdW50GAogASgFUgptb2RlbENvdW50EioKEWN1c3RvbV9tb2RlbF9uYW1lGAsgASgJUg9jdXN0b21Nb2RlbE5hbWUSKAoQY3VzdG9tX21vZGVsX3VybBgMIAEoCVIOY3VzdG9tTW9kZWxVcmw=');
@$core.Deprecated('Use voiceLifecycleEventDescriptor instead')
const VoiceLifecycleEvent$json = const {
  '1': 'VoiceLifecycleEvent',
  '2': const [
    const {'1': 'kind', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.VoiceEventKind', '10': 'kind'},
    const {'1': 'session_id', '3': 2, '4': 1, '5': 9, '10': 'sessionId'},
    const {'1': 'text', '3': 3, '4': 1, '5': 9, '10': 'text'},
    const {'1': 'confidence', '3': 4, '4': 1, '5': 2, '10': 'confidence'},
    const {'1': 'response_text', '3': 5, '4': 1, '5': 9, '10': 'responseText'},
    const {'1': 'audio_base64', '3': 6, '4': 1, '5': 9, '10': 'audioBase64'},
    const {'1': 'duration_ms', '3': 7, '4': 1, '5': 3, '10': 'durationMs'},
    const {'1': 'audio_level', '3': 8, '4': 1, '5': 2, '10': 'audioLevel'},
    const {'1': 'transcription', '3': 9, '4': 1, '5': 9, '10': 'transcription'},
    const {'1': 'turn_response', '3': 10, '4': 1, '5': 9, '10': 'turnResponse'},
    const {'1': 'turn_audio_base64', '3': 11, '4': 1, '5': 9, '10': 'turnAudioBase64'},
    const {'1': 'error', '3': 12, '4': 1, '5': 9, '10': 'error'},
  ],
};

/// Descriptor for `VoiceLifecycleEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceLifecycleEventDescriptor = $convert.base64Decode('ChNWb2ljZUxpZmVjeWNsZUV2ZW50EjIKBGtpbmQYASABKA4yHi5ydW5hbnl3aGVyZS52MS5Wb2ljZUV2ZW50S2luZFIEa2luZBIdCgpzZXNzaW9uX2lkGAIgASgJUglzZXNzaW9uSWQSEgoEdGV4dBgDIAEoCVIEdGV4dBIeCgpjb25maWRlbmNlGAQgASgCUgpjb25maWRlbmNlEiMKDXJlc3BvbnNlX3RleHQYBSABKAlSDHJlc3BvbnNlVGV4dBIhCgxhdWRpb19iYXNlNjQYBiABKAlSC2F1ZGlvQmFzZTY0Eh8KC2R1cmF0aW9uX21zGAcgASgDUgpkdXJhdGlvbk1zEh8KC2F1ZGlvX2xldmVsGAggASgCUgphdWRpb0xldmVsEiQKDXRyYW5zY3JpcHRpb24YCSABKAlSDXRyYW5zY3JpcHRpb24SIwoNdHVybl9yZXNwb25zZRgKIAEoCVIMdHVyblJlc3BvbnNlEioKEXR1cm5fYXVkaW9fYmFzZTY0GAsgASgJUg90dXJuQXVkaW9CYXNlNjQSFAoFZXJyb3IYDCABKAlSBWVycm9y');
@$core.Deprecated('Use performanceEventDescriptor instead')
const PerformanceEvent$json = const {
  '1': 'PerformanceEvent',
  '2': const [
    const {'1': 'kind', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.PerformanceEventKind', '10': 'kind'},
    const {'1': 'memory_bytes', '3': 2, '4': 1, '5': 3, '10': 'memoryBytes'},
    const {'1': 'thermal_state', '3': 3, '4': 1, '5': 9, '10': 'thermalState'},
    const {'1': 'operation', '3': 4, '4': 1, '5': 9, '10': 'operation'},
    const {'1': 'milliseconds', '3': 5, '4': 1, '5': 3, '10': 'milliseconds'},
    const {'1': 'tokens_per_second', '3': 6, '4': 1, '5': 1, '10': 'tokensPerSecond'},
  ],
};

/// Descriptor for `PerformanceEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List performanceEventDescriptor = $convert.base64Decode('ChBQZXJmb3JtYW5jZUV2ZW50EjgKBGtpbmQYASABKA4yJC5ydW5hbnl3aGVyZS52MS5QZXJmb3JtYW5jZUV2ZW50S2luZFIEa2luZBIhCgxtZW1vcnlfYnl0ZXMYAiABKANSC21lbW9yeUJ5dGVzEiMKDXRoZXJtYWxfc3RhdGUYAyABKAlSDHRoZXJtYWxTdGF0ZRIcCglvcGVyYXRpb24YBCABKAlSCW9wZXJhdGlvbhIiCgxtaWxsaXNlY29uZHMYBSABKANSDG1pbGxpc2Vjb25kcxIqChF0b2tlbnNfcGVyX3NlY29uZBgGIAEoAVIPdG9rZW5zUGVyU2Vjb25k');
@$core.Deprecated('Use networkEventDescriptor instead')
const NetworkEvent$json = const {
  '1': 'NetworkEvent',
  '2': const [
    const {'1': 'kind', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.NetworkEventKind', '10': 'kind'},
    const {'1': 'url', '3': 2, '4': 1, '5': 9, '10': 'url'},
    const {'1': 'status_code', '3': 3, '4': 1, '5': 5, '10': 'statusCode'},
    const {'1': 'is_online', '3': 4, '4': 1, '5': 8, '10': 'isOnline'},
    const {'1': 'error', '3': 5, '4': 1, '5': 9, '10': 'error'},
    const {'1': 'latency_ms', '3': 6, '4': 1, '5': 3, '10': 'latencyMs'},
  ],
};

/// Descriptor for `NetworkEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List networkEventDescriptor = $convert.base64Decode('CgxOZXR3b3JrRXZlbnQSNAoEa2luZBgBIAEoDjIgLnJ1bmFueXdoZXJlLnYxLk5ldHdvcmtFdmVudEtpbmRSBGtpbmQSEAoDdXJsGAIgASgJUgN1cmwSHwoLc3RhdHVzX2NvZGUYAyABKAVSCnN0YXR1c0NvZGUSGwoJaXNfb25saW5lGAQgASgIUghpc09ubGluZRIUCgVlcnJvchgFIAEoCVIFZXJyb3ISHQoKbGF0ZW5jeV9tcxgGIAEoA1IJbGF0ZW5jeU1z');
@$core.Deprecated('Use storageEventDescriptor instead')
const StorageEvent$json = const {
  '1': 'StorageEvent',
  '2': const [
    const {'1': 'kind', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.StorageEventKind', '10': 'kind'},
    const {'1': 'model_id', '3': 2, '4': 1, '5': 9, '10': 'modelId'},
    const {'1': 'error', '3': 3, '4': 1, '5': 9, '10': 'error'},
    const {'1': 'total_bytes', '3': 4, '4': 1, '5': 3, '10': 'totalBytes'},
    const {'1': 'available_bytes', '3': 5, '4': 1, '5': 3, '10': 'availableBytes'},
    const {'1': 'used_bytes', '3': 6, '4': 1, '5': 3, '10': 'usedBytes'},
    const {'1': 'stored_model_count', '3': 7, '4': 1, '5': 5, '10': 'storedModelCount'},
    const {'1': 'cache_key', '3': 8, '4': 1, '5': 9, '10': 'cacheKey'},
    const {'1': 'evicted_bytes', '3': 9, '4': 1, '5': 3, '10': 'evictedBytes'},
  ],
};

/// Descriptor for `StorageEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List storageEventDescriptor = $convert.base64Decode('CgxTdG9yYWdlRXZlbnQSNAoEa2luZBgBIAEoDjIgLnJ1bmFueXdoZXJlLnYxLlN0b3JhZ2VFdmVudEtpbmRSBGtpbmQSGQoIbW9kZWxfaWQYAiABKAlSB21vZGVsSWQSFAoFZXJyb3IYAyABKAlSBWVycm9yEh8KC3RvdGFsX2J5dGVzGAQgASgDUgp0b3RhbEJ5dGVzEicKD2F2YWlsYWJsZV9ieXRlcxgFIAEoA1IOYXZhaWxhYmxlQnl0ZXMSHQoKdXNlZF9ieXRlcxgGIAEoA1IJdXNlZEJ5dGVzEiwKEnN0b3JlZF9tb2RlbF9jb3VudBgHIAEoBVIQc3RvcmVkTW9kZWxDb3VudBIbCgljYWNoZV9rZXkYCCABKAlSCGNhY2hlS2V5EiMKDWV2aWN0ZWRfYnl0ZXMYCSABKANSDGV2aWN0ZWRCeXRlcw==');
@$core.Deprecated('Use frameworkEventDescriptor instead')
const FrameworkEvent$json = const {
  '1': 'FrameworkEvent',
  '2': const [
    const {'1': 'kind', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.FrameworkEventKind', '10': 'kind'},
    const {'1': 'framework', '3': 2, '4': 1, '5': 5, '10': 'framework'},
    const {'1': 'adapter_name', '3': 3, '4': 1, '5': 9, '10': 'adapterName'},
    const {'1': 'adapter_count', '3': 4, '4': 1, '5': 5, '10': 'adapterCount'},
    const {'1': 'framework_count', '3': 5, '4': 1, '5': 5, '10': 'frameworkCount'},
    const {'1': 'model_count', '3': 6, '4': 1, '5': 5, '10': 'modelCount'},
    const {'1': 'modality', '3': 7, '4': 1, '5': 9, '10': 'modality'},
    const {'1': 'error', '3': 8, '4': 1, '5': 9, '10': 'error'},
  ],
};

/// Descriptor for `FrameworkEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List frameworkEventDescriptor = $convert.base64Decode('Cg5GcmFtZXdvcmtFdmVudBI2CgRraW5kGAEgASgOMiIucnVuYW55d2hlcmUudjEuRnJhbWV3b3JrRXZlbnRLaW5kUgRraW5kEhwKCWZyYW1ld29yaxgCIAEoBVIJZnJhbWV3b3JrEiEKDGFkYXB0ZXJfbmFtZRgDIAEoCVILYWRhcHRlck5hbWUSIwoNYWRhcHRlcl9jb3VudBgEIAEoBVIMYWRhcHRlckNvdW50EicKD2ZyYW1ld29ya19jb3VudBgFIAEoBVIOZnJhbWV3b3JrQ291bnQSHwoLbW9kZWxfY291bnQYBiABKAVSCm1vZGVsQ291bnQSGgoIbW9kYWxpdHkYByABKAlSCG1vZGFsaXR5EhQKBWVycm9yGAggASgJUgVlcnJvcg==');
@$core.Deprecated('Use deviceEventDescriptor instead')
const DeviceEvent$json = const {
  '1': 'DeviceEvent',
  '2': const [
    const {'1': 'kind', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.DeviceEventKind', '10': 'kind'},
    const {'1': 'device_id', '3': 2, '4': 1, '5': 9, '10': 'deviceId'},
    const {'1': 'os_name', '3': 3, '4': 1, '5': 9, '10': 'osName'},
    const {'1': 'os_version', '3': 4, '4': 1, '5': 9, '10': 'osVersion'},
    const {'1': 'model', '3': 5, '4': 1, '5': 9, '10': 'model'},
    const {'1': 'error', '3': 6, '4': 1, '5': 9, '10': 'error'},
    const {'1': 'property', '3': 7, '4': 1, '5': 9, '10': 'property'},
    const {'1': 'new_value', '3': 8, '4': 1, '5': 9, '10': 'newValue'},
    const {'1': 'old_value', '3': 9, '4': 1, '5': 9, '10': 'oldValue'},
    const {'1': 'battery_level', '3': 10, '4': 1, '5': 2, '10': 'batteryLevel'},
    const {'1': 'is_charging', '3': 11, '4': 1, '5': 8, '10': 'isCharging'},
    const {'1': 'thermal_state', '3': 12, '4': 1, '5': 9, '10': 'thermalState'},
    const {'1': 'is_connected', '3': 13, '4': 1, '5': 8, '10': 'isConnected'},
    const {'1': 'connection_type', '3': 14, '4': 1, '5': 9, '10': 'connectionType'},
  ],
};

/// Descriptor for `DeviceEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List deviceEventDescriptor = $convert.base64Decode('CgtEZXZpY2VFdmVudBIzCgRraW5kGAEgASgOMh8ucnVuYW55d2hlcmUudjEuRGV2aWNlRXZlbnRLaW5kUgRraW5kEhsKCWRldmljZV9pZBgCIAEoCVIIZGV2aWNlSWQSFwoHb3NfbmFtZRgDIAEoCVIGb3NOYW1lEh0KCm9zX3ZlcnNpb24YBCABKAlSCW9zVmVyc2lvbhIUCgVtb2RlbBgFIAEoCVIFbW9kZWwSFAoFZXJyb3IYBiABKAlSBWVycm9yEhoKCHByb3BlcnR5GAcgASgJUghwcm9wZXJ0eRIbCgluZXdfdmFsdWUYCCABKAlSCG5ld1ZhbHVlEhsKCW9sZF92YWx1ZRgJIAEoCVIIb2xkVmFsdWUSIwoNYmF0dGVyeV9sZXZlbBgKIAEoAlIMYmF0dGVyeUxldmVsEh8KC2lzX2NoYXJnaW5nGAsgASgIUgppc0NoYXJnaW5nEiMKDXRoZXJtYWxfc3RhdGUYDCABKAlSDHRoZXJtYWxTdGF0ZRIhCgxpc19jb25uZWN0ZWQYDSABKAhSC2lzQ29ubmVjdGVkEicKD2Nvbm5lY3Rpb25fdHlwZRgOIAEoCVIOY29ubmVjdGlvblR5cGU=');
@$core.Deprecated('Use componentInitializationEventDescriptor instead')
const ComponentInitializationEvent$json = const {
  '1': 'ComponentInitializationEvent',
  '2': const [
    const {'1': 'kind', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.ComponentInitializationEventKind', '10': 'kind'},
    const {'1': 'component', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.SDKComponent', '10': 'component'},
    const {'1': 'model_id', '3': 3, '4': 1, '5': 9, '10': 'modelId'},
    const {'1': 'size_bytes', '3': 4, '4': 1, '5': 3, '10': 'sizeBytes'},
    const {'1': 'progress', '3': 5, '4': 1, '5': 2, '10': 'progress'},
    const {'1': 'error', '3': 6, '4': 1, '5': 9, '10': 'error'},
    const {'1': 'old_state', '3': 7, '4': 1, '5': 9, '10': 'oldState'},
    const {'1': 'new_state', '3': 8, '4': 1, '5': 9, '10': 'newState'},
    const {'1': 'components', '3': 9, '4': 3, '5': 14, '6': '.runanywhere.v1.SDKComponent', '10': 'components'},
    const {'1': 'ready_components', '3': 10, '4': 3, '5': 14, '6': '.runanywhere.v1.SDKComponent', '10': 'readyComponents'},
    const {'1': 'pending_components', '3': 11, '4': 3, '5': 14, '6': '.runanywhere.v1.SDKComponent', '10': 'pendingComponents'},
    const {'1': 'init_success', '3': 12, '4': 1, '5': 8, '10': 'initSuccess'},
    const {'1': 'ready_count', '3': 13, '4': 1, '5': 5, '10': 'readyCount'},
    const {'1': 'failed_count', '3': 14, '4': 1, '5': 5, '10': 'failedCount'},
  ],
};

/// Descriptor for `ComponentInitializationEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List componentInitializationEventDescriptor = $convert.base64Decode('ChxDb21wb25lbnRJbml0aWFsaXphdGlvbkV2ZW50EkQKBGtpbmQYASABKA4yMC5ydW5hbnl3aGVyZS52MS5Db21wb25lbnRJbml0aWFsaXphdGlvbkV2ZW50S2luZFIEa2luZBI6Cgljb21wb25lbnQYAiABKA4yHC5ydW5hbnl3aGVyZS52MS5TREtDb21wb25lbnRSCWNvbXBvbmVudBIZCghtb2RlbF9pZBgDIAEoCVIHbW9kZWxJZBIdCgpzaXplX2J5dGVzGAQgASgDUglzaXplQnl0ZXMSGgoIcHJvZ3Jlc3MYBSABKAJSCHByb2dyZXNzEhQKBWVycm9yGAYgASgJUgVlcnJvchIbCglvbGRfc3RhdGUYByABKAlSCG9sZFN0YXRlEhsKCW5ld19zdGF0ZRgIIAEoCVIIbmV3U3RhdGUSPAoKY29tcG9uZW50cxgJIAMoDjIcLnJ1bmFueXdoZXJlLnYxLlNES0NvbXBvbmVudFIKY29tcG9uZW50cxJHChByZWFkeV9jb21wb25lbnRzGAogAygOMhwucnVuYW55d2hlcmUudjEuU0RLQ29tcG9uZW50Ug9yZWFkeUNvbXBvbmVudHMSSwoScGVuZGluZ19jb21wb25lbnRzGAsgAygOMhwucnVuYW55d2hlcmUudjEuU0RLQ29tcG9uZW50UhFwZW5kaW5nQ29tcG9uZW50cxIhCgxpbml0X3N1Y2Nlc3MYDCABKAhSC2luaXRTdWNjZXNzEh8KC3JlYWR5X2NvdW50GA0gASgFUgpyZWFkeUNvdW50EiEKDGZhaWxlZF9jb3VudBgOIAEoBVILZmFpbGVkQ291bnQ=');
@$core.Deprecated('Use sDKEventDescriptor instead')
const SDKEvent$json = const {
  '1': 'SDKEvent',
  '2': const [
    const {'1': 'timestamp_ms', '3': 1, '4': 1, '5': 3, '10': 'timestampMs'},
    const {'1': 'severity', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.EventSeverity', '10': 'severity'},
    const {'1': 'id', '3': 13, '4': 1, '5': 9, '10': 'id'},
    const {'1': 'session_id', '3': 14, '4': 1, '5': 9, '10': 'sessionId'},
    const {'1': 'destination', '3': 15, '4': 1, '5': 14, '6': '.runanywhere.v1.EventDestination', '10': 'destination'},
    const {'1': 'properties', '3': 16, '4': 3, '5': 11, '6': '.runanywhere.v1.SDKEvent.PropertiesEntry', '10': 'properties'},
    const {'1': 'initialization', '3': 3, '4': 1, '5': 11, '6': '.runanywhere.v1.InitializationEvent', '9': 0, '10': 'initialization'},
    const {'1': 'configuration', '3': 4, '4': 1, '5': 11, '6': '.runanywhere.v1.ConfigurationEvent', '9': 0, '10': 'configuration'},
    const {'1': 'generation', '3': 5, '4': 1, '5': 11, '6': '.runanywhere.v1.GenerationEvent', '9': 0, '10': 'generation'},
    const {'1': 'model', '3': 6, '4': 1, '5': 11, '6': '.runanywhere.v1.ModelEvent', '9': 0, '10': 'model'},
    const {'1': 'performance', '3': 7, '4': 1, '5': 11, '6': '.runanywhere.v1.PerformanceEvent', '9': 0, '10': 'performance'},
    const {'1': 'network', '3': 8, '4': 1, '5': 11, '6': '.runanywhere.v1.NetworkEvent', '9': 0, '10': 'network'},
    const {'1': 'storage', '3': 9, '4': 1, '5': 11, '6': '.runanywhere.v1.StorageEvent', '9': 0, '10': 'storage'},
    const {'1': 'framework', '3': 10, '4': 1, '5': 11, '6': '.runanywhere.v1.FrameworkEvent', '9': 0, '10': 'framework'},
    const {'1': 'device', '3': 11, '4': 1, '5': 11, '6': '.runanywhere.v1.DeviceEvent', '9': 0, '10': 'device'},
    const {'1': 'component_init', '3': 12, '4': 1, '5': 11, '6': '.runanywhere.v1.ComponentInitializationEvent', '9': 0, '10': 'componentInit'},
    const {'1': 'voice', '3': 17, '4': 1, '5': 11, '6': '.runanywhere.v1.VoiceLifecycleEvent', '9': 0, '10': 'voice'},
    const {'1': 'voice_pipeline', '3': 18, '4': 1, '5': 11, '6': '.runanywhere.v1.VoiceEvent', '9': 0, '10': 'voicePipeline'},
  ],
  '3': const [SDKEvent_PropertiesEntry$json],
  '8': const [
    const {'1': 'event'},
  ],
};

@$core.Deprecated('Use sDKEventDescriptor instead')
const SDKEvent_PropertiesEntry$json = const {
  '1': 'PropertiesEntry',
  '2': const [
    const {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    const {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': const {'7': true},
};

/// Descriptor for `SDKEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sDKEventDescriptor = $convert.base64Decode('CghTREtFdmVudBIhCgx0aW1lc3RhbXBfbXMYASABKANSC3RpbWVzdGFtcE1zEjkKCHNldmVyaXR5GAIgASgOMh0ucnVuYW55d2hlcmUudjEuRXZlbnRTZXZlcml0eVIIc2V2ZXJpdHkSDgoCaWQYDSABKAlSAmlkEh0KCnNlc3Npb25faWQYDiABKAlSCXNlc3Npb25JZBJCCgtkZXN0aW5hdGlvbhgPIAEoDjIgLnJ1bmFueXdoZXJlLnYxLkV2ZW50RGVzdGluYXRpb25SC2Rlc3RpbmF0aW9uEkgKCnByb3BlcnRpZXMYECADKAsyKC5ydW5hbnl3aGVyZS52MS5TREtFdmVudC5Qcm9wZXJ0aWVzRW50cnlSCnByb3BlcnRpZXMSTQoOaW5pdGlhbGl6YXRpb24YAyABKAsyIy5ydW5hbnl3aGVyZS52MS5Jbml0aWFsaXphdGlvbkV2ZW50SABSDmluaXRpYWxpemF0aW9uEkoKDWNvbmZpZ3VyYXRpb24YBCABKAsyIi5ydW5hbnl3aGVyZS52MS5Db25maWd1cmF0aW9uRXZlbnRIAFINY29uZmlndXJhdGlvbhJBCgpnZW5lcmF0aW9uGAUgASgLMh8ucnVuYW55d2hlcmUudjEuR2VuZXJhdGlvbkV2ZW50SABSCmdlbmVyYXRpb24SMgoFbW9kZWwYBiABKAsyGi5ydW5hbnl3aGVyZS52MS5Nb2RlbEV2ZW50SABSBW1vZGVsEkQKC3BlcmZvcm1hbmNlGAcgASgLMiAucnVuYW55d2hlcmUudjEuUGVyZm9ybWFuY2VFdmVudEgAUgtwZXJmb3JtYW5jZRI4CgduZXR3b3JrGAggASgLMhwucnVuYW55d2hlcmUudjEuTmV0d29ya0V2ZW50SABSB25ldHdvcmsSOAoHc3RvcmFnZRgJIAEoCzIcLnJ1bmFueXdoZXJlLnYxLlN0b3JhZ2VFdmVudEgAUgdzdG9yYWdlEj4KCWZyYW1ld29yaxgKIAEoCzIeLnJ1bmFueXdoZXJlLnYxLkZyYW1ld29ya0V2ZW50SABSCWZyYW1ld29yaxI1CgZkZXZpY2UYCyABKAsyGy5ydW5hbnl3aGVyZS52MS5EZXZpY2VFdmVudEgAUgZkZXZpY2USVQoOY29tcG9uZW50X2luaXQYDCABKAsyLC5ydW5hbnl3aGVyZS52MS5Db21wb25lbnRJbml0aWFsaXphdGlvbkV2ZW50SABSDWNvbXBvbmVudEluaXQSOwoFdm9pY2UYESABKAsyIy5ydW5hbnl3aGVyZS52MS5Wb2ljZUxpZmVjeWNsZUV2ZW50SABSBXZvaWNlEkMKDnZvaWNlX3BpcGVsaW5lGBIgASgLMhoucnVuYW55d2hlcmUudjEuVm9pY2VFdmVudEgAUg12b2ljZVBpcGVsaW5lGj0KD1Byb3BlcnRpZXNFbnRyeRIQCgNrZXkYASABKAlSA2tleRIUCgV2YWx1ZRgCIAEoCVIFdmFsdWU6AjgBQgcKBWV2ZW50');
