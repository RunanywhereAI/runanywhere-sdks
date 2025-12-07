import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

// Top-level decode functions for compute() isolate support
// These must be top-level functions (not class methods) to work with compute()

/// Decode tar.bz2 bytes (runs in background isolate)
Archive _decodeTarBz2(Uint8List bytes) {
  final decompressed = BZip2Decoder().decodeBytes(bytes);
  return TarDecoder().decodeBytes(decompressed);
}

/// Decode ZIP bytes (runs in background isolate)
Archive _decodeZip(Uint8List bytes) {
  return ZipDecoder().decodeBytes(bytes);
}

/// Decode tar.gz bytes (runs in background isolate)
Archive _decodeTarGz(Uint8List bytes) {
  final decompressed = GZipDecoder().decodeBytes(bytes);
  return TarDecoder().decodeBytes(decompressed);
}

/// Archive extraction utilities for Flutter
///
/// Provides cross-platform archive extraction using pure Dart,
/// avoiding the need for native libarchive on Android.
/// Uses background isolates for CPU-intensive decompression to avoid blocking UI.
class ArchiveUtils {
  ArchiveUtils._();

  /// Extract a tar.bz2 archive to a destination directory
  ///
  /// [archivePath] - Path to the .tar.bz2 file
  /// [destinationPath] - Path to extract to
  /// [onProgress] - Optional progress callback (0.0 to 1.0)
  ///
  /// Runs decompression in a background isolate to avoid blocking UI.
  static Future<void> extractTarBz2({
    required String archivePath,
    required String destinationPath,
    void Function(double progress)? onProgress,
  }) async {
    debugPrint('[RA_ARCHIVE] Extracting: $archivePath -> $destinationPath');

    try {
      // Read the archive file
      final archiveFile = File(archivePath);
      if (!await archiveFile.exists()) {
        throw Exception('Archive file not found: $archivePath');
      }

      final bytes = await archiveFile.readAsBytes();
      debugPrint('[RA_ARCHIVE] Archive size: ${bytes.length} bytes');

      onProgress?.call(0.1);
      debugPrint('[RA_ARCHIVE] Decompressing bz2 in background isolate...');

      // Run CPU-intensive decompression in background isolate
      final archive = await compute<Uint8List, Archive>(_decodeTarBz2, bytes);

      onProgress?.call(0.5);
      debugPrint('[RA_ARCHIVE] Found ${archive.files.length} files in archive');

      // Create destination directory
      final destDir = Directory(destinationPath);
      await destDir.create(recursive: true);

      // Extract all files (file I/O is already async and non-blocking)
      int extractedCount = 0;
      final totalFiles = archive.files.length;
      for (final file in archive.files) {
        final filename = file.name;

        // Validate filename to prevent path traversal attacks
        if (_isUnsafePath(filename)) {
          debugPrint('[RA_ARCHIVE] Skipping suspicious file: $filename');
          continue;
        }

        if (file.isFile) {
          final outputFile = File('$destinationPath/$filename');

          // Create parent directories if needed
          await outputFile.parent.create(recursive: true);

          // Write file content
          await outputFile.writeAsBytes(file.content as List<int>);
          extractedCount++;

          // Update progress periodically (every 10 files to avoid too many updates)
          if (extractedCount % 10 == 0 || extractedCount == totalFiles) {
            final progress = 0.5 + (0.5 * (extractedCount / totalFiles));
            onProgress?.call(progress);
          }
        } else {
          // It's a directory
          final dir = Directory('$destinationPath/$filename');
          await dir.create(recursive: true);
        }
      }

      onProgress?.call(1.0);
      debugPrint('[RA_ARCHIVE] Extracted $extractedCount files successfully');
    } catch (e, stackTrace) {
      debugPrint('[RA_ARCHIVE] Extraction failed: $e');
      debugPrint('[RA_ARCHIVE] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Extract a zip archive to a destination directory
  ///
  /// [archivePath] - Path to the .zip file
  /// [destinationPath] - Path to extract to
  /// [onProgress] - Optional progress callback (0.0 to 1.0)
  ///
  /// Runs decompression in a background isolate to avoid blocking UI.
  static Future<void> extractZip({
    required String archivePath,
    required String destinationPath,
    void Function(double progress)? onProgress,
  }) async {
    debugPrint('[RA_ARCHIVE] Extracting ZIP: $archivePath -> $destinationPath');

    try {
      // Read the archive file
      final archiveFile = File(archivePath);
      if (!await archiveFile.exists()) {
        throw Exception('Archive file not found: $archivePath');
      }

      final bytes = await archiveFile.readAsBytes();
      debugPrint('[RA_ARCHIVE] Archive size: ${bytes.length} bytes');

      onProgress?.call(0.2);
      debugPrint('[RA_ARCHIVE] Decoding ZIP in background isolate...');

      // Run CPU-intensive decoding in background isolate
      final archive = await compute<Uint8List, Archive>(_decodeZip, bytes);
      debugPrint('[RA_ARCHIVE] Found ${archive.files.length} files in archive');

      onProgress?.call(0.4);

      // Create destination directory
      final destDir = Directory(destinationPath);
      await destDir.create(recursive: true);

      // Extract all files (file I/O is already async and non-blocking)
      int extractedCount = 0;
      final totalFiles = archive.files.length;
      for (final file in archive.files) {
        final filename = file.name;

        // Validate filename to prevent path traversal attacks
        if (_isUnsafePath(filename)) {
          debugPrint('[RA_ARCHIVE] Skipping suspicious file: $filename');
          continue;
        }

        if (file.isFile) {
          final outputFile = File('$destinationPath/$filename');

          // Create parent directories if needed
          await outputFile.parent.create(recursive: true);

          // Write file content
          await outputFile.writeAsBytes(file.content as List<int>);
          extractedCount++;

          // Update progress periodically (every 10 files to avoid too many updates)
          if (extractedCount % 10 == 0 || extractedCount == totalFiles) {
            final progress = 0.4 + (0.6 * (extractedCount / totalFiles));
            onProgress?.call(progress);
          }
        } else {
          // It's a directory
          final dir = Directory('$destinationPath/$filename');
          await dir.create(recursive: true);
        }
      }

      onProgress?.call(1.0);
      debugPrint('[RA_ARCHIVE] Extracted $extractedCount files successfully');
    } catch (e, stackTrace) {
      debugPrint('[RA_ARCHIVE] Extraction failed: $e');
      debugPrint('[RA_ARCHIVE] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Extract an archive (auto-detects format from extension)
  ///
  /// Supported formats: .tar.bz2, .tar.gz, .zip
  static Future<void> extractArchive({
    required String archivePath,
    required String destinationPath,
    void Function(double progress)? onProgress,
  }) async {
    final archiveLower = archivePath.toLowerCase();

    if (archiveLower.endsWith('.tar.bz2') || archiveLower.endsWith('.tbz2')) {
      await extractTarBz2(
        archivePath: archivePath,
        destinationPath: destinationPath,
        onProgress: onProgress,
      );
    } else if (archiveLower.endsWith('.tar.gz') ||
        archiveLower.endsWith('.tgz')) {
      await _extractTarGz(
        archivePath: archivePath,
        destinationPath: destinationPath,
        onProgress: onProgress,
      );
    } else if (archiveLower.endsWith('.zip')) {
      await extractZip(
        archivePath: archivePath,
        destinationPath: destinationPath,
        onProgress: onProgress,
      );
    } else {
      throw Exception('Unsupported archive format: $archivePath');
    }
  }

  /// Extract a tar.gz archive
  /// Runs decompression in a background isolate to avoid blocking UI.
  static Future<void> _extractTarGz({
    required String archivePath,
    required String destinationPath,
    void Function(double progress)? onProgress,
  }) async {
    debugPrint(
        '[RA_ARCHIVE] Extracting TAR.GZ: $archivePath -> $destinationPath');

    try {
      final archiveFile = File(archivePath);
      if (!await archiveFile.exists()) {
        throw Exception('Archive file not found: $archivePath');
      }

      final bytes = await archiveFile.readAsBytes();
      onProgress?.call(0.1);
      debugPrint('[RA_ARCHIVE] Decompressing tar.gz in background isolate...');

      // Run CPU-intensive decompression in background isolate
      final archive = await compute<Uint8List, Archive>(_decodeTarGz, bytes);

      onProgress?.call(0.5);
      debugPrint('[RA_ARCHIVE] Found ${archive.files.length} files in archive');

      // Create destination directory
      final destDir = Directory(destinationPath);
      await destDir.create(recursive: true);

      // Extract all files (file I/O is already async and non-blocking)
      int extractedCount = 0;
      final totalFiles = archive.files.length;
      for (final file in archive.files) {
        final filename = file.name;

        // Validate filename to prevent path traversal attacks
        if (_isUnsafePath(filename)) {
          debugPrint('[RA_ARCHIVE] Skipping suspicious file: $filename');
          continue;
        }

        if (file.isFile) {
          final outputFile = File('$destinationPath/$filename');
          await outputFile.parent.create(recursive: true);
          await outputFile.writeAsBytes(file.content as List<int>);
          extractedCount++;

          // Update progress periodically (every 10 files to avoid too many updates)
          if (extractedCount % 10 == 0 || extractedCount == totalFiles) {
            final progress = 0.5 + (0.5 * (extractedCount / totalFiles));
            onProgress?.call(progress);
          }
        } else {
          final dir = Directory('$destinationPath/$filename');
          await dir.create(recursive: true);
        }
      }

      onProgress?.call(1.0);
      debugPrint('[RA_ARCHIVE] Extracted $extractedCount files successfully');
    } catch (e, stackTrace) {
      debugPrint('[RA_ARCHIVE] Extraction failed: $e');
      debugPrint('[RA_ARCHIVE] Stack trace: $stackTrace');
      rethrow;
    }
  }

  /// Check if a path contains path traversal patterns
  static bool _isUnsafePath(String path) {
    // Reject paths containing '..' (path traversal)
    if (path.contains('..')) return true;
    // Reject absolute paths starting with '/'
    if (path.startsWith('/')) return true;
    // Reject Windows absolute paths
    if (path.contains(':')) return true;
    return false;
  }
}
