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
    {'1': 'category', '3': 3, '4': 1, '5': 14, '6': '.runanywhere.v1.EventCategory', '10': 'category'},
    {'1': 'severity', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.ErrorSeverity', '10': 'severity'},
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
    {'1': 'audio_level', '3': 27, '4': 1, '5': 11, '6': '.runanywhere.v1.AudioLevelEvent', '9': 0, '10': 'audioLevel'},
    {'1': 'component_progress', '3': 28, '4': 1, '5': 11, '6': '.runanywhere.v1.ComponentProgressEvent', '9': 0, '10': 'componentProgress'},
    {'1': 'session_id', '3': 30, '4': 1, '5': 9, '10': 'sessionId'},
    {'1': 'turn_id', '3': 31, '4': 1, '5': 9, '10': 'turnId'},
    {'1': 'request_id', '3': 32, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'metadata', '3': 33, '4': 3, '5': 11, '6': '.runanywhere.v1.VoiceEvent.MetadataEntry', '10': 'metadata'},
  ],
  '3': [VoiceEvent_MetadataEntry$json],
  '8': [
    {'1': 'payload'},
  ],
};

@$core.Deprecated('Use voiceEventDescriptor instead')
const VoiceEvent_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `VoiceEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceEventDescriptor = $convert.base64Decode(
    'CgpWb2ljZUV2ZW50EhAKA3NlcRgBIAEoBFIDc2VxEiEKDHRpbWVzdGFtcF91cxgCIAEoA1ILdG'
    'ltZXN0YW1wVXMSOQoIY2F0ZWdvcnkYAyABKA4yHS5ydW5hbnl3aGVyZS52MS5FdmVudENhdGVn'
    'b3J5UghjYXRlZ29yeRI5CghzZXZlcml0eRgEIAEoDjIdLnJ1bmFueXdoZXJlLnYxLkVycm9yU2'
    'V2ZXJpdHlSCHNldmVyaXR5EkQKCWNvbXBvbmVudBgFIAEoDjImLnJ1bmFueXdoZXJlLnYxLlZv'
    'aWNlUGlwZWxpbmVDb21wb25lbnRSCWNvbXBvbmVudBI8Cgl1c2VyX3NhaWQYCiABKAsyHS5ydW'
    '5hbnl3aGVyZS52MS5Vc2VyU2FpZEV2ZW50SABSCHVzZXJTYWlkEk4KD2Fzc2lzdGFudF90b2tl'
    'bhgLIAEoCzIjLnJ1bmFueXdoZXJlLnYxLkFzc2lzdGFudFRva2VuRXZlbnRIAFIOYXNzaXN0YW'
    '50VG9rZW4SNwoFYXVkaW8YDCABKAsyHy5ydW5hbnl3aGVyZS52MS5BdWRpb0ZyYW1lRXZlbnRI'
    'AFIFYXVkaW8SLAoDdmFkGA0gASgLMhgucnVuYW55d2hlcmUudjEuVkFERXZlbnRIAFIDdmFkEk'
    'QKC2ludGVycnVwdGVkGA4gASgLMiAucnVuYW55d2hlcmUudjEuSW50ZXJydXB0ZWRFdmVudEgA'
    'UgtpbnRlcnJ1cHRlZBI4CgVzdGF0ZRgPIAEoCzIgLnJ1bmFueXdoZXJlLnYxLlN0YXRlQ2hhbm'
    'dlRXZlbnRIAFIFc3RhdGUSMgoFZXJyb3IYECABKAsyGi5ydW5hbnl3aGVyZS52MS5FcnJvckV2'
    'ZW50SABSBWVycm9yEjgKB21ldHJpY3MYESABKAsyHC5ydW5hbnl3aGVyZS52MS5NZXRyaWNzRX'
    'ZlbnRIAFIHbWV0cmljcxJjChdjb21wb25lbnRfc3RhdGVfY2hhbmdlZBgSIAEoCzIpLnJ1bmFu'
    'eXdoZXJlLnYxLlZvaWNlQWdlbnRDb21wb25lbnRTdGF0ZXNIAFIVY29tcG9uZW50U3RhdGVDaG'
    'FuZ2VkEkgKDXNlc3Npb25fZXJyb3IYEyABKAsyIS5ydW5hbnl3aGVyZS52MS5Wb2ljZVNlc3Np'
    'b25FcnJvckgAUgxzZXNzaW9uRXJyb3ISTgoPc2Vzc2lvbl9zdGFydGVkGBQgASgLMiMucnVuYW'
    '55d2hlcmUudjEuU2Vzc2lvblN0YXJ0ZWRFdmVudEgAUg5zZXNzaW9uU3RhcnRlZBJOCg9zZXNz'
    'aW9uX3N0b3BwZWQYFSABKAsyIy5ydW5hbnl3aGVyZS52MS5TZXNzaW9uU3RvcHBlZEV2ZW50SA'
    'BSDnNlc3Npb25TdG9wcGVkEmEKFmFnZW50X3Jlc3BvbnNlX3N0YXJ0ZWQYFiABKAsyKS5ydW5h'
    'bnl3aGVyZS52MS5BZ2VudFJlc3BvbnNlU3RhcnRlZEV2ZW50SABSFGFnZW50UmVzcG9uc2VTdG'
    'FydGVkEmcKGGFnZW50X3Jlc3BvbnNlX2NvbXBsZXRlZBgXIAEoCzIrLnJ1bmFueXdoZXJlLnYx'
    'LkFnZW50UmVzcG9uc2VDb21wbGV0ZWRFdmVudEgAUhZhZ2VudFJlc3BvbnNlQ29tcGxldGVkEl'
    '4KFXNwZWVjaF90dXJuX2RldGVjdGlvbhgYIAEoCzIoLnJ1bmFueXdoZXJlLnYxLlNwZWVjaFR1'
    'cm5EZXRlY3Rpb25FdmVudEgAUhNzcGVlY2hUdXJuRGV0ZWN0aW9uEksKDnR1cm5fbGlmZWN5Y2'
    'xlGBkgASgLMiIucnVuYW55d2hlcmUudjEuVHVybkxpZmVjeWNsZUV2ZW50SABSDXR1cm5MaWZl'
    'Y3ljbGUSVAoRd2FrZXdvcmRfZGV0ZWN0ZWQYGiABKAsyJS5ydW5hbnl3aGVyZS52MS5XYWtlV2'
    '9yZERldGVjdGVkRXZlbnRIAFIQd2FrZXdvcmREZXRlY3RlZBJCCgthdWRpb19sZXZlbBgbIAEo'
    'CzIfLnJ1bmFueXdoZXJlLnYxLkF1ZGlvTGV2ZWxFdmVudEgAUgphdWRpb0xldmVsElcKEmNvbX'
    'BvbmVudF9wcm9ncmVzcxgcIAEoCzImLnJ1bmFueXdoZXJlLnYxLkNvbXBvbmVudFByb2dyZXNz'
    'RXZlbnRIAFIRY29tcG9uZW50UHJvZ3Jlc3MSHQoKc2Vzc2lvbl9pZBgeIAEoCVIJc2Vzc2lvbk'
    'lkEhcKB3R1cm5faWQYHyABKAlSBnR1cm5JZBIdCgpyZXF1ZXN0X2lkGCAgASgJUglyZXF1ZXN0'
    'SWQSRAoIbWV0YWRhdGEYISADKAsyKC5ydW5hbnl3aGVyZS52MS5Wb2ljZUV2ZW50Lk1ldGFkYX'
    'RhRW50cnlSCG1ldGFkYXRhGjsKDU1ldGFkYXRhRW50cnkSEAoDa2V5GAEgASgJUgNrZXkSFAoF'
    'dmFsdWUYAiABKAlSBXZhbHVlOgI4AUIJCgdwYXlsb2Fk');

@$core.Deprecated('Use userSaidEventDescriptor instead')
const UserSaidEvent$json = {
  '1': 'UserSaidEvent',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'is_final', '3': 2, '4': 1, '5': 8, '10': 'isFinal'},
    {'1': 'confidence', '3': 3, '4': 1, '5': 2, '10': 'confidence'},
    {'1': 'audio_start_us', '3': 4, '4': 1, '5': 3, '10': 'audioStartUs'},
    {'1': 'audio_end_us', '3': 5, '4': 1, '5': 3, '10': 'audioEndUs'},
    {'1': 'language_code', '3': 6, '4': 1, '5': 9, '10': 'languageCode'},
    {'1': 'segment_index', '3': 7, '4': 1, '5': 5, '10': 'segmentIndex'},
  ],
};

/// Descriptor for `UserSaidEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List userSaidEventDescriptor = $convert.base64Decode(
    'Cg1Vc2VyU2FpZEV2ZW50EhIKBHRleHQYASABKAlSBHRleHQSGQoIaXNfZmluYWwYAiABKAhSB2'
    'lzRmluYWwSHgoKY29uZmlkZW5jZRgDIAEoAlIKY29uZmlkZW5jZRIkCg5hdWRpb19zdGFydF91'
    'cxgEIAEoA1IMYXVkaW9TdGFydFVzEiAKDGF1ZGlvX2VuZF91cxgFIAEoA1IKYXVkaW9FbmRVcx'
    'IjCg1sYW5ndWFnZV9jb2RlGAYgASgJUgxsYW5ndWFnZUNvZGUSIwoNc2VnbWVudF9pbmRleBgH'
    'IAEoBVIMc2VnbWVudEluZGV4');

