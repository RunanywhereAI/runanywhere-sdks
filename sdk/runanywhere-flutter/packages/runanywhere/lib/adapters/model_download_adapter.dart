// SPDX-License-Identifier: Apache-2.0
//
// model_download_adapter.dart — v3 replacement for the old
// `infrastructure/download/download_service.dart`. Drives model
// downloads through the commons Phase H download runner
// (`rac_http_download_execute`) over a native libcurl transport.
//
// Public API (`ModelDownloadService`, `ModelDownloadProgress`,
// `ModelDownloadStage`) is preserved; call sites keep using
// `ModelDownloadService.shared.downloadModel(id)` unchanged.

import 'dart:async';
import 'dart:ffi' as ffi;
import 'dart:io';
import 'dart:isolate';

import 'package:ffi/ffi.dart';
import 'package:path/path.dart' as p;
import 'package:runanywhere/core/native/rac_native.dart';
import 'package:runanywhere/core/types/model_types.dart';
import 'package:runanywhere/foundation/logging/sdk_logger.dart';
import 'package:runanywhere/native/dart_bridge_model_paths.dart';
import 'package:runanywhere/native/dart_bridge_model_registry.dart'
    hide ModelInfo;
import 'package:runanywhere/native/platform_loader.dart';
import 'package:runanywhere/public/capabilities/runanywhere_models.dart';
import 'package:runanywhere/public/events/event_bus.dart';
import 'package:runanywhere/public/events/sdk_event.dart';

// ============================================================================
// Public progress types (stable API — mirrors the old file 1:1)
// ============================================================================

/// Download progress information.
class ModelDownloadProgress {
  final String modelId;
  final int bytesDownloaded;
  final int totalBytes;
  final ModelDownloadStage stage;
  final double overallProgress;
  final String? error;

  const ModelDownloadProgress({
    required this.modelId,
    required this.bytesDownloaded,
    required this.totalBytes,
    required this.stage,
    required this.overallProgress,
    this.error,
  });

  factory ModelDownloadProgress.started(String modelId, int totalBytes) =>
      ModelDownloadProgress(
        modelId: modelId,
        bytesDownloaded: 0,
        totalBytes: totalBytes,
        stage: ModelDownloadStage.downloading,
        overallProgress: 0,
      );

  factory ModelDownloadProgress.downloading(
    String modelId,
    int downloaded,
    int total,
  ) =>
      ModelDownloadProgress(
        modelId: modelId,
        bytesDownloaded: downloaded,
        totalBytes: total,
        stage: ModelDownloadStage.downloading,
        overallProgress: total > 0 ? downloaded / total * 0.9 : 0,
      );

  factory ModelDownloadProgress.extracting(String modelId) =>
      ModelDownloadProgress(
        modelId: modelId,
        bytesDownloaded: 0,
        totalBytes: 0,
        stage: ModelDownloadStage.extracting,
        overallProgress: 0.92,
      );

  factory ModelDownloadProgress.completed(String modelId) =>
      ModelDownloadProgress(
        modelId: modelId,
        bytesDownloaded: 0,
        totalBytes: 0,
        stage: ModelDownloadStage.completed,
        overallProgress: 1.0,
      );

  factory ModelDownloadProgress.failed(String modelId, String error) =>
      ModelDownloadProgress(
        modelId: modelId,
        bytesDownloaded: 0,
        totalBytes: 0,
        stage: ModelDownloadStage.failed,
        overallProgress: 0,
        error: error,
      );
}

enum ModelDownloadStage {
  downloading,
  extracting,
  verifying,
  completed,
  failed,
  cancelled;

  bool get isCompleted => this == ModelDownloadStage.completed;
  bool get isFailed => this == ModelDownloadStage.failed;
}

// ============================================================================
// Service
// ============================================================================

/// Model download service — routes downloads through the commons
/// libcurl-backed runner via FFI.
class ModelDownloadService {
  ModelDownloadService._();
  static final ModelDownloadService shared = ModelDownloadService._();

  final SDKLogger _logger = SDKLogger('ModelDownloadService');

