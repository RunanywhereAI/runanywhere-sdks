/**
 * Focused browser gate for the exact pinned Nemotron 3.5 Sherpa-ONNX bundle.
 *
 * This is opt-in because a clean profile downloads 682,215,356 model bytes.
 * It drives the public Web example picker and file-upload surface, while a
 * thin recorder observes the public RunAnywhere.transcribeStream() iterator.
 *
 * Run:
 *   RA_RUN_NEMOTRON_E2E=1 npx playwright test tests/browser/nemotron-streaming.e2e.spec.ts
 */
import { createHash } from 'node:crypto';
import { Buffer } from 'node:buffer';
import type { Page } from '@playwright/test';
import {
  ensureModelReady,
  expect,
  navigateTo,
  test,
  waitForInteractive,
} from './support/release-harness';

const ENABLED = process.env.RA_RUN_NEMOTRON_E2E === '1';
const MODEL = {
  id: 'sherpa-nemotron-3.5-asr-streaming-0.6b-560ms-int8',
  query: 'Nemotron 3.5',
} as const;
const REVISION = 'ab43d895f5985b1bbab8b6eac8607fcdc05343f3';
const FIXTURE_URL =
  'https://huggingface.co/csukuangfj2/'
  + 'sherpa-onnx-nemotron-3.5-asr-streaming-0.6b-560ms-int8-2026-06-11/'
  + `resolve/${REVISION}/test_wavs/en.wav?download=true`;
const FIXTURE_SIZE = 228_908;
const FIXTURE_SHA256 = 'eb1eb008904465b74c304aad8342e8c7d3c6e61ffe9f66adcaca9cf0f76a93f4';
const REFERENCE_TRANSCRIPT =
  'The Tribal Chief then called for the boy and presented him with fifty pieces of gold.';
const EXPECTED_TRANSCRIPT = /called for the boy.+fifty pieces of gold/i;
const STT_LANGUAGE_EN = 2;

interface StreamRecord {
  text: string;
  isFinal: boolean;
  language: number;
  requestId: string;
  finalText: string;
  finalLanguage: number;
  finalDurationMs: number;
}

test.describe('Nemotron 3.5 ASR Streaming 0.6B INT8 — pinned Web runtime', () => {
  test.skip(
    !ENABLED,
    'Set RA_RUN_NEMOTRON_E2E=1 to download and infer with the 682 MB pinned bundle.',
  );

  test('persists, loads, streams partials, and drains the final token on normal stop', async ({
    appPage,
  }) => {
    test.setTimeout(45 * 60_000);

    const fixture = await downloadPinnedFixture();
    await appPage.goto('/', { waitUntil: 'domcontentloaded' });
    await waitForInteractive(appPage);
    await navigateTo(appPage, 'transcribe');
    await ensureModelReady(appPage, '#transcribe-model-btn', MODEL, {
      downloadTimeout: 30 * 60_000,
      loadTimeout: 12 * 60_000,
    });

    await installStreamRecorder(appPage);
    try {
      await appPage.locator('#mode-live-btn').click();
      await appPage.locator('#file-input').setInputFiles({
        name: 'nemotron-en.wav',
        mimeType: 'audio/wav',
        buffer: fixture,
      });

      await expect.poll(async () => {
        const records = await recordedStream(appPage);
        return records.some(({ isFinal }) => isFinal);
      }, {
        message: 'normal stop must drain one terminal Nemotron result',
        timeout: 10 * 60_000,
      }).toBe(true);
      await expect(appPage.locator('#transcribe-output')).toHaveText(EXPECTED_TRANSCRIPT);

      const records = await recordedStream(appPage);
      const partials = records.filter(({ isFinal, text }) => !isFinal && text.length > 0);
      const finals = records.filter(({ isFinal }) => isFinal);
      expect(partials.length, JSON.stringify(records, null, 2)).toBeGreaterThan(0);
      expect(finals, JSON.stringify(records, null, 2)).toHaveLength(1);
      expect(records.at(-1)?.isFinal).toBe(true);

      const final = finals[0];
      expect(final?.text).toMatch(EXPECTED_TRANSCRIPT);
      expect(final?.finalText).toBe(final?.text);
      const wer = normalizedWordErrorRate(REFERENCE_TRANSCRIPT, final?.text ?? '');
      console.info(`[nemotron-e2e] normalized WER=${wer.toFixed(4)} transcript="${final?.text}"`);
      expect(wer, `transcript: ${final?.text}`).toBeLessThanOrEqual(0.25);
      expect(final?.language).toBe(STT_LANGUAGE_EN);
      expect(final?.finalLanguage).toBe(STT_LANGUAGE_EN);
      expect(final?.finalDurationMs).toBeGreaterThanOrEqual(7_100);
      expect(final?.requestId).toMatch(/^stt-lifecycle-/);
      expect(records.every(({ requestId }) => requestId === final?.requestId)).toBe(true);
      await appPage.waitForTimeout(500);
      expect(await recordedStream(appPage), 'no event may arrive after terminal stop').toEqual(
        records,
      );
    } finally {
      await uninstallStreamRecorder(appPage);
    }
  });
});

