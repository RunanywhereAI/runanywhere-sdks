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
  ],
};

/// Descriptor for `VADEventType`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List vADEventTypeDescriptor = $convert.base64Decode(
    'CgxWQURFdmVudFR5cGUSGQoVVkFEX0VWRU5UX1VOU1BFQ0lGSUVEEAASGQoVVkFEX0VWRU5UX1'
    'ZPSUNFX1NUQVJUEAESJAogVkFEX0VWRU5UX1ZPSUNFX0VORF9PRl9VVFRFUkFOQ0UQAhIWChJW'
    'QURfRVZFTlRfQkFSR0VfSU4QAxIVChFWQURfRVZFTlRfU0lMRU5DRRAE');

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
  ],
};

/// Descriptor for `PipelineState`. Decode as a `google.protobuf.EnumDescriptorProto`.
final $typed_data.Uint8List pipelineStateDescriptor = $convert.base64Decode(
    'Cg1QaXBlbGluZVN0YXRlEh4KGlBJUEVMSU5FX1NUQVRFX1VOU1BFQ0lGSUVEEAASFwoTUElQRU'
    'xJTkVfU1RBVEVfSURMRRABEhwKGFBJUEVMSU5FX1NUQVRFX0xJU1RFTklORxACEhsKF1BJUEVM'
    'SU5FX1NUQVRFX1RISU5LSU5HEAMSGwoXUElQRUxJTkVfU1RBVEVfU1BFQUtJTkcQBBIaChZQSV'
    'BFTElORV9TVEFURV9TVE9QUEVEEAU=');

@$core.Deprecated('Use voiceEventDescriptor instead')
const VoiceEvent$json = {
  '1': 'VoiceEvent',
  '2': [
    {'1': 'seq', '3': 1, '4': 1, '5': 4, '10': 'seq'},
    {'1': 'timestamp_us', '3': 2, '4': 1, '5': 3, '10': 'timestampUs'},
    {'1': 'user_said', '3': 10, '4': 1, '5': 11, '6': '.runanywhere.v1.UserSaidEvent', '9': 0, '10': 'userSaid'},
    {'1': 'assistant_token', '3': 11, '4': 1, '5': 11, '6': '.runanywhere.v1.AssistantTokenEvent', '9': 0, '10': 'assistantToken'},
    {'1': 'audio', '3': 12, '4': 1, '5': 11, '6': '.runanywhere.v1.AudioFrameEvent', '9': 0, '10': 'audio'},
    {'1': 'vad', '3': 13, '4': 1, '5': 11, '6': '.runanywhere.v1.VADEvent', '9': 0, '10': 'vad'},
    {'1': 'interrupted', '3': 14, '4': 1, '5': 11, '6': '.runanywhere.v1.InterruptedEvent', '9': 0, '10': 'interrupted'},
    {'1': 'state', '3': 15, '4': 1, '5': 11, '6': '.runanywhere.v1.StateChangeEvent', '9': 0, '10': 'state'},
    {'1': 'error', '3': 16, '4': 1, '5': 11, '6': '.runanywhere.v1.ErrorEvent', '9': 0, '10': 'error'},
    {'1': 'metrics', '3': 17, '4': 1, '5': 11, '6': '.runanywhere.v1.MetricsEvent', '9': 0, '10': 'metrics'},
  ],
  '8': [
    {'1': 'payload'},
  ],
};

