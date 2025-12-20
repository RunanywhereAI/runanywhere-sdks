/// Where an event should be routed.
///
/// Mirrors iOS `EventDestination` from RunAnywhere SDK.
/// Used by EventPublisher to determine routing:
/// - [publicOnly] → EventBus only (app developers)
/// - [analyticsOnly] → Analytics only (backend telemetry)
/// - [all] → Both destinations (default)
enum EventDestination {
  /// Only to public EventBus (app developers can subscribe)
  publicOnly,

  /// Only to analytics/telemetry (backend)
  analyticsOnly,

  /// Both destinations (default)
  all,
}
