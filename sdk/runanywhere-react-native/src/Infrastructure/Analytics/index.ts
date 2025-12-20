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

// Component-specific analytics services
export { LLMAnalyticsService, STTAnalyticsService, TTSAnalyticsService } from './Services';

// Storage adapters (examples)
export {
  AsyncStorageAdapter,
  CustomStorageAdapter,
  getPlatformStorage,
  initializeAnalytics,
  setupAnalyticsWithAsyncStorage,
} from './AsyncStorageAdapter.example';
