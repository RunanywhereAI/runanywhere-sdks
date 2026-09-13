import { afterEach, describe, expect, it, vi } from 'vitest';
import { __testing__ } from '../../../../../src/Public/API/Namespaces/models.js';

const {
  probeAvailableRamBytes,
  probeAvailableStorageBytes,
  KNOWN_EXHAUSTED_BYTES_SENTINEL,
} = __testing__;

describe('models platform probes', () => {
  afterEach(() => {
    vi.restoreAllMocks();
  });

  describe('probeAvailableStorageBytes', () => {
    it('returns positive free bytes when quota > usage', async () => {
      vi.stubGlobal('navigator', {
        storage: {
          estimate: vi.fn().mockResolvedValue({
            quota: 10_000_000,
            usage: 4_000_000,
          }),
        },
      });

      const free = await probeAvailableStorageBytes();
      expect(free).toBe(6_000_000);
    });

    it('returns KNOWN_EXHAUSTED_BYTES_SENTINEL (1 byte) when quota is known and exhausted (usage >= quota)', async () => {
      vi.stubGlobal('navigator', {
        storage: {
          estimate: vi.fn().mockResolvedValue({
            quota: 10_000_000,
            usage: 10_000_000,
          }),
        },
      });

      const free = await probeAvailableStorageBytes();
      expect(free).toBe(KNOWN_EXHAUSTED_BYTES_SENTINEL);
      expect(free).toBe(1);
    });

    it('returns KNOWN_EXHAUSTED_BYTES_SENTINEL when usage exceeds quota', async () => {
      vi.stubGlobal('navigator', {
        storage: {
          estimate: vi.fn().mockResolvedValue({
            quota: 10_000_000,
            usage: 12_000_000,
          }),
        },
      });

      const free = await probeAvailableStorageBytes();
      expect(free).toBe(KNOWN_EXHAUSTED_BYTES_SENTINEL);
    });

    it('returns 0 (unknown) when quota is missing or 0', async () => {
      vi.stubGlobal('navigator', {
        storage: {
          estimate: vi.fn().mockResolvedValue({
            quota: 0,
            usage: 0,
          }),
        },
      });

      const free = await probeAvailableStorageBytes();
      expect(free).toBe(0);
    });

    it('returns 0 (unknown) when estimate() throws', async () => {
      vi.stubGlobal('navigator', {
        storage: {
          estimate: vi.fn().mockRejectedValue(new Error('Storage estimate failed')),
        },
      });

      const free = await probeAvailableStorageBytes();
      expect(free).toBe(0);
    });

    it('returns 0 (unknown) when navigator.storage is undefined', async () => {
      vi.stubGlobal('navigator', {});

      const free = await probeAvailableStorageBytes();
      expect(free).toBe(0);
    });

    it('returns 0 (unknown) when estimate usage is NaN', async () => {
      vi.stubGlobal('navigator', {
        storage: {
          estimate: vi.fn().mockResolvedValue({
            quota: 10_000_000,
            usage: NaN,
          }),
        },
      });

      const free = await probeAvailableStorageBytes();
      expect(free).toBe(0);
    });

    it('returns 0 (unknown) when estimate quota is NaN', async () => {
      vi.stubGlobal('navigator', {
        storage: {
          estimate: vi.fn().mockResolvedValue({
            quota: NaN,
            usage: 5_000_000,
          }),
        },
      });

      const free = await probeAvailableStorageBytes();
      expect(free).toBe(0);
    });
  });

  describe('probeAvailableRamBytes', () => {
    it('returns bytes when deviceMemory is a positive number', () => {
      vi.stubGlobal('navigator', {
        deviceMemory: 8,
      });

      const ram = probeAvailableRamBytes();
      expect(ram).toBe(8 * 1024 * 1024 * 1024);
    });

    it('returns KNOWN_EXHAUSTED_BYTES_SENTINEL (1 byte) when deviceMemory is 0', () => {
      vi.stubGlobal('navigator', {
        deviceMemory: 0,
      });

      const ram = probeAvailableRamBytes();
      expect(ram).toBe(KNOWN_EXHAUSTED_BYTES_SENTINEL);
      expect(ram).toBe(1);
    });

    it('returns 0 (unknown) when deviceMemory is undefined', () => {
      vi.stubGlobal('navigator', {});

      const ram = probeAvailableRamBytes();
      expect(ram).toBe(0);
    });

    it('returns 0 (unknown) when deviceMemory is not a number', () => {
      vi.stubGlobal('navigator', {
        deviceMemory: 'unknown',
      });

      const ram = probeAvailableRamBytes();
      expect(ram).toBe(0);
    });

    it('returns 0 (unknown) when deviceMemory is NaN', () => {
      vi.stubGlobal('navigator', {
        deviceMemory: NaN,
      });

      const ram = probeAvailableRamBytes();
      expect(ram).toBe(0);
    });
  });
});
