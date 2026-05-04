//
//  Generated code. Do not modify.
//  source: voice_events.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

@$core.Deprecated('Use voiceEventCategoryDescriptor instead')
const VoiceEventCategory$json = {
  '1': 'VoiceEventCategory',
  '2': [
    {'1': 'VOICE_EVENT_CATEGORY_UNSPECIFIED', '2': 0},
    {'1': 'VOICE_EVENT_CATEGORY_VOICE_AGENT', '2': 1},
    {'1': 'VOICE_EVENT_CATEGORY_STT', '2': 2},
    {'1': 'VOICE_EVENT_CATEGORY_ASR', '2': 3},
    {'1': 'VOICE_EVENT_CATEGORY_TTS', '2': 4},
    {'1': 'VOICE_EVENT_CATEGORY_VAD', '2': 5},
    {'1': 'VOICE_EVENT_CATEGORY_STD', '2': 6},
    {'1': 'VOICE_EVENT_CATEGORY_LLM', '2': 7},
    {'1': 'VOICE_EVENT_CATEGORY_AUDIO', '2': 8},
    {'1': 'VOICE_EVENT_CATEGORY_METRICS', '2': 9},
    {'1': 'VOICE_EVENT_CATEGORY_ERROR', '2': 10},
    {'1': 'VOICE_EVENT_CATEGORY_WAKEWORD', '2': 11},
  ],
};

/// Descriptor for `VoiceEventCategory`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List voiceEventCategoryDescriptor = $convert.base64Decode(
    'ChJWb2ljZUV2ZW50Q2F0ZWdvcnkSJAogVk9JQ0VfRVZFTlRfQ0FURUdPUllfVU5TUEVDSUZJRU'
    'QQABIkCiBWT0lDRV9FVkVOVF9DQVRFR09SWV9WT0lDRV9BR0VOVBABEhwKGFZPSUNFX0VWRU5U'
    'X0NBVEVHT1JZX1NUVBACEhwKGFZPSUNFX0VWRU5UX0NBVEVHT1JZX0FTUhADEhwKGFZPSUNFX0'
    'VWRU5UX0NBVEVHT1JZX1RUUxAEEhwKGFZPSUNFX0VWRU5UX0NBVEVHT1JZX1ZBRBAFEhwKGFZP'
    'SUNFX0VWRU5UX0NBVEVHT1JZX1NURBAGEhwKGFZPSUNFX0VWRU5UX0NBVEVHT1JZX0xMTRAHEh'
    '4KGlZPSUNFX0VWRU5UX0NBVEVHT1JZX0FVRElPEAgSIAocVk9JQ0VfRVZFTlRfQ0FURUdPUllf'
    'TUVUUklDUxAJEh4KGlZPSUNFX0VWRU5UX0NBVEVHT1JZX0VSUk9SEAoSIQodVk9JQ0VfRVZFTl'
    'RfQ0FURUdPUllfV0FLRVdPUkQQCw==');

@$core.Deprecated('Use voiceEventSeverityDescriptor instead')
const VoiceEventSeverity$json = {
  '1': 'VoiceEventSeverity',
  '2': [
    {'1': 'VOICE_EVENT_SEVERITY_DEBUG', '2': 0},
    {'1': 'VOICE_EVENT_SEVERITY_INFO', '2': 1},
    {'1': 'VOICE_EVENT_SEVERITY_WARNING', '2': 2},
    {'1': 'VOICE_EVENT_SEVERITY_ERROR', '2': 3},
    {'1': 'VOICE_EVENT_SEVERITY_CRITICAL', '2': 4},
  ],
};

/// Descriptor for `VoiceEventSeverity`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List voiceEventSeverityDescriptor = $convert.base64Decode(
    'ChJWb2ljZUV2ZW50U2V2ZXJpdHkSHgoaVk9JQ0VfRVZFTlRfU0VWRVJJVFlfREVCVUcQABIdCh'
    'lWT0lDRV9FVkVOVF9TRVZFUklUWV9JTkZPEAESIAocVk9JQ0VfRVZFTlRfU0VWRVJJVFlfV0FS'
    'TklORxACEh4KGlZPSUNFX0VWRU5UX1NFVkVSSVRZX0VSUk9SEAMSIQodVk9JQ0VfRVZFTlRfU0'
    'VWRVJJVFlfQ1JJVElDQUwQBA==');

@$core.Deprecated('Use voicePipelineComponentDescriptor instead')
const VoicePipelineComponent$json = {
  '1': 'VoicePipelineComponent',
  '2': [
    {'1': 'VOICE_PIPELINE_COMPONENT_UNSPECIFIED', '2': 0},
    {'1': 'VOICE_PIPELINE_COMPONENT_AGENT', '2': 1},
    {'1': 'VOICE_PIPELINE_COMPONENT_STT', '2': 2},
    {'1': 'VOICE_PIPELINE_COMPONENT_ASR', '2': 3},
    {'1': 'VOICE_PIPELINE_COMPONENT_TTS', '2': 4},
    {'1': 'VOICE_PIPELINE_COMPONENT_VAD', '2': 5},
    {'1': 'VOICE_PIPELINE_COMPONENT_STD', '2': 6},
    {'1': 'VOICE_PIPELINE_COMPONENT_LLM', '2': 7},
    {'1': 'VOICE_PIPELINE_COMPONENT_AUDIO', '2': 8},
    {'1': 'VOICE_PIPELINE_COMPONENT_WAKEWORD', '2': 9},
  ],
};

/// Descriptor for `VoicePipelineComponent`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List voicePipelineComponentDescriptor = $convert.base64Decode(
    'ChZWb2ljZVBpcGVsaW5lQ29tcG9uZW50EigKJFZPSUNFX1BJUEVMSU5FX0NPTVBPTkVOVF9VTl'
    'NQRUNJRklFRBAAEiIKHlZPSUNFX1BJUEVMSU5FX0NPTVBPTkVOVF9BR0VOVBABEiAKHFZPSUNF'
    'X1BJUEVMSU5FX0NPTVBPTkVOVF9TVFQQAhIgChxWT0lDRV9QSVBFTElORV9DT01QT05FTlRfQV'
    'NSEAMSIAocVk9JQ0VfUElQRUxJTkVfQ09NUE9ORU5UX1RUUxAEEiAKHFZPSUNFX1BJUEVMSU5F'
    'X0NPTVBPTkVOVF9WQUQQBRIgChxWT0lDRV9QSVBFTElORV9DT01QT05FTlRfU1REEAYSIAocVk'
    '9JQ0VfUElQRUxJTkVfQ09NUE9ORU5UX0xMTRAHEiIKHlZPSUNFX1BJUEVMSU5FX0NPTVBPTkVO'
    'VF9BVURJTxAIEiUKIVZPSUNFX1BJUEVMSU5FX0NPTVBPTkVOVF9XQUtFV09SRBAJ');