  /// Active downloads keyed by modelId. Each entry owns a cancel flag
  /// shared with the worker isolate.
  final Map<String, _CancelToken> _active = {};

  /// Download a model by ID, emitting [ModelDownloadProgress] as it
  /// makes its way through the download → extraction → registry
  /// update pipeline.
  Stream<ModelDownloadProgress> downloadModel(String modelId) async* {
    _logger.info('Starting download for model: $modelId');

    final models = await RunAnywhereModels.shared.available();
    final model = models.where((m) => m.id == modelId).firstOrNull;

    if (model == null) {
      _logger.error('Model not found: $modelId');
      yield ModelDownloadProgress.failed(modelId, 'Model not found: $modelId');
      return;
    }

    if (model.downloadURL == null) {
      _logger.error('Model has no download URL: $modelId');
      yield ModelDownloadProgress.failed(
          modelId, 'Model has no download URL: $modelId');
      return;
    }

    EventBus.shared.publish(SDKModelEvent.downloadStarted(modelId: modelId));

    try {
      final destDir = await _getModelDirectory(model);
      await destDir.create(recursive: true);
      _logger.info('Download destination: ${destDir.path}');

      if (model.artifactType is MultiFileArtifact) {
        yield* _downloadMultiFile(
          modelId: modelId,
          model: model,
          multiFile: model.artifactType as MultiFileArtifact,
          destDir: destDir,
        );
        return;
      }

      yield* _downloadSingleFile(
        modelId: modelId,
        model: model,
        destDir: destDir,
      );
    } catch (e, stack) {
      _logger
          .error('Download failed: $e', metadata: {'stack': stack.toString()});
      EventBus.shared.publish(SDKModelEvent.downloadFailed(
        modelId: modelId,
        error: e.toString(),
      ));
      yield ModelDownloadProgress.failed(modelId, e.toString());
    }
  }

  /// Cancel an active download.
  void cancelDownload(String modelId) {
    final token = _active[modelId];
    if (token != null) {
      token.cancelled = true;
      _active.remove(modelId);
      _logger.info('Download cancel requested: $modelId');
    }
  }

  /// Download a caller-managed file through the commons download runner.
  ///
  /// This is intended for backend packages that already own their model
  /// destination layout but should still use the shared native transport.
  Future<void> downloadFile({
    required String downloadId,
    required Uri url,
    required File destination,
    void Function(int bytesDownloaded, int totalBytes)? onProgress,
  }) async {
    final cancel = _CancelToken();
    _active[downloadId] = cancel;

    try {
      await destination.parent.create(recursive: true);

      final controller = _ProgressController();
      final downloadFuture = _runDownload(
        url: url.toString(),
        destination: destination.path,
        cancel: cancel,
        onProgress: controller.push,
      );

      await for (final progress in _bridge(downloadFuture, controller.stream)) {
        onProgress?.call(progress.bytesDownloaded, progress.totalBytes);
      }

      final result = await downloadFuture;
      if (result.status != _DlStatus.ok) {
        final httpStatus =
            result.httpStatus > 0 ? ' (http=${result.httpStatus})' : '';
        final error = result.error != null ? ': ${result.error}' : '';
        throw Exception(
          'Download failed for $url: ${result.status.name}$httpStatus$error',
        );
      }
    } finally {
      _active.remove(downloadId);
    }
  }

  // --------------------------------------------------------------------------
  // Multi-file download (e.g. embedding model + vocab.txt)
  // --------------------------------------------------------------------------

