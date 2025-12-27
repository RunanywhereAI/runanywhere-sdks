/// Response model for health check endpoint.
///
/// Matches iOS `HealthCheckResponse` from RunAnywhere SDK.
class HealthCheckResponse {
  final String status;
  final String? version;
  final DateTime? timestamp;

  const HealthCheckResponse({
    required this.status,
    this.version,
    this.timestamp,
  });

  factory HealthCheckResponse.fromJson(Map<String, dynamic> json) {
    return HealthCheckResponse(
      status: json['status'] as String,
      version: json['version'] as String?,
      timestamp: json['timestamp'] != null
          ? DateTime.tryParse(json['timestamp'] as String)
          : null,
    );
  }

  Map<String, dynamic> toJson() => {
        'status': status,
        if (version != null) 'version': version,
        if (timestamp != null) 'timestamp': timestamp!.toIso8601String(),
      };
}
