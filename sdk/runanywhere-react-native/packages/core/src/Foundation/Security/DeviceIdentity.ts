/**
 * DeviceIdentity.ts
 *
 * Thin adapter over native persistent device identity. The JS layer does not
 * cache or generate device identifiers.
 */

import { requireNativeCoreModule } from '../../native/NativeRunAnywhereCore';

export const DeviceIdentity = {
  async getPersistentUUID(): Promise<string> {
    return requireNativeCoreModule().getPersistentDeviceUUID();
  },

  getCachedUUID(): string | null {
    return null;
  },

  clearCache(): void {},

  validateUUID(uuid: string): boolean {
    return /^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(
      uuid
    );
  },
};
