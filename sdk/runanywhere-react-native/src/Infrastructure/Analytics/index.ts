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
