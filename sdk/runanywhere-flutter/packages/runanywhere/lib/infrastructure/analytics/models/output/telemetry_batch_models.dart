//
//  telemetry_batch_models.dart
//  RunAnywhere SDK
//
//  Batch request/response models for telemetry API.
//  Matches iOS TelemetryBatchRequest and TelemetryBatchResponse.
//

import 'package:runanywhere/infrastructure/analytics/models/output/telemetry_event_payload.dart';

/// Batch telemetry request for API
class TelemetryBatchRequest {
  final List<TelemetryEventPayload> events;
  final String deviceId;
  final DateTime timestamp;

  TelemetryBatchRequest({
    required this.events,
    required this.deviceId,
    DateTime? timestamp,
  }) : timestamp = timestamp ?? DateTime.now();

  Map<String, dynamic> toJson() {
    return {
      'events': events.map((e) => e.toJson()).toList(),
      'device_id': deviceId,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}

/// Batch telemetry response from API
class TelemetryBatchResponse {
  final bool success;
  final int eventsReceived;
  final int eventsStored;
  final List<String>? errors;

  TelemetryBatchResponse({
    required this.success,
    required this.eventsReceived,
    required this.eventsStored,
    this.errors,
  });

  factory TelemetryBatchResponse.fromJson(Map<String, dynamic> json) {
    return TelemetryBatchResponse(
      success: json['success'] as bool? ?? false,
      eventsReceived: json['events_received'] as int? ?? 0,
      eventsStored: json['events_stored'] as int? ?? 0,
      errors: (json['errors'] as List<dynamic>?)?.cast<String>(),
    );
  }
}
