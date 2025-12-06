/// Privacy mode settings.
/// Matches iOS PrivacyMode from Public/Configuration/PrivacyMode.swift
enum PrivacyMode {
  /// Standard privacy protection
  standard('standard'),

  /// Enhanced privacy with stricter PII detection
  strict('strict'),

  /// Custom privacy rules
  custom('custom');

  final String rawValue;

  const PrivacyMode(this.rawValue);

  /// Create from raw string value
  static PrivacyMode? fromRawValue(String value) {
    return PrivacyMode.values.cast<PrivacyMode?>().firstWhere(
          (p) => p?.rawValue == value,
          orElse: () => null,
        );
  }
}
