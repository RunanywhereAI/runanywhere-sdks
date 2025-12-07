/**
 * RunAnywhere React Native SDK - Native Module
 *
 * Provides access to native AI capabilities.
 * Automatically uses Nitrogen when available, falls back to legacy TurboModule.
 */

// Primary exports (auto-selects best implementation)
export {
  NativeRunAnywhere,
  isNativeModuleAvailable,
  isUsingNitrogen,
  requireNativeModule,
} from './NativeRunAnywhere';
export type { NativeRunAnywhereModule } from './NativeRunAnywhere';

// Nitrogen HybridObject exports (for direct access when needed)
export {
  getRunAnywhere,
  getFileSystem,
  getDeviceInfo,
  isNitroAvailable,
} from './NitroModules';
export type {
  RunAnywhere as NitroRunAnywhere,
  RunAnywhereFileSystem as NitroFileSystem,
  RunAnywhereDeviceInfo as NitroDeviceInfo,
} from './NitroModules';
