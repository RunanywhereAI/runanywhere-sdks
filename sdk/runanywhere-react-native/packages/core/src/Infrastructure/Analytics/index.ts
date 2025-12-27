/**
 * Analytics Module
 *
 * Centralized analytics infrastructure for the RunAnywhere SDK.
 * Handles event queuing, batching, and transmission to backend.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Analytics/
 */

// Core analytics queue manager
export { AnalyticsQueueManager } from './AnalyticsQueueManager';

// Telemetry repository for persistence and sync
export {
  TelemetryRepository,
  TelemetryEventType,
  type TelemetryDataEntity,
  type TelemetryStorage,
} from './TelemetryRepository';

// Component-specific analytics services
export {
  LLMAnalyticsService,
  STTAnalyticsService,
  TTSAnalyticsService,
} from './Services';

// Errors
export { AnalyticsError, AnalyticsErrorCode, isAnalyticsError } from './Errors';

// Configuration
export {
  type AnalyticsConfiguration,
  DEFAULT_ANALYTICS_CONFIGURATION,
  AnalyticsConfigurationPresets,
  createAnalyticsConfiguration,
  validateAnalyticsConfiguration,
  AnalyticsConfigurationBuilder,
} from './Models/Configuration';

// Constants
export { AnalyticsConstants, type AnalyticsConstantsType } from './Constants';
