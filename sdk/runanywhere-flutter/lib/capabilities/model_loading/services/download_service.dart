import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

/// Download Service for model downloading
/// Similar to Swift SDK's DownloadService
class DownloadService {
  final Dio _dio = Dio();

  /// Download a model from URL
  Future<String> downloadModel({
    required String url,
    required String modelId,
    Function(int, int)? onProgress,
  }) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final modelsDir = Directory(path.join(appDir.path, 'RunAnywhere', 'Models'));
      if (!await modelsDir.exists()) {
        await modelsDir.create(recursive: true);
      }

      final filePath = path.join(modelsDir.path, '$modelId.gguf');

      await _dio.download(
        url,
        filePath,
        onReceiveProgress: onProgress,
      );

      return filePath;
    } catch (e) {
      throw Exception('Failed to download model: $e');
    }
  }

  /// Check if model is already downloaded
  Future<bool> isModelDownloaded(String modelId) async {
    try {
      final appDir = await getApplicationDocumentsDirectory();
      final filePath = path.join(appDir.path, 'RunAnywhere', 'Models', '$modelId.gguf');
      final file = File(filePath);
      return await file.exists();
    } catch (e) {
      return false;
    }
  }
}

