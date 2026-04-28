///
//  Generated code. Do not modify.
//  source: voice_agent_service.proto
//
// @dart = 2.12
// ignore_for_file: annotate_overrides,camel_case_types,constant_identifier_names,deprecated_member_use_from_same_package,directives_ordering,library_prefixes,non_constant_identifier_names,prefer_final_fields,return_of_invalid_type,unnecessary_const,unnecessary_import,unnecessary_this,unused_import,unused_shown_name

import 'dart:core' as $core;
import 'dart:convert' as $convert;
import 'dart:typed_data' as $typed_data;
import 'voice_events.pbjson.dart' as $0;

@$core.Deprecated('Use voiceAgentRequestDescriptor instead')
const VoiceAgentRequest$json = const {
  '1': 'VoiceAgentRequest',
  '2': const [
    const {'1': 'event_filter', '3': 1, '4': 1, '5': 9, '10': 'eventFilter'},
  ],
};

/// Descriptor for `VoiceAgentRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceAgentRequestDescriptor = $convert.base64Decode('ChFWb2ljZUFnZW50UmVxdWVzdBIhCgxldmVudF9maWx0ZXIYASABKAlSC2V2ZW50RmlsdGVy');
@$core.Deprecated('Use voiceAgentResultDescriptor instead')
const VoiceAgentResult$json = const {
  '1': 'VoiceAgentResult',
  '2': const [
    const {'1': 'speech_detected', '3': 1, '4': 1, '5': 8, '10': 'speechDetected'},
    const {'1': 'transcription', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'transcription', '17': true},
    const {'1': 'assistant_response', '3': 3, '4': 1, '5': 9, '9': 1, '10': 'assistantResponse', '17': true},
    const {'1': 'thinking_content', '3': 4, '4': 1, '5': 9, '9': 2, '10': 'thinkingContent', '17': true},
    const {'1': 'synthesized_audio', '3': 5, '4': 1, '5': 12, '9': 3, '10': 'synthesizedAudio', '17': true},
    const {'1': 'final_state', '3': 6, '4': 1, '5': 11, '6': '.runanywhere.v1.VoiceAgentComponentStates', '9': 4, '10': 'finalState', '17': true},
  ],
  '8': const [
    const {'1': '_transcription'},
    const {'1': '_assistant_response'},
    const {'1': '_thinking_content'},
    const {'1': '_synthesized_audio'},
    const {'1': '_final_state'},
  ],
};

/// Descriptor for `VoiceAgentResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceAgentResultDescriptor = $convert.base64Decode('ChBWb2ljZUFnZW50UmVzdWx0EicKD3NwZWVjaF9kZXRlY3RlZBgBIAEoCFIOc3BlZWNoRGV0ZWN0ZWQSKQoNdHJhbnNjcmlwdGlvbhgCIAEoCUgAUg10cmFuc2NyaXB0aW9uiAEBEjIKEmFzc2lzdGFudF9yZXNwb25zZRgDIAEoCUgBUhFhc3Npc3RhbnRSZXNwb25zZYgBARIuChB0aGlua2luZ19jb250ZW50GAQgASgJSAJSD3RoaW5raW5nQ29udGVudIgBARIwChFzeW50aGVzaXplZF9hdWRpbxgFIAEoDEgDUhBzeW50aGVzaXplZEF1ZGlviAEBEk8KC2ZpbmFsX3N0YXRlGAYgASgLMikucnVuYW55d2hlcmUudjEuVm9pY2VBZ2VudENvbXBvbmVudFN0YXRlc0gEUgpmaW5hbFN0YXRliAEBQhAKDl90cmFuc2NyaXB0aW9uQhUKE19hc3Npc3RhbnRfcmVzcG9uc2VCEwoRX3RoaW5raW5nX2NvbnRlbnRCFAoSX3N5bnRoZXNpemVkX2F1ZGlvQg4KDF9maW5hbF9zdGF0ZQ==');
@$core.Deprecated('Use voiceSessionConfigDescriptor instead')
const VoiceSessionConfig$json = const {
  '1': 'VoiceSessionConfig',
  '2': const [
    const {'1': 'silence_duration_ms', '3': 1, '4': 1, '5': 5, '10': 'silenceDurationMs'},
    const {'1': 'speech_threshold', '3': 2, '4': 1, '5': 2, '10': 'speechThreshold'},
    const {'1': 'auto_play_tts', '3': 3, '4': 1, '5': 8, '10': 'autoPlayTts'},
    const {'1': 'continuous_mode', '3': 4, '4': 1, '5': 8, '10': 'continuousMode'},
    const {'1': 'thinking_mode_enabled', '3': 5, '4': 1, '5': 8, '10': 'thinkingModeEnabled'},
  ],
};

