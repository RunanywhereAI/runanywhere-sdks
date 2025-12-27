/// Component state enumeration
enum ComponentState {
  /// Component has not been initialized
  notInitialized,

  /// Component is checking prerequisites
  checking,

  /// Component is initializing
  initializing,

  /// Component is ready for use
  ready,

  /// Component initialization failed
  failed,
}

extension ComponentStateExtension on ComponentState {
  /// Get string representation
  String get value {
    switch (this) {
      case ComponentState.notInitialized:
        return 'not_initialized';
      case ComponentState.checking:
        return 'checking';
      case ComponentState.initializing:
        return 'initializing';
      case ComponentState.ready:
        return 'ready';
      case ComponentState.failed:
        return 'failed';
    }
  }
}