  Stream<ModelDownloadProgress> _downloadMultiFile({
    required String modelId,
    required ModelInfo model,
    required MultiFileArtifact multiFile,
    required Directory destDir,
  }) async* {
    final cancel = _CancelToken();
    _active[modelId] = cancel;

    try {
      final totalFiles = multiFile.files.length;
      _logger.info('Multi-file model: downloading $totalFiles files');
      yield ModelDownloadProgress.started(modelId, model.downloadSize ?? 0);

      for (var i = 0; i < totalFiles; i++) {
        final descriptor = multiFile.files[i];
        final fileUrl = descriptor.url;
        if (fileUrl == null) {
          _logger.warning(
              'No URL for file descriptor: ${descriptor.destinationPath}');
          continue;
        }

        if (cancel.cancelled) {
          yield ModelDownloadProgress.failed(modelId, 'Cancelled');
          return;
        }

        final destPath = p.join(destDir.path, descriptor.destinationPath);
        await Directory(p.dirname(destPath)).create(recursive: true);
        _logger.info(
            'Downloading file ${i + 1}/$totalFiles: ${descriptor.destinationPath}');

        final controller = _ProgressController();
        final fileIndex = i;
        final downloadFuture = _runDownload(
          url: fileUrl.toString(),
          destination: destPath,
          cancel: cancel,
          onProgress: controller.push,
        );

        await for (final progress
            in _bridge(downloadFuture, controller.stream)) {
          final fileProgress =
              model.downloadSize != null && model.downloadSize! > 0
                  ? progress.bytesDownloaded / model.downloadSize!
                  : 0.0;
          final overallProgress = (fileIndex + fileProgress) / totalFiles;
          yield ModelDownloadProgress(
            modelId: modelId,
            bytesDownloaded: progress.bytesDownloaded,
            totalBytes: model.downloadSize ?? 0,
            stage: ModelDownloadStage.downloading,
            overallProgress: overallProgress * 0.9,
          );
        }

        final result = await downloadFuture;
        if (result.status != _DlStatus.ok) {
          throw Exception(
              'Download failed for ${descriptor.destinationPath}: ${result.status.name} (http=${result.httpStatus})');
        }
        _logger.info('Downloaded: ${descriptor.destinationPath}');
      }

      await _updateModelLocalPath(model, destDir.path);
      EventBus.shared
          .publish(SDKModelEvent.downloadCompleted(modelId: modelId));
      yield ModelDownloadProgress.completed(modelId);
      _logger.info(
          'Multi-file model download completed: $modelId -> ${destDir.path}');
    } finally {
      _active.remove(modelId);
    }
  }

  // --------------------------------------------------------------------------
  // Single-file / archive download
  // --------------------------------------------------------------------------

  Stream<ModelDownloadProgress> _downloadSingleFile({
    required String modelId,
    required ModelInfo model,
    required Directory destDir,
  }) async* {
    final cancel = _CancelToken();
    _active[modelId] = cancel;

    try {
      final requiresExtraction = model.artifactType.requiresExtraction;
      _logger.info('Requires extraction: $requiresExtraction');

      final downloadUrl = model.downloadURL!;
      final fileName = p.basename(downloadUrl.path);
      final downloadPath = p.join(destDir.path, fileName);

      final totalBytes = model.downloadSize ?? 0;
      yield ModelDownloadProgress.started(modelId, totalBytes);

      final controller = _ProgressController();
      final downloadFuture = _runDownload(
        url: downloadUrl.toString(),
        destination: downloadPath,
        cancel: cancel,
        onProgress: controller.push,
      );

      await for (final progress in _bridge(downloadFuture, controller.stream)) {
        final effectiveTotal =
            progress.totalBytes > 0 ? progress.totalBytes : totalBytes;
        yield ModelDownloadProgress.downloading(
          modelId,
          progress.bytesDownloaded,
          effectiveTotal > 0 ? effectiveTotal : progress.bytesDownloaded,
        );
      }

      final result = await downloadFuture;
      if (result.status != _DlStatus.ok) {
        throw Exception(
            'Download failed: ${result.status.name} (http=${result.httpStatus})');
      }
      _logger.info('Download complete: $downloadPath');

      String finalModelPath = downloadPath;
      if (requiresExtraction) {
        yield ModelDownloadProgress.extracting(modelId);

        final itemsBefore = await destDir.list().map((e) => e.path).toSet();

        final extractedPath = await _extractArchive(
          downloadPath,
          destDir.path,
          framework: model.framework,
          format: model.format,
        );

        try {
          await File(downloadPath).delete();
        } catch (e) {
          _logger.warning('Failed to delete archive: $e');
        }

        finalModelPath = await _resolveExtractedModelPath(
          destDir.path,
          modelId,
          itemsBefore,
          extractedPath,
        );
      }

      await _updateModelLocalPath(model, finalModelPath);

      EventBus.shared.publish(
        SDKModelEvent.downloadCompleted(modelId: modelId),
      );
      yield ModelDownloadProgress.completed(modelId);
      _logger.info('Model download completed: $modelId -> $finalModelPath');
    } finally {
      _active.remove(modelId);
    }
  }

