import 'download_policy.dart';

/// Simple configuration for model downloads.
/// Matches iOS ModelDownloadConfiguration from Configuration/ModelDownloadConfiguration.swift
class ModelDownloadConfiguration {
  /// Download policy
  final DownloadPolicy policy;

  /// Maximum concurrent downloads
  final int maxConcurrentDownloads;

  /// Number of retry attempts
  final int retryCount;

  /// Download timeout in seconds
  final Duration timeout;

  /// Enable background downloads
  final bool enableBackgroundDownloads;

  const ModelDownloadConfiguration({
    this.policy = DownloadPolicy.automatic,
    this.maxConcurrentDownloads = 3,
    this.retryCount = 3,
    this.timeout = const Duration(seconds: 300),
    this.enableBackgroundDownloads = false,
  });

  /// Create from JSON map
  factory ModelDownloadConfiguration.fromJson(Map<String, dynamic> json) {
    return ModelDownloadConfiguration(
      policy: DownloadPolicy.fromRawValue(
              json['policy'] as String? ?? 'automatic') ??
          DownloadPolicy.automatic,
      maxConcurrentDownloads:
          (json['maxConcurrentDownloads'] as num?)?.toInt() ?? 3,
      retryCount: (json['retryCount'] as num?)?.toInt() ?? 3,
      timeout: Duration(seconds: (json['timeout'] as num?)?.toInt() ?? 300),
      enableBackgroundDownloads:
          json['enableBackgroundDownloads'] as bool? ?? false,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'policy': policy.rawValue,
      'maxConcurrentDownloads': maxConcurrentDownloads,
      'retryCount': retryCount,
      'timeout': timeout.inSeconds,
      'enableBackgroundDownloads': enableBackgroundDownloads,
    };
  }

  /// Create a copy with updated fields
  ModelDownloadConfiguration copyWith({
    DownloadPolicy? policy,
    int? maxConcurrentDownloads,
    int? retryCount,
    Duration? timeout,
    bool? enableBackgroundDownloads,
  }) {
    return ModelDownloadConfiguration(
      policy: policy ?? this.policy,
      maxConcurrentDownloads:
          maxConcurrentDownloads ?? this.maxConcurrentDownloads,
      retryCount: retryCount ?? this.retryCount,
      timeout: timeout ?? this.timeout,
      enableBackgroundDownloads:
          enableBackgroundDownloads ?? this.enableBackgroundDownloads,
    );
  }

  /// Check if download is allowed based on policy
  bool shouldAllowDownload({bool isWiFi = false, bool userConfirmed = false}) {
    switch (policy) {
      case DownloadPolicy.automatic:
        return true;
      case DownloadPolicy.wifiOnly:
        return isWiFi;
      case DownloadPolicy.manual:
        return userConfirmed;
      case DownloadPolicy.never:
        return false;
    }
  }
}