/// Descriptor for `VoiceSessionConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceSessionConfigDescriptor = $convert.base64Decode('ChJWb2ljZVNlc3Npb25Db25maWcSLgoTc2lsZW5jZV9kdXJhdGlvbl9tcxgBIAEoBVIRc2lsZW5jZUR1cmF0aW9uTXMSKQoQc3BlZWNoX3RocmVzaG9sZBgCIAEoAlIPc3BlZWNoVGhyZXNob2xkEiIKDWF1dG9fcGxheV90dHMYAyABKAhSC2F1dG9QbGF5VHRzEicKD2NvbnRpbnVvdXNfbW9kZRgEIAEoCFIOY29udGludW91c01vZGUSMgoVdGhpbmtpbmdfbW9kZV9lbmFibGVkGAUgASgIUhN0aGlua2luZ01vZGVFbmFibGVk');
@$core.Deprecated('Use voiceAgentComposeConfigDescriptor instead')
const VoiceAgentComposeConfig$json = const {
  '1': 'VoiceAgentComposeConfig',
  '2': const [
    const {'1': 'stt_model_path', '3': 1, '4': 1, '5': 9, '9': 0, '10': 'sttModelPath', '17': true},
    const {'1': 'stt_model_id', '3': 2, '4': 1, '5': 9, '9': 1, '10': 'sttModelId', '17': true},
    const {'1': 'stt_model_name', '3': 3, '4': 1, '5': 9, '9': 2, '10': 'sttModelName', '17': true},
    const {'1': 'llm_model_path', '3': 4, '4': 1, '5': 9, '9': 3, '10': 'llmModelPath', '17': true},
    const {'1': 'llm_model_id', '3': 5, '4': 1, '5': 9, '9': 4, '10': 'llmModelId', '17': true},
    const {'1': 'llm_model_name', '3': 6, '4': 1, '5': 9, '9': 5, '10': 'llmModelName', '17': true},
    const {'1': 'tts_voice_path', '3': 7, '4': 1, '5': 9, '9': 6, '10': 'ttsVoicePath', '17': true},
    const {'1': 'tts_voice_id', '3': 8, '4': 1, '5': 9, '9': 7, '10': 'ttsVoiceId', '17': true},
    const {'1': 'tts_voice_name', '3': 9, '4': 1, '5': 9, '9': 8, '10': 'ttsVoiceName', '17': true},
    const {'1': 'vad_sample_rate', '3': 10, '4': 1, '5': 5, '10': 'vadSampleRate'},
    const {'1': 'vad_frame_length', '3': 11, '4': 1, '5': 2, '10': 'vadFrameLength'},
    const {'1': 'vad_energy_threshold', '3': 12, '4': 1, '5': 2, '10': 'vadEnergyThreshold'},
    const {'1': 'wakeword_enabled', '3': 13, '4': 1, '5': 8, '10': 'wakewordEnabled'},
    const {'1': 'wakeword_model_path', '3': 14, '4': 1, '5': 9, '9': 9, '10': 'wakewordModelPath', '17': true},
    const {'1': 'wakeword_model_id', '3': 15, '4': 1, '5': 9, '9': 10, '10': 'wakewordModelId', '17': true},
    const {'1': 'wakeword_phrase', '3': 16, '4': 1, '5': 9, '9': 11, '10': 'wakewordPhrase', '17': true},
    const {'1': 'wakeword_threshold', '3': 17, '4': 1, '5': 2, '10': 'wakewordThreshold'},
    const {'1': 'wakeword_embedding_model_path', '3': 18, '4': 1, '5': 9, '9': 12, '10': 'wakewordEmbeddingModelPath', '17': true},
    const {'1': 'wakeword_vad_model_path', '3': 19, '4': 1, '5': 9, '9': 13, '10': 'wakewordVadModelPath', '17': true},
    const {'1': 'session_config', '3': 20, '4': 1, '5': 11, '6': '.runanywhere.v1.VoiceSessionConfig', '9': 14, '10': 'sessionConfig', '17': true},
  ],
  '8': const [
    const {'1': '_stt_model_path'},
    const {'1': '_stt_model_id'},
    const {'1': '_stt_model_name'},
    const {'1': '_llm_model_path'},
    const {'1': '_llm_model_id'},
    const {'1': '_llm_model_name'},
    const {'1': '_tts_voice_path'},
    const {'1': '_tts_voice_id'},
    const {'1': '_tts_voice_name'},
    const {'1': '_wakeword_model_path'},
    const {'1': '_wakeword_model_id'},
    const {'1': '_wakeword_phrase'},
    const {'1': '_wakeword_embedding_model_path'},
    const {'1': '_wakeword_vad_model_path'},
    const {'1': '_session_config'},
  ],
};