  // --------------------------------------------------------------------------
  // Download runner (dispatches to helper isolate)
  // --------------------------------------------------------------------------

  Future<_DownloadResult> _runDownload({
    required String url,
    required String destination,
    required _CancelToken cancel,
    required void Function(int bytesWritten, int totalBytes) onProgress,
  }) async {
    final receive = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();

    final completer = Completer<_DownloadResult>();
    late final StreamSubscription<dynamic> receiveSub;

    receiveSub = receive.listen((message) {
      if (message is _ProgressMessage) {
        onProgress(message.bytesWritten, message.totalBytes);
      } else if (message is _SendPortMessage) {
        // Worker shipped us its cancel SendPort so we can tell it to
        // abort without destroying the whole isolate.
        cancel.attach(message.sendPort);
      } else if (message is _DownloadResult) {
        if (!completer.isCompleted) completer.complete(message);
      }
    });

    errorPort.listen((error) {
      if (!completer.isCompleted) {
        completer.complete(_DownloadResult(
          status: _DlStatus.unknown,
          httpStatus: 0,
          error: error.toString(),
        ));
      }
    });

    exitPort.listen((_) {
      if (!completer.isCompleted) {
        completer.complete(const _DownloadResult(
          status: _DlStatus.unknown,
          httpStatus: 0,
          error: 'Isolate exited without response',
        ));
      }
    });

    final spec = _DownloadSpec(
      url: url,
      destinationPath: destination,
      sendPort: receive.sendPort,
    );

    final isolate = await Isolate.spawn<_DownloadSpec>(
      _downloadWorker,
      spec,
      onError: errorPort.sendPort,
      onExit: exitPort.sendPort,
      errorsAreFatal: false,
    );

    // Propagate cancel from main → worker via the _CancelToken.
    cancel.onCancel(() {
      // First try a graceful cancel via the worker's SendPort.
      cancel.requestCancel();
    });

    try {
      final result = await completer.future;
      return result;
    } finally {
      try {
        isolate.kill(priority: Isolate.immediate);
      } catch (_) {}
      await receiveSub.cancel();
      receive.close();
      errorPort.close();
      exitPort.close();
    }
  }

  // --------------------------------------------------------------------------
  // Directory / registry helpers (unchanged semantics)
  // --------------------------------------------------------------------------

  Future<Directory> _getModelDirectory(ModelInfo model) async {
    final modelPath =
        await DartBridgeModelPaths.instance.getModelFolderAndCreate(
      model.id,
      model.framework,
    );
    return Directory(modelPath);
  }

  Future<String> _extractArchive(
    String archivePath,
    String destDir, {
    required InferenceFramework framework,
    required ModelFormat format,
  }) async {
    _logger.info('Extracting archive: $archivePath');

    final lib = PlatformLoader.loadCommons();
    final extractFn = lib.lookupFunction<
        ffi.Int32 Function(
            ffi.Pointer<Utf8>,
            ffi.Pointer<Utf8>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>),
        int Function(
            ffi.Pointer<Utf8>,
            ffi.Pointer<Utf8>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>,
            ffi.Pointer<ffi.Void>)>(
      'rac_extract_archive_native',
    );

    final archivePathPtr = archivePath.toNativeUtf8(allocator: calloc);
    final destPathPtr = destDir.toNativeUtf8(allocator: calloc);

    try {
      final result = extractFn(
        archivePathPtr,
        destPathPtr,
        ffi.nullptr,
        ffi.nullptr,
        ffi.nullptr,
        ffi.nullptr,
      );

      if (result != 0) {
        _logger.error('Native extraction failed with code: $result');
        throw Exception('Native extraction failed with code: $result');
      }
    } finally {
      calloc.free(archivePathPtr);
      calloc.free(destPathPtr);
    }

    _logger.info('Extraction complete: $destDir');
    return destDir;
  }

