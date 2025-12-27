/// Battery charging state.
/// Matches iOS BatteryState from Capabilities/DeviceCapability/Models/BatteryInfo.swift
enum BatteryState {
  unknown,
  unplugged,
  charging,
  full;

  String get rawValue => name;

  static BatteryState fromRawValue(String value) {
    return BatteryState.values.firstWhere(
      (s) => s.name == value,
      orElse: () => BatteryState.unknown,
    );
  }
}

/// Battery information for device power status.
/// Matches iOS BatteryInfo from Capabilities/DeviceCapability/Models/BatteryInfo.swift
class BatteryInfo {
  /// Battery level from 0.0 to 1.0 (null if unknown)
  final double? level;

  /// Current battery state
  final BatteryState state;

  /// Whether the device is in low power mode
  final bool isLowPowerModeEnabled;

  const BatteryInfo({
    this.level,
    required this.state,
    this.isLowPowerModeEnabled = false,
  });

  /// Check if battery is low (less than 20%)
  bool get isLowBattery {
    final l = level;
    if (l == null) return false;
    return l < 0.2;
  }

  /// Check if battery is critical (less than 10%)
  bool get isCriticalBattery {
    final l = level;
    if (l == null) return false;
    return l < 0.1;
  }

  /// Create from JSON map
  factory BatteryInfo.fromJson(Map<String, dynamic> json) {
    return BatteryInfo(
      level: (json['level'] as num?)?.toDouble(),
      state: BatteryState.fromRawValue(json['state'] as String? ?? 'unknown'),
      isLowPowerModeEnabled: json['isLowPowerModeEnabled'] as bool? ?? false,
    );
  }

  /// Convert to JSON map
  Map<String, dynamic> toJson() {
    return {
      if (level != null) 'level': level,
      'state': state.rawValue,
      'isLowPowerModeEnabled': isLowPowerModeEnabled,
    };
  }
}
