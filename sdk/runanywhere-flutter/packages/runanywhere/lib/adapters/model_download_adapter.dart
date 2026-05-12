// SPDX-License-Identifier: Apache-2.0
//
// model_download_adapter.dart — compatibility shim over the generated-proto
// download capability. The old Dart-side orchestrator, progress struct mapper,
// path resolver, and registry update policy have been removed.

import 'dart:async';

import 'package:runanywhere/generated/download_service.pb.dart';
import 'package:runanywhere/public/capabilities/runanywhere_downloads.dart';

/// Thin adapter retained for backend callers that still import
/// `ModelDownloadService`. Model download lifecycle data is generated
/// `DownloadProgress` from commons.
class ModelDownloadService {
  ModelDownloadService._();
  static final ModelDownloadService shared = ModelDownloadService._();

  Stream<DownloadProgress> downloadModel(String modelId) =>
      RunAnywhereDownloads.shared.start(modelId);

  void cancelDownload(String modelId) {
    unawaited(RunAnywhereDownloads.shared.cancelDownload(modelId));
  }
}
