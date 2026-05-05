// SPDX-License-Identifier: Apache-2.0
//
// model_download_adapter.dart — compatibility shim over the generated-proto
// download capability. The old Dart-side orchestrator, progress struct mapper,
// path resolver, and registry update policy have been removed.

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/generated/download_service.pb.dart';
import 'package:runanywhere/public/capabilities/runanywhere_downloads.dart';

/// Thin adapter retained for backend callers that still import
/// `ModelDownloadService`. Model download lifecycle data is generated
/// `DownloadProgress` from commons.
class ModelDownloadService {
  ModelDownloadService._();
  static final ModelDownloadService shared = ModelDownloadService._();

  final SDKLogger _logger = SDKLogger('ModelDownloadService');

  Stream<DownloadProgress> downloadModel(String modelId) =>
      RunAnywhereDownloads.shared.start(modelId);

  void cancelDownload(String modelId) {
    unawaited(RunAnywhereDownloads.shared.cancelDownload(modelId));
  }

  /// Download a caller-managed file through the registered commons HTTP runner.
  ///
  /// This remains a host adapter entry point for backend package fallout until
  /// FLT-03 moves those callers to native/background transfer adapters.
  Future<void> downloadFile({
    required String downloadId,
    required Uri url,
    required File destination,
    void Function(int bytesDownloaded, int totalBytes)? onProgress,
    String? expectedSha256Hex,
  }) async {
    await destination.parent.create(recursive: true);

    final bindings = RacNative.bindings;
    final urlPtr = url.toString().toNativeUtf8();
    final destPtr = destination.path.toNativeUtf8();
    final reqPtr = calloc<RacHttpDownloadRequest>();
    final outStatus = calloc<ffi.Int32>();
    final sha256Ptr = expectedSha256Hex != null && expectedSha256Hex.isNotEmpty
        ? expectedSha256Hex.toNativeUtf8()
        : ffi.nullptr.cast<Utf8>();

    reqPtr.ref
      ..url = urlPtr
      ..destinationPath = destPtr
      ..headers = ffi.nullptr.cast()
      ..headerCount = 0
      ..timeoutMs = 0
      ..followRedirects = 1
      ..resumeFromByte = 0
      ..expectedSha256Hex = sha256Ptr;

    int code;
    try {
      code = bindings.rac_http_download_execute(
        reqPtr,
        ffi.nullptr,
        ffi.nullptr,
        outStatus,
      );
    } finally {
      calloc.free(urlPtr);
      calloc.free(destPtr);
      calloc.free(reqPtr);
      calloc.free(outStatus);
      if (sha256Ptr != ffi.nullptr.cast<Utf8>()) {
        calloc.free(sha256Ptr);
      }
    }

    if (code != 0) {
      throw Exception(
        'Download failed for $url (id=$downloadId): status code $code',
      );
    }

    try {
      final len = await destination.length();
      onProgress?.call(len, len);
    } catch (e) {
      _logger.debug('Final file-size progress callback failed: $e');
    }
  }
}
