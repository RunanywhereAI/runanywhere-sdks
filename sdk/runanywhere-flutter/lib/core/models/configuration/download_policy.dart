/// Download policy for models.
/// Matches iOS DownloadPolicy from Configuration/ModelDownloadConfiguration.swift
enum DownloadPolicy {
  /// Download automatically if needed
  automatic('automatic'),

  /// Only download on WiFi
  wifiOnly('wifi_only'),

  /// Require user confirmation
  manual('manual'),

  /// Don't download, fail if not available
  never('never');

  final String rawValue;

  const DownloadPolicy(this.rawValue);

  /// Create from raw string value
  static DownloadPolicy? fromRawValue(String value) {
    return DownloadPolicy.values.cast<DownloadPolicy?>().firstWhere(
          (p) => p?.rawValue == value,
          orElse: () => null,
        );
  }
}
