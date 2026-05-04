//
//  Generated code. Do not modify.
//  source: voice_agent_service.proto
//
// @dart = 2.12

// ignore_for_file: annotate_overrides, camel_case_types, comment_references
// ignore_for_file: constant_identifier_names, library_prefixes
// ignore_for_file: non_constant_identifier_names, prefer_final_fields
// ignore_for_file: unnecessary_import, unnecessary_this, unused_import

import 'dart:convert' as $convert;
import 'dart:core' as $core;
import 'dart:typed_data' as $typed_data;

import 'voice_events.pbjson.dart' as $0;

@$core.Deprecated('Use voiceAgentRequestDescriptor instead')
const VoiceAgentRequest$json = {
  '1': 'VoiceAgentRequest',
  '2': [
    {'1': 'event_filter', '3': 1, '4': 1, '5': 9, '10': 'eventFilter'},
  ],
};

/// Descriptor for `VoiceAgentRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceAgentRequestDescriptor = $convert.base64Decode(
    'ChFWb2ljZUFnZW50UmVxdWVzdBIhCgxldmVudF9maWx0ZXIYASABKAlSC2V2ZW50RmlsdGVy');

@$core.Deprecated('Use voiceAgentResultDescriptor instead')
const VoiceAgentResult$json = {
  '1': 'VoiceAgentResult',
  '2': [
    {'1': 'speech_detected', '3': 1, '4': 1, '5': 8, '10': 'speechDetected'},
    {'1': 'transcription', '3': 2, '4': 1, '5': 9, '9': 0, '10': 'transcription', '17': true},
    {'1': 'assistant_response', '3': 3, '4': 1, '5': 9, '9': 1, '10': 'assistantResponse', '17': true},
    {'1': 'thinking_content', '3': 4, '4': 1, '5': 9, '9': 2, '10': 'thinkingContent', '17': true},
    {'1': 'synthesized_audio', '3': 5, '4': 1, '5': 12, '9': 3, '10': 'synthesizedAudio', '17': true},
    {'1': 'final_state', '3': 6, '4': 1, '5': 11, '6': '.runanywhere.v1.VoiceAgentComponentStates', '9': 4, '10': 'finalState', '17': true},
    {'1': 'synthesized_audio_sample_rate_hz', '3': 7, '4': 1, '5': 5, '10': 'synthesizedAudioSampleRateHz'},
    {'1': 'synthesized_audio_channels', '3': 8, '4': 1, '5': 5, '10': 'synthesizedAudioChannels'},
    {'1': 'synthesized_audio_encoding', '3': 9, '4': 1, '5': 14, '6': '.runanywhere.v1.AudioEncoding', '10': 'synthesizedAudioEncoding'},
  ],
  '8': [
    {'1': '_transcription'},
    {'1': '_assistant_response'},
    {'1': '_thinking_content'},
    {'1': '_synthesized_audio'},
    {'1': '_final_state'},
  ],
};

/// Descriptor for `VoiceAgentResult`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceAgentResultDescriptor = $convert.base64Decode(
    'ChBWb2ljZUFnZW50UmVzdWx0EicKD3NwZWVjaF9kZXRlY3RlZBgBIAEoCFIOc3BlZWNoRGV0ZW'
    'N0ZWQSKQoNdHJhbnNjcmlwdGlvbhgCIAEoCUgAUg10cmFuc2NyaXB0aW9uiAEBEjIKEmFzc2lz'
    'dGFudF9yZXNwb25zZRgDIAEoCUgBUhFhc3Npc3RhbnRSZXNwb25zZYgBARIuChB0aGlua2luZ1'
    '9jb250ZW50GAQgASgJSAJSD3RoaW5raW5nQ29udGVudIgBARIwChFzeW50aGVzaXplZF9hdWRp'
    'bxgFIAEoDEgDUhBzeW50aGVzaXplZEF1ZGlviAEBEk8KC2ZpbmFsX3N0YXRlGAYgASgLMikucn'
    'VuYW55d2hlcmUudjEuVm9pY2VBZ2VudENvbXBvbmVudFN0YXRlc0gEUgpmaW5hbFN0YXRliAEB'
    'EkYKIHN5bnRoZXNpemVkX2F1ZGlvX3NhbXBsZV9yYXRlX2h6GAcgASgFUhxzeW50aGVzaXplZE'
    'F1ZGlvU2FtcGxlUmF0ZUh6EjwKGnN5bnRoZXNpemVkX2F1ZGlvX2NoYW5uZWxzGAggASgFUhhz'
    'eW50aGVzaXplZEF1ZGlvQ2hhbm5lbHMSWwoac3ludGhlc2l6ZWRfYXVkaW9fZW5jb2RpbmcYCS'
    'ABKA4yHS5ydW5hbnl3aGVyZS52MS5BdWRpb0VuY29kaW5nUhhzeW50aGVzaXplZEF1ZGlvRW5j'
    'b2RpbmdCEAoOX3RyYW5zY3JpcHRpb25CFQoTX2Fzc2lzdGFudF9yZXNwb25zZUITChFfdGhpbm'
    'tpbmdfY29udGVudEIUChJfc3ludGhlc2l6ZWRfYXVkaW9CDgoMX2ZpbmFsX3N0YXRl');