@$core.Deprecated('Use tokenKindDescriptor instead')
const TokenKind$json = {
  '1': 'TokenKind',
  '2': [
    {'1': 'TOKEN_KIND_UNSPECIFIED', '2': 0},
    {'1': 'TOKEN_KIND_ANSWER', '2': 1},
    {'1': 'TOKEN_KIND_THOUGHT', '2': 2},
    {'1': 'TOKEN_KIND_TOOL_CALL', '2': 3},
  ],
};

/// Descriptor for `TokenKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List tokenKindDescriptor = $convert.base64Decode(
    'CglUb2tlbktpbmQSGgoWVE9LRU5fS0lORF9VTlNQRUNJRklFRBAAEhUKEVRPS0VOX0tJTkRfQU'
    '5TV0VSEAESFgoSVE9LRU5fS0lORF9USE9VR0hUEAISGAoUVE9LRU5fS0lORF9UT09MX0NBTEwQ'
    'Aw==');

@$core.Deprecated('Use audioEncodingDescriptor instead')
const AudioEncoding$json = {
  '1': 'AudioEncoding',
  '2': [
    {'1': 'AUDIO_ENCODING_UNSPECIFIED', '2': 0},
    {'1': 'AUDIO_ENCODING_PCM_F32_LE', '2': 1},
    {'1': 'AUDIO_ENCODING_PCM_S16_LE', '2': 2},
  ],
};

/// Descriptor for `AudioEncoding`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List audioEncodingDescriptor = $convert.base64Decode(
    'Cg1BdWRpb0VuY29kaW5nEh4KGkFVRElPX0VOQ09ESU5HX1VOU1BFQ0lGSUVEEAASHQoZQVVESU'
    '9fRU5DT0RJTkdfUENNX0YzMl9MRRABEh0KGUFVRElPX0VOQ09ESU5HX1BDTV9TMTZfTEUQAg==');

@$core.Deprecated('Use vADEventTypeDescriptor instead')
const VADEventType$json = {
  '1': 'VADEventType',
  '2': [
    {'1': 'VAD_EVENT_UNSPECIFIED', '2': 0},
    {'1': 'VAD_EVENT_VOICE_START', '2': 1},
    {'1': 'VAD_EVENT_VOICE_END_OF_UTTERANCE', '2': 2},
    {'1': 'VAD_EVENT_BARGE_IN', '2': 3},
    {'1': 'VAD_EVENT_SILENCE', '2': 4},
    {'1': 'VAD_EVENT_STATISTICS', '2': 5},
    {'1': 'VAD_EVENT_STATE_CHANGED', '2': 6},
  ],
};

/// Descriptor for `VADEventType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List vADEventTypeDescriptor = $convert.base64Decode(
    'CgxWQURFdmVudFR5cGUSGQoVVkFEX0VWRU5UX1VOU1BFQ0lGSUVEEAASGQoVVkFEX0VWRU5UX1'
    'ZPSUNFX1NUQVJUEAESJAogVkFEX0VWRU5UX1ZPSUNFX0VORF9PRl9VVFRFUkFOQ0UQAhIWChJW'
    'QURfRVZFTlRfQkFSR0VfSU4QAxIVChFWQURfRVZFTlRfU0lMRU5DRRAEEhgKFFZBRF9FVkVOVF'
    '9TVEFUSVNUSUNTEAUSGwoXVkFEX0VWRU5UX1NUQVRFX0NIQU5HRUQQBg==');

@$core.Deprecated('Use interruptReasonDescriptor instead')
const InterruptReason$json = {
  '1': 'InterruptReason',
  '2': [
    {'1': 'INTERRUPT_REASON_UNSPECIFIED', '2': 0},
    {'1': 'INTERRUPT_REASON_USER_BARGE_IN', '2': 1},
    {'1': 'INTERRUPT_REASON_APP_STOP', '2': 2},
    {'1': 'INTERRUPT_REASON_AUDIO_ROUTE_CHANGE', '2': 3},
    {'1': 'INTERRUPT_REASON_TIMEOUT', '2': 4},
  ],
};

/// Descriptor for `InterruptReason`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List interruptReasonDescriptor = $convert.base64Decode(
    'Cg9JbnRlcnJ1cHRSZWFzb24SIAocSU5URVJSVVBUX1JFQVNPTl9VTlNQRUNJRklFRBAAEiIKHk'
    'lOVEVSUlVQVF9SRUFTT05fVVNFUl9CQVJHRV9JThABEh0KGUlOVEVSUlVQVF9SRUFTT05fQVBQ'
    'X1NUT1AQAhInCiNJTlRFUlJVUFRfUkVBU09OX0FVRElPX1JPVVRFX0NIQU5HRRADEhwKGElOVE'
    'VSUlVQVF9SRUFTT05fVElNRU9VVBAE');

@$core.Deprecated('Use pipelineStateDescriptor instead')
const PipelineState$json = {
  '1': 'PipelineState',
  '2': [
    {'1': 'PIPELINE_STATE_UNSPECIFIED', '2': 0},
    {'1': 'PIPELINE_STATE_IDLE', '2': 1},
    {'1': 'PIPELINE_STATE_LISTENING', '2': 2},
    {'1': 'PIPELINE_STATE_THINKING', '2': 3},
    {'1': 'PIPELINE_STATE_SPEAKING', '2': 4},
    {'1': 'PIPELINE_STATE_STOPPED', '2': 5},
    {'1': 'PIPELINE_STATE_WAITING_WAKEWORD', '2': 6},
    {'1': 'PIPELINE_STATE_PROCESSING_SPEECH', '2': 7},
    {'1': 'PIPELINE_STATE_GENERATING_RESPONSE', '2': 8},
    {'1': 'PIPELINE_STATE_PLAYING_TTS', '2': 9},
    {'1': 'PIPELINE_STATE_COOLDOWN', '2': 10},
    {'1': 'PIPELINE_STATE_ERROR', '2': 11},
  ],
};

