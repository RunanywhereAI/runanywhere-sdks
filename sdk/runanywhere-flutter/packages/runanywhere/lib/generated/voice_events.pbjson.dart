///
//  Generated code. Do not modify.
//  source: voice_events.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
@$core.Deprecated('Use tokenKindDescriptor instead')
const TokenKind$json = const {
  '1': 'TokenKind',
  '2': const [
    const {'1': 'TOKEN_KIND_UNSPECIFIED', '2': 0},
    const {'1': 'TOKEN_KIND_ANSWER', '2': 1},
    const {'1': 'TOKEN_KIND_THOUGHT', '2': 2},
    const {'1': 'TOKEN_KIND_TOOL_CALL', '2': 3},
  ],
};

/// Descriptor for `TokenKind`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List tokenKindDescriptor = $convert.base64Decode('CglUb2tlbktpbmQSGgoWVE9LRU5fS0lORF9VTlNQRUNJRklFRBAAEhUKEVRPS0VOX0tJTkRfQU5TV0VSEAESFgoSVE9LRU5fS0lORF9USE9VR0hUEAISGAoUVE9LRU5fS0lORF9UT09MX0NBTEwQAw==');
@$core.Deprecated('Use audioEncodingDescriptor instead')
const AudioEncoding$json = const {
  '1': 'AudioEncoding',
  '2': const [
    const {'1': 'AUDIO_ENCODING_UNSPECIFIED', '2': 0},
    const {'1': 'AUDIO_ENCODING_PCM_F32_LE', '2': 1},
    const {'1': 'AUDIO_ENCODING_PCM_S16_LE', '2': 2},
  ],
};

/// Descriptor for `AudioEncoding`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List audioEncodingDescriptor = $convert.base64Decode('Cg1BdWRpb0VuY29kaW5nEh4KGkFVRElPX0VOQ09ESU5HX1VOU1BFQ0lGSUVEEAASHQoZQVVESU9fRU5DT0RJTkdfUENNX0YzMl9MRRABEh0KGUFVRElPX0VOQ09ESU5HX1BDTV9TMTZfTEUQAg==');
@$core.Deprecated('Use vADEventTypeDescriptor instead')
const VADEventType$json = const {
  '1': 'VADEventType',
  '2': const [
    const {'1': 'VAD_EVENT_UNSPECIFIED', '2': 0},
    const {'1': 'VAD_EVENT_VOICE_START', '2': 1},
    const {'1': 'VAD_EVENT_VOICE_END_OF_UTTERANCE', '2': 2},
    const {'1': 'VAD_EVENT_BARGE_IN', '2': 3},
    const {'1': 'VAD_EVENT_SILENCE', '2': 4},
  ],
};

/// Descriptor for `VADEventType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List vADEventTypeDescriptor = $convert.base64Decode('CgxWQURFdmVudFR5cGUSGQoVVkFEX0VWRU5UX1VOU1BFQ0lGSUVEEAASGQoVVkFEX0VWRU5UX1ZPSUNFX1NUQVJUEAESJAogVkFEX0VWRU5UX1ZPSUNFX0VORF9PRl9VVFRFUkFOQ0UQAhIWChJWQURfRVZFTlRfQkFSR0VfSU4QAxIVChFWQURfRVZFTlRfU0lMRU5DRRAE');
@$core.Deprecated('Use interruptReasonDescriptor instead')
const InterruptReason$json = const {
  '1': 'InterruptReason',
  '2': const [
    const {'1': 'INTERRUPT_REASON_UNSPECIFIED', '2': 0},
    const {'1': 'INTERRUPT_REASON_USER_BARGE_IN', '2': 1},
    const {'1': 'INTERRUPT_REASON_APP_STOP', '2': 2},
    const {'1': 'INTERRUPT_REASON_AUDIO_ROUTE_CHANGE', '2': 3},
    const {'1': 'INTERRUPT_REASON_TIMEOUT', '2': 4},
  ],
};

