/**
 * Focused VLM browser gate.
 *
 * Opt-in (`RA_RUN_VLM_E2E=1` or `RA_RUN_FULL_E2E=1`). Loads SmolVLM and
 * runs a file-based image analysis through the example Vision tab.
 */
import { test } from '@playwright/test';
import { existsSync } from 'node:fs';
import {
  RELEASE_E2E_ENABLED,
  RELEASE_MODELS,
  IMAGE_FIXTURE,
  ensureModelReady,
  expectSubstantiveText,
  navigateTo,
  waitForInteractive,
} from './support/release-harness';

const shouldRun = RELEASE_E2E_ENABLED || process.env.RA_RUN_VLM_E2E === '1';

test.describe('VLM generate focused E2E', () => {
  test.skip(!shouldRun, 'Set RA_RUN_VLM_E2E=1 or RA_RUN_FULL_E2E=1 to run real VLM inference.');
  test.skip(!existsSync(IMAGE_FIXTURE), `Missing image fixture: ${IMAGE_FIXTURE}`);

  test('analyzes an attached image with a non-empty streamed answer', async ({ page }) => {
    test.setTimeout(45 * 60_000);
    await page.goto('/', { waitUntil: 'domcontentloaded' });
    await waitForInteractive(page);
    await navigateTo(page, 'vision');
    await ensureModelReady(page, '#vision-model-btn, #chat-toolbar-model', RELEASE_MODELS.vlm);

    const fileInput = page.locator('#vision-file-input, input[type="file"]').first();
    await fileInput.setInputFiles(IMAGE_FIXTURE);

    const analyze = page.locator('#vision-analyze-btn, button').filter({ hasText: /Analyze|Process/i }).first();
    await analyze.click();

    await expectSubstantiveText(
      page.locator('#vision-result, .vision-result, .chat-message--assistant .chat-bubble').last(),
      { minLength: 8, timeout: 15 * 60_000 },
    );
  });
});
