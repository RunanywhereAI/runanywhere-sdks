/// Logging infrastructure barrel export
/// Matches iOS Logging module structure
library logging;

// Re-export from foundation logging
export '../../foundation/logging/models/log_entry.dart';
export '../../foundation/logging/models/log_level.dart';
export '../../foundation/logging/models/logging_configuration.dart';

// Infrastructure-specific protocols
export 'protocol/log_destination.dart';
export 'protocol/logging_service.dart';