/// Descriptor for `PipelineState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List pipelineStateDescriptor = $convert.base64Decode(
    'Cg1QaXBlbGluZVN0YXRlEh4KGlBJUEVMSU5FX1NUQVRFX1VOU1BFQ0lGSUVEEAASFwoTUElQRU'
    'xJTkVfU1RBVEVfSURMRRABEhwKGFBJUEVMSU5FX1NUQVRFX0xJU1RFTklORxACEhsKF1BJUEVM'
    'SU5FX1NUQVRFX1RISU5LSU5HEAMSGwoXUElQRUxJTkVfU1RBVEVfU1BFQUtJTkcQBBIaChZQSV'
    'BFTElORV9TVEFURV9TVE9QUEVEEAUSIwofUElQRUxJTkVfU1RBVEVfV0FJVElOR19XQUtFV09S'
    'RBAGEiQKIFBJUEVMSU5FX1NUQVRFX1BST0NFU1NJTkdfU1BFRUNIEAcSJgoiUElQRUxJTkVfU1'
    'RBVEVfR0VORVJBVElOR19SRVNQT05TRRAIEh4KGlBJUEVMSU5FX1NUQVRFX1BMQVlJTkdfVFRT'
    'EAkSGwoXUElQRUxJTkVfU1RBVEVfQ09PTERPV04QChIYChRQSVBFTElORV9TVEFURV9FUlJPUh'
    'AL');

@$core.Deprecated('Use componentLoadStateDescriptor instead')
const ComponentLoadState$json = {
  '1': 'ComponentLoadState',
  '2': [
    {'1': 'COMPONENT_LOAD_STATE_UNSPECIFIED', '2': 0},
    {'1': 'COMPONENT_LOAD_STATE_NOT_LOADED', '2': 1},
    {'1': 'COMPONENT_LOAD_STATE_LOADING', '2': 2},
    {'1': 'COMPONENT_LOAD_STATE_LOADED', '2': 3},
    {'1': 'COMPONENT_LOAD_STATE_ERROR', '2': 4},
  ],
};

/// Descriptor for `ComponentLoadState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List componentLoadStateDescriptor = $convert.base64Decode(
    'ChJDb21wb25lbnRMb2FkU3RhdGUSJAogQ09NUE9ORU5UX0xPQURfU1RBVEVfVU5TUEVDSUZJRU'
    'QQABIjCh9DT01QT05FTlRfTE9BRF9TVEFURV9OT1RfTE9BREVEEAESIAocQ09NUE9ORU5UX0xP'
    'QURfU1RBVEVfTE9BRElORxACEh8KG0NPTVBPTkVOVF9MT0FEX1NUQVRFX0xPQURFRBADEh4KGk'
    'NPTVBPTkVOVF9MT0FEX1NUQVRFX0VSUk9SEAQ=');

@$core.Deprecated('Use voiceSessionErrorCodeDescriptor instead')
const VoiceSessionErrorCode$json = {
  '1': 'VoiceSessionErrorCode',
  '2': [
    {'1': 'VOICE_SESSION_ERROR_CODE_UNSPECIFIED', '2': 0},
    {'1': 'VOICE_SESSION_ERROR_CODE_MICROPHONE_PERMISSION_DENIED', '2': 1},
    {'1': 'VOICE_SESSION_ERROR_CODE_NOT_READY', '2': 2},
    {'1': 'VOICE_SESSION_ERROR_CODE_ALREADY_RUNNING', '2': 3},
    {'1': 'VOICE_SESSION_ERROR_CODE_COMPONENT_FAILURE', '2': 4},
  ],
};

/// Descriptor for `VoiceSessionErrorCode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List voiceSessionErrorCodeDescriptor = $convert.base64Decode(
    'ChVWb2ljZVNlc3Npb25FcnJvckNvZGUSKAokVk9JQ0VfU0VTU0lPTl9FUlJPUl9DT0RFX1VOU1'
    'BFQ0lGSUVEEAASOQo1Vk9JQ0VfU0VTU0lPTl9FUlJPUl9DT0RFX01JQ1JPUEhPTkVfUEVSTUlT'
    'U0lPTl9ERU5JRUQQARImCiJWT0lDRV9TRVNTSU9OX0VSUk9SX0NPREVfTk9UX1JFQURZEAISLA'
    'ooVk9JQ0VfU0VTU0lPTl9FUlJPUl9DT0RFX0FMUkVBRFlfUlVOTklORxADEi4KKlZPSUNFX1NF'
    'U1NJT05fRVJST1JfQ09ERV9DT01QT05FTlRfRkFJTFVSRRAE');

@$core.Deprecated('Use speechTurnDetectionEventKindDescriptor instead')
const SpeechTurnDetectionEventKind$json = {
  '1': 'SpeechTurnDetectionEventKind',
  '2': [
    {'1': 'SPEECH_TURN_DETECTION_EVENT_KIND_UNSPECIFIED', '2': 0},
    {'1': 'SPEECH_TURN_DETECTION_EVENT_KIND_TURN_STARTED', '2': 1},
    {'1': 'SPEECH_TURN_DETECTION_EVENT_KIND_TURN_ENDED', '2': 2},
    {'1': 'SPEECH_TURN_DETECTION_EVENT_KIND_SPEAKER_CHANGED', '2': 3},
    {'1': 'SPEECH_TURN_DETECTION_EVENT_KIND_STATISTICS', '2': 4},
  ],
};

/// Descriptor for `SpeechTurnDetectionEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List speechTurnDetectionEventKindDescriptor = $convert.base64Decode(
    'ChxTcGVlY2hUdXJuRGV0ZWN0aW9uRXZlbnRLaW5kEjAKLFNQRUVDSF9UVVJOX0RFVEVDVElPTl'
    '9FVkVOVF9LSU5EX1VOU1BFQ0lGSUVEEAASMQotU1BFRUNIX1RVUk5fREVURUNUSU9OX0VWRU5U'
    'X0tJTkRfVFVSTl9TVEFSVEVEEAESLworU1BFRUNIX1RVUk5fREVURUNUSU9OX0VWRU5UX0tJTk'
    'RfVFVSTl9FTkRFRBACEjQKMFNQRUVDSF9UVVJOX0RFVEVDVElPTl9FVkVOVF9LSU5EX1NQRUFL'
    'RVJfQ0hBTkdFRBADEi8KK1NQRUVDSF9UVVJOX0RFVEVDVElPTl9FVkVOVF9LSU5EX1NUQVRJU1'
    'RJQ1MQBA==');