/// Descriptor for `InterruptReason`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List interruptReasonDescriptor = $convert.base64Decode('Cg9JbnRlcnJ1cHRSZWFzb24SIAocSU5URVJSVVBUX1JFQVNPTl9VTlNQRUNJRklFRBAAEiIKHklOVEVSUlVQVF9SRUFTT05fVVNFUl9CQVJHRV9JThABEh0KGUlOVEVSUlVQVF9SRUFTT05fQVBQX1NUT1AQAhInCiNJTlRFUlJVUFRfUkVBU09OX0FVRElPX1JPVVRFX0NIQU5HRRADEhwKGElOVEVSUlVQVF9SRUFTT05fVElNRU9VVBAE');
@$core.Deprecated('Use pipelineStateDescriptor instead')
const PipelineState$json = const {
  '1': 'PipelineState',
  '2': const [
    const {'1': 'PIPELINE_STATE_UNSPECIFIED', '2': 0},
    const {'1': 'PIPELINE_STATE_IDLE', '2': 1},
    const {'1': 'PIPELINE_STATE_LISTENING', '2': 2},
    const {'1': 'PIPELINE_STATE_THINKING', '2': 3},
    const {'1': 'PIPELINE_STATE_SPEAKING', '2': 4},
    const {'1': 'PIPELINE_STATE_STOPPED', '2': 5},
  ],
};

/// Descriptor for `PipelineState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List pipelineStateDescriptor = $convert.base64Decode('Cg1QaXBlbGluZVN0YXRlEh4KGlBJUEVMSU5FX1NUQVRFX1VOU1BFQ0lGSUVEEAASFwoTUElQRUxJTkVfU1RBVEVfSURMRRABEhwKGFBJUEVMSU5FX1NUQVRFX0xJU1RFTklORxACEhsKF1BJUEVMSU5FX1NUQVRFX1RISU5LSU5HEAMSGwoXUElQRUxJTkVfU1RBVEVfU1BFQUtJTkcQBBIaChZQSVBFTElORV9TVEFURV9TVE9QUEVEEAU=');
@$core.Deprecated('Use componentLoadStateDescriptor instead')
const ComponentLoadState$json = const {
  '1': 'ComponentLoadState',
  '2': const [
    const {'1': 'COMPONENT_LOAD_STATE_UNSPECIFIED', '2': 0},
    const {'1': 'COMPONENT_LOAD_STATE_NOT_LOADED', '2': 1},
    const {'1': 'COMPONENT_LOAD_STATE_LOADING', '2': 2},
    const {'1': 'COMPONENT_LOAD_STATE_LOADED', '2': 3},
    const {'1': 'COMPONENT_LOAD_STATE_ERROR', '2': 4},
  ],
};

/// Descriptor for `ComponentLoadState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List componentLoadStateDescriptor = $convert.base64Decode('ChJDb21wb25lbnRMb2FkU3RhdGUSJAogQ09NUE9ORU5UX0xPQURfU1RBVEVfVU5TUEVDSUZJRUQQABIjCh9DT01QT05FTlRfTE9BRF9TVEFURV9OT1RfTE9BREVEEAESIAocQ09NUE9ORU5UX0xPQURfU1RBVEVfTE9BRElORxACEh8KG0NPTVBPTkVOVF9MT0FEX1NUQVRFX0xPQURFRBADEh4KGkNPTVBPTkVOVF9MT0FEX1NUQVRFX0VSUk9SEAQ=');
@$core.Deprecated('Use voiceSessionErrorCodeDescriptor instead')
const VoiceSessionErrorCode$json = const {
  '1': 'VoiceSessionErrorCode',
  '2': const [
    const {'1': 'VOICE_SESSION_ERROR_CODE_UNSPECIFIED', '2': 0},
    const {'1': 'VOICE_SESSION_ERROR_CODE_MICROPHONE_PERMISSION_DENIED', '2': 1},
    const {'1': 'VOICE_SESSION_ERROR_CODE_NOT_READY', '2': 2},
    const {'1': 'VOICE_SESSION_ERROR_CODE_ALREADY_RUNNING', '2': 3},
    const {'1': 'VOICE_SESSION_ERROR_CODE_COMPONENT_FAILURE', '2': 4},
  ],
};

