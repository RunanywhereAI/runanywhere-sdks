// SPDX-License-Identifier: Apache-2.0

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/generated/model_types.pb.dart';
import 'package:runanywhere/public/capabilities/runanywhere_model_lifecycle.dart';

void main() {
  group('public capability lifecycle ownership', () {
    for (final file in <String>[
      'runanywhere_tts.dart',
      'runanywhere_stt.dart',
      'runanywhere_vad.dart',
      'runanywhere_diffusion.dart',
      'runanywhere_embeddings.dart',
    ]) {
      test('$file loads through commons lifecycle', () {
        final source = File('lib/public/capabilities/$file').readAsStringSync();

        expect(source, contains('RunAnywhereModelLifecycle.shared.load'));
        expect(source, contains('RunAnywhereModelLifecycle.shared.unload'));
        expect(source, contains('componentSnapshot'));
        expect(source, contains('CurrentModelRequest'));
        expect(source, isNot(contains('DartBridge.modelPaths')));
        expect(source, isNot(contains('resolveArtifact(')));
        expect(
          source,
          isNot(contains('RunAnywhereModels.shared.resolveModelFilePath')),
        );
        expect(source, isNot(contains('model.localPath.isEmpty')));
        expect(source, isNot(contains('modelNotDownloaded')));
      });
    }

    test('non-LLM public one-shot operations use lifecycle ABIs', () {
      final expectations = <String, List<String>>{
        'runanywhere_stt.dart': [
          'DartBridgeSTT.shared.transcribeLifecycleProto',
        ],
        'runanywhere_tts.dart': [
          'DartBridgeTTS.shared.synthesizeLifecycleProto',
        ],
        'runanywhere_vad.dart': ['DartBridgeVAD.shared.processLifecycleProto'],
        'runanywhere_diffusion.dart': ['DartBridgeDiffusion.generateProto'],
        'runanywhere_embeddings.dart': [
          'DartBridgeEmbeddings.shared.embedBatch',
        ],
      };

      for (final entry in expectations.entries) {
        final source = File(
          'lib/public/capabilities/${entry.key}',
        ).readAsStringSync();
        for (final symbol in entry.value) {
          expect(source, contains(symbol), reason: '${entry.key} -> $symbol');
        }
      }
    });

    test('native non-LLM bridges bind lifecycle one-shot symbols', () {
      final expectations = <String, List<String>>{
        'dart_bridge_stt.dart': ['rac_stt_transcribe_lifecycle_proto'],
        'dart_bridge_tts.dart': ['rac_tts_synthesize_lifecycle_proto'],
        'dart_bridge_vad.dart': ['rac_vad_process_lifecycle_proto'],
        'dart_bridge_diffusion.dart': [
          'rac_diffusion_generate_lifecycle_proto',
        ],
        'dart_bridge_embeddings.dart': [
          'rac_embeddings_embed_batch_lifecycle_proto',
        ],
      };

      for (final entry in expectations.entries) {
        final source = File('lib/native/${entry.key}').readAsStringSync();
        for (final symbol in entry.value) {
          expect(source, contains(symbol), reason: '${entry.key} -> $symbol');
        }
      }
    });

    test('public non-LLM capabilities do not call handle-backed bridges', () {
      final forbidden = <String, List<String>>{
        'runanywhere_stt.dart': [
          'DartBridge.stt',
          'DartBridgeSttStreaming',
          'DartBridgeModelRegistry',
          'rac_stt_component_transcribe_proto',
        ],
        'runanywhere_tts.dart': [
          'DartBridge.tts',
          'SystemTTSService',
          'system-tts',
          'rac_tts_component_synthesize_proto',
        ],
        'runanywhere_vad.dart': [
          'DartBridge.vad',
          'rac_vad_component_process_proto',
        ],
        'runanywhere_diffusion.dart': ['rac_diffusion_generate_proto'],
        'runanywhere_embeddings.dart': [
          'DartBridge.embeddings',
          'rac_embeddings_embed_batch_proto',
        ],
      };

      for (final entry in forbidden.entries) {
        final source = File(
          'lib/public/capabilities/${entry.key}',
        ).readAsStringSync();
        for (final needle in entry.value) {
          expect(
            source,
            isNot(contains(needle)),
            reason: '${entry.key} still references $needle',
          );
        }
      }
    });

    test('native diffusion and embeddings bridges use lifecycle APIs', () {
      final diffusion = File(
        'lib/native/dart_bridge_diffusion.dart',
      ).readAsStringSync();
      final embeddings = File(
        'lib/native/dart_bridge_embeddings.dart',
      ).readAsStringSync();
      final bindings = File(
        'lib/core/native/rac_native.dart',
      ).readAsStringSync();

      for (final source in [diffusion, embeddings]) {
        expect(source, isNot(contains('RacHandle')));
        expect(source, isNot(contains('_handle')));
        expect(source, isNot(contains('loadModel(')));
        expect(source, isNot(contains('resolveModelFilePath')));
      }

      expect(diffusion, contains('rac_diffusion_generate_lifecycle_proto'));
      expect(diffusion, isNot(contains('rac_diffusion_create')));
      expect(diffusion, isNot(contains('rac_diffusion_destroy')));
      expect(diffusion, isNot(contains('rac_diffusion_generate_proto')));
      expect(
        embeddings,
        contains('rac_embeddings_embed_batch_lifecycle_proto'),
      );
      expect(embeddings, isNot(contains('rac_embeddings_create')));
      expect(embeddings, isNot(contains('rac_embeddings_destroy')));
      expect(embeddings, isNot(contains('rac_embeddings_embed_batch_proto')));
      expect(bindings, contains("'rac_embeddings_create_proto'"));
      expect(bindings, isNot(contains("'rac_embeddings_create'")));
      expect(bindings, isNot(contains("'rac_embeddings_create_with_config'")));
    });

    test('native STT and TTS path load wrappers were removed', () {
      final stt = File('lib/native/dart_bridge_stt.dart').readAsStringSync();
      final tts = File('lib/native/dart_bridge_tts.dart').readAsStringSync();

      expect(stt, isNot(contains('Future<void> loadModel(')));
      expect(stt, isNot(contains('NativeFunctions.sttLoadModel')));
      expect(tts, isNot(contains('Future<void> loadVoice(')));
      expect(tts, isNot(contains('NativeFunctions.ttsLoadVoice')));
    });

    test('runanywhere_llm.dart uses commons lifecycle router', () {
      final source = File(
        'lib/public/capabilities/runanywhere_llm.dart',
      ).readAsStringSync();
      final bridge = File('lib/native/dart_bridge_llm.dart').readAsStringSync();

      expect(source, contains('RunAnywhereModelLifecycle.shared.load'));
      expect(source, contains('RunAnywhereModelLifecycle.shared.unload'));
      expect(source, contains('DartBridgeLLM.shared.generateProto'));
      expect(source, contains('DartBridgeLLM.shared.generateStreamProto'));
      expect(bridge, contains('rac_llm_generate_proto'));
      expect(bridge, contains('rac_llm_generate_stream_proto'));
      expect(
        source,
        isNot(contains('RunAnywhereModels.shared.resolveModelFilePath')),
      );
      expect(source, isNot(contains('DartBridge.llm')));
    });

    test('runanywhere_vlm.dart uses lifecycle-owned VLM process ABI', () {
      final source = File(
        'lib/public/capabilities/runanywhere_vlm.dart',
      ).readAsStringSync();
      final bridge = File('lib/native/dart_bridge_vlm.dart').readAsStringSync();

      expect(source, contains('RunAnywhereModelLifecycle.shared.load'));
      expect(source, contains('componentSnapshot'));
      expect(source, contains('VLMGenerationRequest'));
      expect(source, contains('SDK_COMPONENT_VLM'));
      expect(
        source,
        isNot(contains('RunAnywhereModels.shared.resolveModelFilePath')),
      );
      expect(source, isNot(contains('DartBridge.modelPaths')));
      expect(source, isNot(contains('mmproj')));
      expect(source, isNot(contains('loadModel(')));
      expect(source, isNot(contains('loadModelFromResolvedArtifacts')));
      expect(source, isNot(contains('requireResolvedArtifactPaths')));

      expect(bridge, contains('VLMGenerationRequest request'));
      expect(bridge, contains('rac_vlm_generate_proto'));
      expect(bridge, contains('rac_vlm_stream_proto'));
      expect(bridge, contains('rac_vlm_cancel_lifecycle_proto'));
      expect(bridge, isNot(contains('RacHandle')));
      expect(bridge, isNot(contains('_handle')));
      expect(bridge, isNot(contains('getHandle')));
      expect(bridge, isNot(contains('rac_vlm_component_')));
      expect(bridge, isNot(contains('rac_vlm_process_proto')));
      expect(bridge, isNot(contains('rac_vlm_process_stream_proto')));
      expect(bridge, isNot(contains('visionProjectorPath')));
      expect(bridge, isNot(contains('base64Encode(image.encoded)')));
      expect(bridge, isNot(contains('RacVlmImageFormat')));
      expect(bridge, isNot(contains('currentMmprojPath')));
      expect(bridge, isNot(contains('String? mmprojPath')));
    });

    test(
      'lifecycle artifact helpers resolve primary and projector by role',
      () {
        final artifacts = [
          ModelFileDescriptor(
            role: ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL,
            localPath: '/models/llava/model.gguf',
          ),
          ModelFileDescriptor(
            role: ModelFileRole.MODEL_FILE_ROLE_VISION_PROJECTOR,
            localPath: '/models/llava/projector.gguf',
          ),
        ];
        final load = ModelLoadResult(resolvedArtifacts: artifacts);
        final current = CurrentModelResult(resolvedArtifacts: artifacts);

        expect(load.resolvedPrimaryModelPath, '/models/llava/model.gguf');
        expect(
          load.resolvedModelFilePath(
            ModelFileRole.MODEL_FILE_ROLE_VISION_PROJECTOR,
          ),
          '/models/llava/projector.gguf',
        );
        expect(
          current.requireResolvedArtifactPaths().visionProjectorPath,
          '/models/llava/projector.gguf',
        );
      },
    );

    test('VLM no longer exposes explicit path loading', () {
      final source = File(
        'lib/public/capabilities/runanywhere_vlm.dart',
      ).readAsStringSync();

      expect(source, isNot(contains('loadWithPath')));
    });

    test('TTS streaming exposes generated proto chunks', () {
      final source = File(
        'lib/public/capabilities/runanywhere_tts.dart',
      ).readAsStringSync();
      final bridge = File('lib/native/dart_bridge_tts.dart').readAsStringSync();

      expect(source, contains('Stream<TTSOutput> synthesizeStream'));
      expect(source, contains('synthesizeStreamLifecycleProto'));
      expect(bridge, contains('rac_tts_synthesize_stream_lifecycle_proto'));
      expect(source, isNot(contains('DartBridge.tts.synthesizeStreamProto')));
      expect(source, isNot(contains('Stream<Uint8List> synthesizeStream')));
      expect(source, isNot(contains('onAudioChunk')));
    });

    test('VLM streaming exposes generated proto events', () {
      final source = File(
        'lib/public/capabilities/runanywhere_vlm.dart',
      ).readAsStringSync();
      final bridge = File('lib/native/dart_bridge_vlm.dart').readAsStringSync();

      expect(source, contains('Stream<VLMStreamEvent> processImageStream'));
      expect(source, contains('processImageStreamProto'));
      expect(bridge, contains('VLMStreamEvent.fromBuffer'));
      expect(source, isNot(contains('class VLMStreamingResult')));
      expect(source, isNot(contains('Stream<String> stream')));
      expect(source, isNot(contains('Future<VLMStreamingResult>')));
    });
  });
}
