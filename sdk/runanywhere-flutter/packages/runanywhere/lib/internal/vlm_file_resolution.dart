import 'dart:io';

String vlmPathBasename(String path) {
  return path.replaceAll('\\', '/').split('/').last;
}

Future<String?> resolveVlmMainModelPath(String modelFolder) async {
  final file = File(modelFolder);
  final dir = await file.exists() ? file.parent : Directory(modelFolder);
  if (!await dir.exists()) return null;

  try {
    final entities = await dir.list().toList();
    final filePaths = entities.whereType<File>().map((f) => f.path).toList();
    final ggufPaths = filePaths
        .where((path) => vlmPathBasename(path).toLowerCase().endsWith('.gguf'))
        .toList();
    final mainModelPaths = ggufPaths
        .where((path) => !vlmPathBasename(path).toLowerCase().contains('mmproj'))
        .toList();

    return mainModelPaths.isNotEmpty ? mainModelPaths.first : null;
  } catch (_) {
    return null;
  }
}

Future<String?> findVlmMmprojPath(String modelDirPath) async {
  final dir = Directory(modelDirPath);
  if (!await dir.exists()) return null;

  try {
    await for (final entity in dir.list()) {
      if (entity is! File) continue;

      final name = vlmPathBasename(entity.path).toLowerCase();
      if (name.contains('mmproj') && name.endsWith('.gguf')) {
        return entity.path;
      }
    }

    return null;
  } catch (_) {
    return null;
  }
}