@$core.Deprecated('Use turnLifecycleEventKindDescriptor instead')
const TurnLifecycleEventKind$json = {
  '1': 'TurnLifecycleEventKind',
  '2': [
    {'1': 'TURN_LIFECYCLE_EVENT_KIND_UNSPECIFIED', '2': 0},
    {'1': 'TURN_LIFECYCLE_EVENT_KIND_STARTED', '2': 1},
    {'1': 'TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_STARTED', '2': 2},
    {'1': 'TURN_LIFECYCLE_EVENT_KIND_USER_SPEECH_ENDED', '2': 3},
    {'1': 'TURN_LIFECYCLE_EVENT_KIND_TRANSCRIPTION_FINAL', '2': 4},
    {'1': 'TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_STARTED', '2': 5},
    {'1': 'TURN_LIFECYCLE_EVENT_KIND_AGENT_RESPONSE_COMPLETED', '2': 6},
    {'1': 'TURN_LIFECYCLE_EVENT_KIND_COMPLETED', '2': 7},
    {'1': 'TURN_LIFECYCLE_EVENT_KIND_CANCELLED', '2': 8},
    {'1': 'TURN_LIFECYCLE_EVENT_KIND_FAILED', '2': 9},
  ],
};

/// Descriptor for `TurnLifecycleEventKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List turnLifecycleEventKindDescriptor = $convert.base64Decode(
    'ChZUdXJuTGlmZWN5Y2xlRXZlbnRLaW5kEikKJVRVUk5fTElGRUNZQ0xFX0VWRU5UX0tJTkRfVU'
    '5TUEVDSUZJRUQQABIlCiFUVVJOX0xJRkVDWUNMRV9FVkVOVF9LSU5EX1NUQVJURUQQARIxCi1U'
    'VVJOX0xJRkVDWUNMRV9FVkVOVF9LSU5EX1VTRVJfU1BFRUNIX1NUQVJURUQQAhIvCitUVVJOX0'
    'xJRkVDWUNMRV9FVkVOVF9LSU5EX1VTRVJfU1BFRUNIX0VOREVEEAMSMQotVFVSTl9MSUZFQ1lD'
    'TEVfRVZFTlRfS0lORF9UUkFOU0NSSVBUSU9OX0ZJTkFMEAQSNAowVFVSTl9MSUZFQ1lDTEVfRV'
    'ZFTlRfS0lORF9BR0VOVF9SRVNQT05TRV9TVEFSVEVEEAUSNgoyVFVSTl9MSUZFQ1lDTEVfRVZF'
    'TlRfS0lORF9BR0VOVF9SRVNQT05TRV9DT01QTEVURUQQBhInCiNUVVJOX0xJRkVDWUNMRV9FVk'
    'VOVF9LSU5EX0NPTVBMRVRFRBAHEicKI1RVUk5fTElGRUNZQ0xFX0VWRU5UX0tJTkRfQ0FOQ0VM'
    'TEVEEAgSJAogVFVSTl9MSUZFQ1lDTEVfRVZFTlRfS0lORF9GQUlMRUQQCQ==');

