/**
 * RunAnywhere+Device.ts
 *
 * NPU chip detection extension. Android only.
 * Returns null on iOS and other platforms.
 */

import { Platform } from 'react-native';
import { requireDeviceInfoModule } from '../../native/NativeRunAnywhereCore';
import { npuChipFromSocModel } from '../../types/NPUChip';
import { SDKLogger } from '../../Foundation/Logging/Logger/SDKLogger';
import type { NPUChip } from '../../types/NPUChip';

const logger = new SDKLogger('RunAnywhere.Device');

/**
 * Detect the device's NPU chipset for Genie model compatibility.
 *
 * Returns the NPUChip if the device has a supported Qualcomm SoC,
 * or null if the device is not Android or does not support NPU inference.
 *
 * @example
 * ```typescript
 * const chip = await getChip();
 * if (chip) {
 *   const url = getNPUDownloadUrl(chip, 'qwen');
 *   await RunAnywhere.registerModel({ id: 'qwen-npu', name: 'Qwen NPU', url, ... });
 * }
 * ```
 */
export async function getChip(): Promise<NPUChip | null> {
  if (Platform.OS !== 'android') {
    return null;
  }

  try {
    const deviceInfo = requireDeviceInfoModule();
    const chipName = await deviceInfo.getChipName();

    if (!chipName || chipName === 'Unknown') {
      logger.debug('No chip name available from device info');
      return null;
    }

    const chip = npuChipFromSocModel(chipName);
    if (chip) {
      logger.info(
        `Detected NPU chip: ${chip.displayName} (chipName=${chipName})`
      );
    } else {
      logger.debug(`No supported NPU chip for: ${chipName}`);
    }

    return chip ?? null;
  } catch (error) {
    logger.debug('Failed to detect NPU chip');
    return null;
  }
}
