/**
 * Focused LLM generate / stream / cancel / thinking browser gate.
 *
 * Opt-in (`RA_RUN_LLM_E2E=1` or `RA_RUN_FULL_E2E=1`). Downloads a small
 * chat model, streams a short prompt, cancels a second run, and verifies
 * disableThinking produces a direct answer on a thinking-capable model.
 */
import { test, expect, type Page } from '@playwright/test';
import {
  RELEASE_E2E_ENABLED,
  RELEASE_MODELS,
  ensureModelReady,
  expectSubstantiveText,
  navigateTo,
  waitForInteractive,
} from './support/release-harness';

const shouldRun = RELEASE_E2E_ENABLED || process.env.RA_RUN_LLM_E2E === '1';

async function startFreshChat(page: Page): Promise<void> {
  const messages = page.locator('.chat-message--user, .chat-message--assistant');
  const input = page.locator('#chat-input');
  if (await messages.count() === 0 && await input.inputValue() === '') return;
  await page.locator('#consumer-new-chat-btn').click();
  await expect(messages).toHaveCount(0);
  await expect(input).toHaveValue('');
}

async function setThinkingMode(page: Page, enabled: boolean): Promise<void> {
  await navigateTo(page, 'settings');
  const toggle = page.locator('#settings-thinking-toggle');
  const current = await toggle.evaluate((node) => node.classList.contains('on'));
  if (current !== enabled) await toggle.click();
  if (enabled) {
    await expect(toggle).toHaveClass(/\bon\b/);
  } else {
    await expect(toggle).toHaveClass(/^(?!.*\bon\b)/);
  }
}

test.describe('LLM generate focused E2E', () => {
  test.skip(!shouldRun, 'Set RA_RUN_LLM_E2E=1 or RA_RUN_FULL_E2E=1 to run real LLM inference.');

  test('streams a short answer, cancels cleanly, and respects disableThinking', async ({ page }) => {
    test.setTimeout(45 * 60_000);
    await page.goto('/', { waitUntil: 'domcontentloaded' });
    await waitForInteractive(page);
    await navigateTo(page, 'chat');
    await ensureModelReady(page, '#chat-toolbar-model', RELEASE_MODELS.llm);

    await startFreshChat(page);
    await page.locator('#chat-input').fill(
      'In one concise sentence, explain why local inference improves privacy.',
    );
    await page.locator('#chat-send-btn').click();
    await expectSubstantiveText(
      page.locator('.chat-message--assistant .chat-bubble').last(),
      { minLength: 24, timeout: 8 * 60_000 },
    );
    await expect(page.locator('#chat-send-btn')).toHaveAttribute('aria-label', 'Send message');

    const runtime = await page.evaluate(() => ({
      executionContext: (
        window as Window & {
          __RUNANYWHERE_SDK__?: { runtime?: { executionContext?: string } };
        }
      ).__RUNANYWHERE_SDK__?.runtime?.executionContext ?? 'main',
    }));
    expect(['main', 'worker']).toContain(runtime.executionContext);

    await startFreshChat(page);
    await page.locator('#chat-input').fill(
      'Count slowly from 1 to 200 with one number per line.',
    );
    await page.locator('#chat-send-btn').click();
    await expect(page.locator('#chat-send-btn')).toHaveAttribute('aria-label', 'Stop generation', {
      timeout: 120_000,
    });
    await page.locator('#chat-send-btn').click();
    await expect(page.locator('#chat-send-btn')).toHaveAttribute('aria-label', 'Send message', {
      timeout: 60_000,
    });

    await ensureModelReady(page, '#chat-toolbar-model', RELEASE_MODELS.thinkingLlm);
    await setThinkingMode(page, false);
    await navigateTo(page, 'chat');
    await startFreshChat(page);
    await page.locator('#chat-input').fill('What is 2+2? Answer with one number only.');
    await page.locator('#chat-send-btn').click();
    await expectSubstantiveText(
      page.locator('.chat-message--assistant .chat-bubble').last(),
      { minLength: 1, timeout: 10 * 60_000 },
    );
    const direct = (
      await page.locator('.chat-message--assistant .chat-bubble').last().innerText()
    ).trim();
    expect(direct).toMatch(/4/);
  });
});
