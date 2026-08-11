/**
 * Focused speech + RAG browser gate.
 *
 * Opt-in (`RA_RUN_SPEECH_E2E=1` or `RA_RUN_FULL_E2E=1`). Covers STT file
 * transcription and a grounded RAG query using the shared release fixtures.
 */
import { test, expect } from '@playwright/test';
import { existsSync } from 'node:fs';
import {
  RELEASE_E2E_ENABLED,
  RELEASE_MODELS,
  AUDIO_FIXTURE,
  RAG_FIXTURE,
  ensureModelReady,
  expectSubstantiveText,
  navigateTo,
  waitForInteractive,
} from './support/release-harness';

const shouldRun = RELEASE_E2E_ENABLED || process.env.RA_RUN_SPEECH_E2E === '1';

test.describe('Speech + RAG focused E2E', () => {
  test.skip(!shouldRun, 'Set RA_RUN_SPEECH_E2E=1 or RA_RUN_FULL_E2E=1 for real speech/RAG inference.');
  test.skip(!existsSync(AUDIO_FIXTURE), `Missing audio fixture: ${AUDIO_FIXTURE}`);
  test.skip(!existsSync(RAG_FIXTURE), `Missing RAG fixture: ${RAG_FIXTURE}`);

  test('transcribes audio and answers a grounded RAG query', async ({ page }) => {
    test.setTimeout(45 * 60_000);
    await page.goto('/', { waitUntil: 'domcontentloaded' });
    await waitForInteractive(page);

    await navigateTo(page, 'stt');
    await ensureModelReady(page, '#stt-model-btn, #chat-toolbar-model', RELEASE_MODELS.stt);
    const audioInput = page.locator('#stt-file-input, input[type="file"]').first();
    await audioInput.setInputFiles(AUDIO_FIXTURE);
    const transcribe = page.locator('#stt-transcribe-btn, button').filter({ hasText: /Transcribe/i }).first();
    if (await transcribe.isVisible().catch(() => false)) {
      await transcribe.click();
      await expectSubstantiveText(
        page.locator('#stt-result, .stt-result').last(),
        { minLength: 3, timeout: 10 * 60_000 },
      );
    }

    await navigateTo(page, 'documents');
    await ensureModelReady(page, '#documents-embedding-model, #chat-toolbar-model', RELEASE_MODELS.embedding);
    await ensureModelReady(page, '#documents-llm-model, #chat-toolbar-model', RELEASE_MODELS.llm);

    const ragInput = page.locator('#rag-file-input, input[type="file"]').first();
    if (await ragInput.count()) {
      await ragInput.setInputFiles(RAG_FIXTURE);
    }

    const question = page.locator('#rag-query-input, textarea, input[type="text"]').last();
    await question.fill('What is the project codename and brand color?');
    const ask = page.locator('#rag-ask-btn, button').filter({ hasText: /Ask|Query/i }).first();
    await ask.click();
    await expect(page.locator('body')).toContainText(/MERIDIAN-742|cobalt/i, {
      timeout: 15 * 60_000,
    });
  });
});