async function downloadPinnedFixture(): Promise<Buffer> {
  const response = await fetch(FIXTURE_URL);
  if (!response.ok) {
    throw new Error(`Pinned Nemotron fixture download failed: HTTP ${response.status}`);
  }
  const fixture = Buffer.from(await response.arrayBuffer());
  expect(fixture.byteLength).toBe(FIXTURE_SIZE);
  expect(createHash('sha256').update(fixture).digest('hex')).toBe(FIXTURE_SHA256);
  return fixture;
}

function normalizedWordErrorRate(reference: string, hypothesis: string): number {
  const words = (value: string): string[] => (
    value.toLowerCase().replace(/[^\p{L}\p{N}]+/gu, ' ').trim().split(/\s+/u).filter(Boolean)
  );
  const expected = words(reference);
  const actual = words(hypothesis);
  let previous = Array.from({ length: actual.length + 1 }, (_, index) => index);

  for (let row = 1; row <= expected.length; row += 1) {
    const current = [row];
    for (let column = 1; column <= actual.length; column += 1) {
      const substitutionCost = expected[row - 1] === actual[column - 1] ? 0 : 1;
      current[column] = Math.min(
        (previous[column] ?? 0) + 1,
        (current[column - 1] ?? 0) + 1,
        (previous[column - 1] ?? 0) + substitutionCost,
      );
    }
    previous = current;
  }

  return (previous[actual.length] ?? expected.length) / Math.max(expected.length, 1);
}

async function installStreamRecorder(page: Page): Promise<void> {
  await page.evaluate(() => {
    interface STTOutputProbe {
      text?: string;
      language?: number;
      durationMs?: number;
    }
    interface STTPartialProbe {
      text: string;
      isFinal: boolean;
      language?: number;
      requestId?: string;
      finalOutput?: STTOutputProbe;
    }
    type STTStream = (...args: unknown[]) => AsyncIterable<STTPartialProbe>;
    const target = window as Window & {
      __RUNANYWHERE_SDK__?: { transcribeStream?: STTStream };
      __RA_NEMOTRON_STREAM__?: StreamRecord[];
      __RA_NEMOTRON_ORIGINAL__?: STTStream;
    };
    const sdk = target.__RUNANYWHERE_SDK__;
    if (!sdk?.transcribeStream) throw new Error('RunAnywhere.transcribeStream is unavailable');
    target.__RA_NEMOTRON_ORIGINAL__ = sdk.transcribeStream;
    target.__RA_NEMOTRON_STREAM__ = [];
    sdk.transcribeStream = (...args: unknown[]): AsyncIterable<STTPartialProbe> => {
      const source = target.__RA_NEMOTRON_ORIGINAL__!.apply(sdk, args);
      return {
        async *[Symbol.asyncIterator](): AsyncGenerator<STTPartialProbe> {
          for await (const partial of source) {
            target.__RA_NEMOTRON_STREAM__?.push({
              text: partial.text.trim(),
              isFinal: partial.isFinal === true,
              language: partial.language ?? 0,
              requestId: partial.requestId ?? '',
              finalText: partial.finalOutput?.text?.trim() ?? '',
              finalLanguage: partial.finalOutput?.language ?? 0,
              finalDurationMs: partial.finalOutput?.durationMs ?? 0,
            });
            yield partial;
          }
        },
      };
    };
  });
}

async function recordedStream(page: Page): Promise<StreamRecord[]> {
  return page.evaluate(() => (
    (window as Window & { __RA_NEMOTRON_STREAM__?: StreamRecord[] })
      .__RA_NEMOTRON_STREAM__ ?? []
  ));
}

async function uninstallStreamRecorder(page: Page): Promise<void> {
  await page.evaluate(() => {
    type STTStream = (...args: unknown[]) => AsyncIterable<unknown>;
    const target = window as Window & {
      __RUNANYWHERE_SDK__?: { transcribeStream?: STTStream };
      __RA_NEMOTRON_STREAM__?: StreamRecord[];
      __RA_NEMOTRON_ORIGINAL__?: STTStream;
    };
    if (target.__RUNANYWHERE_SDK__ && target.__RA_NEMOTRON_ORIGINAL__) {
      target.__RUNANYWHERE_SDK__.transcribeStream = target.__RA_NEMOTRON_ORIGINAL__;
    }
    delete target.__RA_NEMOTRON_STREAM__;
    delete target.__RA_NEMOTRON_ORIGINAL__;
  });
}