@$core.Deprecated('Use voiceEventDescriptor instead')
const VoiceEvent$json = {
  '1': 'VoiceEvent',
  '2': [
    {'1': 'seq', '3': 1, '4': 1, '5': 4, '10': 'seq'},
    {'1': 'timestamp_us', '3': 2, '4': 1, '5': 3, '10': 'timestampUs'},
    {'1': 'category', '3': 3, '4': 1, '5': 14, '6': '.runanywhere.v1.VoiceEventCategory', '10': 'category'},
    {'1': 'severity', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.VoiceEventSeverity', '10': 'severity'},
    {'1': 'component', '3': 5, '4': 1, '5': 14, '6': '.runanywhere.v1.VoicePipelineComponent', '10': 'component'},
    {'1': 'user_said', '3': 10, '4': 1, '5': 11, '6': '.runanywhere.v1.UserSaidEvent', '9': 0, '10': 'userSaid'},
    {'1': 'assistant_token', '3': 11, '4': 1, '5': 11, '6': '.runanywhere.v1.AssistantTokenEvent', '9': 0, '10': 'assistantToken'},
    {'1': 'audio', '3': 12, '4': 1, '5': 11, '6': '.runanywhere.v1.AudioFrameEvent', '9': 0, '10': 'audio'},
    {'1': 'vad', '3': 13, '4': 1, '5': 11, '6': '.runanywhere.v1.VADEvent', '9': 0, '10': 'vad'},
    {'1': 'interrupted', '3': 14, '4': 1, '5': 11, '6': '.runanywhere.v1.InterruptedEvent', '9': 0, '10': 'interrupted'},
    {'1': 'state', '3': 15, '4': 1, '5': 11, '6': '.runanywhere.v1.StateChangeEvent', '9': 0, '10': 'state'},
    {'1': 'error', '3': 16, '4': 1, '5': 11, '6': '.runanywhere.v1.ErrorEvent', '9': 0, '10': 'error'},
    {'1': 'metrics', '3': 17, '4': 1, '5': 11, '6': '.runanywhere.v1.MetricsEvent', '9': 0, '10': 'metrics'},
    {'1': 'component_state_changed', '3': 18, '4': 1, '5': 11, '6': '.runanywhere.v1.VoiceAgentComponentStates', '9': 0, '10': 'componentStateChanged'},
    {'1': 'session_error', '3': 19, '4': 1, '5': 11, '6': '.runanywhere.v1.VoiceSessionError', '9': 0, '10': 'sessionError'},
    {'1': 'session_started', '3': 20, '4': 1, '5': 11, '6': '.runanywhere.v1.SessionStartedEvent', '9': 0, '10': 'sessionStarted'},
    {'1': 'session_stopped', '3': 21, '4': 1, '5': 11, '6': '.runanywhere.v1.SessionStoppedEvent', '9': 0, '10': 'sessionStopped'},
    {'1': 'agent_response_started', '3': 22, '4': 1, '5': 11, '6': '.runanywhere.v1.AgentResponseStartedEvent', '9': 0, '10': 'agentResponseStarted'},
    {'1': 'agent_response_completed', '3': 23, '4': 1, '5': 11, '6': '.runanywhere.v1.AgentResponseCompletedEvent', '9': 0, '10': 'agentResponseCompleted'},
    {'1': 'speech_turn_detection', '3': 24, '4': 1, '5': 11, '6': '.runanywhere.v1.SpeechTurnDetectionEvent', '9': 0, '10': 'speechTurnDetection'},
    {'1': 'turn_lifecycle', '3': 25, '4': 1, '5': 11, '6': '.runanywhere.v1.TurnLifecycleEvent', '9': 0, '10': 'turnLifecycle'},
    {'1': 'wakeword_detected', '3': 26, '4': 1, '5': 11, '6': '.runanywhere.v1.WakeWordDetectedEvent', '9': 0, '10': 'wakewordDetected'},
  ],
  '8': [
    {'1': 'payload'},
  ],
};

/// Descriptor for `VoiceEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceEventDescriptor = $convert.base64Decode(
    'CgpWb2ljZUV2ZW50EhAKA3NlcRgBIAEoBFIDc2VxEiEKDHRpbWVzdGFtcF91cxgCIAEoA1ILdG'
    'ltZXN0YW1wVXMSPgoIY2F0ZWdvcnkYAyABKA4yIi5ydW5hbnl3aGVyZS52MS5Wb2ljZUV2ZW50'
    'Q2F0ZWdvcnlSCGNhdGVnb3J5Ej4KCHNldmVyaXR5GAQgASgOMiIucnVuYW55d2hlcmUudjEuVm'
    '9pY2VFdmVudFNldmVyaXR5UghzZXZlcml0eRJECgljb21wb25lbnQYBSABKA4yJi5ydW5hbnl3'
    'aGVyZS52MS5Wb2ljZVBpcGVsaW5lQ29tcG9uZW50Ugljb21wb25lbnQSPAoJdXNlcl9zYWlkGA'
    'ogASgLMh0ucnVuYW55d2hlcmUudjEuVXNlclNhaWRFdmVudEgAUgh1c2VyU2FpZBJOCg9hc3Np'
    'c3RhbnRfdG9rZW4YCyABKAsyIy5ydW5hbnl3aGVyZS52MS5Bc3Npc3RhbnRUb2tlbkV2ZW50SA'
    'BSDmFzc2lzdGFudFRva2VuEjcKBWF1ZGlvGAwgASgLMh8ucnVuYW55d2hlcmUudjEuQXVkaW9G'
    'cmFtZUV2ZW50SABSBWF1ZGlvEiwKA3ZhZBgNIAEoCzIYLnJ1bmFueXdoZXJlLnYxLlZBREV2ZW'
    '50SABSA3ZhZBJECgtpbnRlcnJ1cHRlZBgOIAEoCzIgLnJ1bmFueXdoZXJlLnYxLkludGVycnVw'
    'dGVkRXZlbnRIAFILaW50ZXJydXB0ZWQSOAoFc3RhdGUYDyABKAsyIC5ydW5hbnl3aGVyZS52MS'
    '5TdGF0ZUNoYW5nZUV2ZW50SABSBXN0YXRlEjIKBWVycm9yGBAgASgLMhoucnVuYW55d2hlcmUu'
    'djEuRXJyb3JFdmVudEgAUgVlcnJvchI4CgdtZXRyaWNzGBEgASgLMhwucnVuYW55d2hlcmUudj'
    'EuTWV0cmljc0V2ZW50SABSB21ldHJpY3MSYwoXY29tcG9uZW50X3N0YXRlX2NoYW5nZWQYEiAB'
    'KAsyKS5ydW5hbnl3aGVyZS52MS5Wb2ljZUFnZW50Q29tcG9uZW50U3RhdGVzSABSFWNvbXBvbm'
    'VudFN0YXRlQ2hhbmdlZBJICg1zZXNzaW9uX2Vycm9yGBMgASgLMiEucnVuYW55d2hlcmUudjEu'
    'Vm9pY2VTZXNzaW9uRXJyb3JIAFIMc2Vzc2lvbkVycm9yEk4KD3Nlc3Npb25fc3RhcnRlZBgUIA'
    'EoCzIjLnJ1bmFueXdoZXJlLnYxLlNlc3Npb25TdGFydGVkRXZlbnRIAFIOc2Vzc2lvblN0YXJ0'
    'ZWQSTgoPc2Vzc2lvbl9zdG9wcGVkGBUgASgLMiMucnVuYW55d2hlcmUudjEuU2Vzc2lvblN0b3'
    'BwZWRFdmVudEgAUg5zZXNzaW9uU3RvcHBlZBJhChZhZ2VudF9yZXNwb25zZV9zdGFydGVkGBYg'
    'ASgLMikucnVuYW55d2hlcmUudjEuQWdlbnRSZXNwb25zZVN0YXJ0ZWRFdmVudEgAUhRhZ2VudF'
    'Jlc3BvbnNlU3RhcnRlZBJnChhhZ2VudF9yZXNwb25zZV9jb21wbGV0ZWQYFyABKAsyKy5ydW5h'
    'bnl3aGVyZS52MS5BZ2VudFJlc3BvbnNlQ29tcGxldGVkRXZlbnRIAFIWYWdlbnRSZXNwb25zZU'
    'NvbXBsZXRlZBJeChVzcGVlY2hfdHVybl9kZXRlY3Rpb24YGCABKAsyKC5ydW5hbnl3aGVyZS52'
    'MS5TcGVlY2hUdXJuRGV0ZWN0aW9uRXZlbnRIAFITc3BlZWNoVHVybkRldGVjdGlvbhJLCg50dX'
    'JuX2xpZmVjeWNsZRgZIAEoCzIiLnJ1bmFueXdoZXJlLnYxLlR1cm5MaWZlY3ljbGVFdmVudEgA'
    'Ug10dXJuTGlmZWN5Y2xlElQKEXdha2V3b3JkX2RldGVjdGVkGBogASgLMiUucnVuYW55d2hlcm'
    'UudjEuV2FrZVdvcmREZXRlY3RlZEV2ZW50SABSEHdha2V3b3JkRGV0ZWN0ZWRCCQoHcGF5bG9h'
    'ZA==');

@$core.Deprecated('Use userSaidEventDescriptor instead')
const UserSaidEvent$json = {
  '1': 'UserSaidEvent',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'is_final', '3': 2, '4': 1, '5': 8, '10': 'isFinal'},
    {'1': 'confidence', '3': 3, '4': 1, '5': 2, '10': 'confidence'},
    {'1': 'audio_start_us', '3': 4, '4': 1, '5': 3, '10': 'audioStartUs'},
    {'1': 'audio_end_us', '3': 5, '4': 1, '5': 3, '10': 'audioEndUs'},
  ],
};

/// Descriptor for `UserSaidEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List userSaidEventDescriptor = $convert.base64Decode(
    'Cg1Vc2VyU2FpZEV2ZW50EhIKBHRleHQYASABKAlSBHRleHQSGQoIaXNfZmluYWwYAiABKAhSB2'
    'lzRmluYWwSHgoKY29uZmlkZW5jZRgDIAEoAlIKY29uZmlkZW5jZRIkCg5hdWRpb19zdGFydF91'
    'cxgEIAEoA1IMYXVkaW9TdGFydFVzEiAKDGF1ZGlvX2VuZF91cxgFIAEoA1IKYXVkaW9FbmRVcw'
    '==');

