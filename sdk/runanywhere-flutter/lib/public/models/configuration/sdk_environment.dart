/// SDK Environment enum
/// Similar to Swift SDK's SDKEnvironment
enum SDKEnvironment {
  development,
  staging,
  production;

  /// Default log level for the environment
  LogLevel get defaultLogLevel {
    switch (this) {
      case SDKEnvironment.development:
        return LogLevel.debug;
      case SDKEnvironment.staging:
        return LogLevel.info;
      case SDKEnvironment.production:
        return LogLevel.warning;
    }
  }

  String get description {
    switch (this) {
      case SDKEnvironment.development:
        return 'Development';
      case SDKEnvironment.staging:
        return 'Staging';
      case SDKEnvironment.production:
        return 'Production';
    }
  }
}

/// Log level enum
enum LogLevel {
  debug,
  info,
  warning,
  error,
  fatal;
}

