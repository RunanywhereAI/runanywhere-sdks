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

import 'stt_options.pbjson.dart' as $2;
import 'tts_options.pbjson.dart' as $1;
import 'voice_events.pbjson.dart' as $0;

@$core.Deprecated('Use voiceAgentRequestDescriptor instead')
const VoiceAgentRequest$json = {
  '1': 'VoiceAgentRequest',
  '2': [
    {'1': 'event_filter', '3': 1, '4': 1, '5': 9, '10': 'eventFilter'},
    {'1': 'session_id', '3': 2, '4': 1, '5': 9, '10': 'sessionId'},
    {'1': 'categories', '3': 3, '4': 3, '5': 14, '6': '.runanywhere.v1.EventCategory', '10': 'categories'},
    {'1': 'min_severity', '3': 4, '4': 1, '5': 14, '6': '.runanywhere.v1.ErrorSeverity', '10': 'minSeverity'},
    {'1': 'replay_from_seq', '3': 5, '4': 1, '5': 4, '10': 'replayFromSeq'},
    {'1': 'include_audio', '3': 6, '4': 1, '5': 8, '10': 'includeAudio'},
  ],
};

/// Descriptor for `VoiceAgentRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceAgentRequestDescriptor = $convert.base64Decode(
    'ChFWb2ljZUFnZW50UmVxdWVzdBIhCgxldmVudF9maWx0ZXIYASABKAlSC2V2ZW50RmlsdGVyEh'
    '0KCnNlc3Npb25faWQYAiABKAlSCXNlc3Npb25JZBI9CgpjYXRlZ29yaWVzGAMgAygOMh0ucnVu'
    'YW55d2hlcmUudjEuRXZlbnRDYXRlZ29yeVIKY2F0ZWdvcmllcxJACgxtaW5fc2V2ZXJpdHkYBC'
    'ABKA4yHS5ydW5hbnl3aGVyZS52MS5FcnJvclNldmVyaXR5UgttaW5TZXZlcml0eRImCg9yZXBs'
    'YXlfZnJvbV9zZXEYBSABKARSDXJlcGxheUZyb21TZXESIwoNaW5jbHVkZV9hdWRpbxgGIAEoCF'
    'IMaW5jbHVkZUF1ZGlv');

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
    {'1': 'session_id', '3': 10, '4': 1, '5': 9, '10': 'sessionId'},
    {'1': 'turn_id', '3': 11, '4': 1, '5': 9, '10': 'turnId'},
    {'1': 'stt_time_ms', '3': 12, '4': 1, '5': 3, '10': 'sttTimeMs'},
    {'1': 'llm_time_ms', '3': 13, '4': 1, '5': 3, '10': 'llmTimeMs'},
    {'1': 'tts_time_ms', '3': 14, '4': 1, '5': 3, '10': 'ttsTimeMs'},
    {'1': 'total_time_ms', '3': 15, '4': 1, '5': 3, '10': 'totalTimeMs'},
    {'1': 'error_message', '3': 16, '4': 1, '5': 9, '9': 5, '10': 'errorMessage', '17': true},
    {'1': 'error_code', '3': 17, '4': 1, '5': 5, '10': 'errorCode'},
  ],
  '8': [
    {'1': '_transcription'},
    {'1': '_assistant_response'},
    {'1': '_thinking_content'},
    {'1': '_synthesized_audio'},
    {'1': '_final_state'},
    {'1': '_error_message'},
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
    'b2RpbmcSHQoKc2Vzc2lvbl9pZBgKIAEoCVIJc2Vzc2lvbklkEhcKB3R1cm5faWQYCyABKAlSBn'
    'R1cm5JZBIeCgtzdHRfdGltZV9tcxgMIAEoA1IJc3R0VGltZU1zEh4KC2xsbV90aW1lX21zGA0g'
    'ASgDUglsbG1UaW1lTXMSHgoLdHRzX3RpbWVfbXMYDiABKANSCXR0c1RpbWVNcxIiCg10b3RhbF'
    '90aW1lX21zGA8gASgDUgt0b3RhbFRpbWVNcxIoCg1lcnJvcl9tZXNzYWdlGBAgASgJSAVSDGVy'
    'cm9yTWVzc2FnZYgBARIdCgplcnJvcl9jb2RlGBEgASgFUgllcnJvckNvZGVCEAoOX3RyYW5zY3'
    'JpcHRpb25CFQoTX2Fzc2lzdGFudF9yZXNwb25zZUITChFfdGhpbmtpbmdfY29udGVudEIUChJf'
    'c3ludGhlc2l6ZWRfYXVkaW9CDgoMX2ZpbmFsX3N0YXRlQhAKDl9lcnJvcl9tZXNzYWdl');