@$core.Deprecated('Use assistantTokenEventDescriptor instead')
const AssistantTokenEvent$json = {
  '1': 'AssistantTokenEvent',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'is_final', '3': 2, '4': 1, '5': 8, '10': 'isFinal'},
    {'1': 'kind', '3': 3, '4': 1, '5': 14, '6': '.runanywhere.v1.TokenKind', '10': 'kind'},
  ],
};

/// Descriptor for `AssistantTokenEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List assistantTokenEventDescriptor = $convert.base64Decode(
    'ChNBc3Npc3RhbnRUb2tlbkV2ZW50EhIKBHRleHQYASABKAlSBHRleHQSGQoIaXNfZmluYWwYAi'
    'ABKAhSB2lzRmluYWwSLQoEa2luZBgDIAEoDjIZLnJ1bmFueXdoZXJlLnYxLlRva2VuS2luZFIE'
    'a2luZA==');

@$core.Deprecated('Use audioFrameEventDescriptor instead')
const AudioFrameEvent$json = {
  '1': 'AudioFrameEvent',
  '2': [
    {'1': 'pcm', '3': 1, '4': 1, '5': 12, '10': 'pcm'},
    {'1': 'sample_rate_hz', '3': 2, '4': 1, '5': 5, '10': 'sampleRateHz'},
    {'1': 'channels', '3': 3, '4': 1, '5': 5, '10': 'channels'},
    {'1': 'encoding', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.AudioEncoding', '10': 'encoding'},
    {'1': 'is_final', '3': 5, '4': 1, '5': 8, '10': 'isFinal'},
  ],
};

/// Descriptor for `AudioFrameEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List audioFrameEventDescriptor = $convert.base64Decode(
    'Cg9BdWRpb0ZyYW1lRXZlbnQSEAoDcGNtGAEgASgMUgNwY20SJAoOc2FtcGxlX3JhdGVfaHoYAi'
    'ABKAVSDHNhbXBsZVJhdGVIehIaCghjaGFubmVscxgDIAEoBVIIY2hhbm5lbHMSOQoIZW5jb2Rp'
    'bmcYBCABKA4yHS5ydW5hbnl3aGVyZS52MS5BdWRpb0VuY29kaW5nUghlbmNvZGluZxIZCghpc1'
    '9maW5hbBgFIAEoCFIHaXNGaW5hbA==');

@$core.Deprecated('Use vADEventDescriptor instead')
const VADEvent$json = {
  '1': 'VADEvent',
  '2': [
    {'1': 'type', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.VADEventType', '10': 'type'},
    {'1': 'frame_offset_us', '3': 2, '4': 1, '5': 3, '10': 'frameOffsetUs'},
    {'1': 'confidence', '3': 3, '4': 1, '5': 2, '10': 'confidence'},
    {'1': 'is_speech', '3': 4, '4': 1, '5': 8, '10': 'isSpeech'},
    {'1': 'speech_duration_ms', '3': 5, '4': 1, '5': 1, '10': 'speechDurationMs'},
    {'1': 'silence_duration_ms', '3': 6, '4': 1, '5': 1, '10': 'silenceDurationMs'},
    {'1': 'noise_floor_db', '3': 7, '4': 1, '5': 1, '10': 'noiseFloorDb'},
  ],
};

/// Descriptor for `VADEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vADEventDescriptor = $convert.base64Decode(
    'CghWQURFdmVudBIwCgR0eXBlGAEgASgOMhwucnVuYW55d2hlcmUudjEuVkFERXZlbnRUeXBlUg'
    'R0eXBlEiYKD2ZyYW1lX29mZnNldF91cxgCIAEoA1INZnJhbWVPZmZzZXRVcxIeCgpjb25maWRl'
    'bmNlGAMgASgCUgpjb25maWRlbmNlEhsKCWlzX3NwZWVjaBgEIAEoCFIIaXNTcGVlY2gSLAoSc3'
    'BlZWNoX2R1cmF0aW9uX21zGAUgASgBUhBzcGVlY2hEdXJhdGlvbk1zEi4KE3NpbGVuY2VfZHVy'
    'YXRpb25fbXMYBiABKAFSEXNpbGVuY2VEdXJhdGlvbk1zEiQKDm5vaXNlX2Zsb29yX2RiGAcgAS'
    'gBUgxub2lzZUZsb29yRGI=');