@$core.Deprecated('Use assistantTokenEventDescriptor instead')
const AssistantTokenEvent$json = {
  '1': 'AssistantTokenEvent',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'is_final', '3': 2, '4': 1, '5': 8, '10': 'isFinal'},
    {'1': 'kind', '3': 3, '4': 1, '5': 14, '6': '.runanywhere.v1.TokenKind', '10': 'kind'},
    {'1': 'token_id', '3': 4, '4': 1, '5': 13, '10': 'tokenId'},
    {'1': 'logprob', '3': 5, '4': 1, '5': 2, '10': 'logprob'},
    {'1': 'finish_reason', '3': 6, '4': 1, '5': 9, '10': 'finishReason'},
  ],
};

/// Descriptor for `AssistantTokenEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List assistantTokenEventDescriptor = $convert.base64Decode(
    'ChNBc3Npc3RhbnRUb2tlbkV2ZW50EhIKBHRleHQYASABKAlSBHRleHQSGQoIaXNfZmluYWwYAi'
    'ABKAhSB2lzRmluYWwSLQoEa2luZBgDIAEoDjIZLnJ1bmFueXdoZXJlLnYxLlRva2VuS2luZFIE'
    'a2luZBIZCgh0b2tlbl9pZBgEIAEoDVIHdG9rZW5JZBIYCgdsb2dwcm9iGAUgASgCUgdsb2dwcm'
    '9iEiMKDWZpbmlzaF9yZWFzb24YBiABKAlSDGZpbmlzaFJlYXNvbg==');