@$core.Deprecated('Use voiceSessionConfigDescriptor instead')
const VoiceSessionConfig$json = {
  '1': 'VoiceSessionConfig',
  '2': [
    {'1': 'silence_duration_ms', '3': 1, '4': 1, '5': 5, '10': 'silenceDurationMs'},
    {'1': 'speech_threshold', '3': 2, '4': 1, '5': 2, '10': 'speechThreshold'},
    {'1': 'auto_play_tts', '3': 3, '4': 1, '5': 8, '10': 'autoPlayTts'},
    {'1': 'continuous_mode', '3': 4, '4': 1, '5': 8, '10': 'continuousMode'},
    {'1': 'thinking_mode_enabled', '3': 5, '4': 1, '5': 8, '10': 'thinkingModeEnabled'},
    {'1': 'max_tokens', '3': 6, '4': 1, '5': 5, '10': 'maxTokens'},
  ],
};

/// Descriptor for `VoiceSessionConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceSessionConfigDescriptor = $convert.base64Decode(
    'ChJWb2ljZVNlc3Npb25Db25maWcSLgoTc2lsZW5jZV9kdXJhdGlvbl9tcxgBIAEoBVIRc2lsZW'
    '5jZUR1cmF0aW9uTXMSKQoQc3BlZWNoX3RocmVzaG9sZBgCIAEoAlIPc3BlZWNoVGhyZXNob2xk'
    'EiIKDWF1dG9fcGxheV90dHMYAyABKAhSC2F1dG9QbGF5VHRzEicKD2NvbnRpbnVvdXNfbW9kZR'
    'gEIAEoCFIOY29udGludW91c01vZGUSMgoVdGhpbmtpbmdfbW9kZV9lbmFibGVkGAUgASgIUhN0'
    'aGlua2luZ01vZGVFbmFibGVkEh0KCm1heF90b2tlbnMYBiABKAVSCW1heFRva2Vucw==');

@$core.Deprecated('Use audioPipelineConfigDescriptor instead')
const AudioPipelineConfig$json = {
  '1': 'AudioPipelineConfig',
  '2': [
    {'1': 'cooldown_duration_ms', '3': 1, '4': 1, '5': 5, '10': 'cooldownDurationMs'},
    {'1': 'strict_transitions', '3': 2, '4': 1, '5': 8, '10': 'strictTransitions'},
    {'1': 'max_tts_duration_ms', '3': 3, '4': 1, '5': 5, '10': 'maxTtsDurationMs'},
  ],
};

/// Descriptor for `AudioPipelineConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List audioPipelineConfigDescriptor = $convert.base64Decode(
    'ChNBdWRpb1BpcGVsaW5lQ29uZmlnEjAKFGNvb2xkb3duX2R1cmF0aW9uX21zGAEgASgFUhJjb2'
    '9sZG93bkR1cmF0aW9uTXMSLQoSc3RyaWN0X3RyYW5zaXRpb25zGAIgASgIUhFzdHJpY3RUcmFu'
    'c2l0aW9ucxItChNtYXhfdHRzX2R1cmF0aW9uX21zGAMgASgFUhBtYXhUdHNEdXJhdGlvbk1z');