@$core.Deprecated('Use interruptedEventDescriptor instead')
const InterruptedEvent$json = {
  '1': 'InterruptedEvent',
  '2': [
    {'1': 'reason', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.InterruptReason', '10': 'reason'},
    {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
  ],
};

/// Descriptor for `InterruptedEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List interruptedEventDescriptor = $convert.base64Decode(
    'ChBJbnRlcnJ1cHRlZEV2ZW50EjcKBnJlYXNvbhgBIAEoDjIfLnJ1bmFueXdoZXJlLnYxLkludG'
    'VycnVwdFJlYXNvblIGcmVhc29uEhYKBmRldGFpbBgCIAEoCVIGZGV0YWls');

@$core.Deprecated('Use stateChangeEventDescriptor instead')
const StateChangeEvent$json = {
  '1': 'StateChangeEvent',
  '2': [
    {'1': 'previous', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.PipelineState', '10': 'previous'},
    {'1': 'current', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.PipelineState', '10': 'current'},
  ],
};

/// Descriptor for `StateChangeEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List stateChangeEventDescriptor = $convert.base64Decode(
    'ChBTdGF0ZUNoYW5nZUV2ZW50EjkKCHByZXZpb3VzGAEgASgOMh0ucnVuYW55d2hlcmUudjEuUG'
    'lwZWxpbmVTdGF0ZVIIcHJldmlvdXMSNwoHY3VycmVudBgCIAEoDjIdLnJ1bmFueXdoZXJlLnYx'
    'LlBpcGVsaW5lU3RhdGVSB2N1cnJlbnQ=');

@$core.Deprecated('Use errorEventDescriptor instead')
const ErrorEvent$json = {
  '1': 'ErrorEvent',
  '2': [
    {'1': 'code', '3': 1, '4': 1, '5': 5, '10': 'code'},
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
    {'1': 'component', '3': 3, '4': 1, '5': 9, '10': 'component'},
    {'1': 'is_recoverable', '3': 4, '4': 1, '5': 8, '10': 'isRecoverable'},
  ],
};

/// Descriptor for `ErrorEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List errorEventDescriptor = $convert.base64Decode(
    'CgpFcnJvckV2ZW50EhIKBGNvZGUYASABKAVSBGNvZGUSGAoHbWVzc2FnZRgCIAEoCVIHbWVzc2'
    'FnZRIcCgljb21wb25lbnQYAyABKAlSCWNvbXBvbmVudBIlCg5pc19yZWNvdmVyYWJsZRgEIAEo'
    'CFINaXNSZWNvdmVyYWJsZQ==');

@$core.Deprecated('Use metricsEventDescriptor instead')
const MetricsEvent$json = {
  '1': 'MetricsEvent',
  '2': [
    {'1': 'stt_final_ms', '3': 1, '4': 1, '5': 1, '10': 'sttFinalMs'},
    {'1': 'llm_first_token_ms', '3': 2, '4': 1, '5': 1, '10': 'llmFirstTokenMs'},
    {'1': 'tts_first_audio_ms', '3': 3, '4': 1, '5': 1, '10': 'ttsFirstAudioMs'},
    {'1': 'end_to_end_ms', '3': 4, '4': 1, '5': 1, '10': 'endToEndMs'},
    {'1': 'tokens_generated', '3': 5, '4': 1, '5': 3, '10': 'tokensGenerated'},
    {'1': 'audio_samples_played', '3': 6, '4': 1, '5': 3, '10': 'audioSamplesPlayed'},
    {'1': 'is_over_budget', '3': 7, '4': 1, '5': 8, '10': 'isOverBudget'},
    {'1': 'created_at_ns', '3': 8, '4': 1, '5': 3, '10': 'createdAtNs'},
  ],
};

/// Descriptor for `MetricsEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List metricsEventDescriptor = $convert.base64Decode(
    'CgxNZXRyaWNzRXZlbnQSIAoMc3R0X2ZpbmFsX21zGAEgASgBUgpzdHRGaW5hbE1zEisKEmxsbV'
    '9maXJzdF90b2tlbl9tcxgCIAEoAVIPbGxtRmlyc3RUb2tlbk1zEisKEnR0c19maXJzdF9hdWRp'
    'b19tcxgDIAEoAVIPdHRzRmlyc3RBdWRpb01zEiEKDWVuZF90b19lbmRfbXMYBCABKAFSCmVuZF'
    'RvRW5kTXMSKQoQdG9rZW5zX2dlbmVyYXRlZBgFIAEoA1IPdG9rZW5zR2VuZXJhdGVkEjAKFGF1'
    'ZGlvX3NhbXBsZXNfcGxheWVkGAYgASgDUhJhdWRpb1NhbXBsZXNQbGF5ZWQSJAoOaXNfb3Zlcl'
    '9idWRnZXQYByABKAhSDGlzT3ZlckJ1ZGdldBIiCg1jcmVhdGVkX2F0X25zGAggASgDUgtjcmVh'
    'dGVkQXROcw==');

@$core.Deprecated('Use voiceAgentComponentStatesDescriptor instead')
const VoiceAgentComponentStates$json = {
  '1': 'VoiceAgentComponentStates',
  '2': [
    {'1': 'stt_state', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.ComponentLoadState', '10': 'sttState'},
    {'1': 'llm_state', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.ComponentLoadState', '10': 'llmState'},
    {'1': 'tts_state', '3': 3, '4': 1, '5': 14, '6': '.runanywhere.v1.ComponentLoadState', '10': 'ttsState'},
    {'1': 'vad_state', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.ComponentLoadState', '10': 'vadState'},
    {'1': 'ready', '3': 5, '4': 1, '5': 8, '10': 'ready'},
    {'1': 'any_loading', '3': 6, '4': 1, '5': 8, '10': 'anyLoading'},
  ],
};

/// Descriptor for `VoiceAgentComponentStates`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceAgentComponentStatesDescriptor = $convert.base64Decode(
    'ChlWb2ljZUFnZW50Q29tcG9uZW50U3RhdGVzEj8KCXN0dF9zdGF0ZRgBIAEoDjIiLnJ1bmFueX'
    'doZXJlLnYxLkNvbXBvbmVudExvYWRTdGF0ZVIIc3R0U3RhdGUSPwoJbGxtX3N0YXRlGAIgASgO'
    'MiIucnVuYW55d2hlcmUudjEuQ29tcG9uZW50TG9hZFN0YXRlUghsbG1TdGF0ZRI/Cgl0dHNfc3'
    'RhdGUYAyABKA4yIi5ydW5hbnl3aGVyZS52MS5Db21wb25lbnRMb2FkU3RhdGVSCHR0c1N0YXRl'
    'Ej8KCXZhZF9zdGF0ZRgEIAEoDjIiLnJ1bmFueXdoZXJlLnYxLkNvbXBvbmVudExvYWRTdGF0ZV'
    'IIdmFkU3RhdGUSFAoFcmVhZHkYBSABKAhSBXJlYWR5Eh8KC2FueV9sb2FkaW5nGAYgASgIUgph'
    'bnlMb2FkaW5n');

@$core.Deprecated('Use voiceSessionErrorDescriptor instead')
const VoiceSessionError$json = {
  '1': 'VoiceSessionError',
  '2': [
    {'1': 'code', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.VoiceSessionErrorCode', '10': 'code'},
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
    {'1': 'failed_component', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'failedComponent', '17': true},
  ],
  '8': [
    {'1': '_failed_component'},
  ],
};

/// Descriptor for `VoiceSessionError`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceSessionErrorDescriptor = $convert.base64Decode(
    'ChFWb2ljZVNlc3Npb25FcnJvchI5CgRjb2RlGAEgASgOMiUucnVuYW55d2hlcmUudjEuVm9pY2'
    'VTZXNzaW9uRXJyb3JDb2RlUgRjb2RlEhgKB21lc3NhZ2UYAiABKAlSB21lc3NhZ2USLgoQZmFp'
    'bGVkX2NvbXBvbmVudBgDIAEoCUgAUg9mYWlsZWRDb21wb25lbnSIAQFCEwoRX2ZhaWxlZF9jb2'
    '1wb25lbnQ=');

@$core.Deprecated('Use sessionStartedEventDescriptor instead')
const SessionStartedEvent$json = {
  '1': 'SessionStartedEvent',
};

/// Descriptor for `SessionStartedEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sessionStartedEventDescriptor = $convert.base64Decode(
    'ChNTZXNzaW9uU3RhcnRlZEV2ZW50');

@$core.Deprecated('Use sessionStoppedEventDescriptor instead')
const SessionStoppedEvent$json = {
  '1': 'SessionStoppedEvent',
};

/// Descriptor for `SessionStoppedEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sessionStoppedEventDescriptor = $convert.base64Decode(
    'ChNTZXNzaW9uU3RvcHBlZEV2ZW50');

