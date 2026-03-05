// Document Service
//
// Utility for extracting plain text from PDF and JSON files.
// Used to prepare document content for RAG ingestion.

import 'dart:convert';
import 'dart:io';

import 'package:syncfusion_flutter_pdf/pdf.dart';

// MARK: - DocumentService

/// Extracts plain text from PDF and JSON files.
///
/// Supports:
/// - PDF — All page text concatenated with newlines (via syncfusion_flutter_pdf).
/// - JSON — Raw UTF-8 file content returned as-is.
class DocumentService {
  // Private constructor — static-only class.
  DocumentService._();

  /// Extract plain text from a file at [filePath].
  ///
  /// Determines the document type from the file extension.
  ///
  /// Throws [UnsupportedError] for unsupported file extensions.
  /// Throws [Exception] if the file cannot be read or parsed.
  static Future<String> extractText(String filePath) async {
    final extension = filePath.split('.').last.toLowerCase();

    switch (extension) {
      case 'pdf':
        return _extractPDFText(filePath);
      case 'json':
        return _extractJSONText(filePath);
      default:
        throw UnsupportedError(
          'Unsupported document format: .$extension. Only PDF and JSON files are supported.',
        );
    }
  }

  // MARK: - Private Helpers

  static Future<String> _extractPDFText(String filePath) async {
    final file = File(filePath);
    final bytes = await file.readAsBytes();

    final document = PdfDocument(inputBytes: bytes);
    final extractor = PdfTextExtractor(document);

    final buffer = StringBuffer();
    final pageCount = document.pages.count;

    for (var i = 0; i < pageCount; i++) {
      final pageText = extractor.extractText(startPageIndex: i, endPageIndex: i);
      if (pageText.trim().isNotEmpty) {
        if (buffer.isNotEmpty) buffer.write('\n');
        buffer.write(pageText);
      }
    }

    document.dispose();

    final result = buffer.toString();
    if (result.isEmpty) {
      throw Exception(
        'Failed to extract text from PDF. The file may be corrupted or image-only.',
      );
    }

    return result;
  }

  static Future<String> _extractJSONText(String filePath) async {
    final file = File(filePath);
    return file.readAsString(encoding: utf8);
  }
}