@$core.Deprecated('Use audioFrameEventDescriptor instead')
const AudioFrameEvent$json = {
  '1': 'AudioFrameEvent',
  '2': [
    {'1': 'pcm', '3': 1, '4': 1, '5': 12, '10': 'pcm'},
    {'1': 'sample_rate_hz', '3': 2, '4': 1, '5': 5, '10': 'sampleRateHz'},
    {'1': 'channels', '3': 3, '4': 1, '5': 5, '10': 'channels'},
    {'1': 'encoding', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.AudioEncoding', '10': 'encoding'},
    {'1': 'is_final', '3': 5, '4': 1, '5': 8, '10': 'isFinal'},
    {'1': 'chunk_index', '3': 6, '4': 1, '5': 5, '10': 'chunkIndex'},
    {'1': 'duration_ms', '3': 7, '4': 1, '5': 3, '10': 'durationMs'},
  ],
};

/// Descriptor for `AudioFrameEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List audioFrameEventDescriptor = $convert.base64Decode(
    'Cg9BdWRpb0ZyYW1lRXZlbnQSEAoDcGNtGAEgASgMUgNwY20SJAoOc2FtcGxlX3JhdGVfaHoYAi'
    'ABKAVSDHNhbXBsZVJhdGVIehIaCghjaGFubmVscxgDIAEoBVIIY2hhbm5lbHMSOQoIZW5jb2Rp'
    'bmcYBCABKA4yHS5ydW5hbnl3aGVyZS52MS5BdWRpb0VuY29kaW5nUghlbmNvZGluZxIZCghpc1'
    '9maW5hbBgFIAEoCFIHaXNGaW5hbBIfCgtjaHVua19pbmRleBgGIAEoBVIKY2h1bmtJbmRleBIf'
    'CgtkdXJhdGlvbl9tcxgHIAEoA1IKZHVyYXRpb25Ncw==');

