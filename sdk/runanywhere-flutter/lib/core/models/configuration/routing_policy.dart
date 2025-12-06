/// Routing policy determines how requests are routed between device and cloud.
/// Matches iOS RoutingPolicy from Public/Configuration/RoutingPolicy.swift
enum RoutingPolicy {
  /// Automatically determine best execution target
  automatic('automatic'),

  /// Always use on-device execution when possible
  preferDevice('prefer_device'),

  /// ONLY use on-device execution - never use cloud
  deviceOnly('device_only'),

  /// Always use cloud execution
  preferCloud('prefer_cloud'),

  /// Use custom routing rules
  custom('custom');

  final String rawValue;

  const RoutingPolicy(this.rawValue);

  /// Create from raw string value
  static RoutingPolicy? fromRawValue(String value) {
    return RoutingPolicy.values.cast<RoutingPolicy?>().firstWhere(
          (p) => p?.rawValue == value,
          orElse: () => null,
        );
  }
}
