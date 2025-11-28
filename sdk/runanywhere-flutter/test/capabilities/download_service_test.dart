import 'package:flutter_test/flutter_test.dart';
import 'package:runanywhere/capabilities/download/download_service.dart';
import 'package:runanywhere/capabilities/registry/registry_service.dart';
import 'package:runanywhere/core/models/common.dart';

void main() {
  group('DownloadService Tests', () {
    late DownloadService downloadService;
    late ModelRegistry registry;

    setUp(() {
      registry = RegistryService();
      downloadService = DownloadService(modelRegistry: registry);
    });

    test('DownloadService initialization', () {
      expect(downloadService, isNotNull);
    });

    test('DownloadTask completed factory', () async {
      const modelId = 'test-model';
      const localPath = '/path/to/model.gguf';

      final task = DownloadTask.completed(modelId, localPath);

      expect(task.modelId, equals(modelId));
      expect(await task.result, equals(localPath));

      // Check progress stream
      final progressList = <DownloadProgress>[];
      await for (final progress in task.progress) {
        progressList.add(progress);
      }

      expect(progressList.length, equals(1));
      expect(progressList.first.state, equals(DownloadState.completed));
    });
  });
}

