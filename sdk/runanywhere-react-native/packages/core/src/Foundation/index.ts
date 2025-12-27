/**
 * Foundation Module
 *
 * Core infrastructure and utilities for the SDK.
 * Matches iOS SDK: Foundation/
 */

// Error Types (matching iOS Foundation/ErrorTypes/)
export * from './ErrorTypes';

// Initialization (matching iOS two-phase initialization pattern)
export * from './Initialization';

// Security (matching iOS Foundation/Security/)
export * from './Security';

// Configuration
export { ConfigurationService } from './Configuration/ConfigurationService';

// Device Identity
export { DeviceIdentityService } from './DeviceIdentity/DeviceIdentityService';

// Dependency Injection
export * from './DependencyInjection';

// File Operations
export { FileManager } from './FileOperations/FileManager';
export {
  ArchiveManager,
  extractArchive,
  isArchive,
  detectArchiveFormat,
} from './FileOperations/ArchiveManager';
export type {
  ArchiveExtractionResult,
  ArchiveFormat,
} from './FileOperations/ArchiveManager';

// Logging
export { SDKLogger } from './Logging/Logger/SDKLogger';
export { LogLevel } from './Logging/Models/LogLevel';
export { LoggingManager } from './Logging/Services/LoggingManager';

// Utilities
export * from './Utilities';
