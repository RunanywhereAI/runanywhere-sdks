import {
  requireNativeModule,
  isNativeModuleAvailable,
  SDKLogger,
} from '@runanywhere/core/internal';

const logger = new SDKLogger('MLX');

/**
 * MLX backend registration facade.
 *
 * Models are still registered through `RunAnywhere.registerModel(...)` /
 * `RunAnywhere.registerMultiFileModel(...)`; this wrapper only installs the
 * Swift MLX callback table into the C++ commons backend.
 */
export const MLX = {
  version: '1.0.0',

  async register(priority = 100): Promise<boolean> {
    if (!isNativeModuleAvailable()) {
      logger.warning(
        'Core native module not available; MLX registration skipped'
      );
      return false;
    }

    const native = requireNativeModule();
    const available = await native.mlxRuntimeAvailable();
    if (!available) {
      logger.warning(
        'MLX Swift runtime not linked. Add the RunAnywhereMLX Swift package product on iOS/macOS.'
      );
      return false;
    }

    const registered = await native.mlxRegisterBackend(priority);
    if (registered) {
      logger.info('MLX backend registered');
    } else {
      logger.warning('MLX backend registration returned false');
    }
    return registered;
  },

  async unregister(): Promise<boolean> {
    if (!isNativeModuleAvailable()) return false;
    const unregistered = await requireNativeModule().mlxUnregisterBackend();
    if (unregistered) {
      logger.info('MLX backend unregistered');
    }
    return unregistered;
  },

  async isRegistered(): Promise<boolean> {
    if (!isNativeModuleAvailable()) return false;
    return requireNativeModule().mlxIsBackendRegistered();
  },

  async isAvailable(): Promise<boolean> {
    if (!isNativeModuleAvailable()) return false;
    return requireNativeModule().mlxRuntimeAvailable();
  },
};
