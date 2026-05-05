import {
  HardwareProfileResult,
  type AccelerationPreference,
  type HardwareProfileResult as ProtoHardwareProfileResult,
} from '@runanywhere/proto-ts/hardware_profile';
import { SDKLogger } from '../Foundation/SDKLogger';
import { ProtoWasmBridge, type ProtoWasmModule, formatRacResult } from '../runtime/ProtoWasm';

const logger = new SDKLogger('HardwareAdapter');
const RAC_SUCCESS = 0;

export interface HardwareModule extends ProtoWasmModule {
  _rac_hardware_profile_get?(protoBytesOut: number, protoSizeOut: number): number;
  _rac_hardware_profile_free?(protoBytes: number): void;
  _rac_hardware_get_accelerators?(protoBytesOut: number, protoSizeOut: number): number;
  _rac_hardware_set_accelerator_preference?(preference: number): number;
}

let defaultModule: HardwareModule | null = null;

export class HardwareAdapter {
  static setDefaultModule(module: HardwareModule): void {
    defaultModule = module;
  }

  static clearDefaultModule(): void {
    defaultModule = null;
  }

  static tryDefault(): HardwareAdapter | null {
    return defaultModule ? new HardwareAdapter(defaultModule) : null;
  }

  constructor(private readonly module: HardwareModule) {}

  supportsProtoHardware(): boolean {
    return this.missingExports().length === 0;
  }

  getProfile(): ProtoHardwareProfileResult | null {
    if (!this.ensureExports('getProfile', ['_rac_hardware_profile_get'])) return null;
    const bytes = this.readOwnedHardwareBytes(
      (outBytesPtr, outSizePtr) => (
        this.module._rac_hardware_profile_get!(outBytesPtr, outSizePtr)
      ),
      'rac_hardware_profile_get',
    );
    return bytes ? HardwareProfileResult.decode(bytes) : null;
  }

  getAccelerators(): ProtoHardwareProfileResult | null {
    if (!this.ensureExports('getAccelerators', ['_rac_hardware_get_accelerators'])) {
      return null;
    }
    const bytes = this.readOwnedHardwareBytes(
      (outBytesPtr, outSizePtr) => (
        this.module._rac_hardware_get_accelerators!(outBytesPtr, outSizePtr)
      ),
      'rac_hardware_get_accelerators',
    );
    return bytes ? HardwareProfileResult.decode(bytes) : null;
  }

  setAccelerationPreference(preference: AccelerationPreference): boolean {
    if (!this.ensureExports('setAccelerationPreference', [
      '_rac_hardware_set_accelerator_preference',
    ])) {
      return false;
    }
    const rc = this.module._rac_hardware_set_accelerator_preference!(preference);
    if (rc !== RAC_SUCCESS) {
      logger.warning(
        `rac_hardware_set_accelerator_preference returned ${formatRacResult(rc)}`,
      );
      return false;
    }
    return true;
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }

  private missingExports(): string[] {
    const required: Array<keyof HardwareModule> = [
      '_malloc',
      '_free',
      'HEAPU8',
      '_rac_hardware_profile_get',
      '_rac_hardware_profile_free',
      '_rac_hardware_get_accelerators',
      '_rac_hardware_set_accelerator_preference',
    ];
    return required.filter((key) => !this.module[key]).map(String);
  }

  private ensureExports(
    operation: string,
    required: Array<keyof HardwareModule>,
  ): boolean {
    const missing = [
      '_malloc',
      '_free',
      'HEAPU8',
      '_rac_hardware_profile_free',
      ...required,
    ].filter((key) => !this.module[key as keyof HardwareModule]);
    if (missing.length > 0) {
      logger.warning(`${operation}: module missing hardware proto exports: ${missing.join(', ')}`);
      return false;
    }
    return true;
  }

  private readOwnedHardwareBytes(
    call: (outBytesPtr: number, outSizePtr: number) => number,
    functionName: string,
  ): Uint8Array | null {
    const bridge = this.bridge();
    const outBytesPtr = bridge.allocOutPtr();
    const outSizePtr = bridge.allocOutPtr();
    if (!outBytesPtr || !outSizePtr) {
      bridge.free(outBytesPtr);
      bridge.free(outSizePtr);
      logger.warning(`${functionName}: failed to allocate output pointers`);
      return null;
    }

    try {
      const rc = call(outBytesPtr, outSizePtr);
      if (rc !== RAC_SUCCESS) {
        logger.warning(`${functionName} returned ${formatRacResult(rc)}`);
        return null;
      }

      const bytesPtr = bridge.readU32(outBytesPtr);
      const size = bridge.readU32(outSizePtr);
      if (!bytesPtr || size === 0) {
        if (bytesPtr) this.module._rac_hardware_profile_free!(bytesPtr);
        return new Uint8Array();
      }

      const bytes = this.module.HEAPU8!.slice(bytesPtr, bytesPtr + size);
      this.module._rac_hardware_profile_free!(bytesPtr);
      return bytes;
    } finally {
      bridge.free(outBytesPtr);
      bridge.free(outSizePtr);
    }
  }
}