@$core.Deprecated('Use voiceAgentComposeConfigDescriptor instead')
const VoiceAgentComposeConfig$json = {
  '1': 'VoiceAgentComposeConfig',
  '2': [
    {'1': 'stt_model_path', '3': 1, '4': 1, '5': 9, '9': 0, '10': 'sttModelPath', '17': true},
    {'1': 'stt_model_id', '3': 2, '4': 1, '5': 9, '9': 1, '10': 'sttModelId', '17': true},
    {'1': 'stt_model_name', '3': 3, '4': 1, '5': 9, '9': 2, '10': 'sttModelName', '17': true},
    {'1': 'llm_model_path', '3': 4, '4': 1, '5': 9, '9': 3, '10': 'llmModelPath', '17': true},
    {'1': 'llm_model_id', '3': 5, '4': 1, '5': 9, '9': 4, '10': 'llmModelId', '17': true},
    {'1': 'llm_model_name', '3': 6, '4': 1, '5': 9, '9': 5, '10': 'llmModelName', '17': true},
    {'1': 'tts_voice_path', '3': 7, '4': 1, '5': 9, '9': 6, '10': 'ttsVoicePath', '17': true},
    {'1': 'tts_voice_id', '3': 8, '4': 1, '5': 9, '9': 7, '10': 'ttsVoiceId', '17': true},
    {'1': 'tts_voice_name', '3': 9, '4': 1, '5': 9, '9': 8, '10': 'ttsVoiceName', '17': true},
    {'1': 'vad_sample_rate', '3': 10, '4': 1, '5': 5, '10': 'vadSampleRate'},
    {'1': 'vad_frame_length', '3': 11, '4': 1, '5': 2, '10': 'vadFrameLength'},
    {'1': 'vad_energy_threshold', '3': 12, '4': 1, '5': 2, '10': 'vadEnergyThreshold'},
    {'1': 'wakeword_enabled', '3': 13, '4': 1, '5': 8, '10': 'wakewordEnabled'},
    {'1': 'wakeword_model_path', '3': 14, '4': 1, '5': 9, '9': 9, '10': 'wakewordModelPath', '17': true},
    {'1': 'wakeword_model_id', '3': 15, '4': 1, '5': 9, '9': 10, '10': 'wakewordModelId', '17': true},
    {'1': 'wakeword_phrase', '3': 16, '4': 1, '5': 9, '9': 11, '10': 'wakewordPhrase', '17': true},
    {'1': 'wakeword_threshold', '3': 17, '4': 1, '5': 2, '10': 'wakewordThreshold'},
    {'1': 'wakeword_embedding_model_path', '3': 18, '4': 1, '5': 9, '9': 12, '10': 'wakewordEmbeddingModelPath', '17': true},
    {'1': 'wakeword_vad_model_path', '3': 19, '4': 1, '5': 9, '9': 13, '10': 'wakewordVadModelPath', '17': true},
    {'1': 'session_config', '3': 20, '4': 1, '5': 11, '6': '.runanywhere.v1.VoiceSessionConfig', '9': 14, '10': 'sessionConfig', '17': true},
    {'1': 'audio_pipeline_config', '3': 21, '4': 1, '5': 11, '6': '.runanywhere.v1.AudioPipelineConfig', '9': 15, '10': 'audioPipelineConfig', '17': true},
  ],
  '8': [
    {'1': '_stt_model_path'},
    {'1': '_stt_model_id'},
    {'1': '_stt_model_name'},
    {'1': '_llm_model_path'},
    {'1': '_llm_model_id'},
    {'1': '_llm_model_name'},
    {'1': '_tts_voice_path'},
    {'1': '_tts_voice_id'},
    {'1': '_tts_voice_name'},
    {'1': '_wakeword_model_path'},
    {'1': '_wakeword_model_id'},
    {'1': '_wakeword_phrase'},
    {'1': '_wakeword_embedding_model_path'},
    {'1': '_wakeword_vad_model_path'},
    {'1': '_session_config'},
    {'1': '_audio_pipeline_config'},
  ],
};