@$core.Deprecated('Use vADEventDescriptor instead')
const VADEvent$json = {
  '1': 'VADEvent',
  '2': [
    {'1': 'type', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.VADStreamEventKind', '10': 'type'},
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
    'CghWQURFdmVudBI2CgR0eXBlGAEgASgOMiIucnVuYW55d2hlcmUudjEuVkFEU3RyZWFtRXZlbn'
    'RLaW5kUgR0eXBlEiYKD2ZyYW1lX29mZnNldF91cxgCIAEoA1INZnJhbWVPZmZzZXRVcxIeCgpj'
    'b25maWRlbmNlGAMgASgCUgpjb25maWRlbmNlEhsKCWlzX3NwZWVjaBgEIAEoCFIIaXNTcGVlY2'
    'gSLAoSc3BlZWNoX2R1cmF0aW9uX21zGAUgASgBUhBzcGVlY2hEdXJhdGlvbk1zEi4KE3NpbGVu'
    'Y2VfZHVyYXRpb25fbXMYBiABKAFSEXNpbGVuY2VEdXJhdGlvbk1zEiQKDm5vaXNlX2Zsb29yX2'
    'RiGAcgASgBUgxub2lzZUZsb29yRGI=');

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
    {'1': 'operation', '3': 5, '4': 1, '5': 9, '10': 'operation'},
    {'1': 'details_json', '3': 6, '4': 1, '5': 9, '10': 'detailsJson'},
  ],
};

/// Descriptor for `ErrorEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List errorEventDescriptor = $convert.base64Decode(
    'CgpFcnJvckV2ZW50EhIKBGNvZGUYASABKAVSBGNvZGUSGAoHbWVzc2FnZRgCIAEoCVIHbWVzc2'
    'FnZRIcCgljb21wb25lbnQYAyABKAlSCWNvbXBvbmVudBIlCg5pc19yZWNvdmVyYWJsZRgEIAEo'
    'CFINaXNSZWNvdmVyYWJsZRIcCglvcGVyYXRpb24YBSABKAlSCW9wZXJhdGlvbhIhCgxkZXRhaW'
    'xzX2pzb24YBiABKAlSC2RldGFpbHNKc29u');

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
    {'1': 'vad_first_speech_ms', '3': 9, '4': 1, '5': 1, '10': 'vadFirstSpeechMs'},
    {'1': 'stt_first_partial_ms', '3': 10, '4': 1, '5': 1, '10': 'sttFirstPartialMs'},
    {'1': 'llm_total_ms', '3': 11, '4': 1, '5': 1, '10': 'llmTotalMs'},
    {'1': 'tts_total_ms', '3': 12, '4': 1, '5': 1, '10': 'ttsTotalMs'},
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
    'dGVkQXROcxItChN2YWRfZmlyc3Rfc3BlZWNoX21zGAkgASgBUhB2YWRGaXJzdFNwZWVjaE1zEi'
    '8KFHN0dF9maXJzdF9wYXJ0aWFsX21zGAogASgBUhFzdHRGaXJzdFBhcnRpYWxNcxIgCgxsbG1f'
    'dG90YWxfbXMYCyABKAFSCmxsbVRvdGFsTXMSIAoMdHRzX3RvdGFsX21zGAwgASgBUgp0dHNUb3'
    'RhbE1z');

