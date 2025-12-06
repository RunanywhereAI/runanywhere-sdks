/// Base protocol for all analytics events
///
/// Corresponds to iOS SDK's AnalyticsEvent protocol in UnifiedAnalytics.swift
abstract class AnalyticsEvent {
  /// Unique identifier for this event
  String get id;

  /// Type/category of the event
  String get type;

  /// Timestamp when the event occurred
  DateTime get timestamp;

  /// Session ID this event belongs to (if any)
  String? get sessionId;

  /// The event data payload
  AnalyticsEventData get eventData;
}

/// Base protocol for analytics event data
///
/// Corresponds to iOS SDK's AnalyticsEventData protocol
abstract class AnalyticsEventData {
  /// Convert the event data to a map for serialization
  Map<String, dynamic> toMap();
}

/// Simple concrete implementation of AnalyticsEventData for basic key-value data
class SimpleAnalyticsEventData implements AnalyticsEventData {
  final Map<String, dynamic> _data;

  const SimpleAnalyticsEventData([Map<String, dynamic>? data])
      : _data = data ?? const {};

  @override
  Map<String, dynamic> toMap() => Map.unmodifiable(_data);

  /// Get a value by key
  dynamic operator [](String key) => _data[key];
}