/// Descriptor for `VoiceEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceEventDescriptor = $convert.base64Decode(
    'CgpWb2ljZUV2ZW50EhAKA3NlcRgBIAEoBFIDc2VxEiEKDHRpbWVzdGFtcF91cxgCIAEoA1ILdG'
    'ltZXN0YW1wVXMSPAoJdXNlcl9zYWlkGAogASgLMh0ucnVuYW55d2hlcmUudjEuVXNlclNhaWRF'
    'dmVudEgAUgh1c2VyU2FpZBJOCg9hc3Npc3RhbnRfdG9rZW4YCyABKAsyIy5ydW5hbnl3aGVyZS'
    '52MS5Bc3Npc3RhbnRUb2tlbkV2ZW50SABSDmFzc2lzdGFudFRva2VuEjcKBWF1ZGlvGAwgASgL'
    'Mh8ucnVuYW55d2hlcmUudjEuQXVkaW9GcmFtZUV2ZW50SABSBWF1ZGlvEiwKA3ZhZBgNIAEoCz'
    'IYLnJ1bmFueXdoZXJlLnYxLlZBREV2ZW50SABSA3ZhZBJECgtpbnRlcnJ1cHRlZBgOIAEoCzIg'
    'LnJ1bmFueXdoZXJlLnYxLkludGVycnVwdGVkRXZlbnRIAFILaW50ZXJydXB0ZWQSOAoFc3RhdG'
    'UYDyABKAsyIC5ydW5hbnl3aGVyZS52MS5TdGF0ZUNoYW5nZUV2ZW50SABSBXN0YXRlEjIKBWVy'
    'cm9yGBAgASgLMhoucnVuYW55d2hlcmUudjEuRXJyb3JFdmVudEgAUgVlcnJvchI4CgdtZXRyaW'
    'NzGBEgASgLMhwucnVuYW55d2hlcmUudjEuTWV0cmljc0V2ZW50SABSB21ldHJpY3NCCQoHcGF5'
    'bG9hZA==');

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
  ],
};

/// Descriptor for `AudioFrameEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List audioFrameEventDescriptor = $convert.base64Decode(
    'Cg9BdWRpb0ZyYW1lRXZlbnQSEAoDcGNtGAEgASgMUgNwY20SJAoOc2FtcGxlX3JhdGVfaHoYAi'
    'ABKAVSDHNhbXBsZVJhdGVIehIaCghjaGFubmVscxgDIAEoBVIIY2hhbm5lbHMSOQoIZW5jb2Rp'
    'bmcYBCABKA4yHS5ydW5hbnl3aGVyZS52MS5BdWRpb0VuY29kaW5nUghlbmNvZGluZw==');

@$core.Deprecated('Use vADEventDescriptor instead')
const VADEvent$json = {
  '1': 'VADEvent',
  '2': [
    {'1': 'type', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.VADEventType', '10': 'type'},
    {'1': 'frame_offset_us', '3': 2, '4': 1, '5': 3, '10': 'frameOffsetUs'},
  ],
};

/// Descriptor for `VADEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List vADEventDescriptor = $convert.base64Decode(
    'CghWQURFdmVudBIwCgR0eXBlGAEgASgOMhwucnVuYW55d2hlcmUudjEuVkFERXZlbnRUeXBlUg'
    'R0eXBlEiYKD2ZyYW1lX29mZnNldF91cxgCIAEoA1INZnJhbWVPZmZzZXRVcw==');

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
  ],
};

/// Descriptor for `MetricsEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List metricsEventDescriptor = $convert.base64Decode(
    'CgxNZXRyaWNzRXZlbnQSIAoMc3R0X2ZpbmFsX21zGAEgASgBUgpzdHRGaW5hbE1zEisKEmxsbV'
    '9maXJzdF90b2tlbl9tcxgCIAEoAVIPbGxtRmlyc3RUb2tlbk1zEisKEnR0c19maXJzdF9hdWRp'
    'b19tcxgDIAEoAVIPdHRzRmlyc3RBdWRpb01zEiEKDWVuZF90b19lbmRfbXMYBCABKAFSCmVuZF'
    'RvRW5kTXMSKQoQdG9rZW5zX2dlbmVyYXRlZBgFIAEoA1IPdG9rZW5zR2VuZXJhdGVkEjAKFGF1'
    'ZGlvX3NhbXBsZXNfcGxheWVkGAYgASgDUhJhdWRpb1NhbXBsZXNQbGF5ZWQSJAoOaXNfb3Zlcl'
    '9idWRnZXQYByABKAhSDGlzT3ZlckJ1ZGdldA==');