@$core.Deprecated('Use audioLevelEventDescriptor instead')
const AudioLevelEvent$json = {
  '1': 'AudioLevelEvent',
  '2': [
    {'1': 'rms', '3': 1, '4': 1, '5': 2, '10': 'rms'},
    {'1': 'peak', '3': 2, '4': 1, '5': 2, '10': 'peak'},
    {'1': 'noise_floor_db', '3': 3, '4': 1, '5': 2, '10': 'noiseFloorDb'},
    {'1': 'is_speech', '3': 4, '4': 1, '5': 8, '10': 'isSpeech'},
  ],
};

/// Descriptor for `AudioLevelEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List audioLevelEventDescriptor = $convert.base64Decode(
    'Cg9BdWRpb0xldmVsRXZlbnQSEAoDcm1zGAEgASgCUgNybXMSEgoEcGVhaxgCIAEoAlIEcGVhax'
    'IkCg5ub2lzZV9mbG9vcl9kYhgDIAEoAlIMbm9pc2VGbG9vckRiEhsKCWlzX3NwZWVjaBgEIAEo'
    'CFIIaXNTcGVlY2g=');

@$core.Deprecated('Use componentProgressEventDescriptor instead')
const ComponentProgressEvent$json = {
  '1': 'ComponentProgressEvent',
  '2': [
    {'1': 'component', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.VoicePipelineComponent', '10': 'component'},
    {'1': 'operation', '3': 2, '4': 1, '5': 9, '10': 'operation'},
    {'1': 'progress', '3': 3, '4': 1, '5': 2, '10': 'progress'},
    {'1': 'message', '3': 4, '4': 1, '5': 9, '10': 'message'},
  ],
};

/// Descriptor for `ComponentProgressEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List componentProgressEventDescriptor = $convert.base64Decode(
    'ChZDb21wb25lbnRQcm9ncmVzc0V2ZW50EkQKCWNvbXBvbmVudBgBIAEoDjImLnJ1bmFueXdoZX'
    'JlLnYxLlZvaWNlUGlwZWxpbmVDb21wb25lbnRSCWNvbXBvbmVudBIcCglvcGVyYXRpb24YAiAB'
    'KAlSCW9wZXJhdGlvbhIaCghwcm9ncmVzcxgDIAEoAlIIcHJvZ3Jlc3MSGAoHbWVzc2FnZRgEIA'
    'EoCVIHbWVzc2FnZQ==');