@$core.Deprecated('Use voiceAgentTurnRequestDescriptor instead')
const VoiceAgentTurnRequest$json = {
  '1': 'VoiceAgentTurnRequest',
  '2': [
    {'1': 'request_id', '3': 1, '4': 1, '5': 9, '10': 'requestId'},
    {'1': 'session_id', '3': 2, '4': 1, '5': 9, '10': 'sessionId'},
    {'1': 'audio_data', '3': 3, '4': 1, '5': 12, '10': 'audioData'},
    {'1': 'sample_rate_hz', '3': 4, '4': 1, '5': 5, '10': 'sampleRateHz'},
    {'1': 'channels', '3': 5, '4': 1, '5': 5, '10': 'channels'},
    {'1': 'encoding', '3': 6, '4': 1, '5': 14, '6': '.runanywhere.v1.AudioEncoding', '10': 'encoding'},
    {'1': 'session_config', '3': 7, '4': 1, '5': 11, '6': '.runanywhere.v1.VoiceSessionConfig', '9': 0, '10': 'sessionConfig', '17': true},
    {'1': 'metadata', '3': 8, '4': 3, '5': 11, '6': '.runanywhere.v1.VoiceAgentTurnRequest.MetadataEntry', '10': 'metadata'},
  ],
  '3': [VoiceAgentTurnRequest_MetadataEntry$json],
  '8': [
    {'1': '_session_config'},
  ],
};

@$core.Deprecated('Use voiceAgentTurnRequestDescriptor instead')
const VoiceAgentTurnRequest_MetadataEntry$json = {
  '1': 'MetadataEntry',
  '2': [
    {'1': 'key', '3': 1, '4': 1, '5': 9, '10': 'key'},
    {'1': 'value', '3': 2, '4': 1, '5': 9, '10': 'value'},
  ],
  '7': {'7': true},
};

/// Descriptor for `VoiceAgentTurnRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceAgentTurnRequestDescriptor = $convert.base64Decode(
    'ChVWb2ljZUFnZW50VHVyblJlcXVlc3QSHQoKcmVxdWVzdF9pZBgBIAEoCVIJcmVxdWVzdElkEh'
    '0KCnNlc3Npb25faWQYAiABKAlSCXNlc3Npb25JZBIdCgphdWRpb19kYXRhGAMgASgMUglhdWRp'
    'b0RhdGESJAoOc2FtcGxlX3JhdGVfaHoYBCABKAVSDHNhbXBsZVJhdGVIehIaCghjaGFubmVscx'
    'gFIAEoBVIIY2hhbm5lbHMSOQoIZW5jb2RpbmcYBiABKA4yHS5ydW5hbnl3aGVyZS52MS5BdWRp'
    'b0VuY29kaW5nUghlbmNvZGluZxJOCg5zZXNzaW9uX2NvbmZpZxgHIAEoCzIiLnJ1bmFueXdoZX'
    'JlLnYxLlZvaWNlU2Vzc2lvbkNvbmZpZ0gAUg1zZXNzaW9uQ29uZmlniAEBEk8KCG1ldGFkYXRh'
    'GAggAygLMjMucnVuYW55d2hlcmUudjEuVm9pY2VBZ2VudFR1cm5SZXF1ZXN0Lk1ldGFkYXRhRW'
    '50cnlSCG1ldGFkYXRhGjsKDU1ldGFkYXRhRW50cnkSEAoDa2V5GAEgASgJUgNrZXkSFAoFdmFs'
    'dWUYAiABKAlSBXZhbHVlOgI4AUIRCg9fc2Vzc2lvbl9jb25maWc=');

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
    {'1': 'max_recording_duration_ms', '3': 7, '4': 1, '5': 5, '10': 'maxRecordingDurationMs'},
    {'1': 'language_code', '3': 8, '4': 1, '5': 9, '9': 0, '10': 'languageCode', '17': true},
    {'1': 'voice_id', '3': 9, '4': 1, '5': 9, '9': 1, '10': 'voiceId', '17': true},
  ],
  '8': [
    {'1': '_language_code'},
    {'1': '_voice_id'},
  ],
};