  Future<String> _resolveExtractedModelPath(
    String destDir,
    String modelId,
    Set<String> itemsBefore,
    String fallbackPath,
  ) async {
    final destDirectory = Directory(destDir);

    final currentItems = await destDirectory.list().toList();
    final newItems =
        currentItems.where((e) => !itemsBefore.contains(e.path)).toList();
    final newDirs = newItems.whereType<Directory>().toList();
    final newFiles = newItems.whereType<File>().toList();

    if (newDirs.length == 1 && newFiles.isEmpty) {
      final extractedDir = newDirs.first;
      _logger.info(
        'Flattening extracted dir '
        "'${p.basename(extractedDir.path)}' into destDir",
      );
      try {
        final innerItems = await extractedDir.list().toList();
        for (final item in innerItems) {
          final target = p.join(destDir, p.basename(item.path));
          try {
            await item.rename(target);
          } catch (e) {
            if (item is File) {
              await item.copy(target);
              await item.delete();
            } else {
              _logger.warning('Failed to move ${item.path}: $e');
            }
          }
        }
        await extractedDir.delete(recursive: true);
        _logger.info(
          'Flattened ${innerItems.length} items from '
          "'${p.basename(extractedDir.path)}' into: $destDir",
        );
      } catch (e) {
        _logger.warning('Error flattening extracted dir: $e');
      }
      return destDir;
    }

    if (newItems.isNotEmpty) {
      _logger
          .info('Extracted ${newItems.length} items directly into: $destDir');
      return destDir;
    }

    return fallbackPath;
  }

  Future<void> _updateModelLocalPath(ModelInfo model, String path) async {
    model.localPath = Uri.file(path);
    _logger.info('Updated model local path: ${model.id} -> $path');
    await _updateModelRegistry(model.id, path);
  }

  Future<void> _updateModelRegistry(String modelId, String path) async {
    try {
      await DartBridgeModelRegistry.instance
          .updateDownloadStatus(modelId, path);
    } catch (e) {
      _logger.debug('Could not update C++ registry: $e');
    }
  }
}

// ============================================================================
// Internal plumbing: progress bridge, cancel token, worker protocol
// ============================================================================

class _ProgressSnapshot {
  const _ProgressSnapshot(this.bytesDownloaded, this.totalBytes);
  final int bytesDownloaded;
  final int totalBytes;
}

class _ProgressController {
  final StreamController<_ProgressSnapshot> _controller =
      StreamController<_ProgressSnapshot>.broadcast(sync: true);

  Stream<_ProgressSnapshot> get stream => _controller.stream;

  void push(int bytesWritten, int totalBytes) {
    if (!_controller.isClosed) {
      _controller.add(_ProgressSnapshot(bytesWritten, totalBytes));
    }
  }

  Future<void> close() async {
    if (!_controller.isClosed) await _controller.close();
  }
}

/// Takes the download's Future + progress stream and yields progress
/// snapshots until the future completes (then closes cleanly).
Stream<_ProgressSnapshot> _bridge(
  Future<_DownloadResult> done,
  Stream<_ProgressSnapshot> progress,
) {
  final controller = StreamController<_ProgressSnapshot>();
  late final StreamSubscription<_ProgressSnapshot> sub;
  sub = progress.listen(controller.add);
  unawaited(done.whenComplete(() async {
    await sub.cancel();
    if (!controller.isClosed) await controller.close();
  }));
  return controller.stream;
}

class _CancelToken {
  bool cancelled = false;
  SendPort? _workerCancelPort;
  final List<void Function()> _listeners = [];

  void attach(SendPort port) {
    _workerCancelPort = port;
  }

  void onCancel(void Function() listener) {
    _listeners.add(listener);
  }