/// Descriptor for `VoiceAgentComposeConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceAgentComposeConfigDescriptor = $convert.base64Decode('ChdWb2ljZUFnZW50Q29tcG9zZUNvbmZpZxIpCg5zdHRfbW9kZWxfcGF0aBgBIAEoCUgAUgxzdHRNb2RlbFBhdGiIAQESJQoMc3R0X21vZGVsX2lkGAIgASgJSAFSCnN0dE1vZGVsSWSIAQESKQoOc3R0X21vZGVsX25hbWUYAyABKAlIAlIMc3R0TW9kZWxOYW1liAEBEikKDmxsbV9tb2RlbF9wYXRoGAQgASgJSANSDGxsbU1vZGVsUGF0aIgBARIlCgxsbG1fbW9kZWxfaWQYBSABKAlIBFIKbGxtTW9kZWxJZIgBARIpCg5sbG1fbW9kZWxfbmFtZRgGIAEoCUgFUgxsbG1Nb2RlbE5hbWWIAQESKQoOdHRzX3ZvaWNlX3BhdGgYByABKAlIBlIMdHRzVm9pY2VQYXRoiAEBEiUKDHR0c192b2ljZV9pZBgIIAEoCUgHUgp0dHNWb2ljZUlkiAEBEikKDnR0c192b2ljZV9uYW1lGAkgASgJSAhSDHR0c1ZvaWNlTmFtZYgBARImCg92YWRfc2FtcGxlX3JhdGUYCiABKAVSDXZhZFNhbXBsZVJhdGUSKAoQdmFkX2ZyYW1lX2xlbmd0aBgLIAEoAlIOdmFkRnJhbWVMZW5ndGgSMAoUdmFkX2VuZXJneV90aHJlc2hvbGQYDCABKAJSEnZhZEVuZXJneVRocmVzaG9sZBIpChB3YWtld29yZF9lbmFibGVkGA0gASgIUg93YWtld29yZEVuYWJsZWQSMwoTd2FrZXdvcmRfbW9kZWxfcGF0aBgOIAEoCUgJUhF3YWtld29yZE1vZGVsUGF0aIgBARIvChF3YWtld29yZF9tb2RlbF9pZBgPIAEoCUgKUg93YWtld29yZE1vZGVsSWSIAQESLAoPd2FrZXdvcmRfcGhyYXNlGBAgASgJSAtSDndha2V3b3JkUGhyYXNliAEBEi0KEndha2V3b3JkX3RocmVzaG9sZBgRIAEoAlIRd2FrZXdvcmRUaHJlc2hvbGQSRgodd2FrZXdvcmRfZW1iZWRkaW5nX21vZGVsX3BhdGgYEiABKAlIDFIad2FrZXdvcmRFbWJlZGRpbmdNb2RlbFBhdGiIAQESOgoXd2FrZXdvcmRfdmFkX21vZGVsX3BhdGgYEyABKAlIDVIUd2FrZXdvcmRWYWRNb2RlbFBhdGiIAQESTgoOc2Vzc2lvbl9jb25maWcYFCABKAsyIi5ydW5hbnl3aGVyZS52MS5Wb2ljZVNlc3Npb25Db25maWdIDlINc2Vzc2lvbkNvbmZpZ4gBAUIRCg9fc3R0X21vZGVsX3BhdGhCDwoNX3N0dF9tb2RlbF9pZEIRCg9fc3R0X21vZGVsX25hbWVCEQoPX2xsbV9tb2RlbF9wYXRoQg8KDV9sbG1fbW9kZWxfaWRCEQoPX2xsbV9tb2RlbF9uYW1lQhEKD190dHNfdm9pY2VfcGF0aEIPCg1fdHRzX3ZvaWNlX2lkQhEKD190dHNfdm9pY2VfbmFtZUIWChRfd2FrZXdvcmRfbW9kZWxfcGF0aEIUChJfd2FrZXdvcmRfbW9kZWxfaWRCEgoQX3dha2V3b3JkX3BocmFzZUIgCh5fd2FrZXdvcmRfZW1iZWRkaW5nX21vZGVsX3BhdGhCGgoYX3dha2V3b3JkX3ZhZF9tb2RlbF9wYXRoQhEKD19zZXNzaW9uX2NvbmZpZw==');
const $core.Map<$core.String, $core.dynamic> VoiceAgentServiceBase$json = const {
  '1': 'VoiceAgent',
  '2': const [
    const {'1': 'Stream', '2': '.runanywhere.v1.VoiceAgentRequest', '3': '.runanywhere.v1.VoiceEvent', '6': true},
  ],
};

