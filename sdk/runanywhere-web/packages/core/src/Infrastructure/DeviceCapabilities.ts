/**
 * RunAnywhere Web SDK - Device Capabilities
 *
 * Detects browser capabilities relevant to on-device AI inference:
 * WebGPU, SharedArrayBuffer (for pthreads), WASM SIMD, etc.
 */

import type { DeviceInfoData } from '../types/models';
import { SDKLogger } from '../Foundation/SDKLogger';
import type { AccelerationMode } from '../Foundation/WASMBridge';

const logger = new SDKLogger('DeviceCapabilities');

export interface WebCapabilities {
  /** WebGPU available and functional */
  hasWebGPU: boolean;
  /** WebGPU adapter info (if available) */
  gpuAdapterInfo?: Record<string, string>;
  /** The acceleration mode actually in use by the WASM module ('webgpu' | 'cpu'). */
  activeAcceleration: AccelerationMode;
  /** SharedArrayBuffer available (needed for pthreads/multithreaded WASM) */
  hasSharedArrayBuffer: boolean;
  /** Cross-Origin Isolation enabled (required for SharedArrayBuffer) */
  isCrossOriginIsolated: boolean;
  /** WebAssembly SIMD supported */
  hasWASMSIMD: boolean;
  /** Origin Private File System available */
  hasOPFS: boolean;
  /** Estimated device memory (GB) */
  deviceMemoryGB: number;
  /** Number of logical CPU cores */
  hardwareConcurrency: number;
  /** User agent string */
  userAgent: string;
}

/**
 * Detect all browser capabilities relevant to AI inference.
 */
export async function detectCapabilities(): Promise<WebCapabilities> {
  // Import WASMBridge lazily to avoid circular imports at module level
  const { WASMBridge } = await import('../Foundation/WASMBridge');

  const capabilities: WebCapabilities = {
    hasWebGPU: false,
    activeAcceleration: WASMBridge.shared.isLoaded ? WASMBridge.shared.accelerationMode : 'cpu',
    hasSharedArrayBuffer: typeof SharedArrayBuffer !== 'undefined',
    isCrossOriginIsolated: typeof crossOriginIsolated !== 'undefined' ? crossOriginIsolated : false,
    hasWASMSIMD: detectWASMSIMD(),
    hasOPFS: typeof navigator !== 'undefined' && 'storage' in navigator && 'getDirectory' in navigator.storage,
    deviceMemoryGB: (navigator as NavigatorWithDeviceMemory).deviceMemory ?? 4,
    hardwareConcurrency: navigator.hardwareConcurrency ?? 4,
    userAgent: navigator.userAgent,
  };

  // Detect WebGPU
  if (typeof navigator !== 'undefined' && 'gpu' in navigator) {
    try {
      const gpu = (navigator as NavigatorWithGPU).gpu;
      const adapter = await gpu?.requestAdapter();
      if (adapter) {
        capabilities.hasWebGPU = true;
        try {
          const info = await (adapter as GPUAdapterWithInfo).requestAdapterInfo();
          capabilities.gpuAdapterInfo = {
            vendor: info.vendor ?? '',
            architecture: info.architecture ?? '',
            description: info.description ?? '',
          };
        } catch { /* adapter info not available */ }
      }
    } catch {
      logger.debug('WebGPU detection failed');
    }
  }

  logger.info(
    `Capabilities: WebGPU=${capabilities.hasWebGPU}, ` +
    `SharedArrayBuffer=${capabilities.hasSharedArrayBuffer}, ` +
    `SIMD=${capabilities.hasWASMSIMD}, ` +
    `OPFS=${capabilities.hasOPFS}, ` +
    `Memory=${capabilities.deviceMemoryGB}GB, ` +
    `Cores=${capabilities.hardwareConcurrency}`,
  );

  return capabilities;
}

/**
 * Build a DeviceInfoData from detected capabilities.
 */
export async function getDeviceInfo(): Promise<DeviceInfoData> {
  const caps = await detectCapabilities();

  return {
    model: 'Browser',
    name: getBrowserName(caps.userAgent),
    osVersion: getOSVersion(caps.userAgent),
    totalMemory: caps.deviceMemoryGB * 1024 * 1024 * 1024,
    architecture: 'wasm32',
    hasWebGPU: caps.hasWebGPU,
    hasSharedArrayBuffer: caps.hasSharedArrayBuffer,
  };
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function detectWASMSIMD(): boolean {
  try {
    // Check for WASM SIMD support by validating a minimal SIMD module
    const simdTest = new Uint8Array([
      0, 97, 115, 109, 1, 0, 0, 0, 1, 5, 1, 96, 0, 1, 123, 3, 2, 1, 0,
      10, 10, 1, 8, 0, 65, 0, 253, 15, 253, 98, 11,
    ]);
    return WebAssembly.validate(simdTest);
  } catch {
    return false;
  }
}

function getBrowserName(ua: string): string {
  if (ua.includes('Firefox')) return 'Firefox';
  if (ua.includes('Edg/')) return 'Edge';
  if (ua.includes('Chrome')) return 'Chrome';
  if (ua.includes('Safari')) return 'Safari';
  return 'Unknown Browser';
}

function getOSVersion(ua: string): string {
  if (ua.includes('Windows')) return 'Windows';
  if (ua.includes('Mac OS X')) return 'macOS';
  if (ua.includes('Linux')) return 'Linux';
  if (ua.includes('Android')) return 'Android';
  if (ua.includes('iOS')) return 'iOS';
  return 'Unknown OS';
}

interface NavigatorWithDeviceMemory extends Navigator {
  deviceMemory?: number;
}

interface NavigatorWithGPU extends Navigator {
  gpu?: {
    requestAdapter: () => Promise<GPUAdapterWithInfo | null>;
  };
}

interface GPUAdapterWithInfo {
  requestAdapterInfo: () => Promise<{
    vendor?: string;
    architecture?: string;
    description?: string;
  }>;
}