  void requestCancel() {
    cancelled = true;
    _workerCancelPort?.send('cancel');
    for (final l in List.of(_listeners)) {
      try {
        l();
      } catch (_) {}
    }
  }
}

enum _DlStatus {
  ok,
  networkError,
  fileError,
  insufficientStorage,
  invalidUrl,
  checksumFailed,
  cancelled,
  serverError,
  timeout,
  networkUnavailable,
  dnsError,
  sslError,
  unknown,
}

_DlStatus _mapStatusCode(int code) {
  switch (code) {
    case 0:
      return _DlStatus.ok;
    case 1:
      return _DlStatus.networkError;
    case 2:
      return _DlStatus.fileError;
    case 3:
      return _DlStatus.insufficientStorage;
    case 4:
      return _DlStatus.invalidUrl;
    case 5:
      return _DlStatus.checksumFailed;
    case 6:
      return _DlStatus.cancelled;
    case 7:
      return _DlStatus.serverError;
    case 8:
      return _DlStatus.timeout;
    case 9:
      return _DlStatus.networkUnavailable;
    case 10:
      return _DlStatus.dnsError;
    case 11:
      return _DlStatus.sslError;
    default:
      return _DlStatus.unknown;
  }
}

class _DownloadResult {
  const _DownloadResult({
    required this.status,
    required this.httpStatus,
    this.error,
  });

  final _DlStatus status;
  final int httpStatus;
  final String? error;
}

class _DownloadSpec {
  const _DownloadSpec({
    required this.url,
    required this.destinationPath,
    required this.sendPort,
  });

  final String url;
  final String destinationPath;
  final SendPort sendPort;
}

class _ProgressMessage {
  const _ProgressMessage(this.bytesWritten, this.totalBytes);
  final int bytesWritten;
  final int totalBytes;
}

class _SendPortMessage {
  const _SendPortMessage(this.sendPort);
  final SendPort sendPort;
}

// ============================================================================
// Worker isolate entry
// ============================================================================

// Keeps the worker's cancellation flag reachable from the native
// progress callback (which runs on the worker's thread).
bool _workerCancelled = false;

int _progressCallback(
    int bytesWritten, int totalBytes, ffi.Pointer<ffi.Void> _) {
  _workerSendPort?.send(_ProgressMessage(bytesWritten, totalBytes));
  return _workerCancelled ? 0 /* RAC_FALSE */ : 1 /* RAC_TRUE */;
}

SendPort? _workerSendPort;

void _downloadWorker(_DownloadSpec spec) {
  _workerSendPort = spec.sendPort;
  final cancelPort = ReceivePort();
  spec.sendPort.send(_SendPortMessage(cancelPort.sendPort));
  cancelPort.listen((_) {
    _workerCancelled = true;
  });

  final bindings = RacNative.bindings;

  final urlPtr = spec.url.toNativeUtf8();
  final destPtr = spec.destinationPath.toNativeUtf8();
  final reqPtr = calloc<RacHttpDownloadRequest>();
  final outStatus = calloc<ffi.Int32>();

  final callback = ffi.Pointer.fromFunction<RacHttpDownloadProgressNative>(
      _progressCallback, 0);

  reqPtr.ref
    ..url = urlPtr
    ..destinationPath = destPtr
    ..headers = ffi.nullptr.cast()
    ..headerCount = 0
    ..timeoutMs = 0
    ..followRedirects = 1
    ..resumeFromByte = 0
    ..expectedSha256Hex = ffi.nullptr.cast<Utf8>();

  int code;
  try {
    code = bindings.rac_http_download_execute(
      reqPtr,
      callback,
      ffi.nullptr,
      outStatus,
    );
  } finally {
    calloc.free(urlPtr);
    calloc.free(destPtr);
    calloc.free(reqPtr);
  }

  final httpStatus = outStatus.value;
  calloc.free(outStatus);

  spec.sendPort.send(_DownloadResult(
    status: _mapStatusCode(code),
    httpStatus: httpStatus,
  ));
  cancelPort.close();
}