/// Descriptor for `VoiceSessionErrorCode`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List voiceSessionErrorCodeDescriptor = $convert.base64Decode('ChVWb2ljZVNlc3Npb25FcnJvckNvZGUSKAokVk9JQ0VfU0VTU0lPTl9FUlJPUl9DT0RFX1VOU1BFQ0lGSUVEEAASOQo1Vk9JQ0VfU0VTU0lPTl9FUlJPUl9DT0RFX01JQ1JPUEhPTkVfUEVSTUlTU0lPTl9ERU5JRUQQARImCiJWT0lDRV9TRVNTSU9OX0VSUk9SX0NPREVfTk9UX1JFQURZEAISLAooVk9JQ0VfU0VTU0lPTl9FUlJPUl9DT0RFX0FMUkVBRFlfUlVOTklORxADEi4KKlZPSUNFX1NFU1NJT05fRVJST1JfQ09ERV9DT01QT05FTlRfRkFJTFVSRRAE');
@$core.Deprecated('Use voiceEventDescriptor instead')
const VoiceEvent$json = const {
  '1': 'VoiceEvent',
  '2': const [
    const {'1': 'seq', '3': 1, '4': 1, '5': 4, '10': 'seq'},
    const {'1': 'timestamp_us', '3': 2, '4': 1, '5': 3, '10': 'timestampUs'},
    const {'1': 'user_said', '3': 10, '4': 1, '5': 11, '6': '.runanywhere.v1.UserSaidEvent', '9': 0, '10': 'userSaid'},
    const {'1': 'assistant_token', '3': 11, '4': 1, '5': 11, '6': '.runanywhere.v1.AssistantTokenEvent', '9': 0, '10': 'assistantToken'},
    const {'1': 'audio', '3': 12, '4': 1, '5': 11, '6': '.runanywhere.v1.AudioFrameEvent', '9': 0, '10': 'audio'},
    const {'1': 'vad', '3': 13, '4': 1, '5': 11, '6': '.runanywhere.v1.VADEvent', '9': 0, '10': 'vad'},
    const {'1': 'interrupted', '3': 14, '4': 1, '5': 11, '6': '.runanywhere.v1.InterruptedEvent', '9': 0, '10': 'interrupted'},
    const {'1': 'state', '3': 15, '4': 1, '5': 11, '6': '.runanywhere.v1.StateChangeEvent', '9': 0, '10': 'state'},
    const {'1': 'error', '3': 16, '4': 1, '5': 11, '6': '.runanywhere.v1.ErrorEvent', '9': 0, '10': 'error'},
    const {'1': 'metrics', '3': 17, '4': 1, '5': 11, '6': '.runanywhere.v1.MetricsEvent', '9': 0, '10': 'metrics'},
    const {'1': 'component_state_changed', '3': 18, '4': 1, '5': 11, '6': '.runanywhere.v1.VoiceAgentComponentStates', '9': 0, '10': 'componentStateChanged'},
    const {'1': 'session_error', '3': 19, '4': 1, '5': 11, '6': '.runanywhere.v1.VoiceSessionError', '9': 0, '10': 'sessionError'},
    const {'1': 'session_started', '3': 20, '4': 1, '5': 11, '6': '.runanywhere.v1.SessionStartedEvent', '9': 0, '10': 'sessionStarted'},
    const {'1': 'session_stopped', '3': 21, '4': 1, '5': 11, '6': '.runanywhere.v1.SessionStoppedEvent', '9': 0, '10': 'sessionStopped'},
    const {'1': 'agent_response_started', '3': 22, '4': 1, '5': 11, '6': '.runanywhere.v1.AgentResponseStartedEvent', '9': 0, '10': 'agentResponseStarted'},
    const {'1': 'agent_response_completed', '3': 23, '4': 1, '5': 11, '6': '.runanywhere.v1.AgentResponseCompletedEvent', '9': 0, '10': 'agentResponseCompleted'},
  ],
  '8': const [
    const {'1': 'payload'},
  ],
};