@$core.Deprecated('Use voiceAgentComponentStatesDescriptor instead')
const VoiceAgentComponentStates$json = {
  '1': 'VoiceAgentComponentStates',
  '2': [
    {'1': 'stt_state', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.ComponentLifecycleState', '10': 'sttState'},
    {'1': 'llm_state', '3': 2, '4': 1, '5': 14, '6': '.runanywhere.v1.ComponentLifecycleState', '10': 'llmState'},
    {'1': 'tts_state', '3': 3, '4': 1, '5': 14, '6': '.runanywhere.v1.ComponentLifecycleState', '10': 'ttsState'},
    {'1': 'vad_state', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.ComponentLifecycleState', '10': 'vadState'},
    {'1': 'ready', '3': 5, '4': 1, '5': 8, '10': 'ready'},
    {'1': 'any_loading', '3': 6, '4': 1, '5': 8, '10': 'anyLoading'},
    {'1': 'wakeword_state', '3': 7, '4': 1, '5': 14, '6': '.runanywhere.v1.ComponentLifecycleState', '10': 'wakewordState'},
    {'1': 'error_message', '3': 8, '4': 1, '5': 9, '9': 0, '10': 'errorMessage', '17': true},
  ],
  '8': [
    {'1': '_error_message'},
  ],
};

/// Descriptor for `VoiceAgentComponentStates`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceAgentComponentStatesDescriptor = $convert.base64Decode(
    'ChlWb2ljZUFnZW50Q29tcG9uZW50U3RhdGVzEkQKCXN0dF9zdGF0ZRgBIAEoDjInLnJ1bmFueX'
    'doZXJlLnYxLkNvbXBvbmVudExpZmVjeWNsZVN0YXRlUghzdHRTdGF0ZRJECglsbG1fc3RhdGUY'
    'AiABKA4yJy5ydW5hbnl3aGVyZS52MS5Db21wb25lbnRMaWZlY3ljbGVTdGF0ZVIIbGxtU3RhdG'
    'USRAoJdHRzX3N0YXRlGAMgASgOMicucnVuYW55d2hlcmUudjEuQ29tcG9uZW50TGlmZWN5Y2xl'
    'U3RhdGVSCHR0c1N0YXRlEkQKCXZhZF9zdGF0ZRgEIAEoDjInLnJ1bmFueXdoZXJlLnYxLkNvbX'
    'BvbmVudExpZmVjeWNsZVN0YXRlUgh2YWRTdGF0ZRIUCgVyZWFkeRgFIAEoCFIFcmVhZHkSHwoL'
    'YW55X2xvYWRpbmcYBiABKAhSCmFueUxvYWRpbmcSTgoOd2FrZXdvcmRfc3RhdGUYByABKA4yJy'
    '5ydW5hbnl3aGVyZS52MS5Db21wb25lbnRMaWZlY3ljbGVTdGF0ZVINd2FrZXdvcmRTdGF0ZRIo'
    'Cg1lcnJvcl9tZXNzYWdlGAggASgJSABSDGVycm9yTWVzc2FnZYgBAUIQCg5fZXJyb3JfbWVzc2'
    'FnZQ==');

@$core.Deprecated('Use voiceSessionErrorDescriptor instead')
const VoiceSessionError$json = {
  '1': 'VoiceSessionError',
  '2': [
    {'1': 'code', '3': 1, '4': 1, '5': 14, '6': '.runanywhere.v1.ErrorCode', '10': 'code'},
    {'1': 'message', '3': 2, '4': 1, '5': 9, '10': 'message'},
    {'1': 'failed_component', '3': 3, '4': 1, '5': 9, '9': 0, '10': 'failedComponent', '17': true},
    {'1': 'c_abi_code', '3': 4, '4': 1, '5': 5, '10': 'cAbiCode'},
    {'1': 'recoverable', '3': 5, '4': 1, '5': 8, '10': 'recoverable'},
  ],
  '8': [
    {'1': '_failed_component'},
  ],
};

/// Descriptor for `VoiceSessionError`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceSessionErrorDescriptor = $convert.base64Decode(
    'ChFWb2ljZVNlc3Npb25FcnJvchItCgRjb2RlGAEgASgOMhkucnVuYW55d2hlcmUudjEuRXJyb3'
    'JDb2RlUgRjb2RlEhgKB21lc3NhZ2UYAiABKAlSB21lc3NhZ2USLgoQZmFpbGVkX2NvbXBvbmVu'
    'dBgDIAEoCUgAUg9mYWlsZWRDb21wb25lbnSIAQESHAoKY19hYmlfY29kZRgEIAEoBVIIY0FiaU'
    'NvZGUSIAoLcmVjb3ZlcmFibGUYBSABKAhSC3JlY292ZXJhYmxlQhMKEV9mYWlsZWRfY29tcG9u'
    'ZW50');

@$core.Deprecated('Use sessionStartedEventDescriptor instead')
const SessionStartedEvent$json = {
  '1': 'SessionStartedEvent',
  '2': [
    {'1': 'session_id', '3': 1, '4': 1, '5': 9, '10': 'sessionId'},
  ],
};

