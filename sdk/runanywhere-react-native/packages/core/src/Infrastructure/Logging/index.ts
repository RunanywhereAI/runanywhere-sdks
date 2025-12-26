/**
 * Logging Infrastructure
 * RunAnywhere SDK
 *
 * Logging infrastructure components.
 * Matches iOS SDK: Infrastructure/Logging/
 */

// Errors
export { LoggingError, LoggingErrorCode, isLoggingError } from './Errors';

// Configuration
export {
  type LoggingConfiguration,
  DEFAULT_LOGGING_CONFIGURATION,
  LoggingConfigurationPresets,
  createLoggingConfiguration,
  validateLoggingConfiguration,
  LoggingConfigurationBuilder,
} from './Models/Configuration';
