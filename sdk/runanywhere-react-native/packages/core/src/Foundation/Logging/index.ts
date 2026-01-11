/**
 * Logging Module
 *
 * Centralized logging infrastructure with multiple destination support.
 * Supports environment-based configuration and multiple log destinations (Console, Sentry, etc.)
 *
 * Matches iOS: sdk/runanywhere-swift/Sources/RunAnywhere/Infrastructure/Logging/
 *
 * Usage:
 *   import { SDKLogger, LoggingManager, SDKEnvironment, SentryDestination } from '@runanywhere/core';
 *
 *   // Configure for production
 *   LoggingManager.shared.applyEnvironmentConfiguration(SDKEnvironment.Production);
 *
 *   // Add Sentry destination (optional)
 *   LoggingManager.shared.addDestination(new SentryDestination(Sentry));
 *
 *   // Use loggers
 *   SDKLogger.llm.info('Model loaded', { modelId: 'llama-3.2' });
 */

// Logger
export { SDKLogger } from './Logger/SDKLogger';

// Log levels
export { LogLevel, getLogLevelDescription } from './Models/LogLevel';

// Configuration
export {
  type LoggingConfiguration,
  SDKEnvironment,
  developmentConfig,
  stagingConfig,
  productionConfig,
  getConfigurationForEnvironment,
  createLoggingConfiguration,
} from './Models/LoggingConfiguration';

// Logging manager with destinations
export {
  LoggingManager,
  ConsoleLogDestination,
  EventLogDestination,
  type LogDestination,
  type LogEntry,
  type LogEventCallback,
} from './Services/LoggingManager';

// Sentry destination
export {
  SentryDestination,
  type SentryInterface,
} from './Destinations/SentryDestination';

// Native log bridge (for receiving logs from iOS/Android)
export {
  NativeLogBridge,
  type NativeLogEntryData,
} from './Destinations/NativeLogBridge';
