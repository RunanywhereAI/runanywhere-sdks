/// Simplified configuration for API network settings.
/// Matches iOS APIConfiguration from Configuration/APIConfiguration.swift
class APIConfiguration {
  /// Base URL for API requests
  final Uri baseURL;

  /// Timeout interval for requests (in seconds)
  final Duration timeout;

  /// Default API base URL
  static final Uri defaultBaseURL = Uri.parse('https://api.runanywhere.ai');

  APIConfiguration({
    Uri? baseURL,
    this.timeout = const Duration(seconds: 30),
  }) : baseURL = baseURL ?? defaultBaseURL;

  /// Create from JSON map
  factory APIConfiguration.fromJson(Map<String, dynamic> json) {
    return APIConfiguration(
      baseURL: json['baseURL'] != null ? Uri.parse(json['baseURL'] as String) : null,
      timeout: Duration(
        seconds: (json['timeoutInterval'] as num?)?.toInt() ?? 30,
      ),
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      'baseURL': baseURL.toString(),
      'timeoutInterval': timeout.inSeconds,
    };
  }

  /// Create a copy with updated fields
  APIConfiguration copyWith({
    Uri? baseURL,
    Duration? timeout,
  }) {
    return APIConfiguration(
      baseURL: baseURL ?? this.baseURL,
      timeout: timeout ?? this.timeout,
    );
  }
}
