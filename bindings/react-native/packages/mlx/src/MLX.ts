/**
 * Apple MLX backend registration for the RunAnywhere React Native SDK.
 *
 * Public model lifecycle and inference APIs remain in `@runanywhere/core`.
 * This facade only connects the linked Swift MLX runtime to the commons
 * backend registry through core's existing Nitro bridge.
 */

import {
  isNativeModuleAvailable,
  requireNativeModule,
  SDKLogger,
} from '@runanywhere/core/internal';

const logger = new SDKLogger('MLX');
const DEFAULT_PRIORITY = 100;

export const MLX = {
  /** Version of the canonical Swift MLX runtime API. */
  version: '1.0.0',

  /** Register the linked Apple MLX runtime with the native backend registry. */
  async register(priority = DEFAULT_PRIORITY): Promise<boolean> {
    if (!Number.isFinite(priority)) {
      throw new RangeError('MLX backend priority must be a finite number');
    }
    if (!isNativeModuleAvailable()) {
      logger.warning(
        'Core native module not available; MLX registration skipped'
      );
      return false;
    }

    const native = requireNativeModule();
    if (!(await native.mlxRuntimeAvailable())) {
      logger.warning(
        'MLX runtime unavailable. Use a physical iOS device and ensure @runanywhere/mlx is installed with CocoaPods.'
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

  /** Unregister the MLX runtime from the native backend registry. */
  async unregister(): Promise<boolean> {
    if (!isNativeModuleAvailable()) return false;
    const unregistered = await requireNativeModule().mlxUnregisterBackend();
    if (unregistered) {
      logger.info('MLX backend unregistered');
    }
    return unregistered;
  },

  /** Return whether the MLX runtime is currently registered. */
  async isRegistered(): Promise<boolean> {
    if (!isNativeModuleAvailable()) return false;
    return requireNativeModule().mlxIsBackendRegistered();
  },

  /**
   * Return whether a linked Apple MLX runtime can execute on this target.
   *
   * The iOS Simulator is intentionally unavailable; its arm64 slice supports
   * package, compile, and link validation only.
   */
  async isAvailable(): Promise<boolean> {
    if (!isNativeModuleAvailable()) return false;
    return requireNativeModule().mlxRuntimeAvailable();
  },
};
