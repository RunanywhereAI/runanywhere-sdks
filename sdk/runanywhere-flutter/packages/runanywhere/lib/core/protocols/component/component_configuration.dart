/// Base protocol for component configurations
abstract class ComponentConfiguration {
  /// Validate the configuration
  void validate();
}

/// Base protocol for component inputs
abstract class ComponentInput {
  /// Validate the input
  void validate();
}

/// Base protocol for component outputs
abstract class ComponentOutput {
  /// Timestamp of when the output was generated
  DateTime get timestamp;
}

/// Base protocol for component initialization parameters
abstract class ComponentInitParameters {
  /// Component type
  String get componentType;

  /// Model identifier (optional)
  String? get modelId;

  /// Validate the parameters
  void validate();
}
