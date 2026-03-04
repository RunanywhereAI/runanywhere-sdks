/// VLM (Vision Language Model) Types
///
/// Public types for VLM image processing.
/// Mirrors iOS VLMTypes.swift adapted for Flutter/Dart.
library vlm_types;

import 'dart:typed_data';

// MARK: - VLM Image Input (Dart-adapted)

/// Image input for VLM - handles Dart-native image formats
///
/// Supports three image formats:
/// - filePath: Path to an image file (JPEG, PNG, etc.)
/// - rgbPixels: Raw RGB pixel data (RGBRGBRGB layout)
/// - base64: Base64-encoded image data
///
/// Matches iOS VLMImage but uses Dart-native types instead of UIImage/CVPixelBuffer.
class VLMImage {
  final VLMImageFormat format;

  const VLMImage._(this.format);

  /// Create from a file path (JPEG, PNG, etc.)
  factory VLMImage.filePath(String path) => VLMImage._(VLMImageFormat.filePath(path));

  /// Create from raw RGB pixel data (RGBRGBRGB layout)
  factory VLMImage.rgbPixels(Uint8List data, {required int width, required int height}) =>
      VLMImage._(VLMImageFormat.rgbPixels(data: data, width: width, height: height));

  /// Create from base64-encoded image data
  factory VLMImage.base64(String encoded) => VLMImage._(VLMImageFormat.base64(encoded));
}

/// Image format variants (sealed class for type safety)
sealed class VLMImageFormat {
  const VLMImageFormat();

  factory VLMImageFormat.filePath(String path) = VLMImageFormatFilePath;
  factory VLMImageFormat.rgbPixels({required Uint8List data, required int width, required int height}) = VLMImageFormatRgbPixels;
  factory VLMImageFormat.base64(String encoded) = VLMImageFormatBase64;
}

/// File path format
class VLMImageFormatFilePath extends VLMImageFormat {
  final String path;
  const VLMImageFormatFilePath(this.path);
}

/// RGB pixels format
class VLMImageFormatRgbPixels extends VLMImageFormat {
  final Uint8List data;
  final int width;
  final int height;
  const VLMImageFormatRgbPixels({required this.data, required this.width, required this.height});
}

/// Base64 format
class VLMImageFormatBase64 extends VLMImageFormat {
  final String encoded;
  const VLMImageFormatBase64(this.encoded);
}

// MARK: - VLM Result

/// Result from VLM generation
/// Matches iOS VLMResult
class VLMResult {
  /// Generated text describing the image
  final String text;

  /// Number of tokens in the prompt (including image tokens)
  final int promptTokens;

  /// Number of tokens generated in the response
  final int completionTokens;

  /// Total processing time in milliseconds
  final double totalTimeMs;

  /// Tokens generated per second
  final double tokensPerSecond;

  const VLMResult({
    required this.text,
    required this.promptTokens,
    required this.completionTokens,
    required this.totalTimeMs,
    required this.tokensPerSecond,
  });

  @override
  String toString() {
    final textPreview = text.length > 50 ? text.substring(0, 50) : text;
    return 'VLMResult(text: "$textPreview...", tokens: $completionTokens, ${tokensPerSecond.toStringAsFixed(1)} tok/s)';
  }
}

// MARK: - VLM Streaming

/// Streaming result for VLM generation
/// Matches iOS VLMStreamingResult, adapted for Dart async patterns
class VLMStreamingResult {
  /// Stream of tokens as they are generated
  final Stream<String> stream;

  /// Future that completes with final result metrics when streaming finishes
  final Future<VLMResult> metrics;

  /// Function to cancel the ongoing generation
  final void Function() cancel;

  const VLMStreamingResult({
    required this.stream,
    required this.metrics,
    required this.cancel,
  });
}

// MARK: - VLM Error Codes

/// VLM-specific error codes
/// Matches iOS SDKError.VLMErrorCode exactly
enum VLMErrorCode {
  /// VLM model not loaded
  notInitialized(1),

  /// Model load operation failed
  modelLoadFailed(2),

  /// Image processing failed
  processingFailed(3),

  /// Invalid image input
  invalidImage(4),

  /// Generation was cancelled
  cancelled(5);

  final int rawValue;
  const VLMErrorCode(this.rawValue);
}
