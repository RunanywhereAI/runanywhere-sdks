// URL utilities used by the example app (mirrors iOS `URL+Normalize.swift`).
//
// Single source of truth so the SDK init path and Settings UI never drift.

/// Normalize a base URL by prepending `https://` when no scheme is present.
String normalizeBaseURL(String url) {
  final trimmed = url.trim();
  if (trimmed.isEmpty) return trimmed;
  if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
    return trimmed;
  }
  return 'https://$trimmed';
}