/// Descriptor for `VoiceAgentComposeConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceAgentComposeConfigDescriptor = $convert.base64Decode(
    'ChdWb2ljZUFnZW50Q29tcG9zZUNvbmZpZxIpCg5zdHRfbW9kZWxfcGF0aBgBIAEoCUgAUgxzdH'
    'RNb2RlbFBhdGiIAQESJQoMc3R0X21vZGVsX2lkGAIgASgJSAFSCnN0dE1vZGVsSWSIAQESKQoO'
    'c3R0X21vZGVsX25hbWUYAyABKAlIAlIMc3R0TW9kZWxOYW1liAEBEikKDmxsbV9tb2RlbF9wYX'
    'RoGAQgASgJSANSDGxsbU1vZGVsUGF0aIgBARIlCgxsbG1fbW9kZWxfaWQYBSABKAlIBFIKbGxt'
    'TW9kZWxJZIgBARIpCg5sbG1fbW9kZWxfbmFtZRgGIAEoCUgFUgxsbG1Nb2RlbE5hbWWIAQESKQ'
    'oOdHRzX3ZvaWNlX3BhdGgYByABKAlIBlIMdHRzVm9pY2VQYXRoiAEBEiUKDHR0c192b2ljZV9p'
    'ZBgIIAEoCUgHUgp0dHNWb2ljZUlkiAEBEikKDnR0c192b2ljZV9uYW1lGAkgASgJSAhSDHR0c1'
    'ZvaWNlTmFtZYgBARImCg92YWRfc2FtcGxlX3JhdGUYCiABKAVSDXZhZFNhbXBsZVJhdGUSKAoQ'
    'dmFkX2ZyYW1lX2xlbmd0aBgLIAEoAlIOdmFkRnJhbWVMZW5ndGgSMAoUdmFkX2VuZXJneV90aH'
    'Jlc2hvbGQYDCABKAJSEnZhZEVuZXJneVRocmVzaG9sZBIpChB3YWtld29yZF9lbmFibGVkGA0g'
    'ASgIUg93YWtld29yZEVuYWJsZWQSMwoTd2FrZXdvcmRfbW9kZWxfcGF0aBgOIAEoCUgJUhF3YW'
    'tld29yZE1vZGVsUGF0aIgBARIvChF3YWtld29yZF9tb2RlbF9pZBgPIAEoCUgKUg93YWtld29y'
    'ZE1vZGVsSWSIAQESLAoPd2FrZXdvcmRfcGhyYXNlGBAgASgJSAtSDndha2V3b3JkUGhyYXNliA'
    'EBEi0KEndha2V3b3JkX3RocmVzaG9sZBgRIAEoAlIRd2FrZXdvcmRUaHJlc2hvbGQSRgodd2Fr'
    'ZXdvcmRfZW1iZWRkaW5nX21vZGVsX3BhdGgYEiABKAlIDFIad2FrZXdvcmRFbWJlZGRpbmdNb2'
    'RlbFBhdGiIAQESOgoXd2FrZXdvcmRfdmFkX21vZGVsX3BhdGgYEyABKAlIDVIUd2FrZXdvcmRW'
    'YWRNb2RlbFBhdGiIAQESTgoOc2Vzc2lvbl9jb25maWcYFCABKAsyIi5ydW5hbnl3aGVyZS52MS'
    '5Wb2ljZVNlc3Npb25Db25maWdIDlINc2Vzc2lvbkNvbmZpZ4gBARJcChVhdWRpb19waXBlbGlu'
    'ZV9jb25maWcYFSABKAsyIy5ydW5hbnl3aGVyZS52MS5BdWRpb1BpcGVsaW5lQ29uZmlnSA9SE2'
    'F1ZGlvUGlwZWxpbmVDb25maWeIAQFCEQoPX3N0dF9tb2RlbF9wYXRoQg8KDV9zdHRfbW9kZWxf'
    'aWRCEQoPX3N0dF9tb2RlbF9uYW1lQhEKD19sbG1fbW9kZWxfcGF0aEIPCg1fbGxtX21vZGVsX2'
    'lkQhEKD19sbG1fbW9kZWxfbmFtZUIRCg9fdHRzX3ZvaWNlX3BhdGhCDwoNX3R0c192b2ljZV9p'
    'ZEIRCg9fdHRzX3ZvaWNlX25hbWVCFgoUX3dha2V3b3JkX21vZGVsX3BhdGhCFAoSX3dha2V3b3'
    'JkX21vZGVsX2lkQhIKEF93YWtld29yZF9waHJhc2VCIAoeX3dha2V3b3JkX2VtYmVkZGluZ19t'
    'b2RlbF9wYXRoQhoKGF93YWtld29yZF92YWRfbW9kZWxfcGF0aEIRCg9fc2Vzc2lvbl9jb25maW'
    'dCGAoWX2F1ZGlvX3BpcGVsaW5lX2NvbmZpZw==');

const $core.Map<$core.String, $core.dynamic> VoiceAgentServiceBase$json = {
  '1': 'VoiceAgent',
  '2': [
    {'1': 'Stream', '2': '.runanywhere.v1.VoiceAgentRequest', '3': '.runanywhere.v1.VoiceEvent', '6': true},
  ],
};

@$core.Deprecated('Use voiceAgentServiceDescriptor instead')
const $core.Map<$core.String, $core.Map<$core.String, $core.dynamic>> VoiceAgentServiceBase$messageJson = {
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
  '.runanywhere.v1.SpeechTurnDetectionEvent': $0.SpeechTurnDetectionEvent$json,
  '.runanywhere.v1.TurnLifecycleEvent': $0.TurnLifecycleEvent$json,
  '.runanywhere.v1.WakeWordDetectedEvent': $0.WakeWordDetectedEvent$json,
};

/// Descriptor for `VoiceAgent`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List voiceAgentServiceDescriptor = $convert.base64Decode(
    'CgpWb2ljZUFnZW50EkkKBlN0cmVhbRIhLnJ1bmFueXdoZXJlLnYxLlZvaWNlQWdlbnRSZXF1ZX'
    'N0GhoucnVuYW55d2hlcmUudjEuVm9pY2VFdmVudDAB');