/// Descriptor for `VoiceEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceEventDescriptor = $convert.base64Decode('CgpWb2ljZUV2ZW50EhAKA3NlcRgBIAEoBFIDc2VxEiEKDHRpbWVzdGFtcF91cxgCIAEoA1ILdGltZXN0YW1wVXMSPAoJdXNlcl9zYWlkGAogASgLMh0ucnVuYW55d2hlcmUudjEuVXNlclNhaWRFdmVudEgAUgh1c2VyU2FpZBJOCg9hc3Npc3RhbnRfdG9rZW4YCyABKAsyIy5ydW5hbnl3aGVyZS52MS5Bc3Npc3RhbnRUb2tlbkV2ZW50SABSDmFzc2lzdGFudFRva2VuEjcKBWF1ZGlvGAwgASgLMh8ucnVuYW55d2hlcmUudjEuQXVkaW9GcmFtZUV2ZW50SABSBWF1ZGlvEiwKA3ZhZBgNIAEoCzIYLnJ1bmFueXdoZXJlLnYxLlZBREV2ZW50SABSA3ZhZBJECgtpbnRlcnJ1cHRlZBgOIAEoCzIgLnJ1bmFueXdoZXJlLnYxLkludGVycnVwdGVkRXZlbnRIAFILaW50ZXJydXB0ZWQSOAoFc3RhdGUYDyABKAsyIC5ydW5hbnl3aGVyZS52MS5TdGF0ZUNoYW5nZUV2ZW50SABSBXN0YXRlEjIKBWVycm9yGBAgASgLMhoucnVuYW55d2hlcmUudjEuRXJyb3JFdmVudEgAUgVlcnJvchI4CgdtZXRyaWNzGBEgASgLMhwucnVuYW55d2hlcmUudjEuTWV0cmljc0V2ZW50SABSB21ldHJpY3MSYwoXY29tcG9uZW50X3N0YXRlX2NoYW5nZWQYEiABKAsyKS5ydW5hbnl3aGVyZS52MS5Wb2ljZUFnZW50Q29tcG9uZW50U3RhdGVzSABSFWNvbXBvbmVudFN0YXRlQ2hhbmdlZBJICg1zZXNzaW9uX2Vycm9yGBMgASgLMiEucnVuYW55d2hlcmUudjEuVm9pY2VTZXNzaW9uRXJyb3JIAFIMc2Vzc2lvbkVycm9yEk4KD3Nlc3Npb25fc3RhcnRlZBgUIAEoCzIjLnJ1bmFueXdoZXJlLnYxLlNlc3Npb25TdGFydGVkRXZlbnRIAFIOc2Vzc2lvblN0YXJ0ZWQSTgoPc2Vzc2lvbl9zdG9wcGVkGBUgASgLMiMucnVuYW55d2hlcmUudjEuU2Vzc2lvblN0b3BwZWRFdmVudEgAUg5zZXNzaW9uU3RvcHBlZBJhChZhZ2VudF9yZXNwb25zZV9zdGFydGVkGBYgASgLMikucnVuYW55d2hlcmUudjEuQWdlbnRSZXNwb25zZVN0YXJ0ZWRFdmVudEgAUhRhZ2VudFJlc3BvbnNlU3RhcnRlZBJnChhhZ2VudF9yZXNwb25zZV9jb21wbGV0ZWQYFyABKAsyKy5ydW5hbnl3aGVyZS52MS5BZ2VudFJlc3BvbnNlQ29tcGxldGVkRXZlbnRIAFIWYWdlbnRSZXNwb25zZUNvbXBsZXRlZEIJCgdwYXlsb2Fk');
@$core.Deprecated('Use userSaidEventDescriptor instead')
const UserSaidEvent$json = const {
  '1': 'UserSaidEvent',
  '2': const [
    const {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    const {'1': 'is_final', '3': 2, '4': 1, '5': 8, '10': 'isFinal'},
    const {'1': 'confidence', '3': 3, '4': 1, '5': 2, '10': 'confidence'},
    const {'1': 'audio_start_us', '3': 4, '4': 1, '5': 3, '10': 'audioStartUs'},
    const {'1': 'audio_end_us', '3': 5, '4': 1, '5': 3, '10': 'audioEndUs'},
  ],
};

/// Descriptor for `UserSaidEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List userSaidEventDescriptor = $convert.base64Decode('Cg1Vc2VyU2FpZEV2ZW50EhIKBHRleHQYASABKAlSBHRleHQSGQoIaXNfZmluYWwYAiABKAhSB2lzRmluYWwSHgoKY29uZmlkZW5jZRgDIAEoAlIKY29uZmlkZW5jZRIkCg5hdWRpb19zdGFydF91cxgEIAEoA1IMYXVkaW9TdGFydFVzEiAKDGF1ZGlvX2VuZF91cxgFIAEoA1IKYXVkaW9FbmRVcw==');
@$core.Deprecated('Use assistantTokenEventDescriptor instead')
const AssistantTokenEvent$json = const {
  '1': 'AssistantTokenEvent',
  '2': const [
    const {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    const {'1': 'is_final', '3': 2, '4': 1, '5': 8, '10': 'isFinal'},
    const {'1': 'kind', '3': 3, '4': 1, '5': 14, '6': '.runanywhere.v1.TokenKind', '10': 'kind'},
  ],
};

/// Descriptor for `AssistantTokenEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List assistantTokenEventDescriptor = $convert.base64Decode('ChNBc3Npc3RhbnRUb2tlbkV2ZW50EhIKBHRleHQYASABKAlSBHRleHQSGQoIaXNfZmluYWwYAiABKAhSB2lzRmluYWwSLQoEa2luZBgDIAEoDjIZLnJ1bmFueXdoZXJlLnYxLlRva2VuS2luZFIEa2luZA==');
@$core.Deprecated('Use audioFrameEventDescriptor instead')
const AudioFrameEvent$json = const {
  '1': 'AudioFrameEvent',
  '2': const [
    const {'1': 'pcm', '3': 1, '4': 1, '5': 12, '10': 'pcm'},
    const {'1': 'sample_rate_hz', '3': 2, '4': 1, '5': 5, '10': 'sampleRateHz'},
    const {'1': 'channels', '3': 3, '4': 1, '5': 5, '10': 'channels'},
    const {'1': 'encoding', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.AudioEncoding', '10': 'encoding'},
  ],
};

/// Descriptor for `AudioFrameEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List audioFrameEventDescriptor = $convert.base64Decode('Cg9BdWRpb0ZyYW1lRXZlbnQSEAoDcGNtGAEgASgMUgNwY20SJAoOc2FtcGxlX3JhdGVfaHoYAiABKAVSDHNhbXBsZVJhdGVIehIaCghjaGFubmVscxgDIAEoBVIIY2hhbm5lbHMSOQoIZW5jb2RpbmcYBCABKA4yHS5ydW5hbnl3aGVyZS52MS5BdWRpb0VuY29kaW5nUghlbmNvZGluZw==');
@$core.Deprecated('Use vADEventDescriptor instead')
const VADEvent$json = const {
  '1': 'VADEvent',
  '2': const [
    const {'1': 'type', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.VADEventType', '10': 'type'},
    const {'1': 'frame_offset_us', '3': 2, '4': 1, '5': 3, '10': 'frameOffsetUs'},
  ],
};

/// Descriptor for `VADEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vADEventDescriptor = $convert.base64Decode('CghWQURFdmVudBIwCgR0eXBlGAEgASgOMhwucnVuYW55d2hlcmUudjEuVkFERXZlbnRUeXBlUgR0eXBlEiYKD2ZyYW1lX29mZnNldF91cxgCIAEoA1INZnJhbWVPZmZzZXRVcw==');
@$core.Deprecated('Use interruptedEventDescriptor instead')
const InterruptedEvent$json = const {
  '1': 'InterruptedEvent',
  '2': const [
    const {'1': 'reason', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.InterruptReason', '10': 'reason'},
    const {'1': 'detail', '3': 2, '4': 1, '5': 9, '10': 'detail'},
  ],
};

/// Descriptor for `InterruptedEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List interruptedEventDescriptor = $convert.base64Decode('ChBJbnRlcnJ1cHRlZEV2ZW50EjcKBnJlYXNvbhgBIAEoDjIfLnJ1bmFueXdoZXJlLnYxLkludGVycnVwdFJlYXNvblIGcmVhc29uEhYKBmRldGFpbBgCIAEoCVIGZGV0YWls');
@$core.Deprecated('Use stateChangeEventDescriptor instead')
const StateChangeEvent$json = const {
  '1': 'StateChangeEvent',
  '2': const [
    const {'1': 'previous', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.PipelineState', '10': 'previous'},
    const {'1': 'current', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.PipelineState', '10': 'current'},
  ],
};

/// Descriptor for `StateChangeEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List stateChangeEventDescriptor = $convert.base64Decode('ChBTdGF0ZUNoYW5nZUV2ZW50EjkKCHByZXZpb3VzGAEgASgOMh0ucnVuYW55d2hlcmUudjEuUGlwZWxpbmVTdGF0ZVIIcHJldmlvdXMSNwoHY3VycmVudBgCIAEoDjIdLnJ1bmFueXdoZXJlLnYxLlBpcGVsaW5lU3RhdGVSB2N1cnJlbnQ=');
@$core.Deprecated('Use errorEventDescriptor instead')
const ErrorEvent$json = const {
  '1': 'ErrorEvent',
  '2': const [
    const {'1': 'code', '3': 1, '4': 1, '5': 5, '10': 'code'},
    const {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
    const {'1': 'component', '3': 3, '4': 1, '5': 9, '10': 'component'},
    const {'1': 'is_recoverable', '3': 4, '4': 1, '5': 8, '10': 'isRecoverable'},
  ],
};

/// Descriptor for `ErrorEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List errorEventDescriptor = $convert.base64Decode('CgpFcnJvckV2ZW50EhIKBGNvZGUYASABKAVSBGNvZGUSGAoHbWVzc2FnZRgCIAEoCVIHbWVzc2FnZRIcCgljb21wb25lbnQYAyABKAlSCWNvbXBvbmVudBIlCg5pc19yZWNvdmVyYWJsZRgEIAEoCFINaXNSZWNvdmVyYWJsZQ==');
@$core.Deprecated('Use metricsEventDescriptor instead')
const MetricsEvent$json = const {
  '1': 'MetricsEvent',
  '2': const [
    const {'1': 'stt_final_ms', '3': 1, '4': 1, '5': 1, '10': 'sttFinalMs'},
    const {'1': 'llm_first_token_ms', '3': 2, '4': 1, '5': 1, '10': 'llmFirstTokenMs'},
    const {'1': 'tts_first_audio_ms', '3': 3, '4': 1, '5': 1, '10': 'ttsFirstAudioMs'},
    const {'1': 'end_to_end_ms', '3': 4, '4': 1, '5': 1, '10': 'endToEndMs'},
    const {'1': 'tokens_generated', '3': 5, '4': 1, '5': 3, '10': 'tokensGenerated'},
    const {'1': 'audio_samples_played', '3': 6, '4': 1, '5': 3, '10': 'audioSamplesPlayed'},
    const {'1': 'is_over_budget', '3': 7, '4': 1, '5': 8, '10': 'isOverBudget'},
    const {'1': 'created_at_ns', '3': 8, '4': 1, '5': 3, '10': 'createdAtNs'},
  ],
};

/// Descriptor for `MetricsEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List metricsEventDescriptor = $convert.base64Decode('CgxNZXRyaWNzRXZlbnQSIAoMc3R0X2ZpbmFsX21zGAEgASgBUgpzdHRGaW5hbE1zEisKEmxsbV9maXJzdF90b2tlbl9tcxgCIAEoAVIPbGxtRmlyc3RUb2tlbk1zEisKEnR0c19maXJzdF9hdWRpb19tcxgDIAEoAVIPdHRzRmlyc3RBdWRpb01zEiEKDWVuZF90b19lbmRfbXMYBCABKAFSCmVuZFRvRW5kTXMSKQoQdG9rZW5zX2dlbmVyYXRlZBgFIAEoA1IPdG9rZW5zR2VuZXJhdGVkEjAKFGF1ZGlvX3NhbXBsZXNfcGxheWVkGAYgASgDUhJhdWRpb1NhbXBsZXNQbGF5ZWQSJAoOaXNfb3Zlcl9idWRnZXQYByABKAhSDGlzT3ZlckJ1ZGdldBIiCg1jcmVhdGVkX2F0X25zGAggASgDUgtjcmVhdGVkQXROcw==');
@$core.Deprecated('Use voiceAgentComponentStatesDescriptor instead')
const VoiceAgentComponentStates$json = const {
  '1': 'VoiceAgentComponentStates',
  '2': const [
    const {'1': 'stt_state', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.ComponentLoadState', '10': 'sttState'},
    const {'1': 'llm_state', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.ComponentLoadState', '10': 'llmState'},
    const {'1': 'tts_state', '3': 3, '4': 1, '5': 14, '6': '.runanywhere.v1.ComponentLoadState', '10': 'ttsState'},
    const {'1': 'vad_state', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.ComponentLoadState', '10': 'vadState'},
    const {'1': 'ready', '3': 5, '4': 1, '5': 8, '10': 'ready'},
    const {'1': 'any_loading', '3': 6, '4': 1, '5': 8, '10': 'anyLoading'},
  ],
};

/// Descriptor for `VoiceAgentComponentStates`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceAgentComponentStatesDescriptor = $convert.base64Decode('ChlWb2ljZUFnZW50Q29tcG9uZW50U3RhdGVzEj8KCXN0dF9zdGF0ZRgBIAEoDjIiLnJ1bmFueXdoZXJlLnYxLkNvbXBvbmVudExvYWRTdGF0ZVIIc3R0U3RhdGUSPwoJbGxtX3N0YXRlGAIgASgOMiIucnVuYW55d2hlcmUudjEuQ29tcG9uZW50TG9hZFN0YXRlUghsbG1TdGF0ZRI/Cgl0dHNfc3RhdGUYAyABKA4yIi5ydW5hbnl3aGVyZS52MS5Db21wb25lbnRMb2FkU3RhdGVSCHR0c1N0YXRlEj8KCXZhZF9zdGF0ZRgEIAEoDjIiLnJ1bmFueXdoZXJlLnYxLkNvbXBvbmVudExvYWRTdGF0ZVIIdmFkU3RhdGUSFAoFcmVhZHkYBSABKAhSBXJlYWR5Eh8KC2FueV9sb2FkaW5nGAYgASgIUgphbnlMb2FkaW5n');
@$core.Deprecated('Use voiceSessionErrorDescriptor instead')
const VoiceSessionError$json = const {
  '1': 'VoiceSessionError',
  '2': const [
    const {'1': 'code', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.VoiceSessionErrorCode', '10': 'code'},
    const {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
    const {'1': 'failed_component', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'failedComponent', '17': true},
  ],
  '8': const [
    const {'1': '_failed_component'},
  ],
};

/// Descriptor for `VoiceSessionError`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceSessionErrorDescriptor = $convert.base64Decode('ChFWb2ljZVNlc3Npb25FcnJvchI5CgRjb2RlGAEgASgOMiUucnVuYW55d2hlcmUudjEuVm9pY2VTZXNzaW9uRXJyb3JDb2RlUgRjb2RlEhgKB21lc3NhZ2UYAiABKAlSB21lc3NhZ2USLgoQZmFpbGVkX2NvbXBvbmVudBgDIAEoCUgAUg9mYWlsZWRDb21wb25lbnSIAQFCEwoRX2ZhaWxlZF9jb21wb25lbnQ=');
@$core.Deprecated('Use sessionStartedEventDescriptor instead')
const SessionStartedEvent$json = const {
  '1': 'SessionStartedEvent',
};

/// Descriptor for `SessionStartedEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sessionStartedEventDescriptor = $convert.base64Decode('ChNTZXNzaW9uU3RhcnRlZEV2ZW50');
@$core.Deprecated('Use sessionStoppedEventDescriptor instead')
const SessionStoppedEvent$json = const {
  '1': 'SessionStoppedEvent',
};

/// Descriptor for `SessionStoppedEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sessionStoppedEventDescriptor = $convert.base64Decode('ChNTZXNzaW9uU3RvcHBlZEV2ZW50');
@$core.Deprecated('Use agentResponseStartedEventDescriptor instead')
const AgentResponseStartedEvent$json = const {
  '1': 'AgentResponseStartedEvent',
};

/// Descriptor for `AgentResponseStartedEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List agentResponseStartedEventDescriptor = $convert.base64Decode('ChlBZ2VudFJlc3BvbnNlU3RhcnRlZEV2ZW50');
@$core.Deprecated('Use agentResponseCompletedEventDescriptor instead')
const AgentResponseCompletedEvent$json = const {
  '1': 'AgentResponseCompletedEvent',
};

/// Descriptor for `AgentResponseCompletedEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List agentResponseCompletedEventDescriptor = $convert.base64Decode('ChtBZ2VudFJlc3BvbnNlQ29tcGxldGVkRXZlbnQ=');
