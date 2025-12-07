import 'dart:io';
import 'package:archive/archive_io.dart';
import 'package:flutter/foundation.dart';

/// Archive extraction utilities for Flutter
///
/// Provides cross-platform archive extraction using pure Dart,
/// avoiding the need for native libarchive on Android.
class ArchiveUtils {
  ArchiveUtils._();

  /// Extract a tar.bz2 archive to a destination directory
  ///
  /// [archivePath] - Path to the .tar.bz2 file
  /// [destinationPath] - Path to extract to
  /// [onProgress] - Optional progress callback (0.0 to 1.0)
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

      // Decode bz2 compression
      onProgress?.call(0.1);
      debugPrint('[RA_ARCHIVE] Decompressing bz2...');
      final decompressed = BZip2Decoder().decodeBytes(bytes);

      onProgress?.call(0.3);
      debugPrint('[RA_ARCHIVE] Decompressed size: ${decompressed.length} bytes');

      // Decode tar archive
      debugPrint('[RA_ARCHIVE] Extracting tar archive...');
      final archive = TarDecoder().decodeBytes(decompressed);

      onProgress?.call(0.5);
      debugPrint('[RA_ARCHIVE] Found ${archive.files.length} files in archive');

      // Create destination directory
      final destDir = Directory(destinationPath);
      await destDir.create(recursive: true);

      // Extract all files
      int extractedCount = 0;
      for (final file in archive.files) {
        final filename = file.name;

        if (file.isFile) {
          final outputFile = File('$destinationPath/$filename');

          // Create parent directories if needed
          await outputFile.parent.create(recursive: true);

          // Write file content
          await outputFile.writeAsBytes(file.content as List<int>);
          extractedCount++;

          // Update progress
          final progress = 0.5 + (0.5 * (extractedCount / archive.files.length));
          onProgress?.call(progress);
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

      // Decode zip archive
      final archive = ZipDecoder().decodeBytes(bytes);
      debugPrint('[RA_ARCHIVE] Found ${archive.files.length} files in archive');

      onProgress?.call(0.4);

      // Create destination directory
      final destDir = Directory(destinationPath);
      await destDir.create(recursive: true);

      // Extract all files
      int extractedCount = 0;
      for (final file in archive.files) {
        final filename = file.name;

        if (file.isFile) {
          final outputFile = File('$destinationPath/$filename');

          // Create parent directories if needed
          await outputFile.parent.create(recursive: true);

          // Write file content
          await outputFile.writeAsBytes(file.content as List<int>);
          extractedCount++;

          // Update progress
          final progress = 0.4 + (0.6 * (extractedCount / archive.files.length));
          onProgress?.call(progress);
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
    } else if (archiveLower.endsWith('.tar.gz') || archiveLower.endsWith('.tgz')) {
      // For tar.gz, use similar logic to tar.bz2 but with gzip decoder
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
  static Future<void> _extractTarGz({
    required String archivePath,
    required String destinationPath,
    void Function(double progress)? onProgress,
  }) async {
    debugPrint('[RA_ARCHIVE] Extracting TAR.GZ: $archivePath -> $destinationPath');

    try {
      final archiveFile = File(archivePath);
      if (!await archiveFile.exists()) {
        throw Exception('Archive file not found: $archivePath');
      }

      final bytes = await archiveFile.readAsBytes();
      onProgress?.call(0.1);

      // Decode gzip compression
      final decompressed = GZipDecoder().decodeBytes(bytes);
      onProgress?.call(0.3);

      // Decode tar archive
      final archive = TarDecoder().decodeBytes(decompressed);
      onProgress?.call(0.5);

      debugPrint('[RA_ARCHIVE] Found ${archive.files.length} files in archive');

      // Create destination directory
      final destDir = Directory(destinationPath);
      await destDir.create(recursive: true);

      // Extract all files
      int extractedCount = 0;
      for (final file in archive.files) {
        final filename = file.name;

        if (file.isFile) {
          final outputFile = File('$destinationPath/$filename');
          await outputFile.parent.create(recursive: true);
          await outputFile.writeAsBytes(file.content as List<int>);
          extractedCount++;

          final progress = 0.5 + (0.5 * (extractedCount / archive.files.length));
          onProgress?.call(progress);
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
}
