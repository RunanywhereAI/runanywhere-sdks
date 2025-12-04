import 'dart:async';

import '../../models/model/model_info.dart';

/// Protocol for custom download strategies provided by host app
/// Allows extending download behavior without modifying core SDK logic
/// Matches iOS DownloadStrategy from Core/Protocols/Downloading/DownloadStrategy.swift
abstract class DownloadStrategy {
  /// Check if this strategy can handle the given model
  bool canHandle(ModelInfo model);

  /// Download the model (can be multi-file, ZIP, etc.)
  /// - Parameters:
  ///   - model: The model to download
  ///   - destinationFolder: Where to save the downloaded files
  ///   - progressHandler: Optional progress callback (0.0 to 1.0)
  /// - Returns: URI to the downloaded model folder
  Future<Uri> download({
    required ModelInfo model,
    required Uri destinationFolder,
    void Function(double progress)? progressHandler,
  });
}
