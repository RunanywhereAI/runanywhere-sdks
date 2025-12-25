/// Configuration source
/// Matches iOS ConfigurationSource from Core/Models/Configuration/ConfigurationData.swift
enum ConfigurationSource {
  remote('remote'),
  consumer('consumer'),
  defaults('defaults'),
  embedded('embedded'); // Models registered via adapter registration

  final String rawValue;

  const ConfigurationSource(this.rawValue);

  /// Create from raw string value
  static ConfigurationSource fromRawValue(String value) {
    return ConfigurationSource.values.firstWhere(
      (s) => s.rawValue == value,
      orElse: () => ConfigurationSource.defaults,
    );
  }
}
