/**
 * File Management Module
 *
 * File management infrastructure components.
 * Matches iOS SDK: Infrastructure/FileManagement/
 *
 * @module Infrastructure/FileManagement
 */

// Errors subsystem
export * from './Errors';

// Models subsystem
export * from './Models';

// Protocol subsystem
export * from './Protocol';

// Configuration
export {
  type StorageConfiguration,
  CacheEvictionPolicy,
  getCacheEvictionPolicyDescription,
  DEFAULT_STORAGE_CONFIGURATION,
  createStorageConfiguration,
  StorageConfigurationPresets,
} from './Models/Configuration';

// Constants
export { StorageConstants, type StorageConstantsType } from './Constants';