/// Descriptor for `VoiceSessionConfig`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceSessionConfigDescriptor = $convert.base64Decode(
    'ChJWb2ljZVNlc3Npb25Db25maWcSLgoTc2lsZW5jZV9kdXJhdGlvbl9tcxgBIAEoBVIRc2lsZW'
    '5jZUR1cmF0aW9uTXMSKQoQc3BlZWNoX3RocmVzaG9sZBgCIAEoAlIPc3BlZWNoVGhyZXNob2xk'
    'EiIKDWF1dG9fcGxheV90dHMYAyABKAhSC2F1dG9QbGF5VHRzEicKD2NvbnRpbnVvdXNfbW9kZR'
    'gEIAEoCFIOY29udGludW91c01vZGUSMgoVdGhpbmtpbmdfbW9kZV9lbmFibGVkGAUgASgIUhN0'
    'aGlua2luZ01vZGVFbmFibGVkEh0KCm1heF90b2tlbnMYBiABKAVSCW1heFRva2VucxI5ChltYX'
    'hfcmVjb3JkaW5nX2R1cmF0aW9uX21zGAcgASgFUhZtYXhSZWNvcmRpbmdEdXJhdGlvbk1zEigK'
    'DWxhbmd1YWdlX2NvZGUYCCABKAlIAFIMbGFuZ3VhZ2VDb2RliAEBEh4KCHZvaWNlX2lkGAkgAS'
    'gJSAFSB3ZvaWNlSWSIAQFCEAoOX2xhbmd1YWdlX2NvZGVCCwoJX3ZvaWNlX2lk');

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
    {'1': 'session_id', '3': 22, '4': 1, '5': 9, '9': 16, '10': 'sessionId', '17': true},
    {'1': 'default_language_code', '3': 23, '4': 1, '5': 9, '9': 17, '10': 'defaultLanguageCode', '17': true},
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
    {'1': '_session_id'},
    {'1': '_default_language_code'},
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
    'F1ZGlvUGlwZWxpbmVDb25maWeIAQESIgoKc2Vzc2lvbl9pZBgWIAEoCUgQUglzZXNzaW9uSWSI'
    'AQESNwoVZGVmYXVsdF9sYW5ndWFnZV9jb2RlGBcgASgJSBFSE2RlZmF1bHRMYW5ndWFnZUNvZG'
    'WIAQFCEQoPX3N0dF9tb2RlbF9wYXRoQg8KDV9zdHRfbW9kZWxfaWRCEQoPX3N0dF9tb2RlbF9u'
    'YW1lQhEKD19sbG1fbW9kZWxfcGF0aEIPCg1fbGxtX21vZGVsX2lkQhEKD19sbG1fbW9kZWxfbm'
    'FtZUIRCg9fdHRzX3ZvaWNlX3BhdGhCDwoNX3R0c192b2ljZV9pZEIRCg9fdHRzX3ZvaWNlX25h'
    'bWVCFgoUX3dha2V3b3JkX21vZGVsX3BhdGhCFAoSX3dha2V3b3JkX21vZGVsX2lkQhIKEF93YW'
    'tld29yZF9waHJhc2VCIAoeX3dha2V3b3JkX2VtYmVkZGluZ19tb2RlbF9wYXRoQhoKGF93YWtl'
    'd29yZF92YWRfbW9kZWxfcGF0aEIRCg9fc2Vzc2lvbl9jb25maWdCGAoWX2F1ZGlvX3BpcGVsaW'
    '5lX2NvbmZpZ0INCgtfc2Vzc2lvbl9pZEIYChZfZGVmYXVsdF9sYW5ndWFnZV9jb2Rl');

