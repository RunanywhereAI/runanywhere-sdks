import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/internal/vlm_file_resolution.dart';

void main() {
  group('VLM file resolution', () {
    test('extracts basename from Windows-style paths', () {
      expect(
        vlmPathBasename(
          r'C:\Users\admin\Documents\RunAnywhere\Models\LlamaCpp\smolvlm-500m-instruct-q8_0\SmolVLM-500M-Instruct-Q8_0.gguf',
        ),
        'SmolVLM-500M-Instruct-Q8_0.gguf',
      );
    });

    test('resolves main model path without rejoining absolute Windows path',
        () async {
      final dir =
          await Directory.systemTemp.createTemp('runanywhere_vlm_resolution_');
      addTearDown(() async {
        if (await dir.exists()) {
          await dir.delete(recursive: true);
        }
      });

      final mainModel = File(
        '${dir.path}${Platform.pathSeparator}SmolVLM-500M-Instruct-Q8_0.gguf',
      );
      final mmproj = File(
        '${dir.path}${Platform.pathSeparator}mmproj-SmolVLM-500M-Instruct-Q8_0.gguf',
      );
      final archive = File(
        '${dir.path}${Platform.pathSeparator}smolvlm-500m-instruct-q8_0.tar.gz',
      );

      await mainModel.writeAsString('main');
      await mmproj.writeAsString('mmproj');
      await archive.writeAsString('archive');

      final resolvedMainModelPath = await resolveVlmMainModelPath(dir.path);
      final resolvedMmprojPath = await findVlmMmprojPath(dir.path);

      expect(resolvedMainModelPath, mainModel.path);
      expect(resolvedMmprojPath, mmproj.path);
    });
  });
}
