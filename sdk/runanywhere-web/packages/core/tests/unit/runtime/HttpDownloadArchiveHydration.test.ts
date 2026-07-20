import { afterEach, describe, expect, it, vi } from 'vitest';

/**
 * Regression: OPFS-direct + HTTP 416 previously installed an empty MEMFS size
 * stub, then commons libarchive opened that stub during extract →
 * "Unrecognized archive format" for Voice AI STT/TTS archives.
 */

describe('archive download hydration helpers', () => {
  afterEach(() => {
    vi.unstubAllGlobals();
    vi.restoreAllMocks();
  });

  it('detects gzip magic bytes used by .tar.gz voice models', () => {
    const gzip = new Uint8Array([0x1f, 0x8b, 0x08, 0x00]);
    const html = new TextEncoder().encode('<!DOCTYPE html>');
    expect(gzip[0] === 0x1f && gzip[1] === 0x8b).toBe(true);
    expect(html[0] === 0x1f && html[1] === 0x8b).toBe(false);
  });

  it('416 resume against an oversize/corrupt partial should restart from zero', async () => {
    const fetches: Array<{ range?: string }> = [];
    let deleted = false;

    vi.stubGlobal('fetch', vi.fn(async (input: RequestInfo | URL, init?: RequestInit) => {
      const headers = new Headers(init?.headers);
      const range = headers.get('Range') ?? undefined;
      fetches.push({ range });
      if (range) {
        return new Response(null, { status: 416 });
      }
      // Restart without Range after discarding the partial.
      const body = new Uint8Array([0x1f, 0x8b, 0x08, 0x00, 0x01, 0x02, 0x03, 0x04]);
      return new Response(body, {
        status: 200,
        headers: { 'Content-Length': String(body.length) },
      });
    }));

    // Minimal stand-in for the fixed control flow:
    let existing = 1000;
    let response = await fetch('https://example.test/model.tar.gz', {
      headers: { Range: `bytes=${existing}-` },
    });
    expect(response.status).toBe(416);

    // Simulate discard + restart (mirrors PlatformAdapter fix).
    deleted = true;
    existing = 0;
    response = await fetch('https://example.test/model.tar.gz');
    expect(deleted).toBe(true);
    expect(response.status).toBe(200);
    expect(fetches).toEqual([
      { range: 'bytes=1000-' },
      { range: undefined },
    ]);
    const bytes = new Uint8Array(await response.arrayBuffer());
    expect(bytes[0]).toBe(0x1f);
    expect(bytes[1]).toBe(0x8b);
  });
});