@$core.Deprecated('Use voiceAgentTranscribeProtoRequestDescriptor instead')
const VoiceAgentTranscribeProtoRequest$json = {
  '1': 'VoiceAgentTranscribeProtoRequest',
  '2': [
    {'1': 'audio_data', '3': 1, '4': 1, '5': 12, '10': 'audioData'},
    {'1': 'session_id', '3': 2, '4': 1, '5': 9, '10': 'sessionId'},
    {'1': 'sample_rate', '3': 3, '4': 1, '5': 5, '10': 'sampleRate'},
    {'1': 'language_hint', '3': 4, '4': 1, '5': 9, '10': 'languageHint'},
    {'1': 'channels', '3': 5, '4': 1, '5': 5, '10': 'channels'},
    {'1': 'encoding', '3': 6, '4': 1, '5': 14, '6': '.runanywhere.v1.AudioEncoding', '10': 'encoding'},
  ],
};

/// Descriptor for `VoiceAgentTranscribeProtoRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceAgentTranscribeProtoRequestDescriptor = $convert.base64Decode(
    'CiBWb2ljZUFnZW50VHJhbnNjcmliZVByb3RvUmVxdWVzdBIdCgphdWRpb19kYXRhGAEgASgMUg'
    'lhdWRpb0RhdGESHQoKc2Vzc2lvbl9pZBgCIAEoCVIJc2Vzc2lvbklkEh8KC3NhbXBsZV9yYXRl'
    'GAMgASgFUgpzYW1wbGVSYXRlEiMKDWxhbmd1YWdlX2hpbnQYBCABKAlSDGxhbmd1YWdlSGludB'
    'IaCghjaGFubmVscxgFIAEoBVIIY2hhbm5lbHMSOQoIZW5jb2RpbmcYBiABKA4yHS5ydW5hbnl3'
    'aGVyZS52MS5BdWRpb0VuY29kaW5nUghlbmNvZGluZw==');

@$core.Deprecated('Use voiceAgentSynthesizeSpeechProtoRequestDescriptor instead')
const VoiceAgentSynthesizeSpeechProtoRequest$json = {
  '1': 'VoiceAgentSynthesizeSpeechProtoRequest',
  '2': [
    {'1': 'text', '3': 1, '4': 1, '5': 9, '10': 'text'},
    {'1': 'session_id', '3': 2, '4': 1, '5': 9, '10': 'sessionId'},
    {'1': 'options', '3': 3, '4': 1, '5': 11, '6': '.runanywhere.v1.TTSOptions', '9': 0, '10': 'options', '17': true},
  ],
  '8': [
    {'1': '_options'},
  ],
};

/// Descriptor for `VoiceAgentSynthesizeSpeechProtoRequest`. Decode as a `google.protobuf.DescriptorProto`.
final $typed_data.Uint8List voiceAgentSynthesizeSpeechProtoRequestDescriptor = $convert.base64Decode(
    'CiZWb2ljZUFnZW50U3ludGhlc2l6ZVNwZWVjaFByb3RvUmVxdWVzdBISCgR0ZXh0GAEgASgJUg'
    'R0ZXh0Eh0KCnNlc3Npb25faWQYAiABKAlSCXNlc3Npb25JZBI5CgdvcHRpb25zGAMgASgLMhou'
    'cnVuYW55d2hlcmUudjEuVFRTT3B0aW9uc0gAUgdvcHRpb25ziAEBQgoKCF9vcHRpb25z');

