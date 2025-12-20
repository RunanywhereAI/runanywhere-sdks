//
//  analytics.dart
//  RunAnywhere SDK
//
//  Barrel export for analytics infrastructure
//

// Constants
export 'constants/analytics_constants.dart';

// Data Sources
export 'data_sources/local_telemetry_data_source.dart';
export 'data_sources/remote_telemetry_data_source.dart';

// Models - Domain
export 'models/domain/telemetry_data.dart';
export 'models/domain/telemetry_event_type.dart';

// Models - Output (API transmission)
export 'models/output/telemetry_batch_models.dart';
export 'models/output/telemetry_event_payload.dart';

// Repositories
export 'repositories/telemetry_repository.dart';

// Services
export 'analytics_queue_manager.dart';
export 'services/telemetry_sync_service.dart';

// Initialization
export 'sdk_analytics_initializer.dart';
