import { detectCapabilities, type WebCapabilities } from '../../Infrastructure/DeviceCapabilities.js';

/**
 * Browser hardware details used to choose model sizes and acceleration.
 * This is a Web helper, not a native hardware-profile replacement.
 */
export const Hardware = {
  profile(): Promise<WebCapabilities> {
    return detectCapabilities();
  },
};

export type { WebCapabilities };