@$core.Deprecated('Use agentResponseStartedEventDescriptor instead')
const AgentResponseStartedEvent$json = {
  '1': 'AgentResponseStartedEvent',
};

/// Descriptor for `AgentResponseStartedEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List agentResponseStartedEventDescriptor = $convert.base64Decode(
    'ChlBZ2VudFJlc3BvbnNlU3RhcnRlZEV2ZW50');

@$core.Deprecated('Use agentResponseCompletedEventDescriptor instead')
const AgentResponseCompletedEvent$json = {
  '1': 'AgentResponseCompletedEvent',
};

/// Descriptor for `AgentResponseCompletedEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List agentResponseCompletedEventDescriptor = $convert.base64Decode(
    'ChtBZ2VudFJlc3BvbnNlQ29tcGxldGVkRXZlbnQ=');

@$core.Deprecated('Use speechTurnDetectionEventDescriptor instead')
const SpeechTurnDetectionEvent$json = {
  '1': 'SpeechTurnDetectionEvent',
  '2': [
    {'1': 'kind', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.SpeechTurnDetectionEventKind', '10': 'kind'},
    {'1': 'speaker_id', '3': 2, '4': 1, '5': 9, '10': 'speakerId'},
    {'1': 'turn_start_us', '3': 3, '4': 1, '5': 3, '10': 'turnStartUs'},
    {'1': 'turn_end_us', '3': 4, '4': 1, '5': 3, '10': 'turnEndUs'},
    {'1': 'confidence', '3': 5, '4': 1, '5': 2, '10': 'confidence'},
    {'1': 'speech_duration_ms', '3': 6, '4': 1, '5': 1, '10': 'speechDurationMs'},
    {'1': 'silence_duration_ms', '3': 7, '4': 1, '5': 1, '10': 'silenceDurationMs'},
  ],
};

/// Descriptor for `SpeechTurnDetectionEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List speechTurnDetectionEventDescriptor = $convert.base64Decode(
    'ChhTcGVlY2hUdXJuRGV0ZWN0aW9uRXZlbnQSQAoEa2luZBgBIAEoDjIsLnJ1bmFueXdoZXJlLn'
    'YxLlNwZWVjaFR1cm5EZXRlY3Rpb25FdmVudEtpbmRSBGtpbmQSHQoKc3BlYWtlcl9pZBgCIAEo'
    'CVIJc3BlYWtlcklkEiIKDXR1cm5fc3RhcnRfdXMYAyABKANSC3R1cm5TdGFydFVzEh4KC3R1cm'
    '5fZW5kX3VzGAQgASgDUgl0dXJuRW5kVXMSHgoKY29uZmlkZW5jZRgFIAEoAlIKY29uZmlkZW5j'
    'ZRIsChJzcGVlY2hfZHVyYXRpb25fbXMYBiABKAFSEHNwZWVjaER1cmF0aW9uTXMSLgoTc2lsZW'
    '5jZV9kdXJhdGlvbl9tcxgHIAEoAVIRc2lsZW5jZUR1cmF0aW9uTXM=');

@$core.Deprecated('Use turnLifecycleEventDescriptor instead')
const TurnLifecycleEvent$json = {
  '1': 'TurnLifecycleEvent',
  '2': [
    {'1': 'kind', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.TurnLifecycleEventKind', '10': 'kind'},
    {'1': 'turn_id', '3': 2, '4': 1, '5': 9, '10': 'turnId'},
    {'1': 'session_id', '3': 3, '4': 1, '5': 9, '10': 'sessionId'},
    {'1': 'transcript', '3': 4, '4': 1, '5': 9, '10': 'transcript'},
    {'1': 'response', '3': 5, '4': 1, '5': 9, '10': 'response'},
    {'1': 'error', '3': 6, '4': 1, '5': 9, '10': 'error'},
  ],
};

/// Descriptor for `TurnLifecycleEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List turnLifecycleEventDescriptor = $convert.base64Decode(
    'ChJUdXJuTGlmZWN5Y2xlRXZlbnQSOgoEa2luZBgBIAEoDjImLnJ1bmFueXdoZXJlLnYxLlR1cm'
    '5MaWZlY3ljbGVFdmVudEtpbmRSBGtpbmQSFwoHdHVybl9pZBgCIAEoCVIGdHVybklkEh0KCnNl'
    'c3Npb25faWQYAyABKAlSCXNlc3Npb25JZBIeCgp0cmFuc2NyaXB0GAQgASgJUgp0cmFuc2NyaX'
    'B0EhoKCHJlc3BvbnNlGAUgASgJUghyZXNwb25zZRIUCgVlcnJvchgGIAEoCVIFZXJyb3I=');

@$core.Deprecated('Use wakeWordDetectedEventDescriptor instead')
const WakeWordDetectedEvent$json = {
  '1': 'WakeWordDetectedEvent',
  '2': [
    {'1': 'wake_word', '3': 1, '4': 1, '5': 9, '10': 'wakeWord'},
    {'1': 'confidence', '3': 2, '4': 1, '5': 2, '10': 'confidence'},
    {'1': 'timestamp_ms', '3': 3, '4': 1, '5': 3, '10': 'timestampMs'},
    {'1': 'model_id', '3': 4, '4': 1, '5': 9, '10': 'modelId'},
    {'1': 'model_index', '3': 5, '4': 1, '5': 5, '10': 'modelIndex'},
    {'1': 'duration_ms', '3': 6, '4': 1, '5': 3, '10': 'durationMs'},
  ],
};

/// Descriptor for `WakeWordDetectedEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List wakeWordDetectedEventDescriptor = $convert.base64Decode(
    'ChVXYWtlV29yZERldGVjdGVkRXZlbnQSGwoJd2FrZV93b3JkGAEgASgJUgh3YWtlV29yZBIeCg'
    'pjb25maWRlbmNlGAIgASgCUgpjb25maWRlbmNlEiEKDHRpbWVzdGFtcF9tcxgDIAEoA1ILdGlt'
    'ZXN0YW1wTXMSGQoIbW9kZWxfaWQYBCABKAlSB21vZGVsSWQSHwoLbW9kZWxfaW5kZXgYBSABKA'
    'VSCm1vZGVsSW5kZXgSHwoLZHVyYXRpb25fbXMYBiABKANSCmR1cmF0aW9uTXM=');