const $core.Map<$core.String, $core.dynamic> VoiceAgentServiceBase$json = {
  '1': 'VoiceAgent',
  '2': [
    {'1': 'Stream', '2': '.runanywhere.v1.VoiceAgentRequest', '3': '.runanywhere.v1.VoiceEvent', '6': true},
    {'1': 'ProcessTurn', '2': '.runanywhere.v1.VoiceAgentTurnRequest', '3': '.runanywhere.v1.VoiceAgentResult'},
    {'1': 'Transcribe', '2': '.runanywhere.v1.VoiceAgentTranscribeProtoRequest', '3': '.runanywhere.v1.STTOutput'},
    {'1': 'SynthesizeSpeech', '2': '.runanywhere.v1.VoiceAgentSynthesizeSpeechProtoRequest', '3': '.runanywhere.v1.TTSOutput'},
    {'1': 'Configure', '2': '.runanywhere.v1.VoiceAgentComposeConfig', '3': '.runanywhere.v1.VoiceAgentResult'},
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
  '.runanywhere.v1.AudioLevelEvent': $0.AudioLevelEvent$json,
  '.runanywhere.v1.ComponentProgressEvent': $0.ComponentProgressEvent$json,
  '.runanywhere.v1.VoiceEvent.MetadataEntry': $0.VoiceEvent_MetadataEntry$json,
  '.runanywhere.v1.VoiceAgentTurnRequest': VoiceAgentTurnRequest$json,
  '.runanywhere.v1.VoiceSessionConfig': VoiceSessionConfig$json,
  '.runanywhere.v1.VoiceAgentTurnRequest.MetadataEntry': VoiceAgentTurnRequest_MetadataEntry$json,
  '.runanywhere.v1.VoiceAgentResult': VoiceAgentResult$json,
  '.runanywhere.v1.VoiceAgentTranscribeProtoRequest': VoiceAgentTranscribeProtoRequest$json,
  '.runanywhere.v1.STTOutput': $2.STTOutput$json,
  '.runanywhere.v1.WordTimestamp': $2.WordTimestamp$json,
  '.runanywhere.v1.TranscriptionAlternative': $2.TranscriptionAlternative$json,
  '.runanywhere.v1.TranscriptionMetadata': $2.TranscriptionMetadata$json,
  '.runanywhere.v1.VoiceAgentSynthesizeSpeechProtoRequest': VoiceAgentSynthesizeSpeechProtoRequest$json,
  '.runanywhere.v1.TTSOptions': $1.TTSOptions$json,
  '.runanywhere.v1.TTSOutput': $1.TTSOutput$json,
  '.runanywhere.v1.TTSPhonemeTimestamp': $1.TTSPhonemeTimestamp$json,
  '.runanywhere.v1.TTSSynthesisMetadata': $1.TTSSynthesisMetadata$json,
  '.runanywhere.v1.VoiceAgentComposeConfig': VoiceAgentComposeConfig$json,
  '.runanywhere.v1.AudioPipelineConfig': AudioPipelineConfig$json,
};

/// Descriptor for `VoiceAgent`. Decode as a `google.protobuf.ServiceDescriptorProto`.
final $typed_data.Uint8List voiceAgentServiceDescriptor = $convert.base64Decode(
    'CgpWb2ljZUFnZW50EkkKBlN0cmVhbRIhLnJ1bmFueXdoZXJlLnYxLlZvaWNlQWdlbnRSZXF1ZX'
    'N0GhoucnVuYW55d2hlcmUudjEuVm9pY2VFdmVudDABElYKC1Byb2Nlc3NUdXJuEiUucnVuYW55'
    'd2hlcmUudjEuVm9pY2VBZ2VudFR1cm5SZXF1ZXN0GiAucnVuYW55d2hlcmUudjEuVm9pY2VBZ2'
    'VudFJlc3VsdBJZCgpUcmFuc2NyaWJlEjAucnVuYW55d2hlcmUudjEuVm9pY2VBZ2VudFRyYW5z'
    'Y3JpYmVQcm90b1JlcXVlc3QaGS5ydW5hbnl3aGVyZS52MS5TVFRPdXRwdXQSZQoQU3ludGhlc2'
    'l6ZVNwZWVjaBI2LnJ1bmFueXdoZXJlLnYxLlZvaWNlQWdlbnRTeW50aGVzaXplU3BlZWNoUHJv'
    'dG9SZXF1ZXN0GhkucnVuYW55d2hlcmUudjEuVFRTT3V0cHV0ElYKCUNvbmZpZ3VyZRInLnJ1bm'
    'FueXdoZXJlLnYxLlZvaWNlQWdlbnRDb21wb3NlQ29uZmlnGiAucnVuYW55d2hlcmUudjEuVm9p'
    'Y2VBZ2VudFJlc3VsdA==');