@$core.Deprecated('Use voiceAgentServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> VoiceAgentServiceBase$messageJson = const {
  '.runanywhere.v1.VoiceAgentRequest': VoiceAgentRequest$json,
  '.runanywhere.v1.VoiceEvent': $0.VoiceEvent$json,
  '.runanywhere.v1.UserSaidEvent': $0.UserSaidEvent$json,
  '.runanywhere.v1.AssistantTokenEvent': $0.AssistantTokenEvent$json,
  '.runanywhere.v1.AudioFrameEvent': $0.AudioFrameEvent$json,
  '.runanywhere.v1.VADEvent': $0.VADEvent$json,
  '.runanywhere.v1.InterruptedEvent': $0.InterruptedEvent$json,
  '.runanywhere.v1.StateChangeEvent': $0.StateChangeEvent$json,
  '.runanywhere.v1.ErrorEvent': $0.ErrorEvent$json,
  '.runanywhere.v1.MetricsEvent': $0.MetricsEvent$json,
  '.runanywhere.v1.VoiceAgentComponentStates': $0.VoiceAgentComponentStates$json,
  '.runanywhere.v1.VoiceSessionError': $0.VoiceSessionError$json,
  '.runanywhere.v1.SessionStartedEvent': $0.SessionStartedEvent$json,
  '.runanywhere.v1.SessionStoppedEvent': $0.SessionStoppedEvent$json,
  '.runanywhere.v1.AgentResponseStartedEvent': $0.AgentResponseStartedEvent$json,
  '.runanywhere.v1.AgentResponseCompletedEvent': $0.AgentResponseCompletedEvent$json,
};

/// Descriptor for `VoiceAgent`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List voiceAgentServiceDescriptor = $convert.base64Decode('CgpWb2ljZUFnZW50EkkKBlN0cmVhbRIhLnJ1bmFueXdoZXJlLnYxLlZvaWNlQWdlbnRSZXF1ZXN0GhoucnVuYW55d2hlcmUudjEuVm9pY2VFdmVudDAB');
