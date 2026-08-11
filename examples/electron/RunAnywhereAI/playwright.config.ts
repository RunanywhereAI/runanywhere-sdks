import { defineConfig } from '@playwright/test';

/**
 * Electron end-to-end tests — visual-parity gate.
 *
 * Playwright drives Electron over CDP, so it renders and screenshots the
 * BrowserWindow **without needing a visible display** — which is what makes this
 * usable on a locked or sleeping machine, and in CI.
 *
 * Baselines live in `test/e2e/__screenshots__/` (chat/models/advanced/settings ×
 * light/dark). Update with `npx playwright test --update-snapshots` when C1/C2
 * intentionally change chrome.
 */
export default defineConfig({
  testDir: './test/e2e',
  // Named baselines: `expect(page).toHaveScreenshot('chat-dark.png')` →
  // `test/e2e/__screenshots__/chat-dark.png`.
  snapshotPathTemplate: '{testDir}/__screenshots__/{arg}{ext}',
  // The app forks a utility process and loads a 43 MB native addon; a cold first
  // launch is genuinely slow.
  timeout: 120_000,
  expect: {
    timeout: 15_000,
    toHaveScreenshot: {
      animations: 'disabled',
      caret: 'hide',
      // Font AA / GPU compositing differ slightly across machines; keep the
      // gate tight enough to catch real chrome regressions.
      maxDiffPixelRatio: 0.02,
    },
  },
  // One Electron app at a time: the main process takes a single-instance lock, so
  // a second worker would quit immediately instead of running its test.
  workers: 1,
  fullyParallel: false,
  reporter: [['list']],
  use: {
    trace: 'retain-on-failure',
    viewport: { width: 1500, height: 1000 },
  },
});