/// Descriptor for `SessionStartedEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sessionStartedEventDescriptor = $convert.base64Decode(
    'ChNTZXNzaW9uU3RhcnRlZEV2ZW50Eh0KCnNlc3Npb25faWQYASABKAlSCXNlc3Npb25JZA==');

@$core.Deprecated('Use sessionStoppedEventDescriptor instead')
const SessionStoppedEvent$json = {
  '1': 'SessionStoppedEvent',
  '2': [
    {'1': 'session_id', '3': 1, '4': 1, '5': 9, '10': 'sessionId'},
    {'1': 'reason', '3': 2, '4': 1, '5': 9, '10': 'reason'},
  ],
};

/// Descriptor for `SessionStoppedEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List sessionStoppedEventDescriptor = $convert.base64Decode(
    'ChNTZXNzaW9uU3RvcHBlZEV2ZW50Eh0KCnNlc3Npb25faWQYASABKAlSCXNlc3Npb25JZBIWCg'
    'ZyZWFzb24YAiABKAlSBnJlYXNvbg==');

@$core.Deprecated('Use agentResponseStartedEventDescriptor instead')
const AgentResponseStartedEvent$json = {
  '1': 'AgentResponseStartedEvent',
  '2': [
    {'1': 'turn_id', '3': 1, '4': 1, '5': 9, '10': 'turnId'},
  ],
};

/// Descriptor for `AgentResponseStartedEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List agentResponseStartedEventDescriptor = $convert.base64Decode(
    'ChlBZ2VudFJlc3BvbnNlU3RhcnRlZEV2ZW50EhcKB3R1cm5faWQYASABKAlSBnR1cm5JZA==');

@$core.Deprecated('Use agentResponseCompletedEventDescriptor instead')
const AgentResponseCompletedEvent$json = {
  '1': 'AgentResponseCompletedEvent',
  '2': [
    {'1': 'turn_id', '3': 1, '4': 1, '5': 9, '10': 'turnId'},
    {'1': 'response_duration_ms', '3': 2, '4': 1, '5': 3, '10': 'responseDurationMs'},
  ],
};

/// Descriptor for `AgentResponseCompletedEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List agentResponseCompletedEventDescriptor = $convert.base64Decode(
    'ChtBZ2VudFJlc3BvbnNlQ29tcGxldGVkRXZlbnQSFwoHdHVybl9pZBgBIAEoCVIGdHVybklkEj'
    'AKFHJlc3BvbnNlX2R1cmF0aW9uX21zGAIgASgDUhJyZXNwb25zZUR1cmF0aW9uTXM=');

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
    {'1': 'started_at_ms', '3': 7, '4': 1, '5': 3, '10': 'startedAtMs'},
    {'1': 'completed_at_ms', '3': 8, '4': 1, '5': 3, '10': 'completedAtMs'},
  ],
};

/// Descriptor for `TurnLifecycleEvent`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List turnLifecycleEventDescriptor = $convert.base64Decode(
    'ChJUdXJuTGlmZWN5Y2xlRXZlbnQSOgoEa2luZBgBIAEoDjImLnJ1bmFueXdoZXJlLnYxLlR1cm'
    '5MaWZlY3ljbGVFdmVudEtpbmRSBGtpbmQSFwoHdHVybl9pZBgCIAEoCVIGdHVybklkEh0KCnNl'
    'c3Npb25faWQYAyABKAlSCXNlc3Npb25JZBIeCgp0cmFuc2NyaXB0GAQgASgJUgp0cmFuc2NyaX'
    'B0EhoKCHJlc3BvbnNlGAUgASgJUghyZXNwb25zZRIUCgVlcnJvchgGIAEoCVIFZXJyb3ISIgoN'
    'c3RhcnRlZF9hdF9tcxgHIAEoA1ILc3RhcnRlZEF0TXMSJgoPY29tcGxldGVkX2F0X21zGAggAS'
    'gDUg1jb21wbGV0ZWRBdE1z');

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

