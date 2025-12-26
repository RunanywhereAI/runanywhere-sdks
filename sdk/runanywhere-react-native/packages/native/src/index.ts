/**
 * @runanywhere/native - Native bindings for RunAnywhere React Native SDK
 *
 * This package provides the native bridge layer including:
 * - Nitro HybridObjects for JSI communication
 * - XCFramework (iOS) with runanywhere-core
 * - JNI libs (Android) with runanywhere-core
 *
 * @packageDocumentation
 */

// Primary exports (auto-selects best implementation)
export {
  NativeRunAnywhere,
  NativeRunAnywhereFileSystem,
  NativeRunAnywhereDeviceInfo,
  isNativeModuleAvailable,
  isUsingNitrogen,
  requireNativeModule,
  requireFileSystemModule,
  requireDeviceInfoModule,
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

// Re-export Nitro specs for type consumers
export type { RunAnywhere } from './specs/RunAnywhere.nitro';
export type { RunAnywhereFileSystem } from './specs/RunAnywhereFileSystem.nitro';
export type { RunAnywhereDeviceInfo } from './specs/RunAnywhereDeviceInfo.nitro';
